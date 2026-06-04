extends Spatial

var score = 0
var hiscores = {0: 0, 1: 0}
var highest_levels = {0: 1, 1: 1}
var game_speed = 1.0

var stats = {
	"total_games": 0,
	"lifetime_score": 0,
	"playtime": 0.0,
	"total_jumps": 0,
	"total_deaths": 0,
	"total_revives": 0,
	"total_distance": 0.0
}
var game_playing = false
var mode_level = 0 # 0: OG, 1: Escalation
var storage_error_shown = false
var run_distance: float = 0.0
var run_max_speed: float = 1.0
var run_playtime: float = 0.0

var current_speed_level = 1
var level_time_survived = 0.0
var time_to_next_level = 25.0
var level_progress_bar: ProgressBar
var level_label: Label
var health_bar: HBoxContainer
var tex_health = preload("res://assets/textures/health.png")
var tex_health_blank = preload("res://assets/textures/health_blank.png")
var max_health = 3
var current_health = 3
var progression_pause_timer = 0.0
var speed_label: Label
var speed_tween: Tween
var menu_info_label: Label
var version_label: Label
var start_label: Label
var settings_button: Button
var stats_button: Button
var bottom_bar: Panel
var settings_panel: Panel
var game_over_panel: Panel
var leaderboard_panel: Panel
var logo_rect: TextureRect

var debug_mode_active: bool = false
var debug_label: Label

var music_volume: float = 1.0
var sfx_enabled: bool = true

var main_menu_bgm: AudioStreamPlayer
var game_over_bgm: AudioStreamPlayer
var ui_button_click: AudioStreamPlayer
var bird_jump: AudioStreamPlayer
var bird_collision: AudioStreamPlayer
var bird_fall: AudioStreamPlayer
var score_sound: AudioStreamPlayer
var bird_pop: AudioStreamPlayer
var level_change_sound: AudioStreamPlayer
var revive_sound: AudioStreamPlayer
var health_refill_sound: AudioStreamPlayer

func create_audio(node_name: String, path: String) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	player.name = node_name
	player.stream = load(path)
	player.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(player)
	return player

func _ready():
	# Warm up the DynamicFont cache on startup to prevent CPU spikes and audio stuttering on mobile web exports
	var warm_fonts = [
		[$UI/Control/Score, "0123456789+"],
		[$UI/Control/SpeedLabel, "LEVEL UP!OG MODE classic rules pure skill Escalation It gets faster Good luck"],
		[$UI/Control/MenuInfoLabel, "-1 HEALTH! YOUR BEST: (Lvl 1) OG"],
		[$UI/Control.get_node_or_null("LevelProgressBar/LevelLabel"), "LEVEL 0123456789"]
	]
	for item in warm_fonts:
		var node = item[0]
		if is_instance_valid(node):
			var font = node.get_font("font")
			if font is DynamicFont:
				for c in item[1]:
					font.get_char_size(ord(c))

	mode_level = Global.current_mode
	main_menu_bgm = create_audio("MainMenuBGM", "res://assets/sounds/main_menu_bgm.ogg")
	game_over_bgm = create_audio("GameOverBGM", "res://assets/sounds/game_over.ogg")
	ui_button_click = create_audio("UIButtonClick", "res://assets/sounds/ui_button_click.wav")
	bird_jump = create_audio("BirdJump", "res://assets/sounds/bird_jump.wav")
	bird_collision = create_audio("BirdCollision", "res://assets/sounds/bird_collision.wav")
	bird_fall = create_audio("BirdFall", "res://assets/sounds/fall.wav")
	score_sound = create_audio("ScoreSound", "res://assets/sounds/score.wav")
	bird_pop = create_audio("BirdPop", "res://assets/sounds/pop.wav")
	level_change_sound = create_audio("LevelChangeSound", "res://assets/sounds/level_change.wav")
	revive_sound = create_audio("ReviveSound", "res://assets/sounds/revive.wav")
	health_refill_sound = create_audio("HealthRefillSound", "res://assets/sounds/health_refill.wav")
	
	if game_over_bgm.stream is AudioStreamOGGVorbis:
		game_over_bgm.stream.loop = false
	
	load_hiscore() # Load before using music_volume
	
	var initial_db = linear2db(music_volume) if music_volume > 0.001 else -80.0
	# Apply standard -10 dB offset to prevent background music from overpowering the game
	var bgm_db = initial_db - 10.0 if initial_db > -79.0 else -80.0
	main_menu_bgm.volume_db = bgm_db
	
	_apply_sfx_volume()
	ui_button_click.volume_db = -6.0
	
	if not Global.auto_start:
		main_menu_bgm.play()

	$bg.start()
	$ScrollingPlatform.start()

	$UI/Control/PlayButton.connect("button_down", self, "_on_StartButton_down")
	$UI/Control/PlayButton.connect("button_up", self, "_on_StartButton_up")
	$UI/Control/PlayButton.connect("pressed", self, "_on_Button_pressed")
	
	$UI/Control/ModeButton.connect("pressed", self, "_on_ModeButton_pressed")
	$UI/Control/LeaderboardButton.connect("pressed", self, "_on_LeaderboardButton_pressed")
	$UI/Control/LeaderboardButton.connect("button_down", self, "_on_CircleButton_down", [$UI/Control/LeaderboardButton])
	$UI/Control/LeaderboardButton.connect("button_up", self, "_on_CircleButton_up", [$UI/Control/LeaderboardButton])
	$UI/Control/StatsButton.connect("pressed", self, "_on_StatsButton_pressed")
	$UI/Control/StatsButton.connect("button_down", self, "_on_CircleButton_down", [$UI/Control/StatsButton])
	$UI/Control/StatsButton.connect("button_up", self, "_on_CircleButton_up", [$UI/Control/StatsButton])
	$UI/Control/RestartButton.connect("pressed", self, "_on_Button2_pressed")
	$UI/Control/MainMenuButton.connect("pressed", self, "_on_Button3_pressed")
	
	$UI/Control/SettingsButton.connect("pressed", self, "_on_SettingsButton_pressed")
	$UI/Control/SettingsButton.connect("button_down", self, "_on_SettingsButton_down")
	$UI/Control/SettingsButton.connect("button_up", self, "_on_SettingsButton_up")
	
	$UI/Control/LeaderboardPanel/CloseLeaderboard.connect("pressed", self, "_on_CloseLeaderboard_pressed")
	$UI/Control/SettingsPanel/CloseSettings.connect("pressed", self, "_on_CloseSettings_pressed")
	$UI/Control/SettingsPanel/ResetButton.connect("pressed", self, "_on_RequestReset_pressed")
	$UI/Control/SettingsPanel/ConfirmPanel/YesButton.connect("pressed", self, "_on_ConfirmReset_Yes")
	$UI/Control/SettingsPanel/ConfirmPanel/NoButton.connect("pressed", self, "_on_ConfirmReset_No")
	
	var music_slider = CustomSlider.new(music_volume)
	music_slider.name = "MusicSlider"
	music_slider.anchor_right = 1.0
	music_slider.anchor_bottom = 1.0
	music_slider.connect("value_changed", self, "_on_MusicSlider_value_changed")
	$UI/Control/SettingsPanel/MusicSliderAnchor.add_child(music_slider)
	
	var sfx_button = CustomToggle.new(sfx_enabled)
	sfx_button.name = "SfxToggle"
	sfx_button.anchor_right = 1.0
	sfx_button.anchor_bottom = 1.0
	sfx_button.connect("toggled", self, "_on_SfxToggle_toggled")
	$UI/Control/SettingsPanel/SfxToggleAnchor.add_child(sfx_button)
	
	$UI/Control/SettingsPanel/VersionLabel.text = "Game Version: " + str(ProjectSettings.get_setting("application/config/version"))
	
	speed_tween = Tween.new()
	add_child(speed_tween)
	var start_tween = Tween.new()
	add_child(start_tween)
	start_tween.interpolate_property($UI/Control/PlayButton, "rect_scale", Vector2(1.0, 1.0), Vector2(1.05, 1.05), 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	start_tween.interpolate_property($UI/Control/PlayButton, "rect_scale", Vector2(1.05, 1.05), Vector2(1.0, 1.0), 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.8)
	start_tween.repeat = true
	start_tween.start()
	
	speed_label = $UI/Control/SpeedLabel
	level_progress_bar = $UI/Control.get_node_or_null("LevelProgressBar")
	if level_progress_bar:
		level_label = level_progress_bar.get_node_or_null("LevelLabel")
	health_bar = $UI/Control.get_node_or_null("HealthBar")
	if health_bar:
		for i in range(max_health):
			var icon = TextureRect.new()
			icon.texture = tex_health
			icon.expand = true
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.rect_min_size = Vector2(80, 80)
			health_bar.add_child(icon)
	menu_info_label = $UI/Control/MenuInfoLabel
	game_over_panel = $UI/Control/GameOverPanel
	leaderboard_panel = $UI/Control/LeaderboardPanel
	settings_panel = $UI/Control/SettingsPanel
	logo_rect = $UI/Control/Logo
	start_label = $UI/Control/PlayButton/PlayLabel
	settings_button = $UI/Control/SettingsButton
	stats_button = $UI/Control/StatsButton
	bottom_bar = $UI/Control/BottomBar
	version_label = null # moved to SettingsPanel

	var stats_panel_node = Panel.new()
	stats_panel_node.name = "StatsPanel"
	stats_panel_node.visible = false
	stats_panel_node.anchor_left = 0.5
	stats_panel_node.anchor_top = 0.5
	stats_panel_node.anchor_right = 0.5
	stats_panel_node.anchor_bottom = 0.5
	stats_panel_node.margin_left = -320
	stats_panel_node.margin_top = -480
	stats_panel_node.margin_right = 320
	stats_panel_node.margin_bottom = 480
	$UI/Control.add_child(stats_panel_node)
	
	var stats_title = Label.new()
	stats_title.text = "Player Stats"
	stats_title.anchor_right = 1.0
	stats_title.margin_top = 40
	stats_title.margin_bottom = 100
	stats_title.align = Label.ALIGN_CENTER
	stats_title.valign = Label.VALIGN_CENTER
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button")
	if title_font: stats_title.add_font_override("font", title_font)
	stats_panel_node.add_child(stats_title)
	
	var stats_vbox = VBoxContainer.new()
	stats_vbox.name = "VBox"
	stats_vbox.anchor_right = 1.0
	stats_vbox.anchor_bottom = 1.0
	stats_vbox.margin_left = 40
	stats_vbox.margin_right = -40
	stats_vbox.margin_top = 150
	stats_vbox.margin_bottom = -200
	stats_vbox.add_constant_override("separation", 20)
	stats_panel_node.add_child(stats_vbox)
	
	var close_stats = Button.new()
	close_stats.text = "Close"
	close_stats.anchor_left = 0.5
	close_stats.anchor_top = 1.0
	close_stats.anchor_right = 0.5
	close_stats.anchor_bottom = 1.0
	close_stats.margin_left = -140
	close_stats.margin_top = -180
	close_stats.margin_right = 140
	close_stats.margin_bottom = -95
	close_stats.connect("pressed", self, "_on_CloseStats_pressed")
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			close_stats.add_font_override("font", ref_font)
		
		var style_hover = ref_btn.get_stylebox("hover")
		if style_hover:
			close_stats.add_stylebox_override("hover", style_hover)
		
		var style_pressed = ref_btn.get_stylebox("pressed")
		if style_pressed:
			close_stats.add_stylebox_override("pressed", style_pressed)
			
		var style_normal = ref_btn.get_stylebox("normal")
		if style_normal:
			close_stats.add_stylebox_override("normal", style_normal)
			
	stats_panel_node.add_child(close_stats)

	var disclaimer = Label.new()
	disclaimer.text = "Stats are stored in your browser's local storage and will reset if cleared."
	disclaimer.anchor_left = 0.0
	disclaimer.anchor_top = 1.0
	disclaimer.anchor_right = 1.0
	disclaimer.anchor_bottom = 1.0
	disclaimer.margin_left = 20
	disclaimer.margin_right = -20
	disclaimer.margin_top = -80
	disclaimer.margin_bottom = -15
	disclaimer.align = Label.ALIGN_CENTER
	disclaimer.valign = Label.VALIGN_CENTER
	disclaimer.autowrap = true
	
	var desc_font = DynamicFont.new()
	desc_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	desc_font.size = 26
	desc_font.outline_size = 2
	desc_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	disclaimer.add_font_override("font", desc_font)
	disclaimer.add_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8))
	stats_panel_node.add_child(disclaimer)

	if OS.is_debug_build():
		debug_label = Label.new()
		# Use default system font (monospaced) for cleaner debug text
		debug_label.add_color_override("font_color", Color(0.2, 1.0, 0.2)) # Hacker green
		debug_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8)) # Black shadow for contrast
		debug_label.add_constant_override("shadow_offset_x", 1)
		debug_label.add_constant_override("shadow_offset_y", 1)
		debug_label.rect_scale = Vector2(3.0, 3.0) # Massive scale for high-res screens
		debug_label.text = "DEBUG MODE OFF"
		debug_label.rect_position = Vector2(10, 10)
		debug_label.hide()
		$UI.add_child(debug_label)
		
		# Move floor to collision layer 2 for God Mode phasing
		if has_node("MeshInstance/StaticBody"):
			$MeshInstance/StaticBody.collision_layer = 2

	var err_panel = Panel.new()
	err_panel.name = "StorageErrorPanel"
	err_panel.visible = false
	err_panel.anchor_left = 0.5
	err_panel.anchor_top = 0.5
	err_panel.anchor_right = 0.5
	err_panel.anchor_bottom = 0.5
	err_panel.margin_left = -250
	err_panel.margin_top = -180
	err_panel.margin_right = 250
	err_panel.margin_bottom = 180
	
	if has_node("UI/Control/SettingsPanel/ConfirmPanel"):
		var warning_style = $UI/Control/SettingsPanel/ConfirmPanel.get_stylebox("panel")
		if warning_style:
			err_panel.add_stylebox_override("panel", warning_style)
			
	$UI/Control.add_child(err_panel)
	
	var err_title = Label.new()
	err_title.text = "Storage Error"
	err_title.anchor_right = 1.0
	err_title.margin_top = 30
	err_title.margin_bottom = 80
	err_title.align = Label.ALIGN_CENTER
	err_title.valign = Label.VALIGN_CENTER
	err_title.add_color_override("font_color", Color(1.0, 0.3, 0.3)) # Warning Red
	var err_title_font = load("res://resources/Theme.tres").get_font("font", "Button")
	if err_title_font: err_title.add_font_override("font", err_title_font)
	err_panel.add_child(err_title)

	var err_msg = Label.new()
	err_msg.name = "MessageLabel"
	err_msg.text = ""
	err_msg.autowrap = true
	err_msg.align = Label.ALIGN_CENTER
	err_msg.valign = Label.VALIGN_CENTER
	err_msg.anchor_left = 0.05
	err_msg.anchor_right = 0.95
	err_msg.margin_top = 90
	err_msg.margin_bottom = 250
	var msg_font = $UI/Control/MenuInfoLabel.get_font("font")
	if msg_font: err_msg.add_font_override("font", msg_font)
	err_panel.add_child(err_msg)
	
	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.anchor_left = 0.5
	ok_btn.anchor_top = 1.0
	ok_btn.anchor_right = 0.5
	ok_btn.anchor_bottom = 1.0
	ok_btn.margin_left = -70
	ok_btn.margin_top = -90
	ok_btn.margin_right = 70
	ok_btn.margin_bottom = -25
	ok_btn.connect("pressed", self, "_on_CloseStorageError_pressed")
	err_panel.add_child(ok_btn)

	update_mode_button_text()
	update_score_display()
	
	if Global.auto_start:
		Global.auto_start = false
		call_deferred("_on_Button_pressed", false)

func _exit_tree():
	save_hiscore()
	
func save_hiscore():
	var file = File.new()
	var err = file.open("user://save_game.dat", File.WRITE)
	if err != OK or not file.is_open():
		if not storage_error_shown:
			storage_error_shown = true
			show_storage_error("Failed to save player stats and settings. Storage access might be restricted by your browser.")
		return
	var data = {
		"hiscores": hiscores,
		"highest_levels": highest_levels,
		"mode": mode_level,
		"music_volume": music_volume,
		"sfx_enabled": sfx_enabled,
		"stats": stats
	}
	file.store_var(data)
	file.close()

func load_hiscore():
	var file = File.new()
	if not file.file_exists("user://save_game.dat"):
		return
		
	var err = file.open("user://save_game.dat", File.READ)
	
	if err != OK or not file.is_open():
		if file:
			file.close()
		if not storage_error_shown:
			storage_error_shown = true
			show_storage_error("Failed to restore player stats and settings. Storage access might be restricted by your browser.")
		return
		
	var content = file.get_var()
	if typeof(content) == TYPE_DICTIONARY:
		# Always start in OG mode, so we don't load the saved mode_level
		if content.has("hiscores"):
			hiscores = content.get("hiscores")
		else:
			# Upgrade intermediate save format
			hiscores[mode_level] = content.get("hiscore", 0)
			
		if content.has("highest_levels"):
			var loaded_levels = content.get("highest_levels")
			highest_levels[0] = int(max(1, loaded_levels.get(0, 1)))
			highest_levels[1] = int(max(1, loaded_levels.get(1, 1)))
			
		if content.has("music_volume"):
			music_volume = content.get("music_volume")
			
		if content.has("sfx_enabled"):
			sfx_enabled = content.get("sfx_enabled")
			
		if content.has("stats"):
			var loaded_stats = content.get("stats")
			for key in stats.keys():
				if loaded_stats.has(key):
					stats[key] = loaded_stats[key]
	else:
		# Fallback to older integer format
		file.seek(0)
		var old_content = file.get_64()
		if old_content != null:
			hiscores[0] = old_content # Assume OG
			
	file.close()

func _process(delta):
	if OS.is_debug_build() and debug_mode_active and is_instance_valid(debug_label):
		var mem = OS.get_dynamic_memory_usage() / 1024.0 / 1024.0
		var is_god = "ON" if (has_node("Bird") and $Bird.is_invincible) else "OFF"
		var stats = PoolStringArray([
			"--- DEVELOPER MONITOR ---",
			"FPS: " + str(Engine.get_frames_per_second()),
			"Memory: %.2f MB" % mem,
			"Resolution: " + str(OS.window_size.x) + "x" + str(OS.window_size.y),
			"Game Speed Multiplier: %.2f" % game_speed,
			"Current Level: " + str(current_speed_level),
			"Time in Level: %.1fs / %.1fs" % [level_time_survived, time_to_next_level],
			"Score: " + str(score),
			"God Mode (I): " + is_god,
			"",
			"Commands: [L] Level Up | [H] Health | [C] Score"
		])
		debug_label.text = stats.join("\n")

	if game_playing:
		if mode_level == 1:
			run_playtime += delta
			# Obstacles move at base speed 10, so distance = delta * 10 * game_speed
			if not get_tree().paused:
				run_distance += (delta * 10.0 * game_speed)
				if game_speed > run_max_speed:
					run_max_speed = game_speed
		if progression_pause_timer > 0.0:
			progression_pause_timer -= delta
		else:
			if mode_level == 1: # Escalation
				level_time_survived += delta
			
				# Asymptotic speed curve towards a hard cap (MAX_SPEED = 2.5)
				# This makes the game smoothly accelerate but safely taper off near human limits
				var MAX_SPEED = 2.5
				game_speed += (MAX_SPEED - game_speed) * 0.003 * delta
				
				if level_progress_bar:
					level_progress_bar.value = (level_time_survived / time_to_next_level) * 100.0
					
				if level_time_survived >= time_to_next_level:
					current_speed_level += 1
					level_time_survived -= time_to_next_level
					
					# Cap level duration at 45 seconds to prevent late-game fatigue
					if time_to_next_level < 45.0:
						time_to_next_level += 5.0
					
					if current_speed_level > highest_levels[mode_level]:
						highest_levels[mode_level] = current_speed_level
						save_hiscore()
					
					trigger_health_refill_animation()
					
					if is_instance_valid(level_change_sound):
						level_change_sound.play()
					if level_label:
						level_label.text = "LEVEL " + str(current_speed_level)
					if speed_label and speed_tween:
						speed_label.text = "LEVEL UP!"
						speed_label.modulate.a = 1.0
						speed_label.rect_scale = Vector2(1.5, 1.5)
						
						speed_tween.stop_all()
						speed_tween.interpolate_property(speed_label, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.4, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
						speed_tween.interpolate_property(speed_label, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, 1.0)
						speed_tween.start()
			
	# Add a gentle floating/breathing effect to the logo on the main menu
	if not game_playing and is_instance_valid(logo_rect) and logo_rect.visible:
		if not game_over_panel.visible:
			logo_rect.rect_rotation = sin(OS.get_ticks_msec() * 0.0004) * 0.5
			logo_rect.rect_scale = Vector2(1.0, 1.0) + Vector2(1, 1) * sin(OS.get_ticks_msec() * 0.0005) * 0.005
		else:
			logo_rect.rect_rotation = 0.0
			logo_rect.rect_scale = Vector2(1.0, 1.0)

func _on_ModeButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	mode_level += 1
	if mode_level > 1:
		mode_level = 0
	Global.current_mode = mode_level
	update_mode_button_text()
	update_score_display()

func get_mode_string() -> String:
	if mode_level == 0: return "OG"
	elif mode_level == 1: return "Escalation"
	return "Unknown"

func update_mode_button_text():
	$UI/Control/ModeButton.text = "Mode: " + get_mode_string()

func update_health_display():
	if health_bar:
		var idx = 0
		for child in health_bar.get_children():
			if child is TextureRect:
				if idx < current_health:
					child.texture = tex_health
				else:
					child.texture = tex_health_blank
				idx += 1

func play_health_consumed_animation(lost_index: int):
	if health_bar and lost_index >= 0 and lost_index < health_bar.get_child_count():
		var lost_icon = health_bar.get_child(lost_index)
		var h_tween = Tween.new()
		add_child(h_tween)
		
		# Pulse the whole bar slightly red as a warning
		h_tween.interpolate_property(health_bar, "modulate", Color(2, 0, 0), Color(1, 1, 1), 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
		
		# Animate the lost icon (it shakes and shrinks slightly)
		lost_icon.rect_pivot_offset = lost_icon.rect_size / 2.0
		h_tween.interpolate_property(lost_icon, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.5, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		h_tween.interpolate_property(lost_icon, "modulate", Color(2, 0, 0), Color(1, 1, 1), 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
		
		h_tween.start()
		h_tween.connect("tween_all_completed", h_tween, "queue_free")
		
		# Floating "-1 HEALTH!" text
		var float_txt = Label.new()
		float_txt.text = "-1 HEALTH!"
		var font = $UI/Control/MenuInfoLabel.get_font("font")
		float_txt.add_font_override("font", font)
		float_txt.add_color_override("font_color", Color(1.0, 0.2, 0.2)) # Strong red for damage
		
		$UI.add_child(float_txt)
		
		var text_size = font.get_string_size(float_txt.text)
		float_txt.rect_min_size = text_size
		float_txt.rect_size = text_size
		float_txt.rect_pivot_offset = text_size / 2.0
		
		var spawn_x = lost_icon.rect_global_position.x - text_size.x - 150
		var spawn_y = lost_icon.rect_global_position.y
		
		float_txt.rect_global_position = Vector2(spawn_x, spawn_y)
		float_txt.rect_scale = Vector2(0.1, 0.1)
		
		var txt_tween = Tween.new()
		float_txt.add_child(txt_tween)
		
		txt_tween.interpolate_property(float_txt, "rect_scale", Vector2(0.1, 0.1), Vector2(1.5, 1.5), 0.2, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		txt_tween.interpolate_property(float_txt, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.2)
		
		var start_pos = float_txt.rect_global_position
		var end_pos = start_pos + Vector2(-40, 60) # Drift down and left like it's falling away
		txt_tween.interpolate_property(float_txt, "rect_global_position", start_pos, end_pos, 1.2, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		txt_tween.interpolate_property(float_txt, "modulate:a", 1.0, 0.0, 1.2, Tween.TRANS_SINE, Tween.EASE_IN)
		
		txt_tween.start()
		txt_tween.connect("tween_all_completed", float_txt, "queue_free")

func request_revive() -> bool:
	if mode_level == 0:
		return false
		
	if current_health > 1:
		current_health -= 1
		update_health_display()
		play_health_consumed_animation(current_health)
		
		if is_instance_valid(revive_sound):
			get_tree().create_timer(0.15).connect("timeout", self, "play_revive_sound")
		
		progression_pause_timer = 2.5 / max(game_speed, 1.0) # Pause progression until pipes arrive
		$ObstacleSpawner.clear_obstacles()
		stats["total_revives"] = stats.get("total_revives", 0) + 1
		return true
	elif current_health == 1:
		current_health -= 1
		update_health_display()
		play_health_consumed_animation(current_health)
		return false
	return false

func play_revive_sound():
	if has_node("Bird") and not $Bird.is_dead and is_instance_valid(revive_sound):
		revive_sound.play()

func update_score_display():
	$UI/Control/Score.text = String(score)
	if menu_info_label:
		if mode_level == 1:
			menu_info_label.text = "YOUR BEST: " + String(hiscores[mode_level]) + " (Lvl " + str(highest_levels[mode_level]) + ")"
		else:
			menu_info_label.text = "YOUR BEST: " + String(hiscores[mode_level])

func _on_Button_pressed(play_sound: bool = true):
	if play_sound and is_instance_valid(ui_button_click):
		ui_button_click.play()
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.stop()
		
	game_speed = 1.0
	current_speed_level = 1
	level_time_survived = 0.0
	time_to_next_level = 30.0
	progression_pause_timer = 0.0
	
	if level_progress_bar:
		level_progress_bar.value = 0.0
	if level_label:
		level_label.text = "LEVEL 1"

	game_playing = true
	
	if mode_level == 1:
		stats["total_games"] = stats.get("total_games", 0) + 1
		
	run_distance = 0.0
	run_max_speed = 1.0
	run_playtime = 0.0
	
	save_hiscore()

	$UI/Control/PlayButton.hide()
	if start_label: start_label.hide()
	$UI/Control/ModeButton.hide()
	$UI/Control/LeaderboardButton.hide()
	if stats_button: stats_button.hide()
	if menu_info_label: menu_info_label.hide()
	if version_label: version_label.hide()
	if settings_button: settings_button.hide()
	if bottom_bar: bottom_bar.hide()
	if is_instance_valid(logo_rect): logo_rect.hide()
	
	$UI/Control/Score.show()
	$UI/Control/Score.text = "0"
	
	if mode_level == 1:
		speed_label.text = "ESCALATION MODE\nIt gets faster. Good luck."
		if level_progress_bar:
			level_progress_bar.show()
		current_health = max_health
		update_health_display()
		if health_bar:
			health_bar.show()
	else:
		speed_label.text = "OG MODE\nClassic rules. Pure skill."
		if level_progress_bar:
			level_progress_bar.hide()
		if health_bar:
			health_bar.hide()
		
	speed_label.modulate.a = 1.0
	speed_label.rect_scale = Vector2(1.5, 1.5)
	speed_label.show()
	
	speed_tween.stop_all()
	speed_tween.interpolate_property(speed_label, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.5, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
	speed_tween.interpolate_property(speed_label, "modulate:a", 1.0, 0.0, 1.5, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT, 1.5)
	speed_tween.start()
		
	
	if game_over_panel:
		game_over_panel.hide()
	$Bird.start()
	$ObstacleSpawner.start_spawning()

func _on_Button2_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		yield(ui_button_click, "finished")
		
	Global.auto_start = true
	get_tree().reload_current_scene()
	get_tree().paused = false

func _on_Button3_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		yield(ui_button_click, "finished")
		
	get_tree().reload_current_scene()
	get_tree().paused = false

func _on_LeaderboardButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	$UI/Control/PlayButton.hide()
	if start_label: start_label.hide()
	$UI/Control/ModeButton.hide()
	$UI/Control/LeaderboardButton.hide()
	if stats_button: stats_button.hide()
	settings_button.hide()
	if menu_info_label: menu_info_label.hide()
	if version_label: version_label.hide()
	if bottom_bar: bottom_bar.hide()
	leaderboard_panel.show()

func _on_CloseLeaderboard_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	leaderboard_panel.hide()
	$UI/Control/PlayButton.show()
	if start_label: start_label.show()
	$UI/Control/ModeButton.show()
	$UI/Control/LeaderboardButton.show()
	if stats_button: stats_button.show()
	settings_button.show()
	if menu_info_label: menu_info_label.show()
	if version_label: version_label.show()
	if bottom_bar: bottom_bar.show()

func _on_SettingsButton_down():
	settings_button.rect_scale = Vector2(0.85, 0.85)
	settings_button.self_modulate = Color(0.7, 0.7, 0.7) # Dim slightly when pressed

func _on_SettingsButton_up():
	settings_button.rect_scale = Vector2(1.0, 1.0)
	settings_button.self_modulate = Color(1.0, 1.0, 1.0) # Back to original color

func _on_StatsButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	var stats_panel_node = $UI/Control.get_node_or_null("StatsPanel")
	if not stats_panel_node: return
	
	var vbox = stats_panel_node.get_node("VBox")
	for child in vbox.get_children():
		child.queue_free()
	
	var stats_labels = [
		["Total Games Played", str(stats["total_games"])],
		["Lifetime Score", str(stats["lifetime_score"])],
		["Highest Level", str(highest_levels[1])],
		["Total Jumps", str(stats["total_jumps"])],
		["Total Deaths", str(stats["total_deaths"])],
		["Total Revives", str(stats.get("total_revives", 0))],
		["Distance Traveled", "%.0f m" % stats.get("total_distance", 0.0)],
		["Playtime", "%.1f min" % (stats["playtime"] / 60.0)]
	]
	
	var base_font = $UI/Control/MenuInfoLabel.get_font("font")
	var font = base_font.duplicate() if base_font else null
	if font:
		font.size = 42 # slightly smaller to fit perfectly without crowding
		
	for stat_pair in stats_labels:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var label1 = Label.new()
		label1.text = stat_pair[0]
		label1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if font: label1.add_font_override("font", font)
		row.add_child(label1)
		
		var label2 = Label.new()
		label2.text = stat_pair[1]
		label2.align = Label.ALIGN_RIGHT
		label2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if font: label2.add_font_override("font", font)
		row.add_child(label2)
		
		vbox.add_child(row)
	
	$UI/Control/PlayButton.hide()
	if start_label: start_label.hide()
	$UI/Control/ModeButton.hide()
	$UI/Control/LeaderboardButton.hide()
	if stats_button: stats_button.hide()
	settings_button.hide()
	if menu_info_label: menu_info_label.hide()
	if version_label: version_label.hide()
	if bottom_bar: bottom_bar.hide()
	stats_panel_node.show()

func _on_CloseStats_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	var stats_panel_node = $UI/Control.get_node_or_null("StatsPanel")
	if stats_panel_node: stats_panel_node.hide()
	
	$UI/Control/PlayButton.show()
	if start_label: start_label.show()
	$UI/Control/ModeButton.show()
	$UI/Control/LeaderboardButton.show()
	if stats_button: stats_button.show()
	settings_button.show()
	if menu_info_label: menu_info_label.show()
	if version_label: version_label.show()
	if bottom_bar: bottom_bar.show()

func show_storage_error(message: String):
	var popup = $UI/Control.get_node_or_null("StorageErrorPanel")
	if popup:
		var msg_label = popup.get_node("MessageLabel")
		if msg_label:
			msg_label.text = message
		popup.show()

func _on_CloseStorageError_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	var popup = $UI/Control.get_node_or_null("StorageErrorPanel")
	if popup:
		popup.hide()

func _on_CircleButton_down(button: Button):
	button.rect_scale = Vector2(0.85, 0.85)
	button.self_modulate = Color(0.7, 0.7, 0.7)

func _on_CircleButton_up(button: Button):
	button.rect_scale = Vector2(1.0, 1.0)
	button.self_modulate = Color(1.0, 1.0, 1.0)

func _on_SettingsButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	$UI/Control/PlayButton.hide()
	if start_label: start_label.hide()
	$UI/Control/ModeButton.hide()
	$UI/Control/LeaderboardButton.hide()
	if stats_button: stats_button.hide()
	settings_button.hide()
	if menu_info_label: menu_info_label.hide()
	if version_label: version_label.hide()
	if bottom_bar: bottom_bar.hide()
	settings_panel.show()

func _on_CloseSettings_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	settings_panel.hide()
	$UI/Control/PlayButton.show()
	if start_label: start_label.show()
	$UI/Control/ModeButton.show()
	$UI/Control/LeaderboardButton.show()
	if stats_button: stats_button.show()
	settings_button.show()
	if menu_info_label: menu_info_label.show()
	if version_label: version_label.show()
	if bottom_bar: bottom_bar.show()

func _on_MusicSlider_value_changed(value: float):
	music_volume = value
	var raw_db = linear2db(value) if value > 0.001 else -80.0
	# Apply standard -10 dB offset to prevent background music from overpowering the game
	var db = raw_db - 10.0 if raw_db > -79.0 else -80.0
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.volume_db = db
	save_hiscore()

func _apply_sfx_volume():
	var db = 0.0 if sfx_enabled else -80.0
	var sfx_nodes = [bird_jump, bird_collision, bird_fall, score_sound, bird_pop, level_change_sound, revive_sound, health_refill_sound, game_over_bgm]
	for node in sfx_nodes:
		if is_instance_valid(node):
			node.volume_db = db

func _on_SfxToggle_toggled(button_pressed: bool):
	sfx_enabled = button_pressed
	_apply_sfx_volume()
	save_hiscore()
	if is_instance_valid(ui_button_click):
		ui_button_click.play()

func _on_RequestReset_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	settings_panel.get_node("ConfirmPanel").show()

func _on_ConfirmReset_Yes():
	settings_panel.get_node("ConfirmPanel").hide()
	_on_ResetStats_pressed()

func _on_ConfirmReset_No():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	settings_panel.get_node("ConfirmPanel").hide()

func _on_ResetStats_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	# Reset scores
	hiscores = {0: 0, 1: 0}
	highest_levels = {0: 1, 1: 1}
	stats = {
		"total_games": 0,
		"lifetime_score": 0,
		"playtime": 0.0,
		"total_jumps": 0,
		"total_deaths": 0,
		"total_revives": 0,
		"total_distance": 0.0
	}
	save_hiscore()
	update_score_display()
	
	# Reset settings
	music_volume = 1.0
	sfx_enabled = true
	
	# Apply audio settings
	_apply_sfx_volume()
	var raw_db = linear2db(music_volume) if music_volume > 0.001 else -80.0
	# Apply standard -10 dB offset to prevent background music from overpowering the game
	var db = raw_db - 10.0 if raw_db > -79.0 else -80.0
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.volume_db = db
		
	# Sync UI controls if panel is valid
	if is_instance_valid(settings_panel):
		var slider = settings_panel.get_node_or_null("MusicSliderAnchor/MusicSlider")
		if slider and slider.has_method("set_value"):
			slider.set_value(music_volume)
			
		var toggle = settings_panel.get_node_or_null("SfxToggleAnchor/SfxToggle")
		if toggle and toggle.has_method("set_on"):
			toggle.set_on(sfx_enabled)

func increment_score(obstacle_position: Vector3 = Vector3.ZERO):
	var pts = 1
	if mode_level == 1:
		pts = int(max(1, current_speed_level))
		
	if game_playing:
		score += pts
	
	# Spawn floating text effect
	var floating_text = Label.new()
	floating_text.text = "+" + str(pts)
	floating_text.align = Label.ALIGN_CENTER
	floating_text.add_font_override("font", $UI/Control/Score.get_font("font"))
	
	# Pop scale effect and golden color
	floating_text.add_color_override("font_color", Color(1.0, 0.85, 0.2)) # Golden
	floating_text.rect_scale = Vector2(0.1, 0.1)
	
	# Get 2D screen coordinate from 3D gap position
	var camera = get_viewport().get_camera()
	var screen_pos = Vector2(get_viewport().size.x / 2, 150.0) # Fallback
	if is_instance_valid(camera):
		# Project the 3D position to the 2D screen
		screen_pos = camera.unproject_position(obstacle_position)
		# Offset slightly upwards so it doesn't spawn exactly on the bird, and center it
		screen_pos.y -= 20
		screen_pos.x -= 30 # Rough center offset for text width
	
	floating_text.rect_position = screen_pos
	
	$UI.add_child(floating_text)
	
	# Call yield idle_frame to ensure layout updates size properly before setting pivot
	yield(get_tree(), "idle_frame")
	if is_instance_valid(floating_text):
		floating_text.rect_pivot_offset = floating_text.rect_size / 2.0
		
		var ft_tween = Tween.new()
		floating_text.add_child(ft_tween)
		
		# Pop scale 0.1 -> 1.5 -> 1.0
		ft_tween.interpolate_property(floating_text, "rect_scale", Vector2(0.1, 0.1), Vector2(1.5, 1.5), 0.2, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		ft_tween.interpolate_property(floating_text, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.2)
		
		# Float up and fade
		ft_tween.interpolate_property(floating_text, "rect_position:y", screen_pos.y, screen_pos.y - 120, 1.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		ft_tween.interpolate_property(floating_text, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_CUBIC, Tween.EASE_IN)
		
		ft_tween.start()
		ft_tween.connect("tween_all_completed", floating_text, "queue_free")
	
	if is_instance_valid(score_sound):
		score_sound.play()
	
	if score >= hiscores[mode_level]:
		hiscores[mode_level] = score
	
	update_score_display()

func _on_StartButton_down():
	if start_label:
		start_label.margin_top = 254
		start_label.margin_bottom = 365

func _on_StartButton_up():
	if start_label:
		start_label.margin_top = 240
		start_label.margin_bottom = 351

func trigger_hit_phase():
	if game_playing:
		if mode_level == 1:
			stats["total_deaths"] += 1
		save_hiscore()
	
	game_playing = false
	$ObstacleSpawner.stop()
	$bg.stop()
	$ScrollingPlatform.stop()
	
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.stop()

func trigger_grounded_phase():
	if not $UI/Control/RestartButton.visible:
		$UI/Control/RestartButton.show()
		$UI/Control/MainMenuButton.show()
		$UI/Control/Score.hide()
		if level_progress_bar:
			level_progress_bar.hide()
		if health_bar:
			health_bar.hide()
		if speed_label:
			speed_label.hide()
		if version_label:
			version_label.show()
		if is_instance_valid(logo_rect):
			logo_rect.show()
			
		if game_over_panel:
			if mode_level == 1:
				stats["total_distance"] = stats.get("total_distance", 0.0) + run_distance
				stats["playtime"] = stats.get("playtime", 0.0) + run_playtime
				stats["lifetime_score"] = stats.get("lifetime_score", 0) + score
				save_hiscore()
				
			var score_str = String(score)
			if mode_level == 1:
				score_str += " (Lvl " + str(current_speed_level) + ")"
			game_over_panel.get_node("VBox/ScoreRow/Value").text = score_str
			
			var best_str = String(hiscores[mode_level])
			if mode_level == 1:
				best_str += " (Lvl " + str(highest_levels[mode_level]) + ")"
			game_over_panel.get_node("VBox/HighScoreRow/Value").text = best_str
			
			var dist_row = game_over_panel.get_node_or_null("VBox/DistanceRow")
			var speed_row = game_over_panel.get_node_or_null("VBox/SpeedRow")
			
			if mode_level == 1:
				if dist_row:
					dist_row.show()
					var dist_val = dist_row.get_node_or_null("Value")
					if dist_val: dist_val.text = "%.0f m" % run_distance
				if speed_row:
					speed_row.show()
					var speed_val = speed_row.get_node_or_null("Value")
					if speed_val: speed_val.text = "%.0f%%" % (run_max_speed * 100.0)
				game_over_panel.margin_bottom = 210.0
			else:
				if dist_row:
					dist_row.hide()
				if speed_row:
					speed_row.hide()
				game_over_panel.margin_bottom = 54.0
			
			game_over_panel.get_node("VBox/ModeRow/Value").text = get_mode_string()
			game_over_panel.show()
			if is_instance_valid(game_over_bgm):
				game_over_bgm.play()
		


class CustomSlider extends Control:
	signal value_changed(value)
	var value: float = 0.5
	var track: Panel
	var fill: Panel
	var knob: Panel
	var is_dragging: bool = false
	var width: float = 400.0
	
	func _init(initial_value: float = 0.5):
		value = initial_value
		rect_min_size = Vector2(width, 80)
		
		track = Panel.new()
		track.rect_min_size = Vector2(width, 30)
		track.rect_position = Vector2(0, 25)
		track.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(track)
		
		var track_style = StyleBoxFlat.new()
		track_style.bg_color = Color(0.15, 0.15, 0.2)
		track_style.anti_aliasing = true
		track_style.corner_detail = 20
		track_style.corner_radius_top_left = 15
		track_style.corner_radius_top_right = 15
		track_style.corner_radius_bottom_left = 15
		track_style.corner_radius_bottom_right = 15
		track_style.border_width_left = 3
		track_style.border_width_top = 3
		track_style.border_width_right = 3
		track_style.border_width_bottom = 3
		track_style.border_color = Color(0.1, 0.1, 0.1)
		track.add_stylebox_override("panel", track_style)
		
		fill = Panel.new()
		fill.rect_min_size = Vector2(width * value, 30)
		fill.rect_position = Vector2(0, 25)
		fill.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(fill)
		
		var fill_style = StyleBoxFlat.new()
		fill_style.bg_color = Color(0.2, 0.65, 1.0) # Match UI blue
		fill_style.anti_aliasing = true
		fill_style.corner_detail = 20
		fill_style.corner_radius_top_left = 15
		fill_style.corner_radius_top_right = 15
		fill_style.corner_radius_bottom_left = 15
		fill_style.corner_radius_bottom_right = 15
		fill_style.border_width_left = 3
		fill_style.border_width_top = 3
		fill_style.border_width_right = 3
		fill_style.border_width_bottom = 3
		fill_style.border_color = Color(0.1, 0.4, 0.8)
		fill.add_stylebox_override("panel", fill_style)
		
		knob = Panel.new()
		knob.rect_min_size = Vector2(56, 56)
		knob.rect_position = Vector2(width * value - 28, 12)
		knob.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(knob)
		
		var knob_style = StyleBoxFlat.new()
		knob_style.bg_color = Color(0.95, 0.95, 0.95)
		knob_style.anti_aliasing = true
		knob_style.corner_detail = 20
		knob_style.corner_radius_top_left = 28
		knob_style.corner_radius_top_right = 28
		knob_style.corner_radius_bottom_left = 28
		knob_style.corner_radius_bottom_right = 28
		knob_style.border_width_left = 4
		knob_style.border_width_top = 4
		knob_style.border_width_right = 4
		knob_style.border_width_bottom = 4
		knob_style.border_color = Color(0.6, 0.6, 0.6)
		knob_style.shadow_color = Color(0, 0, 0, 0.3)
		knob_style.shadow_size = 4
		knob.add_stylebox_override("panel", knob_style)
		
	func _gui_input(event):
		if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
			if event.pressed:
				is_dragging = true
				update_value_from_mouse(event.position.x)
			else:
				is_dragging = false
		elif event is InputEventMouseMotion and is_dragging:
			update_value_from_mouse(event.position.x)
			
	func update_value_from_mouse(x_pos: float):
		var clamped_x = clamp(x_pos, 0.0, width)
		value = clamped_x / width
		fill.rect_min_size.x = max(30, clamped_x) # ensure some width so border isn't weird
		knob.rect_position.x = clamped_x - 28
		emit_signal("value_changed", value)
		
	func set_value(new_value: float):
		value = clamp(new_value, 0.0, 1.0)
		var clamped_x = value * width
		fill.rect_min_size.x = max(30, clamped_x)
		knob.rect_position.x = clamped_x - 28

class CustomToggle extends Control:
	signal toggled(is_on)
	var is_on: bool = false
	var bg_panel: Panel
	var knob: Panel
	var tween: Tween
	var width: float = 160.0
	var height: float = 76.0
	
	func _init(initial_state: bool = false):
		is_on = initial_state
		rect_min_size = Vector2(width, height)
		
		bg_panel = Panel.new()
		bg_panel.rect_min_size = Vector2(width, height)
		bg_panel.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(bg_panel)
		
		var bg_style = StyleBoxFlat.new()
		bg_style.anti_aliasing = true
		bg_style.corner_detail = 20
		bg_style.corner_radius_top_left = int(height / 2)
		bg_style.corner_radius_top_right = int(height / 2)
		bg_style.corner_radius_bottom_left = int(height / 2)
		bg_style.corner_radius_bottom_right = int(height / 2)
		bg_style.border_width_left = 4
		bg_style.border_width_top = 4
		bg_style.border_width_right = 4
		bg_style.border_width_bottom = 4
		bg_style.border_color = Color(0.1, 0.1, 0.1)
		bg_panel.add_stylebox_override("panel", bg_style)
		
		knob = Panel.new()
		var knob_size = height - 16
		knob.rect_min_size = Vector2(knob_size, knob_size)
		knob.rect_position = Vector2(8, 8) if not is_on else Vector2(width - knob_size - 8, 8)
		knob.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(knob)
		
		var knob_style = StyleBoxFlat.new()
		knob_style.bg_color = Color(0.95, 0.95, 0.95)
		knob_style.anti_aliasing = true
		knob_style.corner_detail = 20
		knob_style.corner_radius_top_left = int(knob_size / 2)
		knob_style.corner_radius_top_right = int(knob_size / 2)
		knob_style.corner_radius_bottom_left = int(knob_size / 2)
		knob_style.corner_radius_bottom_right = int(knob_size / 2)
		knob_style.border_width_left = 3
		knob_style.border_width_top = 3
		knob_style.border_width_right = 3
		knob_style.border_width_bottom = 3
		knob_style.border_color = Color(0.6, 0.6, 0.6)
		knob_style.shadow_color = Color(0, 0, 0, 0.3)
		knob_style.shadow_size = 4
		knob.add_stylebox_override("panel", knob_style)
		
		tween = Tween.new()
		add_child(tween)
		
		update_colors()
		
	func _gui_input(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
			is_on = !is_on
			emit_signal("toggled", is_on)
			animate()

	func set_on(new_state: bool):
		if is_on != new_state:
			is_on = new_state
			animate()

	func animate():
		var knob_size = height - 16
		var target_x = width - knob_size - 8 if is_on else 8.0
		tween.interpolate_property(knob, "rect_position:x", knob.rect_position.x, target_x, 0.2, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		tween.start()
		update_colors()
		
	func update_colors():
		var bg_style = bg_panel.get_stylebox("panel") as StyleBoxFlat
		if is_on:
			bg_style.bg_color = Color(0.4, 0.8, 0.2) # Bright Green
		else:
			bg_style.bg_color = Color(0.6, 0.2, 0.2) # Soft Red

func trigger_health_refill_animation():
	if mode_level == 0:
		return
		
	if current_health < max_health:
		current_health += 1
		
		# Delay the visual/audio sequence safely using a Node Timer 
		# This prevents "Resumed after yield" errors if the game is reset!
		var timer = Timer.new()
		timer.wait_time = 0.6
		timer.one_shot = true
		timer.autostart = true
		add_child(timer)
		timer.connect("timeout", self, "_on_health_refill_delayed_timeout", [timer])

func _on_health_refill_delayed_timeout(timer):
	if is_instance_valid(timer):
		timer.queue_free()
		
	if not game_playing or not has_node("UI") or not is_instance_valid(health_bar):
		return
		
	update_health_display()
	
	if is_instance_valid(health_refill_sound):
		health_refill_sound.play() # Play instantly with the animation!
		
	var restored_icon = health_bar.get_child(current_health - 1)
	var h_tween = Tween.new()
	add_child(h_tween)
	h_tween.interpolate_property(health_bar, "modulate", Color(0, 2, 0), Color(1, 1, 1), 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
	
	restored_icon.rect_pivot_offset = restored_icon.rect_size / 2.0
	h_tween.interpolate_property(restored_icon, "rect_scale", Vector2(1.8, 1.8), Vector2(1.0, 1.0), 0.5, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
	h_tween.start()
	h_tween.connect("tween_all_completed", h_tween, "queue_free")
		
	var float_txt = Label.new()
	float_txt.text = "+1 HEALTH!"
	float_txt.add_font_override("font", $UI/Control/MenuInfoLabel.get_font("font"))
	float_txt.add_color_override("font_color", Color(1.0, 0.4, 0.4)) # Soft pastel/salmon red
	
	$UI.add_child(float_txt)
	
	# Small tiny delay to allow font layout, handled safely by a fast tween
	var txt_tween = Tween.new()
	float_txt.add_child(txt_tween)
	
	# Wait exactly 1 frame before positioning
	txt_tween.interpolate_callback(self, 0.01, "_position_floating_text", float_txt, restored_icon, txt_tween)
	txt_tween.start()

func _position_floating_text(float_txt, restored_icon, txt_tween):
	if not is_instance_valid(float_txt) or not is_instance_valid(restored_icon):
		if is_instance_valid(float_txt): float_txt.queue_free()
		return
		
	var font = float_txt.get_font("font")
	if font == null: # Fallback just in case
		font = $UI/Control/MenuInfoLabel.get_font("font")
	var text_size = font.get_string_size(float_txt.text)
	
	float_txt.rect_min_size = text_size
	float_txt.rect_size = text_size
	float_txt.rect_pivot_offset = text_size / 2.0
	
	var spawn_x = restored_icon.rect_global_position.x - text_size.x - 150
	var spawn_y = restored_icon.rect_global_position.y
	
	float_txt.rect_global_position = Vector2(spawn_x, spawn_y)
	float_txt.rect_scale = Vector2(0.1, 0.1)
	
	txt_tween.interpolate_property(float_txt, "rect_scale", Vector2(0.1, 0.1), Vector2(1.5, 1.5), 0.2, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
	txt_tween.interpolate_property(float_txt, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.2)
	
	var start_pos = float_txt.rect_global_position
	var end_pos = start_pos + Vector2(-60, 60)
	txt_tween.interpolate_property(float_txt, "rect_global_position", start_pos, end_pos, 1.2, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	txt_tween.interpolate_property(float_txt, "modulate:a", 1.0, 0.0, 1.2, Tween.TRANS_SINE, Tween.EASE_IN)
	
	txt_tween.start()
	txt_tween.connect("tween_all_completed", float_txt, "queue_free")


func _input(event):
	if OS.is_debug_build() and event is InputEventKey and event.pressed:
		if event.scancode == KEY_F1:
			debug_mode_active = !debug_mode_active
			if debug_label:
				debug_label.visible = debug_mode_active
				
		if debug_mode_active and game_playing:
			if event.scancode == KEY_L:
				# Mathematically simulate the game speed accelerating over the exact amount of time we are skipping
				var time_skipped = time_to_next_level - level_time_survived
				var sim_delta = 0.1
				var steps = int(time_skipped / sim_delta)
				var MAX_SPEED = 2.5
				for i in range(steps):
					game_speed += (MAX_SPEED - game_speed) * 0.003 * sim_delta
					
				# Force level up by fulfilling time requirement
				level_time_survived = time_to_next_level
			elif event.scancode == KEY_H:
				# Refill health
				trigger_health_refill_animation()
			elif event.scancode == KEY_C:
				# Add score
				var pts = 1 if mode_level == 0 else current_speed_level
				score += pts * 5
				update_score_display()
			elif event.scancode == KEY_I:
				# Toggle Invincibility
				if has_node("Bird"):
					$Bird.set_invincible(!$Bird.is_invincible)

