extends StaticBody3D

## Invisible world border that follows the outline of the terrain tiles.
##
## The outline is built at runtime from the tile footprints written by
## tools/blend_seams.js (res://assets/terrain_seams/*.json), so it adapts
## automatically when tiles are added, moved or removed (re-run the tool).
##
## The covered area is rasterised into a grid, shrunk by `inset` metres, and
## every outer edge of the result becomes a tall, invisible box wall. Because
## it traces the real outline, missing corners of the map are walled off too.

## How far inside the terrain edge the border sits (metres).
@export var inset: float = 8.0
## Wall height above / depth below the ground (metres).
@export var wall_top: float = 400.0
@export var wall_bottom: float = -200.0
## Wall thickness (metres). Thick enough that fast vehicles can't tunnel through.
@export var thickness: float = 4.0
## Raster resolution (metres). Smaller = follows the outline more closely.
@export var cell: float = 2.0
## Show the walls as translucent red boxes (for checking the layout).
@export var debug_visible: bool = false

const SEAM_DIR := "res://assets/terrain_seams/"


func _ready() -> void:
	var rects := _load_tile_rects()
	if rects.is_empty():
		push_warning("WorldBorder: no tile data in %s - run tools/blend_seams.js" % SEAM_DIR)
		return

	# --- Rasterise the union of all tile footprints ---
	var bounds: Rect2 = rects[0]
	for r in rects:
		bounds = bounds.merge(r)
	bounds = bounds.grow(cell * 2.0)
	var nx := ceili(bounds.size.x / cell)
	var nz := ceili(bounds.size.y / cell)
	var inside := PackedByteArray()
	inside.resize(nx * nz)
	for r in rects:
		var x0 := clampi(ceili((r.position.x - bounds.position.x) / cell), 0, nx)
		var x1 := clampi(floori((r.end.x - bounds.position.x) / cell), 0, nx)
		var z0 := clampi(ceili((r.position.y - bounds.position.y) / cell), 0, nz)
		var z1 := clampi(floori((r.end.y - bounds.position.y) / cell), 0, nz)
		for z in range(z0, z1):
			for x in range(x0, x1):
				inside[z * nx + x] = 1

	# --- Shrink by `inset` (square erosion) ---
	var steps := ceili(inset / cell)
	for _i in steps:
		var next := inside.duplicate()
		for z in nz:
			for x in nx:
				if inside[z * nx + x] == 0:
					continue
				if x == 0 or z == 0 or x == nx - 1 or z == nz - 1 \
						or inside[z * nx + x - 1] == 0 or inside[z * nx + x + 1] == 0 \
						or inside[(z - 1) * nx + x] == 0 or inside[(z + 1) * nx + x] == 0:
					next[z * nx + x] = 0
		inside = next

	# --- Trace outer edges, merged into straight runs ---
	var walls := 0
	var at := func(x: int, z: int) -> bool:
		return x >= 0 and z >= 0 and x < nx and z < nz and inside[z * nx + x] == 1
	# Edges running along X (wall faces north / south)
	for z in range(nz + 1):
		for side in [-1, 1]:
			var x := 0
			while x < nx:
				# inside cell on one side of the line, outside on the other
				var cz_in := z - 1 if side == -1 else z
				var cz_out := z if side == -1 else z - 1
				if at.call(x, cz_in) and not at.call(x, cz_out):
					var start := x
					while x < nx and at.call(x, cz_in) and not at.call(x, cz_out):
						x += 1
					var line_z := bounds.position.y + z * cell
					_add_wall(Vector3(bounds.position.x + start * cell, 0, line_z),
							Vector3(bounds.position.x + x * cell, 0, line_z), Vector3(0, 0, -side))
					walls += 1
				else:
					x += 1
	# Edges running along Z (wall faces east / west)
	for x in range(nx + 1):
		for side in [-1, 1]:
			var z := 0
			while z < nz:
				var cx_in := x - 1 if side == -1 else x
				var cx_out := x if side == -1 else x - 1
				if at.call(cx_in, z) and not at.call(cx_out, z):
					var start := z
					while z < nz and at.call(cx_in, z) and not at.call(cx_out, z):
						z += 1
					var line_x := bounds.position.x + x * cell
					_add_wall(Vector3(line_x, 0, bounds.position.y + start * cell),
							Vector3(line_x, 0, bounds.position.y + z * cell), Vector3(-side, 0, 0))
					walls += 1
				else:
					z += 1
	print("WorldBorder: %d wall segments around %d tiles (inset %.1f m)" % [walls, rects.size(), inset])


## Reads every tile footprint (world XZ rectangle) from the seam data.
func _load_tile_rects() -> Array:
	var out := []
	var dir := DirAccess.open(SEAM_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		# Exported builds may list remapped names - strip those suffixes.
		var fname := f.trim_suffix(".remap").trim_suffix(".import")
		if not fname.ends_with(".json"):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(SEAM_DIR + fname))
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var c := float(d.cell)
		out.append(Rect2(float(d.min_x), float(d.min_z), int(d.nx) * c, int(d.nz) * c))
	return out


## Adds one wall along the line a->b. `outward` points away from the map, so
## the wall's inner face sits exactly on the line.
func _add_wall(a: Vector3, b: Vector3, outward: Vector3) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var height := wall_top - wall_bottom
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	# No extension past the ends: inner faces of neighbouring walls meet
	# exactly at each corner, and a stub would poke into the walkable area at
	# inner corners of the outline.
	var size := Vector3(length if along_x else thickness, height,
			thickness if along_x else length)
	var centre := (a + b) * 0.5 + outward * (thickness * 0.5)
	centre.y = (wall_top + wall_bottom) * 0.5

	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = centre
	add_child(col)

	if debug_visible:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x, minf(size.y, 60.0), size.z)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 0.1, 0.1, 0.35)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(centre.x, 15.0, centre.z)
		add_child(mi)
