tool
extends SceneTree

func _initialize():
	print("--- WALL INSPECTION START ---")
	var dir = Directory.new()
	var models = ["wall_001.glb", "wall_002.glb"]
	for m in models:
		var path = "res://assets/models/" + m
		if dir.file_exists(path):
			var scene = load(path)
			if scene:
				var inst = scene.instance()
				var aabb = get_aabb_recursive(inst)
				print("Model: ", m, " | AABB Size: ", aabb.size, " | AABB Position: ", aabb.position)
				inst.queue_free()
			else:
				print("Failed to load scene: ", path)
		else:
			print("File does not exist: ", path)
	print("--- WALL INSPECTION END ---")
	quit()

func get_aabb_recursive(node: Node) -> AABB:
	var total_aabb = AABB()
	var first = true
	if node is MeshInstance:
		if node.mesh:
			total_aabb = node.mesh.get_aabb()
			first = false
	
	for child in node.get_children():
		var child_aabb = get_aabb_recursive(child)
		if child_aabb.size != Vector3.ZERO:
			if first:
				total_aabb = child_aabb
				first = false
			else:
				total_aabb = total_aabb.merge(child_aabb)
	return total_aabb
