extends Node


signal console_opened
signal console_closed
signal console_unknown_command


class ConsoleCommand:
	var function
	var param_count
	var hidden := false
	func _init(in_function, in_param_count):
		function = in_function
		param_count = in_param_count


var font_size := 38

var perf_monitor: PanelContainer
var perf_label: Label

var frame_times := []
const MAX_FRAME_HISTORY = 600

onready var control := Control.new()
onready var rich_label := RichTextLabel.new()
onready var line_edit := LineEdit.new()

var console_commands := {}
var console_history := []
var console_history_index := 0
var command_parameters : Dictionary = {}
var mobile_tap_count := 0
var mobile_last_tap_time := 0


func _ready():
	if OS.has_feature("JavaScript"):
		JavaScript.eval("""
			(function() {
				if (typeof HTMLElement !== 'undefined' && HTMLElement.prototype && HTMLElement.prototype.focus) {
					var origFocus = HTMLElement.prototype.focus;
					HTMLElement.prototype.focus = function(options) {
						options = options || {};
						options.preventScroll = true;
						origFocus.call(this, options);
					};
				}
			})();
		""")

	var canvas_layer := CanvasLayer.new()
	canvas_layer.layer = 3
	add_child(canvas_layer)
	control.anchor_bottom = 1.0
	control.anchor_right = 1.0
	canvas_layer.add_child(control)
	
	# Performance Monitor Overlay
	perf_monitor = PanelContainer.new()
	perf_monitor.name = "PerfMonitor"
	perf_monitor.visible = false
	
	var perf_stylebox = StyleBoxFlat.new()
	perf_stylebox.bg_color = Color(0, 0, 0, 0.7)
	perf_stylebox.content_margin_left = 16
	perf_stylebox.content_margin_right = 16
	perf_stylebox.content_margin_top = 8
	perf_stylebox.content_margin_bottom = 8
	perf_monitor.add_stylebox_override("panel", perf_stylebox)
	
	perf_monitor.anchor_left = 0.0
	perf_monitor.anchor_right = 1.0
	perf_monitor.anchor_top = 0.0
	perf_monitor.anchor_bottom = 0.0
	perf_monitor.margin_left = 0
	perf_monitor.margin_right = 0
	perf_monitor.margin_top = 0
	
	perf_label = Label.new()
	perf_label.name = "PerfLabel"
	perf_monitor.add_child(perf_label)
	canvas_layer.add_child(perf_monitor)
	
	# Load and apply high-DPI friendly monospace font
	var dynamic_font = DynamicFont.new()
	var font_data = load("res://assets/fonts/Lucida Console Regular.ttf")
	if font_data:
		dynamic_font.font_data = font_data
		dynamic_font.size = font_size
		dynamic_font.use_filter = true
		dynamic_font.use_mipmaps = true
		rich_label.add_font_override("normal_font", dynamic_font)
		rich_label.add_font_override("bold_font", dynamic_font)
		rich_label.add_font_override("italics_font", dynamic_font)
		rich_label.add_font_override("bold_italics_font", dynamic_font)
		rich_label.add_font_override("mono_font", dynamic_font)
		line_edit.add_font_override("font", dynamic_font)
		
		# Set smaller font for performance monitor
		var perf_font = DynamicFont.new()
		perf_font.font_data = font_data
		perf_font.size = 32
		perf_font.use_filter = true
		perf_font.use_mipmaps = true
		perf_label.add_font_override("font", perf_font)
		perf_label.add_color_override("font_color", Color(0.0, 0.9, 0.1))
		perf_label.align = Label.ALIGN_CENTER
		perf_label.valign = Label.VALIGN_CENTER
	
	var is_mobile = OS.has_touchscreen_ui_hint()
	var bottom_anchor = 0.4 if is_mobile else 0.5
	
	rich_label.bbcode_enabled = true
	rich_label.scroll_following = true
	rich_label.anchor_right = 1.0
	rich_label.anchor_bottom = bottom_anchor
	
	var bg_stylebox = load("res://addons/console/console_background.tres")
	if bg_stylebox is StyleBoxFlat:
		bg_stylebox = bg_stylebox.duplicate()
		bg_stylebox.content_margin_left = 24
		bg_stylebox.content_margin_right = 24
		bg_stylebox.content_margin_top = 24
		bg_stylebox.content_margin_bottom = 24
	rich_label.add_stylebox_override("normal", bg_stylebox)
	
	control.add_child(rich_label)
	rich_label.bbcode_text = (
		"[b]=== RUSHY BIRD DEVELOPER CONSOLE ===[/b]\n" +
		"Type [color=#ffff66]help[/color] to list all available commands.\n\n" +
		"--------------------------------------------------------------------------------\n" +
		"[color=#666666]Sure, a developer console might be complete overkill for a simple arcade game like this... " +
		"but I built it to experiment with game mechanics, tweak settings on the fly, and break " +
		"things in real-time. Messing around under the hood is just as fun as playing the game![/color]\n\n"
	)
	
	line_edit.anchor_top = bottom_anchor
	line_edit.anchor_right = 1.0
	line_edit.anchor_bottom = bottom_anchor
	line_edit.margin_left = 24
	if is_mobile:
		line_edit.margin_right = -180
	else:
		line_edit.margin_right = -24
	line_edit.margin_top = 0
	line_edit.margin_bottom = font_size + 16
	line_edit.rect_min_size.y = font_size + 16
	control.add_child(line_edit)
	
	if is_mobile:
		var send_btn = Button.new()
		send_btn.name = "SendButton"
		send_btn.text = "Send"
		send_btn.anchor_left = 1.0
		send_btn.anchor_top = bottom_anchor
		send_btn.anchor_right = 1.0
		send_btn.anchor_bottom = bottom_anchor
		send_btn.margin_left = -160
		send_btn.margin_right = -24
		send_btn.margin_top = 0
		send_btn.margin_bottom = font_size + 16
		send_btn.rect_min_size.y = font_size + 16
		
		if dynamic_font:
			send_btn.add_font_override("font", dynamic_font)
			
		control.add_child(send_btn)
		send_btn.connect("pressed", self, "_on_send_button_pressed")
	
	line_edit.connect("text_entered", self, "_on_text_entered")
	line_edit.connect("text_changed", self, "_on_text_changed")
	control.visible = false
	pause_mode = PAUSE_MODE_PROCESS
	
	add_command("quit", self, "quit", 0)
	add_command("exit", self, "quit", 0)
	add_command("gamemode", self, "set_gamemode", 1)
	add_command_autocomplete_list("gamemode", ["classic", "escalation", "0", "1"])
	add_command("help", self, "cmd_help", 0)
	add_command("clear", self, "cmd_clear", 0)
	add_command("cls", self, "cmd_clear", 0)
	add_command("status", self, "cmd_status", 0)
	add_command("volume", self, "cmd_volume", 2)
	add_command_autocomplete_list("volume", ["music", "sfx"])
	add_command("mute", self, "cmd_mute", 0)
	add_command("unmute", self, "cmd_unmute", 0)
	add_command("controls", self, "cmd_controls", 0)
	add_command("credits", self, "cmd_credits", 0)
	add_command("performance", self, "cmd_performance", 0)
	add_command("perf", self, "cmd_performance", 0)
	add_command("link", self, "cmd_link", 0)
	add_command("logout", self, "cmd_logout", 0)
	
	# Cheats (Classic Mode only in production builds)
	add_command("invincible", self, "cmd_invincible", 0)
	add_command("speed", self, "cmd_speed", 1)
	add_command_autocomplete_list("speed", ["0.5", "1.0", "1.5", "2.0", "2.5"])
	add_command("addscore", self, "cmd_addscore", 1)
	add_command_autocomplete_list("addscore", ["10", "50", "100", "500"])

	# Developer debug commands restricted to debug builds/editor runs
	if OS.is_debug_build():
		add_command("levelup", self, "cmd_levelup", 0)
		add_command("lvlup", self, "cmd_levelup", 0)
		add_command("set_level", self, "cmd_set_level", 1)
		add_command("set_lvl", self, "cmd_set_level", 1)
		add_command("heal", self, "cmd_heal", 0)
		add_command("kill", self, "cmd_kill", 0)
		add_command("restart", self, "cmd_restart", 0)
		add_command("timescale", self, "cmd_timescale", 1)
		add_command("clear_stats", self, "cmd_clear_stats", 1)
		add_command("reset_guest", self, "cmd_reset_guest", 0)
		add_command("delete_guest", self, "cmd_delete_guest", 1)
		add_command("profile", self, "cmd_profile", 0)
		
		add_command_autocomplete_list("timescale", ["0.25", "0.5", "1.0", "2.0", "3.0"])
		add_command_autocomplete_list("set_level", ["1", "5", "10", "15", "20"])
		add_command_autocomplete_list("set_lvl", ["1", "5", "10", "15", "20"])
		add_command_autocomplete_list("clear_stats", ["confirm"])
		add_command_autocomplete_list("delete_guest", ["confirm"])


func _is_mobile_web_device() -> bool:
	if OS.has_feature("HTML5") or OS.has_feature("JavaScript"):
		var js_is_desktop = JavaScript.eval("/Windows|Macintosh|Linux/i.test(navigator.userAgent) && !/Mobi|Android|Tablet|iPad|iPhone/i.test(navigator.userAgent)")
		return not js_is_desktop
	return false

func handle_mobile_tap(pos: Vector2):
	if _is_mobile_web_device() or control.visible:
		return
	if pos.x <= 200 and pos.y <= 200:
		var current_time = OS.get_ticks_msec()
		if current_time - mobile_last_tap_time < 500:
			mobile_tap_count += 1
		else:
			mobile_tap_count = 1
		mobile_last_tap_time = current_time
		
		if mobile_tap_count >= 5:
			mobile_tap_count = 0
			toggle_console()


func _input(event : InputEvent):
	if _is_mobile_web_device():
		return
		
	if event is InputEventScreenTouch and event.pressed:
		if control.visible:
			var line_edit_bottom = line_edit.rect_global_position.y + line_edit.rect_size.y
			if event.position.y > line_edit_bottom + 10:
				toggle_console()
				get_tree().set_input_as_handled()
				return
		else:
			handle_mobile_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		if control.visible:
			var line_edit_bottom = line_edit.rect_global_position.y + line_edit.rect_size.y
			if event.position.y > line_edit_bottom + 10:
				toggle_console()
				get_tree().set_input_as_handled()
				return
		else:
			handle_mobile_tap(event.position)

	if (event is InputEventKey):
		if (event.physical_scancode == 96): # Reverse-nice.  Also ~ key.
			if (event.pressed):
				toggle_console()
			get_tree().set_input_as_handled()
		elif (event.physical_scancode == KEY_ESCAPE && control.visible): # Disable console on ESC
			if (event.pressed):
				toggle_console()
				get_tree().set_input_as_handled()
	if (control.visible):
		if (event.is_action_pressed("ui_up")):
			get_tree().set_input_as_handled()
			if (console_history_index > 0):
				console_history_index -= 1
				if (console_history_index >= 0):
					line_edit.text = console_history[console_history_index]
					line_edit.caret_position = line_edit.text.length()
					reset_autocomplete()
		if (event.is_action_pressed("ui_down")):
			if (console_history_index < console_history.size()):
				console_history_index += 1
				if (console_history_index < console_history.size()):
					line_edit.text = console_history[console_history_index]
					line_edit.caret_position = line_edit.text.length()
					reset_autocomplete()
				else:
					line_edit.text = ""
					reset_autocomplete()
		if (event is InputEventKey && event.is_pressed()):
			if (event.get_physical_scancode_with_modifiers() == KEY_TAB):
				autocomplete()
				get_tree().get_root().set_input_as_handled()



func toggle_console():
	if _is_mobile_web_device():
		return
		
	if not control.visible:
		var main_node = get_tree().root.get_node_or_null("Main")
		if is_instance_valid(main_node) and main_node.mode_level == 1:
			if not OS.is_debug_build() or ProjectSettings.has_setting("global/mock_release_cheats"):
				return

	control.visible = !control.visible
	if (control.visible):
		get_tree().paused = true
		line_edit.grab_focus()
		emit_signal("console_opened")
	else:
		get_tree().paused = false
		reset_autocomplete()
		emit_signal("console_closed")


func print_line(text : String):
	if (!rich_label): # Tried to print something before the console was loaded.
		call_deferred("print_line", text)
	else:
		rich_label.append_bbcode(text)
		rich_label.append_bbcode("\n")


func _on_text_entered(text : String):
	line_edit.clear()
	reset_autocomplete()
	add_input_history(text)
	print_line(text)
	var split_text := text.split(" ", true)
	if (split_text.size() > 0):
		var command_string := split_text[0].to_lower()
		if (console_commands.has(command_string)):
			var command_entry : ConsoleCommand = console_commands[command_string]
			match command_entry.param_count:
				0:
					command_entry.function.call_func()
				1:
					command_entry.function.call_func(split_text[1] if split_text.size() > 1 else "")
				2:
					command_entry.function.call_func(split_text[1] if split_text.size() > 1 else "", split_text[2] if split_text.size() > 2 else "")
				3:
					command_entry.function.call_func(split_text[1] if split_text.size() > 1 else "", split_text[2] if split_text.size() > 2 else "", split_text[3] if split_text.size() > 3 else "")
				_:
					print_line("Commands with more than 3 parameters not supported.")
		else:
			emit_signal("console_unknown_command")
			print_line("Command not found.")


func _on_text_changed(text : String):
	reset_autocomplete()


func _on_send_button_pressed():
	var text = line_edit.text
	_on_text_entered(text)


func add_command(command_name : String, object : Object, function_name : String, param_count : int = 0):
	console_commands[command_name] = ConsoleCommand.new(funcref(object, function_name), param_count)


## Removes a command from the console.  This should be called on a script's _exit_tree()
## if you have console commands for things that are unloaded before the project closes.
func remove_command(command_name : String):
	console_commands.erase(command_name)
	command_parameters.erase(command_name)


func quit():
	get_tree().quit()


func set_gamemode(mode_str: String = ""):
	mode_str = mode_str.to_lower().strip_edges()
	if mode_str == "":
		var main_node = get_tree().root.get_node_or_null("Main")
		var current_mode_name = "Classic" if Global.current_mode == 0 else "Escalation"
		if is_instance_valid(main_node):
			current_mode_name = main_node.get_mode_string()
		print_line("Current game mode is: " + current_mode_name)
		print_line("Usage: gamemode <classic|escalation|0|1>")
		return

	var mode = -1
	if mode_str == "classic" or mode_str == "0":
		mode = 0
	elif mode_str == "escalation" or mode_str == "1":
		mode = 1
	else:
		print_line("Invalid mode: '" + mode_str + "'")
		print_line("Usage: gamemode <classic|escalation|0|1>")
		return
	
	Global.current_mode = mode
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		main_node.mode_level = mode
		if main_node.has_method("update_mode_button_text"):
			main_node.update_mode_button_text()
		if main_node.has_method("update_score_display"):
			main_node.update_score_display()
		
		# If game is already running, notify player
		if main_node.game_playing:
			print_line("Game mode set to: " + ("Classic" if mode == 0 else "Escalation") + ". Restart the game to apply.")
		else:
			print_line("Game mode set to: " + ("Classic" if mode == 0 else "Escalation"))
	else:
		print_line("Game mode set to: " + ("Classic" if mode == 0 else "Escalation"))


func check_cheat_allowed() -> bool:
	var main_node = get_tree().root.get_node_or_null("Main")
	if not is_instance_valid(main_node):
		print_line("Error: Main node not found.")
		return false
	if OS.is_debug_build() and not ProjectSettings.has_setting("global/mock_release_cheats"):
		main_node.cheats_used = true
		var score_node = main_node.get_node_or_null("UI/Control/Score")
		if is_instance_valid(score_node):
			score_node.modulate = Color(1.0, 0.4, 0.4)
		return true
	if main_node.mode_level != 0:
		print_line("Error: This cheat command is restricted to Classic Mode.")
		return false
	main_node.cheats_used = true
	var score_node = main_node.get_node_or_null("UI/Control/Score")
	if is_instance_valid(score_node):
		score_node.modulate = Color(1.0, 0.4, 0.4)
	return true


func cmd_invincible():
	if not check_cheat_allowed():
		return
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		var bird = main_node.get_node_or_null("Bird")
		if is_instance_valid(bird):
			var new_state = !bird.is_invincible
			bird.set_invincible(new_state)
			print_line("Invincibility: " + ("ON" if new_state else "OFF"))
		else:
			print_line("Error: Bird node not found.")
	else:
		print_line("Error: Main node not found.")


func cmd_levelup():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		if main_node.game_playing:
			if main_node.mode_level == 1:
				var time_skipped = main_node.time_to_next_level - main_node.level_time_survived
				var sim_delta = 0.1
				var steps = int(time_skipped / sim_delta)
				var MAX_SPEED = 2.5
				for _i in range(steps):
					main_node.game_speed += (MAX_SPEED - main_node.game_speed) * 0.003 * sim_delta
				main_node.level_time_survived = main_node.time_to_next_level
				print_line("Leveled up to Level " + str(main_node.current_speed_level + 1))
			else:
				print_line("Leveling up is only supported in Escalation mode.")
		else:
			print_line("Error: Game is not playing.")
	else:
		print_line("Error: Main node not found.")


func cmd_heal():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		if main_node.game_playing:
			main_node.current_health = main_node.max_health
			main_node.update_health_display()
			if main_node.has_method("trigger_health_refill_animation"):
				main_node.trigger_health_refill_animation()
			print_line("Health fully restored.")
		else:
			print_line("Error: Game is not playing.")
	else:
		print_line("Error: Main node not found.")


func cmd_addscore(amount_str: String = ""):
	if not check_cheat_allowed():
		return
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		if main_node.game_playing:
			var amount = 10
			if amount_str != "":
				amount = int(amount_str)
				if amount <= 0:
					print_line("Usage: addscore [amount]")
					return
			main_node.score += amount
			main_node.update_score_display()
			print_line("Added " + str(amount) + " points to score. New score: " + str(main_node.score))
		else:
			print_line("Error: Game is not playing.")
	else:
		print_line("Error: Main node not found.")


func cmd_kill():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		var bird = main_node.get_node_or_null("Bird")
		if is_instance_valid(bird):
			if main_node.game_playing and not bird.is_dead:
				bird.die()
				print_line("Killed the bird.")
			else:
				print_line("Bird is already dead or game not playing.")
		else:
			print_line("Error: Bird node not found.")
	else:
		print_line("Error: Main node not found.")


func cmd_speed(speed_str: String = ""):
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		if speed_str == "":
			print_line("Current game speed multiplier: " + str(main_node.game_speed))
			print_line("Usage: speed <multiplier>")
			return
		if not check_cheat_allowed():
			return
		var speed_val = float(speed_str)
		if speed_val <= 0.0:
			print_line("Error: Speed must be positive.")
			return
		main_node.game_speed = speed_val
		print_line("Game speed multiplier set to: " + str(speed_val))
	else:
		print_line("Error: Main node not found.")


func cmd_clear():
	rich_label.text = ""


func cmd_help():
	print_line("[b]=== DEV CONSOLE COMMANDS HELP ===[/b]\n")
	
	print_line("[color=#88ccff][b]SYSTEM & GENERAL[/b][/color]")
	print_line("  [b]help[/b] - Shows this list.")
	print_line("  [b]clear[/b] / [b]cls[/b] - Clears the console window.")
	print_line("  [b]performance[/b] / [b]perf[/b] - Toggle performance monitor overlay.")
	print_line("  [b]controls[/b] - List keyboard/screen controls.")
	print_line("  [b]credits[/b] - Show credits.")
	print_line("  [b]status[/b] - Shows network, system, and sync status report.")
	print_line("  [b]link[/b] - Open player profile / login panel.")
	print_line("  [b]logout[/b] - Log out from profile and switch to a guest session.")
	print_line("  [b]quit[/b] / [b]exit[/b] - Close the game.\n")
	
	print_line("[color=#a2f5a2][b]GAMEPLAY[/b][/color]")
	print_line("  [b]gamemode [classic|escalation][/b] - Set active game mode.\n")
	
	print_line("[color=#ffddaa][b]AUDIO[/b][/color]")
	print_line("  [b]volume [music|sfx] [0-100][/b] - Set volume of music or SFX.")
	print_line("  [b]mute[/b] - Mutes all game audio.")
	print_line("  [b]unmute[/b] - Restores volume to 100%.\n")
	
	print_line("[color=#ff8888][b]CHEATS (Classic Mode only)[/b][/color]")
	print_line("  [b]invincible[/b] - Toggle bird's invincibility.")
	print_line("  [b]speed [multiplier][/b] - Set game speed multiplier (e.g. 1.5).")
	print_line("  [b]addscore [amount][/b] - Add score points (default 10).\n")
	
	if OS.is_debug_build():
		print_line("[color=#e088ff][b]DEBUG ONLY[/b][/color]")
		print_line("  [b]levelup[/b] / [b]lvlup[/b] - Skip level in Escalation mode.")
		print_line("  [b]set_level[/b] / [b]set_lvl [number][/b] - Skip directly to a level.")
		print_line("  [b]heal[/b] - Refill health to max.")
		print_line("  [b]kill[/b] - Instantly kill the bird.")
		print_line("  [b]timescale [scale][/b] - Set engine speed (e.g. 0.5).")
		print_line("  [b]restart[/b] - Restart game session.")
		print_line("  [b]clear_stats [confirm][/b] - Reset all high scores and stats.")
		print_line("  [b]reset_guest[/b] - Wipes local stats and creates a new anonymous Firebase profile.")
		print_line("  [b]delete_guest [confirm][/b] - Wipes local stats, deletes user from all Firestore collections, and deletes Auth user account.")
		print_line("  [b]profile[/b] - Prints player stats, name, Firebase UID, and auth status.\n")


func cmd_volume(target_str: String = "", val_str: String = ""):
	var main_node = get_tree().root.get_node_or_null("Main")
	if not is_instance_valid(main_node):
		print_line("Error: Main node not found.")
		return
		
	target_str = target_str.to_lower().strip_edges()
	val_str = val_str.strip_edges()
	
	if target_str == "":
		var music_pct = int(main_node.music_volume * 100.0)
		var sfx_status = "ENABLED (100%)" if main_node.sfx_enabled else "MUTED (0%)"
		print_line("Current volume settings:")
		print_line("- Music: " + str(music_pct) + "%")
		print_line("- SFX: " + sfx_status)
		print_line("Usage: volume [music|sfx] [0-100]")
		return
		
	if target_str != "music" and target_str != "sfx":
		print_line("Invalid volume target: '" + target_str + "'")
		print_line("Usage: volume [music|sfx] [0-100]")
		return
		
	if val_str == "":
		print_line("Error: Please specify a volume value from 0 to 100.")
		print_line("Usage: volume " + target_str + " [0-100]")
		return
		
	var val = int(val_str)
	if val < 0 or val > 100:
		print_line("Error: Volume value must be between 0 and 100.")
		return
		
	var linear_val = float(val) / 100.0
	
	if target_str == "music":
		main_node.music_volume = linear_val
		var raw_db = linear2db(linear_val) if linear_val > 0.001 else -80.0
		var db = raw_db - 10.0 if raw_db > -79.0 else -80.0
		if is_instance_valid(main_node.main_menu_bgm):
			main_node.main_menu_bgm.set_volume_db(db)
		
		# Sync SettingsPanel Slider if open
		if is_instance_valid(main_node.settings_panel):
			var slider = main_node.settings_panel.get_node_or_null("MusicSliderAnchor/MusicSlider")
			if slider and slider.has_method("set_value"):
				slider.set_value(linear_val)
				
		main_node.save_hiscore()
		print_line("Music volume set to " + str(val) + "%")
	else: # sfx
		var enabled = val > 0
		main_node.sfx_enabled = enabled
		main_node._apply_sfx_volume()
		
		# Sync SettingsPanel Toggle if open
		if is_instance_valid(main_node.settings_panel):
			var toggle = main_node.settings_panel.get_node_or_null("SfxToggleAnchor/SfxToggle")
			if toggle and toggle.has_method("set_on"):
				toggle.set_on(enabled)
				
		main_node.save_hiscore()
		print_line("SFX volume set to " + str(val) + "% (Status: " + ("ENABLED" if enabled else "MUTED") + ")")


func cmd_mute():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		main_node.music_volume = 0.0
		if is_instance_valid(main_node.main_menu_bgm):
			main_node.main_menu_bgm.set_volume_db(-80.0)
		
		main_node.sfx_enabled = false
		main_node._apply_sfx_volume()
		
		if is_instance_valid(main_node.settings_panel):
			var slider = main_node.settings_panel.get_node_or_null("MusicSliderAnchor/MusicSlider")
			if slider and slider.has_method("set_value"):
				slider.set_value(0.0)
			var toggle = main_node.settings_panel.get_node_or_null("SfxToggleAnchor/SfxToggle")
			if toggle and toggle.has_method("set_on"):
				toggle.set_on(false)
				
		main_node.save_hiscore()
		print_line("All audio muted.")
	else:
		print_line("Error: Main node not found.")


func cmd_unmute():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		main_node.music_volume = 1.0
		var raw_db = linear2db(1.0)
		var db = raw_db - 10.0
		if is_instance_valid(main_node.main_menu_bgm):
			main_node.main_menu_bgm.set_volume_db(db)
			
		main_node.sfx_enabled = true
		main_node._apply_sfx_volume()
		
		if is_instance_valid(main_node.settings_panel):
			var slider = main_node.settings_panel.get_node_or_null("MusicSliderAnchor/MusicSlider")
			if slider and slider.has_method("set_value"):
				slider.set_value(1.0)
			var toggle = main_node.settings_panel.get_node_or_null("SfxToggleAnchor/SfxToggle")
			if toggle and toggle.has_method("set_on"):
				toggle.set_on(true)
				
		main_node.save_hiscore()
		print_line("Audio unmuted (Volume restored to 100%).")
	else:
		print_line("Error: Main node not found.")


func cmd_controls():
	print_line("--- GAME CONTROLS ---")
	print_line("Jump / Navigate: Spacebar (Keyboard) or Touch Screen (Mobile)")
	print_line("Toggle Console: Tilde / Backtick key (~ or `)")
	print_line("Close Console: Escape key (ESC)")
	print_line("Command Autocomplete: Tab key")
	print_line("Command History: Up / Down Arrow keys")


func cmd_credits():
	print_line("--- RUSHY BIRD CREDITS ---")
	print_line("Game Development: Rezaye Rabbi")
	print_line("Co-programming & Mentor: Johnny Rouddro")
	print_line("Art & Assets: Borna Barua")
	print_line("Thank you for playing Rushy Bird!")


func cmd_set_level(level_str: String = ""):
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		if level_str == "":
			print_line("Current speed level: " + str(main_node.current_speed_level))
			print_line("Usage: set_level <level_number>")
			return
		
		var level_val = int(level_str)
		if level_val < 1:
			print_line("Error: Level must be 1 or higher.")
			return
			
		if not main_node.game_playing:
			print_line("Error: Game is not playing.")
			return
			
		if main_node.mode_level != 1:
			print_line("Error: set_level is only supported in Escalation mode.")
			return
			
		main_node.current_speed_level = level_val
		main_node.level_time_survived = 0.0
		main_node.time_to_next_level = min(45.0, 30.0 + 5.0 * (level_val - 1))
		
		var target_speed = 1.0 + (1.5 * (1.0 - exp(-0.08 * (level_val - 1))))
		main_node.game_speed = target_speed
		
		if main_node.level_label:
			main_node.level_label.text = "LEVEL " + str(level_val)
		if main_node.has_method("trigger_health_refill_animation"):
			main_node.trigger_health_refill_animation()
		if is_instance_valid(main_node.level_change_sound):
			main_node.level_change_sound.play()
			
		print_line("Skipped to Level " + str(level_val) + " (Game Speed set to: " + str(stepify(target_speed, 0.01)) + ")")
	else:
		print_line("Error: Main node not found.")


func cmd_restart():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		if main_node.has_method("_on_Button3_pressed"):
			main_node.call_deferred("_on_Button3_pressed")
		else:
			get_tree().reload_current_scene()
			get_tree().paused = false
	else:
		get_tree().reload_current_scene()
		get_tree().paused = false
	print_line("Reloading scene...")
	toggle_console()


func cmd_timescale(scale_str: String = ""):
	if scale_str == "":
		print_line("Current Engine time_scale: " + str(Engine.time_scale))
		print_line("Usage: timescale <scale>")
		return
	var scale_val = float(scale_str)
	if scale_val <= 0.0:
		print_line("Error: Scale must be positive.")
		return
	Engine.time_scale = scale_val
	print_line("Engine time_scale set to: " + str(scale_val))


func cmd_clear_stats(confirm_str: String = ""):
	confirm_str = confirm_str.to_lower().strip_edges()
	if confirm_str != "confirm":
		print_line("[color=#ff4444]WARNING: This will permanently delete all saved high scores, statistics, and settings from this machine![/color]")
		print_line("To proceed, type: [color=#ffff66]clear_stats confirm[/color]")
		return
		
	var dir = Directory.new()
	if dir.file_exists("user://save_game.dat"):
		dir.remove("user://save_game.dat")
	if dir.file_exists("user://save_game.dat.bak"):
		dir.remove("user://save_game.dat.bak")
	if dir.file_exists("user://player_data_rushybird.dat"):
		dir.remove("user://player_data_rushybird.dat")
	
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		main_node.player_data = {
			"player_name": Global.player_name,
			"classic_highscore": 0,
			"escalation_highscore": 0,
			"escalation_highest_level": 1,
			"total_games": 0,
			"playtime": 0.0,
			"total_deaths": 0,
			"total_revives": 0,
			"total_distance": 0.0,
			"is_registered": false,
			"last_updated": 0,
			"has_changed_name_logged_in": false
		}
		main_node.score = 0
		main_node.update_score_display()
		if main_node.has_method("update_health_display"):
			main_node.update_health_display()
		main_node.save_hiscore()
	print_line("All saved data and high scores have been successfully deleted.")


func cmd_reset_guest():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		randomize()
		Global.player_name = "Player" + str(randi() % 900000 + 100000)
		Global.has_changed_name = false
		main_node.player_data = {
			"player_name": Global.player_name,
			"classic_highscore": 0,
			"escalation_highscore": 0,
			"escalation_highest_level": 1,
			"total_games": 0,
			"playtime": 0.0,
			"total_deaths": 0,
			"total_revives": 0,
			"total_distance": 0.0,
			"is_registered": false,
			"last_updated": 0,
			"has_changed_name_logged_in": false
		}
		main_node.score = 0
		main_node.update_score_display()
		if main_node.has_method("update_health_display"):
			main_node.update_health_display()
			
		# Reset Firebase Auth session and clear local credentials
		if Firebase.Auth.has_method("remove_auth"):
			Firebase.Auth.remove_auth()
		Firebase.Auth.auth = {}
		FirebaseManager.user_id = ""
		FirebaseManager.is_logged_in = false
		Firebase.Auth.login_anonymous()
		
		main_node.save_hiscore()
		print_line("[color=#88ff88]Player name reset to: " + Global.player_name + "[/color]")
		print_line("[color=#88ff88]Player name and stats have been completely cleared.[/color]")
		print_line("[color=#88ff88]Firebase session reset; logging in anonymously...[/color]")
		print_line("[color=#88ff88]You will now appear as a brand new player on the leaderboard.[/color]")
	else:
		print_line("Error: Main node not found.")


func cmd_delete_guest(confirm_str: String = ""):
	confirm_str = confirm_str.to_lower().strip_edges()
	if confirm_str != "confirm":
		print_line("[color=#ff4444]WARNING: This will permanently delete your player data from Firestore, clear your leaderboard entries, and delete your Firebase account![/color]")
		print_line("To proceed, type: [color=#ffff66]delete_guest confirm[/color]")
		return

	var uid = FirebaseManager.get_current_user_id()
	if uid == "":
		print_line("Error: No authenticated user session found.")
		return
		
	print_line("[color=#ff8888]Initiating complete deletion of current user...[/color]")
	
	# 1. Delete associated Firestore documents
	print_line("Deleting Firestore documents...")
	
	var alltime_col = Firebase.Firestore.collection("leaderboard_rushybird_alltime")
	FirebaseManager._delete_doc(alltime_col, uid)
	yield(FirebaseManager, "delete_completed")
	print_line("Deleted from leaderboard_rushybird_alltime.")
	
	var seasonal_col = Firebase.Firestore.collection("leaderboard_rushybird_seasonal")
	FirebaseManager._delete_doc(seasonal_col, uid)
	yield(FirebaseManager, "delete_completed")
	print_line("Deleted from leaderboard_rushybird_seasonal.")
	
	var stats_col = Firebase.Firestore.collection("player_data_rushybird")
	FirebaseManager._delete_doc(stats_col, uid)
	yield(FirebaseManager, "delete_completed")
	print_line("Deleted from player_data_rushybird.")
	
	# 2. Delete the user account from Firebase Authentication
	print_line("Deleting Auth account from Firebase Authentication...")
	Firebase.Auth.delete_user_account()
	var auth_result : Array = yield(Firebase.Auth, "auth_request")
	if auth_result.size() > 0 and (auth_result[0] == 1 or str(auth_result[0]) == "1"):
		print_line("Auth account deletion finished successfully.")
	else:
		var err_content = auth_result[1] if auth_result.size() > 1 else "Unknown"
		print_line("Auth account deletion failed. Error: " + str(err_content))
	
	# 3. Reset local stats and save files (like in reset_guest)
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		randomize()
		Global.player_name = "Player" + str(randi() % 900000 + 100000)
		Global.has_changed_name = false
		main_node.player_data = {
			"player_name": Global.player_name,
			"classic_highscore": 0,
			"escalation_highscore": 0,
			"escalation_highest_level": 1,
			"total_games": 0,
			"playtime": 0.0,
			"total_deaths": 0,
			"total_revives": 0,
			"total_distance": 0.0,
			"is_registered": false,
			"last_updated": 0,
			"has_changed_name_logged_in": false
		}
		main_node.score = 0
		main_node.update_score_display()
		if main_node.has_method("update_health_display"):
			main_node.update_health_display()
			
		main_node.save_hiscore()
		
	# 4. Reset Firebase Auth session and clear local credentials
	if Firebase.Auth.has_method("remove_auth"):
		Firebase.Auth.remove_auth()
	Firebase.Auth.auth = {}
	FirebaseManager.user_id = ""
	FirebaseManager.is_logged_in = false
	Firebase.Auth.login_anonymous()
	
	print_line("[color=#88ff88]Player name reset to: " + Global.player_name + "[/color]")
	print_line("[color=#88ff88]Local stats cleared and anonymous session restarted successfully.[/color]")


func cmd_profile():
	var main_node = get_tree().root.get_node_or_null("Main")
	if not is_instance_valid(main_node):
		print_line("Error: Main node not found.")
		return
		
	print_line("--- CURRENT PROFILE & STATS ---")
	
	var p_name = Global.player_name
	if p_name == "":
		p_name = "[None - Will prompt on next High Score]"
	
	var name_status = " (Default Guest)"
	if Global.has_changed_name:
		name_status = " (Modified/Set)"
	print_line("Player Name: " + p_name + name_status)
	
	var my_uid = FirebaseManager.get_current_user_id()
	var all_time_rank_str = "N/A"
	var seasonal_rank_str = "N/A"
	if my_uid != "":
		var idx = 0
		for entry in FirebaseManager._temp_all_time:
			if entry.get("uid", "") == my_uid:
				all_time_rank_str = "#" + str(idx + 1)
				break
			idx += 1
		
		idx = 0
		for entry in FirebaseManager._temp_seasonal:
			if entry.get("uid", "") == my_uid:
				seasonal_rank_str = "#" + str(idx + 1)
				break
			idx += 1
			
	print_line("All-Time Rank: " + all_time_rank_str)
	print_line("Seasonal Rank: " + seasonal_rank_str)
	
	var player_data = main_node.player_data
	print_line("Total Games Played: " + str(player_data.get("total_games", 0)))
	print_line("High Score: " + str(main_node.get_highscore(main_node.mode_level)))
	print_line("Highest Level: " + str(main_node.get_highest_level(main_node.mode_level)))
	print_line("Total Deaths: " + str(player_data.get("total_deaths", 0)))
	print_line("Total Revives: " + str(player_data.get("total_revives", 0)))
	print_line("Distance Traveled: %.1f m" % player_data.get("total_distance", 0.0))
	print_line("Playtime: %.1f min" % (player_data.get("playtime", 0.0) / 60.0))
	
	var email = ""
	var is_guest = true
	if FirebaseManager.is_logged_in and Firebase.Auth.auth:
		email = Firebase.Auth.auth.get("email", "")
		
	var auth_status = ""
	if email != "":
		is_guest = false
		
	if FirebaseManager.is_logged_in:
		if email != "":
			auth_status = "[color=#88ff88]Authenticated (" + email + ")[/color]"
		else:
			auth_status = "[color=#88ff88]Authenticated (Guest)[/color]"
	else:
		auth_status = "[color=#ff8888]Not Authenticated / Connecting...[/color]"
		
	print_line("Firebase UID: " + (my_uid if my_uid != "" else "Connecting..."))
	print_line("Authentication Status: " + auth_status)
	
	var last_synced_str = "Never"
	if main_node.last_sync_timestamp > 0:
		var local_offset = main_node.get_local_timezone_offset()
		var t = OS.get_datetime_from_unix_time(main_node.last_sync_timestamp + local_offset)
		var ampm = "AM"
		var hr = t.hour
		if hr >= 12:
			ampm = "PM"
			if hr > 12:
				hr -= 12
		elif hr == 0:
			hr = 12
		last_synced_str = "%02d-%02d-%04d %02d:%02d:%02d %s" % [t.day, t.month, t.year, hr, t.minute, t.second, ampm]
		
	print_line("Last Synced: " + last_synced_str)
	if is_guest:
		print_line("[color=#aaaaaa]Note: Guest user data will be reset if the browser data is cleared.[/color]")

func add_input_history(text : String):
	if (!console_history.size() || text != console_history.back()): # Don't add consecutive duplicates
		console_history.append(text)
	console_history_index = console_history.size()


func _enter_tree():
	var console_history_file := File.new()
	if (console_history_file.open("user://console_history.txt", File.READ) == OK):
		while (!console_history_file.eof_reached()):
			var line := console_history_file.get_line()
			if (line.length()):
				add_input_history(line)
		console_history_file.close()


func _exit_tree():
	var console_history_file := File.new()
	if (console_history_file.open("user://console_history.txt", File.WRITE) == OK):
		var write_index := 0
		var start_write_index := console_history.size() - 100 # Max lines to write
		for line in console_history:
			if (write_index >= start_write_index):
				console_history_file.store_line(line)
			write_index += 1
		console_history_file.close()


var suggestions := []
var current_suggest := 0
var suggesting := false

func autocomplete() -> void:
	if (suggesting):
		for i in range(suggestions.size()):
			if (current_suggest == i):
				line_edit.text = str(suggestions[i])
				line_edit.caret_position = line_edit.text.length()
				if (current_suggest == suggestions.size() - 1):
					current_suggest = 0
				else:
					current_suggest += 1
				return
	else:
		suggesting = true

		if (" " in line_edit.text): # We're searching for a parameter to autocomplete
			var split_text := parse_line_input(line_edit.text)
			if (split_text.size() > 1):
				var command := split_text[0]
				var param_input := split_text[1]
				if (command_parameters.has(command)):
					for param in command_parameters[command]:
						if (param_input in param):
							suggestions.append(str(command, " ", param))
		else:
			var sorted_commands := []
			for command in console_commands:
				if (!console_commands[command].hidden):
					sorted_commands.append(str(command))
			sorted_commands.sort()
			sorted_commands.invert()

			var prev_index := 0
			for command in sorted_commands:
				if (!line_edit.text || (line_edit.text in command)):
					var index : int = command.find(line_edit.text)
					if (index <= prev_index):
						suggestions.push_front(command)
					else:
						suggestions.push_back(command)
					prev_index = index
		autocomplete()


func reset_autocomplete() -> void:
	suggestions.clear()
	current_suggest = 0
	suggesting = false


func parse_line_input(text : String) -> PoolStringArray:
	var out_array : PoolStringArray
	var first_char := true
	var in_quotes := false
	var escaped := false
	var token : String
	for c in text:
		if (c == '\\'):
			escaped = true
			continue
		elif (escaped):
			if (c == 'n'):
				c = '\n'
			elif (c == 't'):
				c = '\t'
			elif (c == 'r'):
				c = '\r'
			elif (c == 'a'):
				c = '\a'
			elif (c == 'b'):
				c = '\b'
			elif (c == 'f'):
				c = '\f'
			escaped = false
		elif (c == '\"'):
			in_quotes = !in_quotes
			continue
		elif (c == ' ' || c == '\t'):
			if (!in_quotes):
				out_array.push_back(token)
				token = ""
				continue
		token += c
	out_array.push_back(token)
	return out_array


## Useful if you have a list of possible parameters (ex: level names).
func add_command_autocomplete_list(command_name : String, param_list : PoolStringArray):
	command_parameters[command_name] = param_list


func get_one_percent_low_fps() -> float:
	if frame_times.empty():
		return 0.0
	
	var sorted_times = frame_times.duplicate()
	sorted_times.sort() # Ascending order (smallest delta to largest delta)
	
	var count = int(max(1, round(sorted_times.size() * 0.01)))
	var sum = 0.0
	for i in range(sorted_times.size() - count, sorted_times.size()):
		sum += sorted_times[i]
		
	var avg_delta = sum / count
	if avg_delta > 0.0:
		return 1.0 / avg_delta
	return 0.0


func _process(delta):
	# Track active gameplay frame times (when not paused)
	if not get_tree().paused:
		frame_times.append(delta)
		if frame_times.size() > MAX_FRAME_HISTORY:
			frame_times.pop_front()

	if is_instance_valid(perf_monitor) and perf_monitor.visible:
		var fps = Engine.get_frames_per_second()
		var low_fps = get_one_percent_low_fps()
		var main_node = get_tree().root.get_node_or_null("Main")
		
		var game_mode_str = "N/A"
		var health_str = "N/A"
		var speed_str = "1.00x"
		var level_str = "N/A"
		var progress_str = "N/A"
		var score_str = "0"
		
		if is_instance_valid(main_node):
			game_mode_str = main_node.get_mode_string()
			score_str = str(main_node.score)
			speed_str = "%.2fx" % main_node.game_speed
			if main_node.mode_level == 1:
				health_str = "%d / %d" % [main_node.current_health, main_node.max_health]
				level_str = str(main_node.current_speed_level)
				progress_str = "%.1f%%" % ((main_node.level_time_survived / main_node.time_to_next_level) * 100.0)
		
		if OS.is_debug_build():
			var mem = OS.get_static_memory_usage() / 1024.0 / 1024.0
			var peak_mem = Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0 / 1024.0
			var vram = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1024.0 / 1024.0
			var draw_calls = Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)
			var vertices = Performance.get_monitor(Performance.RENDER_VERTICES_IN_FRAME)
			var nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			var orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
			
			var line1 = "FPS: %d (1%% Low: %d)   |   RAM: %.1f MB (Peak: %.1f MB)" % [fps, int(low_fps), mem, peak_mem]
			var line2 = "VRAM: %.1f MB   |   Draws: %d   |   Verts: %d" % [vram, draw_calls, vertices]
			var line3 = "Nodes: %d   |   Orphans: %d   |   Res: %dx%d" % [nodes, orphans, OS.window_size.x, OS.window_size.y]
			var line4 = "Mode: %s   |   Lvl: %s   |   Prog: %s" % [game_mode_str, level_str, progress_str]
			var line5 = "Spd: %s   |   Score: %s   |   Health: %s" % [speed_str, score_str, health_str]
			
			perf_label.text = line1 + "\n" + line2 + "\n" + line3 + "\n" + line4 + "\n" + line5
		else:
			var line1 = "FPS: %d (1%% Low: %d)   |   Mode: %s" % [fps, int(low_fps), game_mode_str]
			var line2 = "Lvl: %s   |   Prog: %s   |   Spd: %s" % [level_str, progress_str, speed_str]
			var line3 = "Score: %s   |   Health: %s" % [score_str, health_str]
			
			perf_label.text = line1 + "\n" + line2 + "\n" + line3


func cmd_performance():
	if is_instance_valid(perf_monitor):
		perf_monitor.visible = !perf_monitor.visible
		print_line("Performance monitor: " + ("ENABLED" if perf_monitor.visible else "DISABLED"))
	else:
		print_line("Error: Performance monitor overlay not initialized.")


func cmd_link():
	var is_linked = false
	var email = ""
	if FirebaseManager.is_logged_in and Firebase.Auth.auth:
		email = Firebase.Auth.auth.get("email", "")
		if email != "":
			is_linked = true
			
	if is_linked:
		print_line("Account already linked/logged in: " + email)
		return

	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		if main_node.active_panel_name != "profile":
			main_node._on_ProfileButton_pressed()
		main_node._on_ClaimProfile_pressed()
		toggle_console()
		print_line("Opening profile linking panel.")
	else:
		print_line("Error: Main node not found.")


func cmd_logout():
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		main_node._on_Logout_pressed()
		print_line("Logged out successfully. User logged in anonymously.")
	else:
		Firebase.Auth.logout()
		FirebaseManager.is_logged_in = false
		FirebaseManager.user_id = ""
		var dir = Directory.new()
		if dir.file_exists("user://user.auth"):
			dir.remove("user://user.auth")
		Firebase.Auth.login_anonymous()
		print_line("Logged out from Firebase Manager.")


func cmd_status():
	print_line("[b]=== GAME & NETWORK STATUS REPORT ===[/b]\n")
	
	# 1. Technical & System Info
	print_line("[color=#88ccff][b]SYSTEM INFO[/b][/color]")
	print_line("  OS Platform: " + OS.get_name())
	var build_type = "Debug (Editor/Debug Run)" if OS.is_debug_build() else "Release"
	print_line("  Build Type: " + build_type)
	print_line("  Window Size: %dx%d" % [OS.window_size.x, OS.window_size.y])
	print_line("  FPS: %d" % Engine.get_frames_per_second())
	print_line("  Static Memory Usage: %.2f MB" % (OS.get_static_memory_usage() / 1024.0 / 1024.0))
	print_line("")

	# 2. Account & Authentication Status
	print_line("[color=#e088ff][b]ACCOUNT & AUTHENTICATION[/b][/color]")
	var auth_status = "Connected" if FirebaseManager.is_logged_in else "Disconnected"
	var auth_color = "#88ff88" if FirebaseManager.is_logged_in else "#ff8888"
	print_line("  Firebase Client: [color=%s]%s[/color]" % [auth_color, auth_status])
	
	var uid = FirebaseManager.get_current_user_id()
	if uid == "":
		print_line("  Firebase UID: [color=#ff8888]Not Authenticated[/color]")
	else:
		print_line("  Firebase UID: " + uid)
		
	var is_guest = true
	var email = ""
	if FirebaseManager.is_logged_in and Firebase.Auth.auth:
		email = Firebase.Auth.auth.get("email", "")
		if email != "":
			is_guest = false
			
	var account_type = "Guest Account (Anonymous)" if is_guest else "Linked Account (" + email + ")"
	print_line("  Account Type: " + account_type)
	
	if FirebaseManager.last_refresh_time > 0:
		var refresh_age = OS.get_unix_time() - FirebaseManager.last_refresh_time
		print_line("  Token Age: %d seconds (Last refreshed: %d)" % [refresh_age, FirebaseManager.last_refresh_time])
	else:
		print_line("  Token Age: Never Refreshed")
	print_line("")

	# 3. Connection & Configuration
	print_line("[color=#ffddaa][b]CONNECTION & CONFIG[/b][/color]")
	var config_status = "[color=#88ff88]Loaded[/color]" if FirebaseManager.is_config_available else "[color=#ff8888]Missing (.env not found)[/color]"
	print_line("  Firebase Config: " + config_status)
	var network_mode = "HTML5 Javascript Bridge (Web)" if OS.has_feature("JavaScript") else "Native Godot REST Client"
	print_line("  Connection Interface: " + network_mode)
	print_line("")

	# 4. Game State Info
	print_line("[color=#a2f5a2][b]GAME STATE[/b][/color]")
	var main_node = get_tree().root.get_node_or_null("Main")
	if is_instance_valid(main_node):
		var mode_name = main_node.get_mode_string()
		print_line("  Active Game Mode: " + mode_name)
		print_line("  Is Running: " + ("Yes" if main_node.game_playing else "No"))
		print_line("  Current Run Score: " + str(main_node.score))
		if main_node.mode_level == 1:
			print_line("  Current Level: " + str(main_node.current_speed_level))
		print_line("  Speed Multiplier: %.2fx" % main_node.game_speed)
		var cheats_color = "#ff8888" if main_node.cheats_used else "#88ff88"
		var cheats_status = "YES (Leaderboard ineligible)" if main_node.cheats_used else "NO"
		print_line("  Cheats Active: [color=%s]%s[/color]" % [cheats_color, cheats_status])
	else:
		print_line("  Error: Main game node not active.")
	print_line("")

	# 5. Cloud Sync Status
	print_line("[color=#ffff66][b]CLOUD SYNC[/b][/color]")
	if is_instance_valid(main_node):
		var sync_status = "Pending"
		if main_node.last_sync_attempted:
			if main_node.last_sync_success:
				var local_offset = main_node.get_local_timezone_offset()
				var t = OS.get_datetime_from_unix_time(main_node.last_sync_timestamp + local_offset)
				sync_status = "Synced at %02d:%02d:%02d" % [t.hour, t.minute, t.second]
			else:
				sync_status = "Sync Failed"
		print_line("  Score Sync Status: " + sync_status)
	else:
		print_line("  Score Sync Status: N/A")
	print_line("")
