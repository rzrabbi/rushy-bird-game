extends SceneTree

func _init():
	var packed = load("res://assets/models/platform_001.glb")
	if not packed:
		print("Failed to load platform_001.glb")
		quit()
		return
	var scene = packed.instance()
	for child in scene.get_children():
		if child is MeshInstance:
			print("MeshInstance found: ", child.name)
			var mesh = child.mesh
			for i in range(mesh.get_surface_count()):
				var mat = mesh.surface_get_material(i)
				if mat:
					print("  Surface ", i, " material: ", mat.resource_path)
					if mat is SpatialMaterial:
						print("    Albedo tex: ", mat.albedo_texture.resource_path if mat.albedo_texture else "none")
						print("    Normal tex: ", mat.normal_texture.resource_path if mat.normal_texture else "none")
				else:
					print("  Surface ", i, " has NO material")
	quit()
