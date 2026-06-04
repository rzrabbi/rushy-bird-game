extends Spatial

var obstacle = preload("res://scenes/Obstacle.tscn")

var offset_y = 8.5
var spawn_timer = 0.0
var spawn_interval = 2.0
var is_spawning = false
var last_offset_y = 0.0

func _ready():
	set_process(false)

func start_spawning():
	is_spawning = true
	last_offset_y = 0.0
	spawn_timer = spawn_interval # trigger immediately
	set_process(true)

func _process(delta):
	if not is_spawning:
		return
		
	var current_game_speed = get_parent().game_speed if get_parent().get("game_speed") != null else 1.0
	var current_level = get_parent().current_speed_level if get_parent().get("current_speed_level") != null else 1
	
	# Dynamic Spawn Pressure: Decrease interval to squeeze pipes together as levels increase
	var dynamic_interval = max(1.6, 2.0 - ((current_level - 1) * 0.03))
	
	# Partial decoupling: spawn rate increases with speed, but at half the rate
	spawn_timer += delta * lerp(1.0, current_game_speed, 0.5)
	
	if spawn_timer >= dynamic_interval:
		spawn_timer -= dynamic_interval
		spawn_obstacle(current_level)

func spawn_obstacle(current_level = 1):
	var spawned_obstacle = obstacle.instance()
	add_child(spawned_obstacle)
	
	var current_game_speed = get_parent().game_speed if get_parent().get("game_speed") != null else 1.0
	
	# Progressive Vertical Variance: Limit the Y-axis randomness in early levels so it's easier to learn
	# By level 5, the full 8.5 offset is unlocked.
	var current_offset_y = min(offset_y, 4.0 + ((current_level - 1) * 1.0))
	
	# At higher speeds, limit how far consecutive pipes can jump vertically.
	var max_diff = lerp(17.0, 12.0, clamp((current_game_speed - 1.0) / 0.75, 0.0, 1.0))
	
	var new_offset = rand_range(-current_offset_y, current_offset_y)
	new_offset = clamp(new_offset, last_offset_y - max_diff, last_offset_y + max_diff)
	new_offset = clamp(new_offset, -current_offset_y, current_offset_y)
	last_offset_y = new_offset
	
	spawned_obstacle.translate(new_offset * Vector3.UP)

func stop():
	is_spawning = false
	set_process(false)
	for child in get_children():
		if child.has_method("set_physics_process"):
			child.set_physics_process(false)

func clear_obstacles():
	for child in get_children():
		if child is Spatial and not child is Timer:
			child.queue_free()
