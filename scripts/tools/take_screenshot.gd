extends Spatial

func _ready():
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.5, 0.5)
	env.ambient_light_color = Color(1, 1, 1)
	
	var world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	
	var dir_light = DirectionalLight.new()
	dir_light.transform.basis = Basis(Vector3(1, 0, 0), -PI/4)
	add_child(dir_light)
	
	var models = ["platform_001.glb", "platform_002.glb", "platform_003.glb", "platform_004.glb", "ruins_road_001.glb", "ruins_road_002.glb", "ruins_road_003.glb"]
	var x = 0
	for m in models:
		var scene = load("res://assets/models/" + m)
		if scene:
			var inst = scene.instance()
			add_child(inst)
			inst.translation = Vector3(x, 0, 0)
			x += 12
			
	var cam = Camera.new()
	add_child(cam)
	cam.translation = Vector3(30, 20, 30)
	cam.look_at(Vector3(30, 0, 0), Vector3.UP)
	
	# Wait for 3 frames to ensure rendering is complete
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	
	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("res://models_preview.png")
	get_tree().quit()
