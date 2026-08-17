@tool
extends EditorScript

func _run():
	var scene_root = EditorInterface.get_edited_scene_root()
	var mi: MeshInstance3D = scene_root.get_node("MarsGaleCrater/empty_1/empty_2")
	var col: CollisionShape3D = mi.get_node("TerrainBody/CollisionShape3D")
	col.shape = mi.mesh.create_trimesh_shape()
	EditorInterface.save_scene()
	print("Trimesh baked: ", col.shape.get_faces().size() / 3, " triangles.")
