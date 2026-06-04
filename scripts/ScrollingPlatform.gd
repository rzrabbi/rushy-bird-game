extends Spatial

var speed = 10

var starting_pos

func _ready():
	starting_pos = global_transform.origin
	set_physics_process(false)

func start():
	set_physics_process(true)
	
func _physics_process(delta):
	var main_node = get_parent()
	if not main_node:
		return
		
	var game_speed = main_node.game_speed if main_node.get("game_speed") != null else 1.0
	
	global_transform.origin += delta * speed * game_speed * Vector3.LEFT
	
	# Since each unstretched platform segment is 8 units wide,
	# snap back by 8.0 units once we've traveled that distance to create a seamless loop.
	if starting_pos.x - global_transform.origin.x >= 8.0:
		global_transform.origin.x += 8.0

func stop():
	set_physics_process(false)
