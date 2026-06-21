extends ScrollContainer

var dragging = false
var has_dragged = false
var drag_accumulated_distance = 0.0
var drag_threshold = 10.0
var active_touch_index = -1

# Scrolling configuration for premium feel
var drag_sensitivity = 0.9         # 0.9 balances finger tracking speed
var friction = 3.5                 # Rate of deceleration for smooth glide (default was 3.0, previous was 5.0)
var velocity_multiplier = 0.8      # Momentum release speed factor (default was 1.0, previous was 0.5)

var velocity = 0.0
var last_positions = []
var last_times = []

func _ready():
	# Ensure ScrollContainer handles inputs
	mouse_filter = MOUSE_FILTER_STOP

func _process(delta):
	if not dragging and abs(velocity) > 0.1:
		scroll_vertical -= velocity * delta
		velocity *= exp(-friction * delta)
		if abs(velocity) < 10.0:
			velocity = 0.0

func _is_pos_inside(event) -> bool:
	if not ("position" in event):
		return false
	var local_event = make_input_local(event)
	return Rect2(Vector2.ZERO, rect_size).has_point(local_event.position)

func _is_click_on_scrollbar(event) -> bool:
	var v_bar = get_v_scrollbar()
	if v_bar and v_bar.is_visible_in_tree():
		var local_event = v_bar.make_input_local(event)
		if Rect2(Vector2.ZERO, v_bar.rect_size).has_point(local_event.position):
			return true
			
	var h_bar = get_h_scrollbar()
	if h_bar and h_bar.is_visible_in_tree():
		var local_event = h_bar.make_input_local(event)
		if Rect2(Vector2.ZERO, h_bar.rect_size).has_point(local_event.position):
			return true
			
	return false

func _input(event):
	if not is_visible_in_tree():
		return

	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			if event.position == Vector2(-10000, -10000):
				return
			if event.pressed:
				if _is_pos_inside(event) and not _is_click_on_scrollbar(event):
					var local_pos = make_input_local(event).position
					dragging = true
					has_dragged = false
					drag_accumulated_distance = 0.0
					velocity = 0.0
					last_positions.clear()
					last_times.clear()
					last_positions.append(local_pos)
					last_times.append(OS.get_ticks_msec())
			else:
				if dragging:
					dragging = false
					_calculate_release_velocity()
					if has_dragged:
						cancel_click()
						get_tree().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if dragging:
			var local_pos = make_input_local(event).position
			var current_time = OS.get_ticks_msec()
			last_positions.append(local_pos)
			last_times.append(current_time)
			if last_positions.size() > 5:
				last_positions.remove(0)
				last_times.remove(0)

			drag_accumulated_distance += event.relative.length()
			if not has_dragged and drag_accumulated_distance > drag_threshold:
				has_dragged = true
				cancel_click()
			
			if has_dragged:
				scroll_vertical -= event.relative.y * drag_sensitivity
				get_tree().set_input_as_handled()

	elif event is InputEventScreenTouch:
		if event.position == Vector2(-10000, -10000):
			return
		if event.pressed:
			if active_touch_index == -1:
				if _is_pos_inside(event) and not _is_click_on_scrollbar(event):
					active_touch_index = event.index
					var local_pos = make_input_local(event).position
					dragging = true
					has_dragged = false
					drag_accumulated_distance = 0.0
					velocity = 0.0
					last_positions.clear()
					last_times.clear()
					last_positions.append(local_pos)
					last_times.append(OS.get_ticks_msec())
		else:
			if dragging and event.index == active_touch_index:
				active_touch_index = -1
				dragging = false
				_calculate_release_velocity()
				if has_dragged:
					cancel_click()
					get_tree().set_input_as_handled()

	elif event is InputEventScreenDrag:
		if dragging and event.index == active_touch_index:
			var local_pos = make_input_local(event).position
			var current_time = OS.get_ticks_msec()
			last_positions.append(local_pos)
			last_times.append(current_time)
			if last_positions.size() > 5:
				last_positions.remove(0)
				last_times.remove(0)

			drag_accumulated_distance += event.relative.length()
			if not has_dragged and drag_accumulated_distance > drag_threshold:
				has_dragged = true
				cancel_click()

			if has_dragged:
				scroll_vertical -= event.relative.y * drag_sensitivity
				get_tree().set_input_as_handled()

func _calculate_release_velocity():
	if last_positions.size() < 2:
		velocity = 0.0
		return
	
	var first_idx = 0
	var last_idx = last_positions.size() - 1
	
	var time_diff = (last_times[last_idx] - last_times[first_idx]) / 1000.0
	if time_diff > 0.02:
		var distance = last_positions[last_idx].y - last_positions[first_idx].y
		var raw_velocity = (distance / time_diff) * velocity_multiplier
		# Cap maximum scroll speed to prevent flying past elements too quickly
		var max_speed = 2500.0
		velocity = clamp(raw_velocity, -max_speed, max_speed)
	else:
		velocity = 0.0

func cancel_click():
	# Cancel mouse focus/press by sending a release event far away
	var ev = InputEventMouseButton.new()
	ev.button_index = BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(-10000, -10000)
	ev.global_position = Vector2(-10000, -10000)
	get_viewport().input(ev)
	
	# Cancel touch focus/press
	var ev_touch = InputEventScreenTouch.new()
	ev_touch.pressed = false
	ev_touch.position = Vector2(-10000, -10000)
	get_viewport().input(ev_touch)
