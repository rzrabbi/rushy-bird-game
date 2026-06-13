extends RigidBody

var jump_power = 32
var is_dead = false
var has_played_fall_sound = false
var initial_y = 0.0
var initial_x = 0.0
var hover_time = 0.0
var is_on_floor = false
var in_score_area = false
var is_invincible = false

func _ready():
	initial_y = translation.y
	initial_x = translation.x
	collision_mask = 3

func set_invincible(state: bool):
	is_invincible = state
	if is_invincible:
		collision_layer = 2 # Move bird to layer 2 so pipes (mask 1) ignore it
		collision_mask = 2  # Only detect floor (layer 2)
	else:
		collision_layer = 1 # Back to normal layer 1
		collision_mask = 3  # Detect pipes (1) and floor (2)

func _physics_process(_delta):
	if mode == RigidBody.MODE_RIGID and not is_dead:
		var main_node = get_parent()
		if main_node and "game_speed" in main_node:
			var current_speed = main_node.game_speed
			# Scale jump power linearly and gravity quadratically to preserve the exact jump shape
			# Soft cap gravity at 4.0 (reached at 2.0x speed) for better playability at extreme speeds
			jump_power = 32.0 * current_speed
			gravity_scale = 5.0 * min(current_speed * current_speed, 4.0)

func _process(delta):
	if mode != RigidBody.MODE_RIGID and not is_dead:
		hover_time += delta * 4.0
		translation.y = initial_y + sin(hover_time) * 0.5
		
	if mode == RigidBody.MODE_RIGID and not is_dead:
		if translation.y > 27.5:
			die(false)
			
	if is_dead and not is_on_floor and not in_score_area:
		if translation.y < -15.0 and not has_played_fall_sound:
			has_played_fall_sound = true
			if has_node("../BirdFall"):
				$"../BirdFall".play()
				
		if translation.y < -35.0:
			vanish_silently()


func _unhandled_input(event):
	if event.is_action_pressed("Jump") || (event is InputEventMouseButton && event.pressed):
		jump()


func jump():
	if mode == RigidBody.MODE_STATIC or is_dead:
		return
	apply_central_impulse(jump_power * Vector3.UP)
	if has_node("../BirdJump"):
		$"../BirdJump".play()
	



func start():
	mode = RigidBody.MODE_RIGID


func _on_Bird_body_entered(body):
	if get_tree().paused:
		return
		
	if is_invincible:
		return

	var is_floor = body.get_parent() != null and body.get_parent().name == "MeshInstance"
	
	if is_floor:
		if not is_on_floor:
			is_on_floor = true
			
			if has_node("../BirdFall") and not has_played_fall_sound:
				has_played_fall_sound = true
				$"../BirdFall".play()
				
			die(false)
			$"..".trigger_grounded_phase()
			# Explicitly hide the bird so it is absolutely not visible
			if has_node("rushy_bird"):
				$rushy_bird.hide()
	else:
		if is_dead:
			return # Ignore extra pipe hits in the same frame if already dead
			
		# Health/revive system handles taking damage and giving a chance to continue
		if $"..".has_method("revive_me_jett") and $"..".revive_me_jett():
			if has_node("../BirdCollision"):
				$"../BirdCollision".play()
			
			call_deferred("reset_position_deferred")
			
			linear_velocity.y = 0.0 # Reset Y velocity so the bounce is consistent
			apply_central_impulse(jump_power * 0.5 * Vector3.UP)
			
			blink_ghost()
		else:
			die(true)

func blink_ghost():
	if has_node("rushy_bird"):
		var tween = Tween.new()
		add_child(tween)
		for i in range(4):
			tween.interpolate_callback($rushy_bird, i * 0.2, "hide")
			tween.interpolate_callback($rushy_bird, i * 0.2 + 0.1, "show")
		tween.start()
		tween.connect("tween_all_completed", tween, "queue_free")

func reset_position_deferred():
	linear_velocity.x = 0.0
	translation.x = initial_x

func disable_collision_deferred():
	collision_layer = 0
	collision_mask = 0
	translation.z -= 2.0

func destroy_body():
	if has_node("rushy_bird"):
		$rushy_bird.hide()
	if has_node("../BirdPop"):
		$"../BirdPop".play()
	collision_layer = 0
	collision_mask = 0
	mode = RigidBody.MODE_STATIC

func vanish_silently():
	if has_node("rushy_bird"):
		$rushy_bird.hide()
	collision_layer = 0
	collision_mask = 0
	mode = RigidBody.MODE_STATIC

func die(play_sound = true):
	if is_dead:
		return
	is_dead = true
	axis_lock_angular_z = false
	
	if play_sound and has_node("../BirdCollision"):
		$"../BirdCollision".play()
		
	if in_score_area:
		pass
		
	if play_sound or translation.y > 27.0:
		if translation.y <= 27.0 and has_node("../Camera"):
			var cam = $"../Camera"
			var original_size = cam.size
			var original_pos = cam.translation
			var target_pos = Vector3(translation.x, translation.y, original_pos.z)
			
			var max_y_offset = original_size * 0.15 # (1.0 - 0.7) / 2
			target_pos.y = clamp(target_pos.y, original_pos.y - max_y_offset, original_pos.y + max_y_offset)
			
			var tween = Tween.new()
			cam.add_child(tween)
			
			tween.interpolate_property(cam, "size", original_size, original_size * 0.7, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
			tween.interpolate_property(cam, "translation", original_pos, target_pos, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
			
			tween.interpolate_property(cam, "size", original_size * 0.7, original_size, 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.8)
			tween.interpolate_property(cam, "translation", target_pos, original_pos, 0.6, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.8)
			
			tween.start()
			tween.connect("tween_all_completed", tween, "queue_free")
		
	$"..".trigger_hit_phase()
	
	get_tree().create_timer(1.5).connect("timeout", $"..", "trigger_grounded_phase")
