@tool
extends StaticBody3D

## Builds an exact per-triangle collision surface for a terrain tile, applies
## its material, and blends its edges into neighbouring tiles.
##
## This lives at scene-root level rather than inside the imported .glb
## subtree: property edits made directly on nodes of an instanced scene are
## not reliably persisted, which is why earlier attempts silently lost both
## the collision body and the material_override.
##
## Seam blending: tools/blend_seams.js writes a height-correction grid per
## tile to res://assets/terrain_seams/<TileName>.json. The SAME correction is
## applied to the visuals (vertex shader) and to the collision triangles here,
## so the player walks exactly on the surface they see.

## The MeshInstance3D to trace. May also point at the instanced .glb root -
## the first MeshInstance3D below it is used (some NASA models ship with
## unnamed nodes, so their exact mesh path is not stable).
@export var mesh_path: NodePath = ^"../MarsSurface"

## Material applied to the mesh (leave empty to keep the imported one).
@export var terrain_material: Material
const TERRAIN_MATERIAL_PATH := "res://assets/materials/mars_regolith.tres"

## Blend this tile's edges into its neighbours using the precomputed grid.
@export var blend_seams: bool = true
const SEAM_DIR := "res://assets/terrain_seams/"

const TRIS_PER_TASK := 20000

# Seam grid (filled by _load_seam)
var _seam: PackedFloat32Array
var _seam_nx: int = 0
var _seam_nz: int = 0
var _seam_min := Vector2.ZERO
var _seam_cell: float = 1.0
## Local edge expansion (scale_x, scale_y, centre_x, centre_y)
var _expand := Vector4(1.0, 1.0, 0.0, 0.0)
## Local box of the model (min_x, max_x, min_y, max_y) - side walls are dropped
var _bounds := Vector4(-1e9, 1e9, -1e9, 1e9)

# Shared with worker threads (read-only while they run)
var _src_faces: PackedVector3Array
var _basis := Basis.IDENTITY
var _origin := Vector3.ZERO
var _flip_winding := false
var _chunks: Array = []


func _find_mesh(node: Node) -> MeshInstance3D:
	if node == null:
		return null
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r := _find_mesh(c)
		if r:
			return r
	return null


## Name of the tile node this body belongs to (the instanced .glb root that
## sits next to this body in the scene).
func _tile_name(mi: Node) -> String:
	var n := mi
	while n and n.get_parent() != get_parent():
		n = n.get_parent()
	return String(n.name) if n else ""


func _ready() -> void:
	if terrain_material == null:
		terrain_material = load(TERRAIN_MATERIAL_PATH)
	var mi := _find_mesh(get_node_or_null(mesh_path))
	if mi == null:
		push_error("TerrainCollision: MeshInstance3D not found at %s" % mesh_path)
		return
	if mi.mesh == null:
		push_error("TerrainCollision: node has no mesh.")
		return

	var has_seam := blend_seams and _load_seam(_tile_name(mi))

	# --- Material -----------------------------------------------------------
	if terrain_material != null:
		if has_seam and terrain_material is ShaderMaterial:
			# Each tile needs its own correction texture -> own material copy.
			var mat: ShaderMaterial = terrain_material.duplicate()
			var img := Image.create_from_data(_seam_nx, _seam_nz, false, Image.FORMAT_RF, _seam.to_byte_array())
			mat.set_shader_parameter("seam_enabled", true)
			mat.set_shader_parameter("seam_delta", ImageTexture.create_from_image(img))
			mat.set_shader_parameter("seam_rect", Vector4(_seam_min.x, _seam_min.y,
					_seam_nx * _seam_cell, _seam_nz * _seam_cell))
			mat.set_shader_parameter("seam_expand", _expand)
			mat.set_shader_parameter("seam_bounds", _bounds)
			mi.material_override = mat
		else:
			mi.material_override = terrain_material

	# Collision is only needed in the running game, not in the editor.
	if Engine.is_editor_hint():
		return
	if get_node_or_null("TerrainShape") != null:
		return

	var xform := mi.global_transform
	var shape: ConcavePolygonShape3D

	if has_seam or xform.basis.determinant() < 0.0:
		# Bake orientation (+ seam correction) into the triangles. Needed for
		# mirrored tiles (physics can't take negative scale) and so the seam
		# correction is added straight up in WORLD space, matching the shader.
		shape = _build_world_shape(mi.mesh.get_faces(), xform, has_seam)
		global_transform = Transform3D(Basis.IDENTITY, xform.origin)
	else:
		shape = mi.mesh.create_trimesh_shape()
		global_transform = xform

	if shape == null:
		push_error("TerrainCollision: failed to build trimesh shape.")
		return
	var col := CollisionShape3D.new()
	col.name = "TerrainShape"
	col.shape = shape
	add_child(col)


# ---------------------------------------------------------------------------
#  Seam grid
# ---------------------------------------------------------------------------
func _load_seam(tile: String) -> bool:
	var path := SEAM_DIR + tile + ".json"
	if tile == "" or not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("TerrainCollision: could not read %s" % path)
		return false
	_seam_nx = int(parsed.nx)
	_seam_nz = int(parsed.nz)
	_seam_cell = float(parsed.cell)
	_seam_min = Vector2(float(parsed.min_x), float(parsed.min_z))
	_seam = PackedFloat32Array(parsed.data)
	if _seam.size() != _seam_nx * _seam_nz:
		push_warning("TerrainCollision: %s has a wrong size, ignoring." % path)
		return false
	var e = parsed.get("expand")
	if e is Array and e.size() == 4:
		_expand = Vector4(float(e[0]), float(e[1]), float(e[2]), float(e[3]))
	var bd = parsed.get("bounds")
	if bd is Array and bd.size() == 4:
		_bounds = Vector4(float(bd[0]), float(bd[1]), float(bd[2]), float(bd[3]))
	return true


## Bilinear lookup, identical to the GPU's linear filtering of the texture
## (samples sit at cell centres, clamped at the border).
func _seam_at(x: float, z: float) -> float:
	var fx := clampf((x - _seam_min.x) / _seam_cell - 0.5, 0.0, _seam_nx - 1.0)
	var fz := clampf((z - _seam_min.y) / _seam_cell - 0.5, 0.0, _seam_nz - 1.0)
	var x0 := int(fx)
	var z0 := int(fz)
	var x1 := mini(x0 + 1, _seam_nx - 1)
	var z1 := mini(z0 + 1, _seam_nz - 1)
	var tx := fx - x0
	var tz := fz - z0
	var a := lerpf(_seam[z0 * _seam_nx + x0], _seam[z0 * _seam_nx + x1], tx)
	var b := lerpf(_seam[z1 * _seam_nx + x0], _seam[z1 * _seam_nx + x1], tx)
	return lerpf(a, b, tz)


# ---------------------------------------------------------------------------
#  Collision building (multi-threaded)
# ---------------------------------------------------------------------------
func _build_world_shape(src: PackedVector3Array, xform: Transform3D, use_seam: bool) -> ConcavePolygonShape3D:
	_src_faces = src
	_basis = xform.basis
	_origin = xform.origin
	_flip_winding = xform.basis.determinant() < 0.0
	if not use_seam:
		_seam_nx = 0

	var tri_count := src.size() / 3
	var tasks := ceili(float(tri_count) / TRIS_PER_TASK)
	_chunks.resize(tasks)
	var id := WorkerThreadPool.add_group_task(_process_chunk, tasks, -1, true, "terrain seam bake")
	WorkerThreadPool.wait_for_group_task_completion(id)

	var faces := PackedVector3Array()
	for c in _chunks:
		faces.append_array(c)
	_chunks.clear()
	_src_faces = PackedVector3Array()

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape


## Same local edge expansion the shader applies (mesh-local X/Y plane).
func _grow(v: Vector3) -> Vector3:
	return Vector3(_expand.z + (v.x - _expand.z) * _expand.x,
			_expand.w + (v.y - _expand.w) * _expand.y, v.z)


## Side wall or underside of the model's box (same rule as the shader).
func _is_box_wall(p0: Vector3, p1: Vector3, p2: Vector3) -> bool:
	# Godot's get_faces() uses clockwise winding, so the face normal is the
	# NEGATED cross product (the top surface then points to +Z, as in the
	# model). Mirroring lives only in the basis, so local winding is unchanged.
	var n := (p2 - p0).cross(p1 - p0)
	if n.length_squared() < 1e-12:
		return false
	n = n.normalized()
	if n.z < -0.5:
		return true
	if absf(n.z) >= 0.5:
		return false
	var eps := 0.001 * maxf(_bounds.y - _bounds.x, _bounds.w - _bounds.z)
	var planes := [_bounds.x, _bounds.y, _bounds.z, _bounds.w]
	for side in 4:
		var all_on := true
		for p in [p0, p1, p2]:
			var v: float = p.x if side < 2 else p.y
			if absf(v - planes[side]) > eps:
				all_on = false
				break
		if all_on:
			return true
	return false


func _process_chunk(task: int) -> void:
	var t0 := task * TRIS_PER_TASK
	var t1 := mini(t0 + TRIS_PER_TASK, _src_faces.size() / 3)
	var out := PackedVector3Array()
	out.resize((t1 - t0) * 3)
	var w := 0
	for t in range(t0, t1):
		var i := t * 3
		if _seam_nx > 0 and _is_box_wall(_src_faces[i], _src_faces[i + 1], _src_faces[i + 2]):
			continue
		var a := _basis * _grow(_src_faces[i])
		var b := _basis * _grow(_src_faces[i + 1])
		var c := _basis * _grow(_src_faces[i + 2])
		if _seam_nx > 0:
			a.y += _seam_at(a.x + _origin.x, a.z + _origin.z)
			b.y += _seam_at(b.x + _origin.x, b.z + _origin.z)
			c.y += _seam_at(c.x + _origin.x, c.z + _origin.z)
		out[w] = a
		if _flip_winding:
			out[w + 1] = c
			out[w + 2] = b
		else:
			out[w + 1] = b
			out[w + 2] = c
		w += 3
	out.resize(w)
	_chunks[task] = out
