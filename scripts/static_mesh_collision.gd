extends Node3D

## Gives every mesh below this node exact (per-triangle) static collision at
## runtime, so buildings and props can't be walked or driven through.
##
## Done at runtime on purpose: edits made inside an instanced .glb are not
## reliably saved by Godot (the same reason terrain_collision.gd exists).

func _ready() -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh != null:
			mi.create_trimesh_collision()
