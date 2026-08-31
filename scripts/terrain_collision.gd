@tool
extends StaticBody3D

## Builds an exact per-triangle collision surface for a MeshInstance3D and
## applies its material.
##
## This lives at scene-root level rather than inside the imported .glb
## subtree: property edits made directly on nodes of an instanced scene are
## not reliably persisted, which is why earlier attempts silently lost both
## the collision body and the material_override.

## The MeshInstance3D to trace.
@export var mesh_path: NodePath = ^"../MarsGaleCrater/empty_1/empty_2"

## Material applied to the mesh (leave empty to keep the imported one).
@export var terrain_material: Material
const TERRAIN_MATERIAL_PATH := "res://assets/materials/mars_regolith.tres"

func _ready() -> void:
	if terrain_material == null:
		terrain_material = load(TERRAIN_MATERIAL_PATH)
	var mi := get_node_or_null(mesh_path) as MeshInstance3D
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
