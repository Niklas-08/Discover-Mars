@tool
extends StaticBody3D

## Builds an exact per-triangle collision surface for a MeshInstance3D and
## applies its material.
##
## This lives at scene-root level rather than inside the imported .glb
## subtree: property edits made directly on nodes of an instanced scene are
## not reliably persisted, which is why earlier attempts silently lost both
## the collision body and the material_override.

## The MeshInstance3D to trace. May also point at the instanced .glb root -
## the first MeshInstance3D below it is used (some NASA models ship with
## unnamed nodes, so their exact mesh path is not stable).
@export var mesh_path: NodePath = ^"../MarsGaleCrater/empty_1/empty_2"

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

## Material applied to the mesh (leave empty to keep the imported one).
@export var terrain_material: Material
const TERRAIN_MATERIAL_PATH := "res://assets/materials/mars_regolith.tres"

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

	if terrain_material != null:
		mi.material_override = terrain_material

	# Skip rebuilding if a shape already exists (e.g. @tool re-entry).
	if get_node_or_null("TerrainShape") != null:
		return

	# ConcavePolygonShape3D traces every triangle of the terrain, so the
	# player walks the real surface instead of a flat box lid.
	var xform := mi.global_transform

	# Mirrored tiles (negative scale) are not supported reliably by the
	# physics engine on a body transform. Bake the basis into the triangles
	# instead, flip the winding so faces still point up, and keep only the
	# translation on the body.
	if xform.basis.determinant() < 0.0:
		var src := mi.mesh.get_faces()
		var faces := PackedVector3Array()
		faces.resize(src.size())
		var b := xform.basis
		for i in range(0, src.size(), 3):
			faces[i] = b * src[i]
			faces[i + 1] = b * src[i + 2]
			faces[i + 2] = b * src[i + 1]
		var mirrored := ConcavePolygonShape3D.new()
		mirrored.set_faces(faces)
		var mcol := CollisionShape3D.new()
		mcol.name = "TerrainShape"
		mcol.shape = mirrored
		add_child(mcol)
		global_transform = Transform3D(Basis.IDENTITY, xform.origin)
		return

	var shape := mi.mesh.create_trimesh_shape()
	if shape == null:
		push_error("TerrainCollision: failed to build trimesh shape.")
		return

	var col := CollisionShape3D.new()
	col.name = "TerrainShape"
	col.shape = shape
	add_child(col)

	# Match the mesh's world transform (handles the -90 deg X rotation the
	# .glb root carries).
	global_transform = mi.global_transform
