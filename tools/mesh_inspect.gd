@tool
extends EditorScript

func _find_mesh(node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var r = _find_mesh(c)
		if r:
			return r
	return null

func _run():
	var scene_root = EditorInterface.get_edited_scene_root()
	var mi = _find_mesh(scene_root)
	if mi == null:
		print("No MeshInstance3D found")
		return
	var mesh = mi.mesh
	var arr = mesh.surface_get_arrays(0)
	var verts = arr[Mesh.ARRAY_VERTEX]
	var min_y = INF
	var max_y = -INF
	var min_z = INF
	var max_z = -INF
	for v in verts:
		if v.y < min_y:
			min_y = v.y
		if v.y > max_y:
			max_y = v.y
		if v.z < min_z:
			min_z = v.z
		if v.z > max_z:
			max_z = v.z
	print("Vertex local Y: ", min_y, " to ", max_y)
	print("Vertex local Z: ", min_z, " to ", max_z)
	print("AABB: ", mesh.get_aabb())
