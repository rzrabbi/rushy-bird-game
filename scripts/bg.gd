extends Spatial

var speed = 3

var starting_pos

func _ready():
	starting_pos = global_transform.origin
	set_physics_process(false)
	
func start():
	set_physics_process(true)
	
func _physics_process(delta):
	var current_game_speed = get_parent().game_speed if get_parent().get("game_speed") != null else 1.0
	global_transform.origin += delta * speed * current_game_speed * Vector3.LEFT
	
	# Since each background piece is 20 units wide, snap back by 20 units 
	# once we've traveled that distance to create a perfectly seamless, stutter-free loop.
	if starting_pos.x - global_transform.origin.x >= 20.0:
		global_transform.origin.x += 20.0

func stop():
	set_physics_process(false)
