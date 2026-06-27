extends Spatial

var score = 0
var game_speed = 1.0

var player_data = {
	"player_name": "", 
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
	"has_changed_name_logged_in": false, 
	"pending_stats_sync": false, 
	"pending_score_sync": false
}

func get_highscore(mode: int) -> int:
	if mode == 0:
		return int(player_data.get("classic_highscore", 0))
	elif mode == 1:
		return int(player_data.get("escalation_highscore", 0))
	return 0

func set_highscore(mode: int, val: int):
	if mode == 0:
		player_data["classic_highscore"] = val
	elif mode == 1:
		player_data["escalation_highscore"] = val

func get_highest_level(mode: int) -> int:
	if mode == 1:
		return int(player_data.get("escalation_highest_level", 1))
	return 1

func set_highest_level(mode: int, val: int):
	if mode == 1:
		player_data["escalation_highest_level"] = val

func get_local_timezone_offset() -> int:
	var local_unix = OS.get_unix_time_from_datetime(OS.get_datetime(false))
	var utc_unix = OS.get_unix_time()
	var diff = local_unix - utc_unix
	return int(round(float(diff) / 900.0)) * 900

var game_playing = false
var is_game_over_active: bool = false
var mode_level = 0
var storage_error_shown = false
var last_sync_success: bool = false
var last_sync_timestamp: int = 0
var last_sync_attempted: bool = false
var run_distance: float = 0.0
var run_max_speed: float = 1.0
var run_playtime: float = 0.0
var is_new_high_score: bool = false

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
var settings_button: TextureButton
var profile_button: TextureButton
var bottom_bar: Panel
var game_over_bottom_bar: Panel
var game_over_leaderboard_button: TextureButton
var game_over_profile_button: TextureButton
var game_over_settings_button: TextureButton
var settings_panel: Panel
var game_over_panel: Panel
var leaderboard_panel: Panel
var logo_rect: TextureRect
var active_panel_name: String = ""


var music_volume: float = 0.5
var sfx_enabled: bool = true
var onscreen_keyboard_setting_enabled: bool = false
var cheats_used: bool = false
var web_volume_warning_shown: bool = false

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
var error_sound: AudioStreamPlayer

var loading_overlay: Panel
var loading_spinner_icon: Control

const WEB_SOUND_MAPPING = {
	"MainMenuBGM": "main_menu_bgm.mp3",
	"GameOverBGM": "game_over.mp3",
	"UIButtonClick": "ui_button_click.wav",
	"BirdJump": "bird_jump.wav",
	"BirdCollision": "bird_collision.wav",
	"BirdFall": "fall.wav",
	"ScoreSound": "score.wav",
	"BirdPop": "pop.wav",
	"LevelChangeSound": "level_change.wav",
	"ReviveSound": "revive.wav",
	"HealthRefillSound": "health_refill.wav",
	"ErrorSound": "error.wav",
	"KeyboardSound": "keyboard.wav"
}

func create_audio(node_name: String, path: String) -> AudioStreamPlayer:
	var player = AudioStreamPlayer.new()
	if OS.has_feature("HTML5"):
		player.set_script(load("res://scripts/WebAudioPlayer.gd"))
		if WEB_SOUND_MAPPING.has(node_name):
			player.sound_name = WEB_SOUND_MAPPING[node_name]
		else:
			player.sound_name = node_name
	player.name = node_name
	player.stream = load(path)
	player.pause_mode = Node.PAUSE_MODE_PROCESS
	add_child(player)
	return player

func _ready():
	VisualServer.set_default_clear_color(Color(0.06, 0.08, 0.14, 1))
	circle_bg_texture = _create_circle_texture(256)
	
	var is_desktop = OS.get_name() in ["Windows", "OSX", "X11"]
	if OS.has_feature("HTML5"):
		var js_is_desktop = JavaScript.eval("/Windows|Macintosh|Linux/i.test(navigator.userAgent) && !/Mobi|Android|Tablet|iPad|iPhone/i.test(navigator.userAgent)")
		if js_is_desktop:
			is_desktop = true

	var base_width = ProjectSettings.get_setting("display/window/size/width")
	var base_height = ProjectSettings.get_setting("display/window/size/height")
	if OS.is_debug_build() and OS.has_feature("HTML5") and is_desktop:
		get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_2D, SceneTree.STRETCH_ASPECT_KEEP, Vector2(base_width, base_height))

	
	var warm_fonts = [
		[$UI / Control / Score, "0123456789+"], 
		[$UI / Control / SpeedLabel, "LEVEL UP!CLASSIC MODE classic rules pure skill Escalation It gets faster Good luck"], 
		[$UI / Control / MenuInfoLabel, "-1 HEALTH! YOUR BEST: (Lvl 1) Classic"], 
		[$UI / Control.get_node_or_null("LevelProgressBar/LevelLabel"), "LEVEL 0123456789"]
	]
	for item in warm_fonts:
		var node = item[0]
		if is_instance_valid(node):
			var font = node.get_font("font")
			if font is DynamicFont:
				for c in item[1]:
					font.get_char_size(ord(c))

	mode_level = Global.current_mode
	main_menu_bgm = create_audio("MainMenuBGM", "res://assets/sounds/main_menu_bgm.mp3")
	game_over_bgm = create_audio("GameOverBGM", "res://assets/sounds/game_over.mp3")
	ui_button_click = create_audio("UIButtonClick", "res://assets/sounds/ui_button_click.wav")
	bird_jump = create_audio("BirdJump", "res://assets/sounds/bird_jump.wav")
	bird_collision = create_audio("BirdCollision", "res://assets/sounds/bird_collision.wav")
	bird_fall = create_audio("BirdFall", "res://assets/sounds/fall.wav")
	score_sound = create_audio("ScoreSound", "res://assets/sounds/score.wav")
	bird_pop = create_audio("BirdPop", "res://assets/sounds/pop.wav")
	level_change_sound = create_audio("LevelChangeSound", "res://assets/sounds/level_change.wav")
	revive_sound = create_audio("ReviveSound", "res://assets/sounds/revive.wav")
	health_refill_sound = create_audio("HealthRefillSound", "res://assets/sounds/health_refill.wav")
	error_sound = create_audio("ErrorSound", "res://assets/sounds/error.wav")
	
	if OS.has_feature("HTML5"):
		var files_to_load = []
		for sound_key in WEB_SOUND_MAPPING:
			files_to_load.append(WEB_SOUND_MAPPING[sound_key])
		AudioManager.loadAudios(files_to_load, "assets/sounds", {})
	
	if is_instance_valid(main_menu_bgm) and is_instance_valid(main_menu_bgm.stream):
		if "loop" in main_menu_bgm.stream:
			main_menu_bgm.stream.loop = true
			
	if is_instance_valid(game_over_bgm) and is_instance_valid(game_over_bgm.stream):
		if "loop" in game_over_bgm.stream:
			game_over_bgm.stream.loop = false
	
	load_hiscore()
	
	var initial_db = linear2db(music_volume) if music_volume > 0.001 else - 80.0
	
	var bgm_db = initial_db - 10.0 if initial_db > - 79.0 else - 80.0
	main_menu_bgm.set_volume_db(bgm_db)
	
	_apply_sfx_volume()
	var ui_click_vol = db2linear( - 6.0)
	ui_button_click.set_volume_db(linear2db(ui_click_vol))
	
	if not Global.auto_start:
		main_menu_bgm.play()

	$bg.start()
	$ScrollingPlatform.start()

	$UI / Control / PlayButton.connect("pressed", self, "_on_Button_pressed")
	
	$UI / Control / ModeButton.connect("pressed", self, "_on_ModeButton_pressed")
	$UI / Control / LeaderboardButton.connect("pressed", self, "_on_LeaderboardButton_pressed")
	$UI / Control / LeaderboardButton.connect("button_down", self, "_on_CircleButton_down", [$UI / Control / LeaderboardButton])
	$UI / Control / LeaderboardButton.connect("button_up", self, "_on_CircleButton_up", [$UI / Control / LeaderboardButton])
	$UI / Control / ProfileButton.connect("pressed", self, "_on_ProfileButton_pressed")
	$UI / Control / ProfileButton.connect("button_down", self, "_on_CircleButton_down", [$UI / Control / ProfileButton])
	$UI / Control / ProfileButton.connect("button_up", self, "_on_CircleButton_up", [$UI / Control / ProfileButton])
	$UI / Control / RestartButton.connect("pressed", self, "_on_Button2_pressed")
	$UI / Control / RestartButton.connect("button_down", self, "_on_CircleButton_down", [$UI / Control / RestartButton])
	$UI / Control / RestartButton.connect("button_up", self, "_on_CircleButton_up", [$UI / Control / RestartButton])
	$UI / Control / MainMenuButton.connect("pressed", self, "_on_Button3_pressed")
	$UI / Control / MainMenuButton.connect("button_down", self, "_on_CircleButton_down", [$UI / Control / MainMenuButton])
	$UI / Control / MainMenuButton.connect("button_up", self, "_on_CircleButton_up", [$UI / Control / MainMenuButton])
	
	$UI / Control / SettingsButton.connect("pressed", self, "_on_SettingsButton_pressed")
	$UI / Control / SettingsButton.connect("button_down", self, "_on_CircleButton_down", [$UI / Control / SettingsButton])
	$UI / Control / SettingsButton.connect("button_up", self, "_on_CircleButton_up", [$UI / Control / SettingsButton])
	$UI / Control / SettingsPanel / ResetButton.connect("pressed", self, "_on_RequestReset_pressed")
	$UI / Control / SettingsPanel / ConfirmPanel / YesButton.connect("pressed", self, "_on_ConfirmReset_Yes")
	$UI / Control / SettingsPanel / ConfirmPanel / NoButton.connect("pressed", self, "_on_ConfirmReset_No")
	FirebaseManager.connect("stats_sync_finished", self, "_on_stats_sync_finished")
	FirebaseManager.connect("auth_state_changed", self, "_on_auth_state_changed")
	FirebaseManager.connect("profile_claim_succeeded", self, "_on_profile_claim_succeeded")
	FirebaseManager.connect("profile_claim_failed", self, "_on_profile_claim_failed")
	FirebaseManager.connect("profile_claim_conflict", self, "_on_profile_claim_conflict")
	FirebaseManager.connect("token_refresh_done", self, "_on_token_refresh_done")
	FirebaseManager.connect("score_sync_finished", self, "_on_score_sync_finished")
	FirebaseManager.connect("password_reset_finished", self, "_on_password_reset_finished")
	FirebaseManager.connect("claim_status_changed", self, "_on_claim_status_changed")
	
	_create_claim_profile_panel()
	_create_loading_overlay()
	_create_manage_account_panel()
	_create_conflict_panel()
	_create_overwrite_confirm_panel()
	var music_slider = CustomSlider.new(music_volume, 440.0)
	music_slider.name = "MusicSlider"
	music_slider.anchor_right = 1.0
	music_slider.anchor_bottom = 1.0
	music_slider.connect("value_changed", self, "_on_MusicSlider_value_changed")
	$UI / Control / SettingsPanel / MusicSliderAnchor.add_child(music_slider)
	
	var sfx_button = CustomToggle.new(sfx_enabled)
	sfx_button.name = "SfxToggle"
	sfx_button.anchor_right = 1.0
	sfx_button.anchor_bottom = 1.0
	sfx_button.connect("toggled", self, "_on_SfxToggle_toggled")
	$UI / Control / SettingsPanel / SfxToggleAnchor.add_child(sfx_button)
	
	
	var s_music_lbl = $UI / Control / SettingsPanel / MusicLabel
	if s_music_lbl:
		s_music_lbl.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		var font = s_music_lbl.get_font("font")
		if font:
			var clean_font = font.duplicate()
			clean_font.size = 48
			clean_font.outline_size = 3
			clean_font.outline_color = Color(0.05, 0.05, 0.1)
			s_music_lbl.add_font_override("font", clean_font)
			
	var s_sfx_lbl = $UI / Control / SettingsPanel / SfxLabel
	if s_sfx_lbl:
		s_sfx_lbl.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		var font = s_sfx_lbl.get_font("font")
		if font:
			var clean_font = font.duplicate()
			clean_font.size = 48
			clean_font.outline_size = 3
			clean_font.outline_color = Color(0.05, 0.05, 0.1)
			s_sfx_lbl.add_font_override("font", clean_font)
	
	
	if _is_pc_device():
		var kb_label = Label.new()
		kb_label.name = "KeyboardLabel"
		kb_label.text = "On-Screen Keyboard"
		kb_label.align = Label.ALIGN_CENTER
		kb_label.anchor_left = 0.1
		kb_label.anchor_right = 0.9
		kb_label.margin_top = 860.0
		kb_label.margin_bottom = 920.0
		kb_label.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		
		var sfx_lbl = $UI / Control / SettingsPanel / SfxLabel
		if sfx_lbl:
			var font = sfx_lbl.get_font("font")
			if font:
				var clean_font = font.duplicate()
				clean_font.size = 48
				clean_font.outline_size = 3
				clean_font.outline_color = Color(0.05, 0.05, 0.1)
				kb_label.add_font_override("font", clean_font)
		$UI / Control / SettingsPanel.add_child(kb_label)
		
		var kb_anchor = Control.new()
		kb_anchor.name = "KeyboardToggleAnchor"
		kb_anchor.anchor_left = 0.5
		kb_anchor.anchor_right = 0.5
		kb_anchor.margin_left = - 80.0
		kb_anchor.margin_top = 940.0
		kb_anchor.margin_right = 80.0
		kb_anchor.margin_bottom = 1020.0
		$UI / Control / SettingsPanel.add_child(kb_anchor)
		
		var kb_toggle = CustomToggle.new(onscreen_keyboard_setting_enabled)
		kb_toggle.name = "KeyboardToggle"
		kb_toggle.anchor_right = 1.0
		kb_toggle.anchor_bottom = 1.0
		kb_toggle.connect("toggled", self, "_on_KeyboardToggle_toggled")
		kb_anchor.add_child(kb_toggle)
	
	var version_lbl = $UI / Control / SettingsPanel / VersionLabel
	version_lbl.text = "Game Version: " + str(ProjectSettings.get_setting("application/config/version"))
	version_lbl.modulate = Color(1, 1, 1, 1)
	version_lbl.add_color_override("font_color", Color(0.55, 0.55, 0.6, 0.7))
	var v_font = version_lbl.get_font("font")
	if v_font:
		v_font = v_font.duplicate()
		v_font.size = 24
		v_font.outline_size = 2
		v_font.outline_color = Color(0.05, 0.05, 0.1, 0.8)
		v_font.use_filter = false
		version_lbl.add_font_override("font", v_font)
	
	var build_config = ConfigFile.new()
	var build_err = build_config.load("res://build_number.cfg")
	if build_err == OK:
		var build_str = build_config.get_value("current", "build", "")
		if build_str != "":
			var build_label = Label.new()
			build_label.name = "BuildLabel"
			build_label.text = "Build: " + build_str
			build_label.align = Label.ALIGN_CENTER
			build_label.anchor_left = 0.5
			build_label.anchor_right = 0.5
			build_label.anchor_top = 1.0
			build_label.anchor_bottom = 1.0
			build_label.margin_left = - 200
			build_label.margin_right = 200
			build_label.margin_top = - 45
			build_label.margin_bottom = - 20
			build_label.modulate = Color(1, 1, 1, 1)
			build_label.add_color_override("font_color", Color(0.55, 0.55, 0.6, 0.7))
			if v_font:
				build_label.add_font_override("font", v_font.duplicate())
			$UI / Control / SettingsPanel.add_child(build_label)
	
	
	speed_tween = Tween.new()
	add_child(speed_tween)
	$UI / Control / PlayButton.rect_scale = Vector2(1.0, 1.0)
	var start_tween = Tween.new()
	add_child(start_tween)
	start_tween.interpolate_property($UI / Control / PlayButton, "margin_top", 230.0, 222.0, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	start_tween.interpolate_property($UI / Control / PlayButton, "margin_bottom", 380.0, 372.0, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	start_tween.interpolate_property($UI / Control / PlayButton, "margin_top", 222.0, 230.0, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.8)
	start_tween.interpolate_property($UI / Control / PlayButton, "margin_bottom", 372.0, 380.0, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.8)
	start_tween.repeat = true
	start_tween.start()
	
	speed_label = $UI / Control / SpeedLabel
	level_progress_bar = $UI / Control.get_node_or_null("LevelProgressBar")
	if level_progress_bar:
		level_label = level_progress_bar.get_node_or_null("LevelLabel")
	health_bar = $UI / Control.get_node_or_null("HealthBar")
	if health_bar:
		for _i in range(max_health):
			var icon = TextureRect.new()
			icon.texture = tex_health
			icon.expand = true
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.rect_min_size = Vector2(80, 80)
			health_bar.add_child(icon)
	menu_info_label = $UI / Control / MenuInfoLabel
	game_over_panel = $UI / Control / GameOverPanel
	leaderboard_panel = $UI / Control / LeaderboardPanel
	if is_instance_valid(leaderboard_panel):
		leaderboard_panel.add_stylebox_override("panel", _get_panel_stylebox())
		_create_panel_close_button(leaderboard_panel, "_on_CloseLeaderboard_pressed")
		
	settings_panel = $UI / Control / SettingsPanel
	if is_instance_valid(settings_panel):
		settings_panel.add_stylebox_override("panel", _get_panel_stylebox())
		_create_panel_close_button(settings_panel, "_on_CloseSettings_pressed")
	logo_rect = $UI / Control / Logo
	settings_button = $UI / Control / SettingsButton
	profile_button = $UI / Control / ProfileButton
	bottom_bar = $UI / Control / BottomBar
	version_label = null
	
	game_over_bottom_bar = $UI / Control.get_node_or_null("GameOverBottomBar")
	game_over_leaderboard_button = $UI / Control.get_node_or_null("GameOverLeaderboardButton")
	game_over_profile_button = $UI / Control.get_node_or_null("GameOverProfileButton")
	game_over_settings_button = $UI / Control.get_node_or_null("GameOverSettingsButton")
	
	if is_instance_valid(game_over_leaderboard_button):
		game_over_leaderboard_button.connect("pressed", self, "_on_LeaderboardButton_pressed")
		game_over_leaderboard_button.connect("button_down", self, "_on_CircleButton_down", [game_over_leaderboard_button])
		game_over_leaderboard_button.connect("button_up", self, "_on_CircleButton_up", [game_over_leaderboard_button])
	if is_instance_valid(game_over_profile_button):
		game_over_profile_button.connect("pressed", self, "_on_ProfileButton_pressed")
		game_over_profile_button.connect("button_down", self, "_on_CircleButton_down", [game_over_profile_button])
		game_over_profile_button.connect("button_up", self, "_on_CircleButton_up", [game_over_profile_button])
	if is_instance_valid(game_over_settings_button):
		game_over_settings_button.connect("pressed", self, "_on_SettingsButton_pressed")
		game_over_settings_button.connect("button_down", self, "_on_CircleButton_down", [game_over_settings_button])
		game_over_settings_button.connect("button_up", self, "_on_CircleButton_up", [game_over_settings_button])
	version_label = null
	
	_setup_firebase_ui()

	var profile_panel_node = Panel.new()
	profile_panel_node.name = "ProfilePanel"
	profile_panel_node.visible = false
	profile_panel_node.anchor_left = 0.5
	profile_panel_node.anchor_top = 0.5
	profile_panel_node.anchor_right = 0.5
	profile_panel_node.anchor_bottom = 0.5
	profile_panel_node.margin_left = - 525
	profile_panel_node.margin_top = - 840
	profile_panel_node.margin_right = 525
	profile_panel_node.margin_bottom = 520
	
	profile_panel_node.add_stylebox_override("panel", _get_panel_stylebox())
	$UI / Control.add_child(profile_panel_node)
	
	
	var profile_title = Label.new()
	profile_title.text = "Player Profile"
	profile_title.anchor_right = 1.0
	profile_title.margin_top = 30
	profile_title.margin_bottom = 90
	profile_title.margin_left = 40
	profile_title.margin_right = - 40
	profile_title.align = Label.ALIGN_CENTER
	profile_title.valign = Label.VALIGN_CENTER
	var title_font = $UI / Control / LeaderboardPanel / Title.get_font("font")
	if title_font: profile_title.add_font_override("font", title_font)
	profile_title.add_color_override("font_color", Color(1.0, 0.62, 0.25))
	profile_panel_node.add_child(profile_title)
	
	
	_create_panel_close_button(profile_panel_node, "_on_CloseProfile_pressed")
	
	
	var profile_divider = Panel.new()
	profile_divider.name = "Divider"
	profile_divider.anchor_left = 0.1
	profile_divider.anchor_right = 0.9
	profile_divider.margin_top = 110
	profile_divider.margin_bottom = 113
	var ref_div = $UI / Control / LeaderboardPanel / Divider
	if ref_div:
		var div_style = ref_div.get_stylebox("panel")
		if div_style:
			profile_divider.add_stylebox_override("panel", div_style)
	profile_panel_node.add_child(profile_divider)
	
	
	var profile_avatar_bg = TextureRect.new()
	profile_avatar_bg.name = "AvatarBg"
	profile_avatar_bg.texture = circle_bg_texture
	profile_avatar_bg.expand = true
	profile_avatar_bg.stretch_mode = TextureRect.STRETCH_SCALE
	profile_avatar_bg.anchor_left = 0.5
	profile_avatar_bg.anchor_right = 0.5
	profile_avatar_bg.margin_left = -90
	profile_avatar_bg.margin_right = 90
	profile_avatar_bg.margin_top = 130
	profile_avatar_bg.margin_bottom = 310
	profile_avatar_bg.rect_min_size = Vector2(180, 180)
	profile_avatar_bg.self_modulate = Color("#6eb4e8")
	profile_panel_node.add_child(profile_avatar_bg)
	
	profile_avatar = TextureRect.new()
	profile_avatar.name = "Avatar"
	profile_avatar.texture = tex_avatar_guest
	profile_avatar.expand = true
	profile_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	profile_avatar.anchor_left = 0.5
	profile_avatar.anchor_right = 0.5
	profile_avatar.margin_left = - 90
	profile_avatar.margin_right = 90
	profile_avatar.margin_top = 130
	profile_avatar.margin_bottom = 310
	profile_avatar.rect_min_size = Vector2(180, 180)
	profile_panel_node.add_child(profile_avatar)
	
	
	profile_name_label = Label.new()
	profile_name_label.name = "PlayerName"
	profile_name_label.text = "Player"
	profile_name_label.anchor_left = 0.0
	profile_name_label.anchor_right = 1.0
	profile_name_label.margin_top = 315
	profile_name_label.margin_bottom = 395
	profile_name_label.margin_left = 30
	profile_name_label.margin_right = - 30
	profile_name_label.align = Label.ALIGN_CENTER
	profile_name_label.valign = Label.VALIGN_CENTER
	var name_font = DynamicFont.new()
	name_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	name_font.size = 72
	name_font.outline_size = 5
	name_font.outline_color = Color(0.05, 0.08, 0.15)
	name_font.use_filter = true
	profile_name_label.add_font_override("font", name_font)
	profile_name_label.add_color_override("font_color", Color(0.5, 0.8, 1.0))
	profile_name_label.add_color_override("font_color_shadow", Color(0.2, 0.5, 0.9, 0.45))
	profile_name_label.add_constant_override("shadow_offset_x", 0)
	profile_name_label.add_constant_override("shadow_offset_y", 5)
	profile_panel_node.add_child(profile_name_label)
	
	
	profile_badge = Label.new()
	profile_badge.name = "AccountBadge"
	profile_badge.text = "Guest Account"
	profile_badge.anchor_left = 0.5
	profile_badge.anchor_right = 0.5
	profile_badge.margin_left = - 120
	profile_badge.margin_right = 120
	profile_badge.margin_top = 420
	profile_badge.margin_bottom = 458
	profile_badge.align = Label.ALIGN_CENTER
	profile_badge.valign = Label.VALIGN_CENTER
	var badge_font = DynamicFont.new()
	badge_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	badge_font.size = 26
	badge_font.outline_size = 1
	badge_font.outline_color = Color(0.05, 0.05, 0.1, 0.6)
	badge_font.use_filter = true
	profile_badge.add_font_override("font", badge_font)
	profile_badge.add_color_override("font_color", Color(1, 1, 1))
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.42, 0.45, 0.5, 0.95)
	badge_style.corner_radius_top_left = 12
	badge_style.corner_radius_top_right = 12
	badge_style.corner_radius_bottom_right = 12
	badge_style.corner_radius_bottom_left = 12
	badge_style.content_margin_left = 8
	badge_style.content_margin_right = 8
	badge_style.content_margin_top = 2
	badge_style.content_margin_bottom = 2
	profile_badge.add_stylebox_override("normal", badge_style)
	profile_panel_node.add_child(profile_badge)
	
	
	var rank_font = DynamicFont.new()
	rank_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	rank_font.size = 48
	rank_font.outline_size = 3
	rank_font.outline_color = Color(0.05, 0.05, 0.12)
	rank_font.use_filter = true
	
	var rank_value_font = DynamicFont.new()
	rank_value_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	rank_value_font.size = 48
	rank_value_font.outline_size = 3
	rank_value_font.outline_color = Color(0.3, 0.2, 0.0)
	rank_value_font.use_filter = true
	
	
	var rank_alltime_row = HBoxContainer.new()
	rank_alltime_row.anchor_left = 0.0
	rank_alltime_row.anchor_right = 1.0
	rank_alltime_row.margin_left = 110
	rank_alltime_row.margin_right = - 110
	rank_alltime_row.margin_top = 475
	rank_alltime_row.margin_bottom = 525
	rank_alltime_row.alignment = BoxContainer.ALIGN_CENTER
	rank_alltime_row.add_constant_override("separation", 24)
	var rank_alltime_label = Label.new()
	rank_alltime_label.text = "All-time Rank"
	rank_alltime_label.add_font_override("font", rank_font)
	rank_alltime_label.add_color_override("font_color", Color(0.9, 0.92, 1.0))
	rank_alltime_row.add_child(rank_alltime_label)
	profile_rank_alltime = Label.new()
	profile_rank_alltime.name = "RankAlltimeValue"
	profile_rank_alltime.text = "#2"
	profile_rank_alltime.add_font_override("font", rank_value_font)
	profile_rank_alltime.add_color_override("font_color", Color(1.0, 0.85, 0.2))
	rank_alltime_row.add_child(profile_rank_alltime)
	profile_panel_node.add_child(rank_alltime_row)
	
	
	var rank_season_row = HBoxContainer.new()
	rank_season_row.anchor_left = 0.0
	rank_season_row.anchor_right = 1.0
	rank_season_row.margin_left = 110
	rank_season_row.margin_right = - 110
	rank_season_row.margin_top = 530
	rank_season_row.margin_bottom = 580
	rank_season_row.alignment = BoxContainer.ALIGN_CENTER
	rank_season_row.add_constant_override("separation", 24)
	var rank_season_label = Label.new()
	rank_season_label.text = "Season Rank"
	rank_season_label.add_font_override("font", rank_font)
	rank_season_label.add_color_override("font_color", Color(0.9, 0.92, 1.0))
	rank_season_row.add_child(rank_season_label)
	profile_rank_season = Label.new()
	profile_rank_season.name = "RankSeasonValue"
	profile_rank_season.text = "#7"
	profile_rank_season.add_font_override("font", rank_value_font)
	profile_rank_season.add_color_override("font_color", Color(1.0, 0.85, 0.2))
	rank_season_row.add_child(profile_rank_season)
	profile_panel_node.add_child(rank_season_row)
	
	
	profile_stats_divider = Panel.new()
	profile_stats_divider.name = "StatsDivider"
	profile_stats_divider.anchor_left = 0.105
	profile_stats_divider.anchor_right = 0.895
	profile_stats_divider.margin_top = 595
	profile_stats_divider.margin_bottom = 598
	var stats_div_style = StyleBoxFlat.new()
	stats_div_style.bg_color = Color(0.3, 0.4, 0.55, 0.5)
	profile_stats_divider.add_stylebox_override("panel", stats_div_style)
	profile_panel_node.add_child(profile_stats_divider)
	
	
	profile_stats_vbox = VBoxContainer.new()
	profile_stats_vbox.name = "StatsVBox"
	profile_stats_vbox.anchor_right = 1.0
	profile_stats_vbox.margin_left = 110
	profile_stats_vbox.margin_right = - 110
	profile_stats_vbox.margin_top = 615
	profile_stats_vbox.margin_bottom = 1065
	profile_stats_vbox.add_constant_override("separation", 10)
	profile_panel_node.add_child(profile_stats_vbox)
	
	
	
	btn_claim_profile = Button.new()
	btn_claim_profile.text = "Link Account"
	btn_claim_profile.anchor_left = 0.5
	btn_claim_profile.anchor_top = 1.0
	btn_claim_profile.anchor_right = 0.5
	btn_claim_profile.anchor_bottom = 1.0
	btn_claim_profile.margin_left = - 300
	btn_claim_profile.margin_top = - 210
	btn_claim_profile.margin_right = 300
	btn_claim_profile.margin_bottom = - 115
	btn_claim_profile.connect("pressed", self, "_on_ClaimProfile_pressed")
	
	var green_btn_font = DynamicFont.new()
	green_btn_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	green_btn_font.size = 42
	green_btn_font.outline_size = 3
	green_btn_font.outline_color = Color(0.15, 0.4, 0.08)
	green_btn_font.use_filter = true
	btn_claim_profile.add_font_override("font", green_btn_font)
	
	var green_normal = StyleBoxFlat.new()
	green_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_normal.anti_aliasing = true
	green_normal.corner_radius_top_left = 22
	green_normal.corner_radius_top_right = 22
	green_normal.corner_radius_bottom_right = 22
	green_normal.corner_radius_bottom_left = 22
	green_normal.border_width_bottom = 8
	green_normal.border_color = Color(0.3, 0.6, 0.15)
	green_normal.shadow_color = Color(0, 0, 0, 0.2)
	green_normal.shadow_size = 4
	green_normal.shadow_offset = Vector2(0, 2)
	green_normal.content_margin_left = 20
	green_normal.content_margin_right = 20
	
	var green_hover = StyleBoxFlat.new()
	green_hover.bg_color = Color(0.45, 0.85, 0.25)
	green_hover.anti_aliasing = true
	green_hover.corner_radius_top_left = 22
	green_hover.corner_radius_top_right = 22
	green_hover.corner_radius_bottom_right = 22
	green_hover.corner_radius_bottom_left = 22
	green_hover.border_width_bottom = 8
	green_hover.border_color = Color(0.35, 0.65, 0.18)
	green_hover.shadow_color = Color(0, 0, 0, 0.25)
	green_hover.shadow_size = 6
	green_hover.shadow_offset = Vector2(0, 3)
	green_hover.content_margin_left = 20
	green_hover.content_margin_right = 20

	var green_pressed = StyleBoxFlat.new()
	green_pressed.bg_color = Color(0.35, 0.7, 0.15)
	green_pressed.anti_aliasing = true
	green_pressed.corner_radius_top_left = 22
	green_pressed.corner_radius_top_right = 22
	green_pressed.corner_radius_bottom_right = 22
	green_pressed.corner_radius_bottom_left = 22
	green_pressed.border_width_top = 4
	green_pressed.border_width_bottom = 4
	green_pressed.border_color = Color(0.25, 0.5, 0.1)
	green_pressed.shadow_color = Color(0, 0, 0, 0.15)
	green_pressed.shadow_size = 2
	green_pressed.shadow_offset = Vector2(0, 1)
	green_pressed.content_margin_left = 20
	green_pressed.content_margin_right = 20

	btn_claim_profile.add_stylebox_override("normal", green_normal)
	btn_claim_profile.add_stylebox_override("hover", green_hover)
	btn_claim_profile.add_stylebox_override("pressed", green_pressed)
	btn_claim_profile.add_color_override("font_color", Color(1, 1, 1))
	btn_claim_profile.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_claim_profile.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	profile_panel_node.add_child(btn_claim_profile)

	
	btn_manage_account = Button.new()
	btn_manage_account.text = "Manage Account"
	btn_manage_account.anchor_left = 0.5
	btn_manage_account.anchor_top = 1.0
	btn_manage_account.anchor_right = 0.5
	btn_manage_account.anchor_bottom = 1.0
	btn_manage_account.margin_left = - 300
	btn_manage_account.margin_top = - 210
	btn_manage_account.margin_right = 300
	btn_manage_account.margin_bottom = - 115
	btn_manage_account.connect("pressed", self, "_on_ManageAccount_pressed")
	
	var manage_btn_font = green_btn_font.duplicate()
	manage_btn_font.size = 45
	btn_manage_account.add_font_override("font", manage_btn_font)
	btn_manage_account.add_stylebox_override("normal", green_normal)
	btn_manage_account.add_stylebox_override("hover", green_hover)
	btn_manage_account.add_stylebox_override("pressed", green_pressed)
	btn_manage_account.add_color_override("font_color", Color(1, 1, 1))
	btn_manage_account.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_manage_account.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	profile_panel_node.add_child(btn_manage_account)

	
	btn_reconnect = Button.new()
	btn_reconnect.text = "Retry Connection"
	btn_reconnect.anchor_left = 0.5
	btn_reconnect.anchor_top = 1.0
	btn_reconnect.anchor_right = 0.5
	btn_reconnect.anchor_bottom = 1.0
	btn_reconnect.margin_left = - 300
	btn_reconnect.margin_top = - 210
	btn_reconnect.margin_right = 300
	btn_reconnect.margin_bottom = - 115
	btn_reconnect.connect("pressed", self, "_on_Reconnect_pressed")
	
	var reconnect_btn_font = green_btn_font.duplicate()
	reconnect_btn_font.size = 45
	btn_reconnect.add_font_override("font", reconnect_btn_font)
	btn_reconnect.add_stylebox_override("normal", green_normal)
	btn_reconnect.add_stylebox_override("hover", green_hover)
	btn_reconnect.add_stylebox_override("pressed", green_pressed)
	btn_reconnect.add_color_override("font_color", Color(1, 1, 1))
	btn_reconnect.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_reconnect.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	profile_panel_node.add_child(btn_reconnect)

	
	profile_disclaimer = RichTextLabel.new()
	profile_disclaimer.bbcode_enabled = true
	profile_disclaimer.scroll_active = false
	profile_disclaimer.anchor_left = 0.0
	profile_disclaimer.anchor_top = 1.0
	profile_disclaimer.anchor_right = 1.0
	profile_disclaimer.anchor_bottom = 1.0
	profile_disclaimer.margin_left = 20
	profile_disclaimer.margin_right = - 20
	profile_disclaimer.margin_top = - 100
	profile_disclaimer.margin_bottom = - 10
	var footer_font = DynamicFont.new()
	footer_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	footer_font.size = 24
	footer_font.outline_size = 2
	footer_font.outline_color = Color(0.05, 0.05, 0.1, 0.8)
	footer_font.use_filter = false
	profile_disclaimer.add_font_override("normal_font", footer_font)
	profile_disclaimer.add_color_override("default_color", Color(0.55, 0.55, 0.6, 0.7))
	profile_panel_node.add_child(profile_disclaimer)

	inspector_panel_node = Panel.new()
	inspector_panel_node.name = "InspectorPanel"
	inspector_panel_node.visible = false
	inspector_panel_node.anchor_left = 0.5
	inspector_panel_node.anchor_top = 0.5
	inspector_panel_node.anchor_right = 0.5
	inspector_panel_node.anchor_bottom = 0.5
	inspector_panel_node.margin_left = - 525
	inspector_panel_node.margin_top = - 840
	inspector_panel_node.margin_right = 525
	inspector_panel_node.margin_bottom = 520
	inspector_panel_node.add_stylebox_override("panel", _get_panel_stylebox())
	$UI / Control.add_child(inspector_panel_node)
	
	var inspector_title = Label.new()
	inspector_title.name = "Title"
	inspector_title.text = "Inspect Profile"
	inspector_title.anchor_right = 1.0
	inspector_title.margin_top = 30
	inspector_title.margin_bottom = 90
	inspector_title.margin_left = 40
	inspector_title.margin_right = - 40
	inspector_title.align = Label.ALIGN_CENTER
	inspector_title.valign = Label.VALIGN_CENTER
	if title_font: inspector_title.add_font_override("font", title_font)
	inspector_title.add_color_override("font_color", Color(1.0, 0.62, 0.25))
	inspector_panel_node.add_child(inspector_title)
	
	_create_panel_close_button(inspector_panel_node, "_on_CloseInspector_pressed")
	
	var inspector_divider = Panel.new()
	inspector_divider.name = "Divider"
	inspector_divider.anchor_left = 0.1
	inspector_divider.anchor_right = 0.9
	inspector_divider.margin_top = 110
	inspector_divider.margin_bottom = 113
	ref_div = $UI / Control / LeaderboardPanel / Divider
	if ref_div:
		var div_style = ref_div.get_stylebox("panel")
		if div_style:
			inspector_divider.add_stylebox_override("panel", div_style)
	inspector_panel_node.add_child(inspector_divider)
	
	var inspector_avatar_bg = TextureRect.new()
	inspector_avatar_bg.name = "AvatarBg"
	inspector_avatar_bg.texture = circle_bg_texture
	inspector_avatar_bg.expand = true
	inspector_avatar_bg.stretch_mode = TextureRect.STRETCH_SCALE
	inspector_avatar_bg.anchor_left = 0.5
	inspector_avatar_bg.anchor_right = 0.5
	inspector_avatar_bg.margin_left = -90
	inspector_avatar_bg.margin_right = 90
	inspector_avatar_bg.margin_top = 130
	inspector_avatar_bg.margin_bottom = 310
	inspector_avatar_bg.rect_min_size = Vector2(180, 180)
	inspector_avatar_bg.self_modulate = Color("#6eb4e8")
	inspector_panel_node.add_child(inspector_avatar_bg)
	
	inspector_avatar = TextureRect.new()
	inspector_avatar.name = "Avatar"
	inspector_avatar.texture = tex_avatar_guest
	inspector_avatar.expand = true
	inspector_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	inspector_avatar.anchor_left = 0.5
	inspector_avatar.anchor_right = 0.5
	inspector_avatar.margin_left = - 90
	inspector_avatar.margin_right = 90
	inspector_avatar.margin_top = 130
	inspector_avatar.margin_bottom = 310
	inspector_avatar.rect_min_size = Vector2(180, 180)
	inspector_panel_node.add_child(inspector_avatar)
	
	inspector_name_label = Label.new()
	inspector_name_label.name = "PlayerName"
	inspector_name_label.text = "Player"
	inspector_name_label.anchor_left = 0.0
	inspector_name_label.anchor_right = 1.0
	inspector_name_label.margin_top = 315
	inspector_name_label.margin_bottom = 395
	inspector_name_label.margin_left = 30
	inspector_name_label.margin_right = - 30
	inspector_name_label.align = Label.ALIGN_CENTER
	inspector_name_label.valign = Label.VALIGN_CENTER
	var insp_name_font = DynamicFont.new()
	insp_name_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	insp_name_font.size = 72
	insp_name_font.outline_size = 5
	insp_name_font.outline_color = Color(0.05, 0.08, 0.15)
	insp_name_font.use_filter = true
	inspector_name_label.add_font_override("font", insp_name_font)
	inspector_name_label.add_color_override("font_color", Color(0.5, 0.8, 1.0))
	inspector_name_label.add_color_override("font_color_shadow", Color(0.2, 0.5, 0.9, 0.45))
	inspector_name_label.add_constant_override("shadow_offset_x", 0)
	inspector_name_label.add_constant_override("shadow_offset_y", 5)
	inspector_panel_node.add_child(inspector_name_label)
	
	inspector_badge = Label.new()
	inspector_badge.name = "AccountBadge"
	inspector_badge.text = "Guest Account"
	inspector_badge.anchor_left = 0.5
	inspector_badge.anchor_right = 0.5
	inspector_badge.margin_left = - 120
	inspector_badge.margin_right = 120
	inspector_badge.margin_top = 420
	inspector_badge.margin_bottom = 458
	inspector_badge.align = Label.ALIGN_CENTER
	inspector_badge.valign = Label.VALIGN_CENTER
	var insp_badge_font = DynamicFont.new()
	insp_badge_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	insp_badge_font.size = 26
	insp_badge_font.outline_size = 1
	insp_badge_font.outline_color = Color(0.05, 0.05, 0.1, 0.6)
	insp_badge_font.use_filter = true
	inspector_badge.add_font_override("font", insp_badge_font)
	inspector_badge.add_color_override("font_color", Color(1, 1, 1))
	var insp_badge_style = StyleBoxFlat.new()
	insp_badge_style.bg_color = Color(0.42, 0.45, 0.5, 0.95)
	insp_badge_style.corner_radius_top_left = 12
	insp_badge_style.corner_radius_top_right = 12
	insp_badge_style.corner_radius_bottom_right = 12
	insp_badge_style.corner_radius_bottom_left = 12
	insp_badge_style.content_margin_left = 8
	insp_badge_style.content_margin_right = 8
	insp_badge_style.content_margin_top = 2
	insp_badge_style.content_margin_bottom = 2
	inspector_badge.add_stylebox_override("normal", insp_badge_style)
	inspector_panel_node.add_child(inspector_badge)
	
	var insp_rank_font = DynamicFont.new()
	insp_rank_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	insp_rank_font.size = 48
	insp_rank_font.outline_size = 3
	insp_rank_font.outline_color = Color(0.05, 0.05, 0.12)
	insp_rank_font.use_filter = true
	
	var insp_rank_value_font = DynamicFont.new()
	insp_rank_value_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	insp_rank_value_font.size = 48
	insp_rank_value_font.outline_size = 3
	insp_rank_value_font.outline_color = Color(0.3, 0.2, 0.0)
	insp_rank_value_font.use_filter = true
	
	rank_alltime_row = HBoxContainer.new()
	rank_alltime_row.anchor_left = 0.0
	rank_alltime_row.anchor_right = 1.0
	rank_alltime_row.margin_left = 110
	rank_alltime_row.margin_right = - 110
	rank_alltime_row.margin_top = 475
	rank_alltime_row.margin_bottom = 525
	rank_alltime_row.alignment = BoxContainer.ALIGN_CENTER
	rank_alltime_row.add_constant_override("separation", 24)
	rank_alltime_label = Label.new()
	rank_alltime_label.text = "All-time Rank"
	rank_alltime_label.add_font_override("font", insp_rank_font)
	rank_alltime_label.add_color_override("font_color", Color(0.9, 0.92, 1.0))
	rank_alltime_row.add_child(rank_alltime_label)
	inspector_rank_alltime = Label.new()
	inspector_rank_alltime.name = "RankAlltimeValue"
	inspector_rank_alltime.text = "Unranked"
	inspector_rank_alltime.add_font_override("font", insp_rank_value_font)
	inspector_rank_alltime.add_color_override("font_color", Color(1.0, 0.85, 0.2))
	rank_alltime_row.add_child(inspector_rank_alltime)
	inspector_panel_node.add_child(rank_alltime_row)
	
	rank_season_row = HBoxContainer.new()
	rank_season_row.anchor_left = 0.0
	rank_season_row.anchor_right = 1.0
	rank_season_row.margin_left = 110
	rank_season_row.margin_right = - 110
	rank_season_row.margin_top = 530
	rank_season_row.margin_bottom = 580
	rank_season_row.alignment = BoxContainer.ALIGN_CENTER
	rank_season_row.add_constant_override("separation", 24)
	rank_season_label = Label.new()
	rank_season_label.text = "Season Rank"
	rank_season_label.add_font_override("font", insp_rank_font)
	rank_season_label.add_color_override("font_color", Color(0.9, 0.92, 1.0))
	rank_season_row.add_child(rank_season_label)
	inspector_rank_season = Label.new()
	inspector_rank_season.name = "RankSeasonValue"
	inspector_rank_season.text = "Unranked"
	inspector_rank_season.add_font_override("font", insp_rank_value_font)
	inspector_rank_season.add_color_override("font_color", Color(1.0, 0.85, 0.2))
	rank_season_row.add_child(inspector_rank_season)
	inspector_panel_node.add_child(rank_season_row)
	
	inspector_stats_divider = Panel.new()
	inspector_stats_divider.name = "StatsDivider"
	inspector_stats_divider.anchor_left = 0.105
	inspector_stats_divider.anchor_right = 0.895
	inspector_stats_divider.margin_top = 595
	inspector_stats_divider.margin_bottom = 598
	stats_div_style = StyleBoxFlat.new()
	stats_div_style.bg_color = Color(0.3, 0.4, 0.55, 0.5)
	inspector_stats_divider.add_stylebox_override("panel", stats_div_style)
	inspector_panel_node.add_child(inspector_stats_divider)
	
	inspector_vbox = VBoxContainer.new()
	inspector_vbox.name = "VBox"
	inspector_vbox.anchor_right = 1.0
	inspector_vbox.margin_left = 110
	inspector_vbox.margin_right = - 110
	inspector_vbox.margin_top = 615
	inspector_vbox.margin_bottom = 1065
	inspector_vbox.add_constant_override("separation", 10)
	inspector_panel_node.add_child(inspector_vbox)
	
	inspector_disclaimer = RichTextLabel.new()
	inspector_disclaimer.bbcode_enabled = true
	inspector_disclaimer.scroll_active = false
	inspector_disclaimer.anchor_left = 0.0
	inspector_disclaimer.anchor_top = 1.0
	inspector_disclaimer.anchor_right = 1.0
	inspector_disclaimer.anchor_bottom = 1.0
	inspector_disclaimer.margin_left = 20
	inspector_disclaimer.margin_right = - 20
	inspector_disclaimer.margin_top = - 100
	inspector_disclaimer.margin_bottom = - 10
	var desc_font = DynamicFont.new()
	desc_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	desc_font.size = 24
	desc_font.outline_size = 2
	desc_font.outline_color = Color(0.05, 0.05, 0.1, 0.8)
	desc_font.use_filter = false
	inspector_disclaimer.add_font_override("normal_font", desc_font)
	inspector_disclaimer.add_color_override("default_color", Color(0.55, 0.55, 0.6, 0.7))
	inspector_panel_node.add_child(inspector_disclaimer)

	if OS.is_debug_build():
		
		if has_node("MeshInstance/StaticBody"):
			$MeshInstance / StaticBody.collision_layer = 2

	var err_panel = Panel.new()
	err_panel.name = "StorageErrorPanel"
	err_panel.visible = false
	err_panel.anchor_right = 1.0
	err_panel.anchor_bottom = 1.0
	
	err_panel.add_stylebox_override("panel", StyleBoxEmpty.new())
	_add_blur_background(err_panel)
	
	var card = Panel.new()
	card.name = "Card"
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.margin_left = - 460
	card.margin_top = - 340
	card.margin_right = 460
	card.margin_bottom = 340
	
	var err_panel_style = StyleBoxFlat.new()
	err_panel_style.bg_color = Color(0.06, 0.09, 0.15, 1.0)
	err_panel_style.corner_radius_top_left = 24
	err_panel_style.corner_radius_top_right = 24
	err_panel_style.corner_radius_bottom_right = 24
	err_panel_style.corner_radius_bottom_left = 24
	err_panel_style.corner_detail = 30
	err_panel_style.anti_aliasing = true
	err_panel_style.border_width_left = 4
	err_panel_style.border_width_top = 4
	err_panel_style.border_width_right = 4
	err_panel_style.border_width_bottom = 4
	err_panel_style.border_color = Color(0.18, 0.35, 0.55, 0.8)
	card.add_stylebox_override("panel", err_panel_style)
	err_panel.add_child(card)
			
	$UI / Control.add_child(err_panel)
	
	var err_title = Label.new()
	err_title.text = "Storage Error"
	err_title.anchor_right = 1.0
	err_title.margin_left = 40
	err_title.margin_right = - 40
	err_title.margin_top = 40
	err_title.margin_bottom = 130
	err_title.align = Label.ALIGN_CENTER
	err_title.valign = Label.VALIGN_CENTER
	err_title.add_color_override("font_color", Color(1, 1, 1))
	var err_title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if err_title_font:
		err_title_font.size = 60
		err_title_font.outline_size = 3
		err_title_font.outline_color = Color(0.08, 0.1, 0.15)
		err_title.add_font_override("font", err_title_font)
	card.add_child(err_title)
	
	var err_divider = Panel.new()
	err_divider.anchor_left = 0.1
	err_divider.anchor_right = 0.9
	err_divider.margin_top = 148
	err_divider.margin_bottom = 151
	var err_div_style = StyleBoxFlat.new()
	err_div_style.bg_color = Color(0.18, 0.35, 0.55, 0.7)
	err_divider.add_stylebox_override("panel", err_div_style)
	card.add_child(err_divider)

	var err_msg = Label.new()
	err_msg.name = "MessageLabel"
	err_msg.text = ""
	err_msg.autowrap = true
	err_msg.align = Label.ALIGN_CENTER
	err_msg.valign = Label.VALIGN_CENTER
	err_msg.anchor_left = 0.05
	err_msg.anchor_right = 0.95
	err_msg.margin_top = 175
	err_msg.margin_bottom = 510
	var msg_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if msg_font:
		msg_font.size = 40
		msg_font.outline_size = 2
		msg_font.outline_color = Color(0.08, 0.1, 0.15)
		err_msg.add_font_override("font", msg_font)
	err_msg.add_color_override("font_color", Color(0.85, 0.88, 0.95))
	card.add_child(err_msg)
	
	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.anchor_left = 0.5
	ok_btn.anchor_top = 1.0
	ok_btn.anchor_right = 0.5
	ok_btn.anchor_bottom = 1.0
	ok_btn.margin_left = - 200
	ok_btn.margin_top = - 140
	ok_btn.margin_right = 200
	ok_btn.margin_bottom = - 40
	ok_btn.connect("pressed", self, "_on_CloseStorageError_pressed")
	var ok_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if ok_font:
		ok_font.size = 45
		ok_font.outline_size = 3
		ok_font.outline_color = Color(0.15, 0.4, 0.08)
		ok_btn.add_font_override("font", ok_font)
	var ok_style = StyleBoxFlat.new()
	ok_style.bg_color = Color(0.4, 0.8, 0.2)
	ok_style.corner_radius_top_left = 20
	ok_style.corner_radius_top_right = 20
	ok_style.corner_radius_bottom_right = 20
	ok_style.corner_radius_bottom_left = 20
	ok_style.border_width_bottom = 8
	ok_style.border_color = Color(0.3, 0.6, 0.15)
	ok_style.content_margin_left = 30
	ok_style.content_margin_right = 30
	
	var ok_hover = ok_style.duplicate()
	ok_hover.bg_color = Color(0.45, 0.85, 0.25)
	ok_hover.border_color = Color(0.35, 0.65, 0.18)
	
	var ok_pressed = ok_style.duplicate()
	ok_pressed.bg_color = Color(0.35, 0.7, 0.15)
	ok_pressed.border_width_top = 4
	ok_pressed.border_width_bottom = 4
	ok_pressed.border_color = Color(0.25, 0.5, 0.1)
	
	ok_btn.add_stylebox_override("normal", ok_style)
	ok_btn.add_stylebox_override("hover", ok_hover)
	ok_btn.add_stylebox_override("pressed", ok_pressed)
	ok_btn.add_color_override("font_color", Color(1, 1, 1))
	ok_btn.add_color_override("font_color_hover", Color(1, 1, 1))
	ok_btn.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	card.add_child(ok_btn)

	update_mode_button_text()
	update_score_display()
	_update_onscreen_keyboard_visibility()
	
	if Global.auto_start:
		Global.auto_start = false
		call_deferred("_on_Button_pressed", false)
func _exit_tree():
	if FirebaseManager.is_claiming_profile():
		FirebaseManager.resolve_conflict_cancel()
	save_hiscore(false)
	
func save_hiscore(sync_to_cloud: bool = true):
	var file = File.new()
	var err = file.open("user://player_data_rushybird.dat", File.WRITE)
	if err != OK or not file.is_open():
		if not storage_error_shown:
			storage_error_shown = true
			show_storage_error("Failed to save player stats and settings. Storage access might be restricted by your browser.")
		return
		
	player_data["player_name"] = Global.player_name
	player_data["last_updated"] = OS.get_unix_time()
	
	var data = {
		"player_data": player_data, 
		"mode": mode_level, 
		"music_volume": music_volume, 
		"sfx_enabled": sfx_enabled, 
		"onscreen_keyboard_setting_enabled": onscreen_keyboard_setting_enabled, 
		"has_changed_name": Global.has_changed_name, 
		"last_sync_timestamp": last_sync_timestamp, 
		"web_volume_warning_shown": web_volume_warning_shown
	}
	file.store_var(data)
	file.close()
	
	if OS.is_debug_build() and sync_to_cloud:
		var stats_p = player_data.get("pending_stats_sync", false)
		var score_p = player_data.get("pending_score_sync", false)
		if stats_p or score_p:
			print("[Debug Sync] Saved local data. Unsynced changes pending: stats = ", stats_p, ", score = ", score_p)
	
	if sync_to_cloud:
		FirebaseManager.submit_stats(player_data)

func load_hiscore():
	if Global.player_name == "":
		randomize()
		Global.player_name = "Player" + str(randi() % 900000 + 100000)
		player_data["player_name"] = Global.player_name

	var file = File.new()
	if not file.file_exists("user://player_data_rushybird.dat"):
		return
		
	var err = file.open("user://player_data_rushybird.dat", File.READ)
	
	if err != OK or not file.is_open():
		if file:
			file.close()
		if not storage_error_shown:
			storage_error_shown = true
			show_storage_error("Failed to restore player stats and settings. Storage access might be restricted by your browser.")
		return
		
	var content = file.get_var()
	if typeof(content) == TYPE_DICTIONARY:
		if content.has("player_data"):
			var loaded_data = content.get("player_data")
			for key in player_data.keys():
				if loaded_data.has(key):
					player_data[key] = loaded_data[key]
		
		if content.has("music_volume"):
			music_volume = content.get("music_volume")
			
		if content.has("sfx_enabled"):
			sfx_enabled = content.get("sfx_enabled")
			
		if content.has("onscreen_keyboard_setting_enabled"):
			onscreen_keyboard_setting_enabled = content.get("onscreen_keyboard_setting_enabled")
			
		if content.has("has_changed_name"):
			Global.has_changed_name = content.get("has_changed_name")
			
		if content.has("last_sync_timestamp"):
			last_sync_timestamp = content.get("last_sync_timestamp")
			
		if content.has("web_volume_warning_shown"):
			web_volume_warning_shown = content.get("web_volume_warning_shown")
			
		if player_data.has("player_name"):
			Global.player_name = player_data["player_name"]
	
	file.close()

func _process(delta):
	if game_playing:
		if mode_level == 1:
			run_playtime += delta
			
			if not get_tree().paused:
				run_distance += (delta * 10.0 * game_speed)
				if game_speed > run_max_speed:
					run_max_speed = game_speed
		if progression_pause_timer > 0.0:
			progression_pause_timer -= delta
		else:
			if mode_level == 1:
				level_time_survived += delta
			
				
				
				var MAX_SPEED = 2.5
				game_speed += (MAX_SPEED - game_speed) * 0.003 * delta
				
				if level_progress_bar:
					level_progress_bar.value = (level_time_survived / time_to_next_level) * 100.0
					
				if level_time_survived >= time_to_next_level:
					current_speed_level += 1
					level_time_survived -= time_to_next_level
					
					
					if time_to_next_level < 45.0:
						time_to_next_level += 5.0
					
					if current_speed_level > get_highest_level(mode_level):
						set_highest_level(mode_level, current_speed_level)
						save_hiscore(false)
					
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
			
	
	if not game_playing and is_instance_valid(logo_rect) and logo_rect.visible:
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
	if mode_level == 0: return "Classic"
	elif mode_level == 1: return "Escalation"
	return "Unknown"

func update_mode_button_text():
	$UI / Control / ModeButton.text = "Mode: " + get_mode_string()

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
		
		
		h_tween.interpolate_property(health_bar, "modulate", Color(2, 0, 0), Color(1, 1, 1), 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
		
		
		lost_icon.rect_pivot_offset = lost_icon.rect_size / 2.0
		h_tween.interpolate_property(lost_icon, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.5, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		h_tween.interpolate_property(lost_icon, "modulate", Color(2, 0, 0), Color(1, 1, 1), 0.5, Tween.TRANS_LINEAR, Tween.EASE_IN_OUT)
		
		h_tween.start()
		h_tween.connect("tween_all_completed", h_tween, "queue_free")
		
		
		var float_txt = Label.new()
		float_txt.text = "-1 HEALTH!"
		var font = $UI / Control / MenuInfoLabel.get_font("font")
		float_txt.add_font_override("font", font)
		float_txt.add_color_override("font_color", Color(1.0, 0.2, 0.2))
		
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
		var end_pos = start_pos + Vector2( - 40, 60)
		txt_tween.interpolate_property(float_txt, "rect_global_position", start_pos, end_pos, 1.2, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		txt_tween.interpolate_property(float_txt, "modulate:a", 1.0, 0.0, 1.2, Tween.TRANS_SINE, Tween.EASE_IN)
		
		txt_tween.start()
		txt_tween.connect("tween_all_completed", float_txt, "queue_free")

func revive_me_jett() -> bool:
	if mode_level == 0:
		return false
		
	if current_health > 1:
		current_health -= 1
		update_health_display()
		play_health_consumed_animation(current_health)
		
		if is_instance_valid(revive_sound):
			get_tree().create_timer(0.15).connect("timeout", self, "play_revive_sound")
		
		progression_pause_timer = 2.5 / max(game_speed, 1.0)
		$ObstacleSpawner.clear_obstacles()
		player_data["total_revives"] = player_data.get("total_revives", 0) + 1
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
	$UI / Control / Score.text = String(score)
	if not cheats_used:
		if score > get_highscore(mode_level):
			is_new_high_score = true
		if score >= get_highscore(mode_level):
			set_highscore(mode_level, score)
		
	if menu_info_label:
		if mode_level == 1:
			menu_info_label.text = "YOUR BEST: " + String(get_highscore(mode_level)) + " (Lvl " + str(get_highest_level(mode_level)) + ")"
		else:
			menu_info_label.text = "YOUR BEST: " + String(get_highscore(mode_level))

func _on_Button_pressed(play_sound: bool = true):
	cheats_used = false
	if has_node("UI/Control/Score"):
		$UI / Control / Score.modulate = Color(1.0, 1.0, 1.0)
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

	is_new_high_score = false
	game_playing = true
	is_game_over_active = false
	
	if mode_level == 1:
		player_data["total_games"] = player_data.get("total_games", 0) + 1
		
	run_distance = 0.0
	run_max_speed = 1.0
	run_playtime = 0.0
	
	save_hiscore(false)

	$UI / Control / PlayButton.hide()
	$UI / Control / ModeButton.hide()
	$UI / Control / LeaderboardButton.hide()
	if profile_button: profile_button.hide()
	if menu_info_label: menu_info_label.hide()
	if version_label: version_label.hide()
	if settings_button: settings_button.hide()
	if bottom_bar: bottom_bar.hide()
	if is_instance_valid(logo_rect): logo_rect.hide()
	
	if is_instance_valid(game_over_bottom_bar): game_over_bottom_bar.hide()
	if is_instance_valid(game_over_leaderboard_button): game_over_leaderboard_button.hide()
	if is_instance_valid(game_over_profile_button): game_over_profile_button.hide()
	if is_instance_valid(game_over_settings_button): game_over_settings_button.hide()
	
	$UI / Control / Score.show()
	$UI / Control / Score.text = "0"
	
	if mode_level == 1:
		speed_label.text = "ESCALATION MODE\nIt gets faster. Good luck."
		if level_progress_bar:
			level_progress_bar.show()
		current_health = max_health
		update_health_display()
		if health_bar:
			health_bar.show()
	else:
		speed_label.text = "CLASSIC MODE\nClassic rules. Pure skill."
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

func _hide_active_screen():
	if is_game_over_active:
		if game_over_panel: game_over_panel.hide()
		$UI / Control / RestartButton.hide()
		$UI / Control / MainMenuButton.hide()
		
		if is_instance_valid(logo_rect): logo_rect.hide()
	else:
		
		$UI / Control / PlayButton.hide()
		$UI / Control / ModeButton.hide()
		if menu_info_label: menu_info_label.hide()
		if version_label: version_label.hide()
		if is_instance_valid(logo_rect): logo_rect.hide()
		



func _close_active_panel_only():
	if active_panel_name == "leaderboard":
		if leaderboard_panel: leaderboard_panel.hide()
	elif active_panel_name == "profile":
		var p = $UI / Control.get_node_or_null("ProfilePanel")
		if p: p.hide()
	elif active_panel_name == "settings":
		if settings_panel: settings_panel.hide()
	if inspector_panel_node:
		inspector_panel_node.hide()
	active_panel_name = ""

func _show_active_screen():
	if is_game_over_active:
		if game_over_panel: game_over_panel.show()
		$UI / Control / RestartButton.show()
		$UI / Control / MainMenuButton.show()
		if is_instance_valid(game_over_bottom_bar): game_over_bottom_bar.show()
		if is_instance_valid(game_over_leaderboard_button): game_over_leaderboard_button.show()
		if is_instance_valid(game_over_profile_button): game_over_profile_button.show()
		if is_instance_valid(game_over_settings_button): game_over_settings_button.show()
		if is_instance_valid(logo_rect): logo_rect.show()
		if version_label: version_label.show()
	else:
		$UI / Control / PlayButton.show()
		$UI / Control / ModeButton.show()
		$UI / Control / LeaderboardButton.show()
		if profile_button: profile_button.show()
		if is_instance_valid(settings_button): settings_button.show()
		if menu_info_label: menu_info_label.show()
		if version_label: version_label.show()
		if bottom_bar: bottom_bar.show()
		if is_instance_valid(logo_rect): logo_rect.show()

func _on_LeaderboardButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	
	if active_panel_name == "leaderboard":
		if inspector_panel_node and inspector_panel_node.visible:
			inspector_panel_node.hide()
			leaderboard_panel.show()
			return
		active_panel_name = ""
		leaderboard_panel.hide()
		_show_active_screen()
		return
	
	
	var was_panel_open = active_panel_name != ""
	_close_active_panel_only()
	
	
	if not was_panel_open:
		_hide_active_screen()
	
	active_panel_name = "leaderboard"
	leaderboard_panel.show()
	_show_loading_leaderboards()
	FirebaseManager.fetch_leaderboards()

func _show_loading_leaderboards():
	for child in all_time_vbox.get_children():
		child.queue_free()
	for child in seasonal_vbox.get_children():
		child.queue_free()
		
	var all_time_loading = _create_vbox_spinner("Loading...")
	var seasonal_loading = _create_vbox_spinner("Loading...")
	
	all_time_vbox.add_child(all_time_loading)
	seasonal_vbox.add_child(seasonal_loading)
	
	var all_time_spinner = all_time_loading.find_node("SpinnerIcon", true, false)
	var seasonal_spinner = seasonal_loading.find_node("SpinnerIcon", true, false)
	_start_spinner_animation(all_time_spinner)
	_start_spinner_animation(seasonal_spinner)

func _on_leaderboard_updated(all_time, seasonal):
	for child in all_time_vbox.get_children():
		child.queue_free()
	for child in seasonal_vbox.get_children():
		child.queue_free()
		
	_populate_leaderboard(all_time_vbox, all_time)
	_populate_leaderboard(seasonal_vbox, seasonal)
	_update_profile_panel()

func _populate_leaderboard(vbox, data):
	var top_spacer = Control.new()
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_spacer.rect_min_size = Vector2(0, 15)
	vbox.add_child(top_spacer)
	
	var base_font = $UI / Control / MenuInfoLabel.get_font("font")
	var row_font = null
	if base_font:
		row_font = base_font.duplicate()
		row_font.size = 48
		row_font.outline_size = 2.5
		row_font.outline_color = Color(0.05, 0.05, 0.1)
	
	if vbox == seasonal_vbox:
		var timer_label = leaderboard_panel.get_node_or_null("SeasonalTimerLabel")
		if timer_label:
			timer_label.text = _get_seasonal_reset_time_string()
	if data == null:
		var offline = Label.new()
		offline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not FirebaseManager.is_config_available:
			offline.text = "Offline Mode.\nLeaderboard is disabled."
		else:
			offline.text = "Connection Error.\nFailed to load leaderboard."
		offline.align = Label.ALIGN_CENTER
		offline.valign = Label.VALIGN_CENTER
		offline.size_flags_vertical = Control.SIZE_EXPAND_FILL
		offline.add_color_override("font_color", Color(1.0, 0.3, 0.3))
		if row_font: offline.add_font_override("font", row_font)
		vbox.add_child(offline)
		return
		
	if data.empty():
		var empty = Label.new()
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.text = "No scores yet!"
		empty.align = Label.ALIGN_CENTER
		empty.valign = Label.VALIGN_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if row_font: empty.add_font_override("font", row_font)
		vbox.add_child(empty)
		return
		
	var rank = 1
	for entry in data:
		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_constant_override("separation", 0)
		
		var uid = entry.get("uid", "")
		var is_current_user = (uid != "" and uid == FirebaseManager.get_current_user_id())
		
		var rank_lbl = Label.new()
		rank_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rank_lbl.text = "#" + str(rank)
		rank_lbl.rect_min_size = Vector2(120, 0)
		rank_lbl.align = Label.ALIGN_CENTER
		rank_lbl.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		if row_font: rank_lbl.add_font_override("font", row_font)
		
		var name_container = HBoxContainer.new()
		name_container.mouse_filter = Control.MOUSE_FILTER_PASS
		name_container.rect_min_size = Vector2(560, 0)
		name_container.alignment = BoxContainer.ALIGN_CENTER
		
		var name_btn = LinkButton.new()
		var p_name = entry.get("player_name", "Unknown")
		if p_name.length() > 20:
			p_name = p_name.substr(0, 17) + "..."
		name_btn.text = p_name
		name_btn.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		name_btn.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		name_btn.add_color_override("font_color_hover", Color(0.85, 0.88, 0.95).lightened(0.15))
		name_btn.add_color_override("font_color_pressed", Color(0.85, 0.88, 0.95).darkened(0.15))
		if row_font: name_btn.add_font_override("font", row_font)
		
		var is_entry_verified = bool(entry.get("is_registered", false)) or (uid == DEVELOPER_UID)
		if uid != "" and is_entry_verified:
			name_btn.connect("pressed", self, "_on_leaderboard_player_clicked", [uid, entry.get("player_name", "Unknown")])
		else:
			name_btn.underline = LinkButton.UNDERLINE_MODE_NEVER
			name_btn.mouse_default_cursor_shape = Control.CURSOR_ARROW
		
		name_container.add_child(name_btn)
		
		if bool(entry.get("is_registered", false)):
			var check_spacer = Control.new()
			check_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			check_spacer.rect_min_size = Vector2(8, 0)
			name_container.add_child(check_spacer)
			
			var check_icon = TextureRect.new()
			check_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			check_icon.texture = tex_verified_badge
			check_icon.expand = true
			check_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			check_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var badge_size = 26
			if row_font:
				badge_size = int(row_font.size * 0.9)
			check_icon.rect_min_size = Vector2(badge_size, badge_size)
			name_container.add_child(check_icon)
		
		var score_lbl = Label.new()
		score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_lbl.text = str(entry.get("score", 0))
		score_lbl.align = Label.ALIGN_CENTER
		score_lbl.rect_min_size = Vector2(160, 0)
		score_lbl.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		if row_font: score_lbl.add_font_override("font", row_font)
		
		var lvl_lbl = Label.new()
		lvl_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var level_val = entry.get("level")
		if level_val != null:
			lvl_lbl.text = str(level_val)
		else:
			lvl_lbl.text = "-"
		lvl_lbl.align = Label.ALIGN_CENTER
		lvl_lbl.rect_min_size = Vector2(120, 0)
		lvl_lbl.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		if row_font: lvl_lbl.add_font_override("font", row_font)
		
		var left_spacer = Control.new()
		left_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		left_spacer.rect_min_size = Vector2(20, 0)
		row.add_child(left_spacer)
		
		row.add_child(rank_lbl)
		row.add_child(name_container)
		row.add_child(score_lbl)
		row.add_child(lvl_lbl)
		
		var row_margin = MarginContainer.new()
		row_margin.mouse_filter = Control.MOUSE_FILTER_PASS
		row_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_margin.add_constant_override("margin_left", 0)
		row_margin.add_constant_override("margin_right", 0)
		
		if is_current_user:
			var highlight = PanelContainer.new()
			highlight.mouse_filter = Control.MOUSE_FILTER_PASS
			highlight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var highlight_style = StyleBoxFlat.new()
			highlight_style.bg_color = Color(0.4, 0.8, 0.2, 0.15)
			highlight_style.corner_radius_top_left = 6
			highlight_style.corner_radius_top_right = 6
			highlight_style.corner_radius_bottom_left = 6
			highlight_style.corner_radius_bottom_right = 6
			highlight_style.content_margin_top = 4
			highlight_style.content_margin_bottom = 4
			highlight_style.content_margin_left = 0
			highlight_style.content_margin_right = 0
			highlight.add_stylebox_override("panel", highlight_style)
			highlight.add_child(row)
			row_margin.add_child(highlight)
		else:
			row_margin.add_child(row)
			
		vbox.add_child(row_margin)
			
		var item_spacer = Control.new()
		item_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_spacer.rect_min_size = Vector2(0, 12)
		vbox.add_child(item_spacer)
		
		rank += 1
		
	var bottom_spacer = Control.new()
	bottom_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_spacer.rect_min_size = Vector2(0, 15)
	vbox.add_child(bottom_spacer)


func _on_CloseLeaderboard_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	active_panel_name = ""
	leaderboard_panel.hide()
	_show_active_screen()

func _on_leaderboard_tab_changed(tab_idx):
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	var timer = leaderboard_panel.get_node_or_null("SeasonalTimerLabel")
	if timer:
		timer.visible = (tab_idx == 1)
		
	if is_instance_valid(leaderboard_tabs):
		var active_tab_child = leaderboard_tabs.get_child(tab_idx)
		if active_tab_child:
			if is_instance_valid(tab_transition_tween):
				tab_transition_tween.stop_all()
				tab_transition_tween.queue_free()
			
			active_tab_child.modulate.a = 0.0
			
			tab_transition_tween = Tween.new()
			add_child(tab_transition_tween)
			tab_transition_tween.interpolate_property(active_tab_child, "modulate:a", 0.0, 1.0, 0.2, Tween.TRANS_SINE, Tween.EASE_OUT)
			tab_transition_tween.start()


func _get_panel_stylebox() -> StyleBoxFlat:
	var pp_style = StyleBoxFlat.new()
	pp_style.bg_color = Color(0.06, 0.1, 0.18, 0.97)
	pp_style.border_width_left = 3
	pp_style.border_width_top = 3
	pp_style.border_width_right = 3
	pp_style.border_width_bottom = 3
	pp_style.border_color = Color(0.18, 0.35, 0.55, 0.6)
	pp_style.corner_radius_top_left = 30
	pp_style.corner_radius_top_right = 30
	pp_style.corner_radius_bottom_right = 30
	pp_style.corner_radius_bottom_left = 30
	pp_style.shadow_color = Color(0, 0, 0, 0.5)
	pp_style.shadow_size = 12
	pp_style.shadow_offset = Vector2(0, 4)
	return pp_style



func _create_panel_close_button(panel: Panel, callback_name: String) -> TextureButton:
	var close_btn = TextureButton.new()
	close_btn.name = "CloseButton"
	close_btn.texture_normal = tex_close_button
	close_btn.expand = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	close_btn.anchor_left = 1.0
	close_btn.anchor_right = 1.0
	close_btn.margin_left = - 110
	close_btn.margin_top = 15
	close_btn.margin_right = - 15
	close_btn.margin_bottom = 110
	close_btn.connect("pressed", self, callback_name)
	close_btn.connect("button_down", self, "_on_CircleButton_down", [close_btn])
	close_btn.connect("button_up", self, "_on_CircleButton_up", [close_btn])
	close_btn.rect_pivot_offset = Vector2(47.5, 47.5)
	panel.add_child(close_btn)
	return close_btn

func _update_profile_panel():
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if not profile_panel_node: return
	
	var my_uid = FirebaseManager.get_current_user_id()
	var is_developer = (my_uid == DEVELOPER_UID)
	
	var is_guest = true
	var email = ""
	if FirebaseManager.is_logged_in and Firebase.Auth.auth:
		email = Firebase.Auth.auth.get("email", "")
	if email != "":
		is_guest = false
	
	if profile_avatar:
		if is_developer:
			profile_avatar.texture = tex_avatar_developer
		elif is_guest:
			profile_avatar.texture = tex_avatar_guest
		else:
			profile_avatar.texture = tex_avatar_verified
			
	var profile_avatar_bg = profile_panel_node.get_node_or_null("AvatarBg")
	if profile_avatar_bg:
		if profile_avatar_bg is TextureRect:
			if is_developer:
				profile_avatar_bg.self_modulate = Color("#2a6feb")
			elif is_guest:
				profile_avatar_bg.self_modulate = Color("#577399")
			else:
				profile_avatar_bg.self_modulate = Color("#2a6feb")
		else:
			var bg_style = profile_avatar_bg.get_stylebox("panel")
			if bg_style is StyleBoxFlat:
				if is_developer:
					bg_style.bg_color = Color("#2a6feb")
				elif is_guest:
					bg_style.bg_color = Color("#577399")
				else:
					bg_style.bg_color = Color("#2a6feb")
	
	var p_name = Global.player_name
	if p_name == "":
		p_name = "Player" + FirebaseManager.get_current_user_id().left(6)
		if p_name == "Player":
			p_name = "Unknown"
	if profile_name_label:
		profile_name_label.text = p_name
	
	if profile_badge:
		if is_developer:
			profile_badge.text = "Developer"
			var badge_style = profile_badge.get_stylebox("normal")
			if badge_style is StyleBoxFlat:
				badge_style.bg_color = Color(0.8, 0.3, 0.3, 0.95)
		elif is_guest:
			profile_badge.text = "Guest Account"
			var badge_style = profile_badge.get_stylebox("normal")
			if badge_style is StyleBoxFlat:
				badge_style.bg_color = Color(0.42, 0.45, 0.5, 0.95)
		else:
			profile_badge.text = "Verified Account"
			var badge_style = profile_badge.get_stylebox("normal")
			if badge_style is StyleBoxFlat:
				badge_style.bg_color = Color(0.17, 0.45, 0.96, 0.95)
	
	
	my_uid = FirebaseManager.get_current_user_id()
	
	var all_time_rank_str = "Unranked"
	if my_uid != "":
		var idx = 0
		for entry in FirebaseManager._temp_all_time:
			if entry.get("uid", "") == my_uid:
				all_time_rank_str = "#" + str(idx + 1)
				break
			idx += 1
			
	var seasonal_rank_str = "Unranked"
	if my_uid != "":
		var idx = 0
		for entry in FirebaseManager._temp_seasonal:
			if entry.get("uid", "") == my_uid:
				seasonal_rank_str = "#" + str(idx + 1)
				break
			idx += 1
	
	if profile_rank_alltime:
		profile_rank_alltime.text = all_time_rank_str
	if profile_rank_season:
		profile_rank_season.text = seasonal_rank_str
	
	
	if profile_stats_vbox:
		for child in profile_stats_vbox.get_children():
			child.queue_free()
		
		var stats_labels = [
			["Total Games Played", str(player_data["total_games"])], 
			["Classic High Score", str(get_highscore(0))], 
			["Escalation High Score", str(get_highscore(1))], 
			["Highest Level", str(get_highest_level(1))], 
			["Total Death", str(player_data["total_deaths"])], 
			["Total Revives", str(player_data.get("total_revives", 0))], 
			["Distance Travel", "%.0f m" % player_data.get("total_distance", 0.0)], 
			["Playtime", "%.1f min" % (player_data["playtime"] / 60.0)]
		]
		
		var base_font = $UI / Control / MenuInfoLabel.get_font("font")
		var stat_label_font = base_font.duplicate() if base_font else null
		if stat_label_font:
			stat_label_font.size = 48
			stat_label_font.outline_size = 3
			stat_label_font.outline_color = Color(0.05, 0.05, 0.1)
		var stat_value_font = base_font.duplicate() if base_font else null
		if stat_value_font:
			stat_value_font.size = 48
			stat_value_font.outline_size = 3
			stat_value_font.outline_color = Color(0.05, 0.05, 0.1)
		
		for stat_pair in stats_labels:
			var row = HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var label1 = Label.new()
			label1.text = stat_pair[0]
			label1.size_flags_horizontal = Control.SIZE_FILL
			label1.add_color_override("font_color", Color(0.85, 0.88, 0.95))
			if stat_label_font: label1.add_font_override("font", stat_label_font)
			row.add_child(label1)
			
			var label2 = Label.new()
			label2.text = stat_pair[1]
			label2.align = Label.ALIGN_RIGHT
			label2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label2.add_color_override("font_color", Color(0.85, 0.88, 0.95))
			if stat_value_font: label2.add_font_override("font", stat_value_font)
			row.add_child(label2)
			
			profile_stats_vbox.add_child(row)
	
	
	var auth_status = ""
	if FirebaseManager.is_logged_in:
		if email != "":
			auth_status = "Authentication Status: [color=#88ff88]Authenticated (" + email + ")[/color]"
		else:
			auth_status = "Authentication Status: [color=#88ff88]Authenticated (Guest)[/color]"
	else:
		if FirebaseManager.consecutive_login_failures >= 3:
			auth_status = "Authentication Status: [color=#ffaaaa]Offline (No Connection)[/color]"
		else:
			auth_status = "Authentication Status: [color=#ff8888]Not Authenticated / Connecting...[/color]"
		
	var last_synced_str = "Never"
	if last_sync_timestamp > 0:
		var local_offset = get_local_timezone_offset()
		var t = OS.get_datetime_from_unix_time(last_sync_timestamp + local_offset)
		var ampm = "AM"
		var hr = t.hour
		if hr >= 12:
			ampm = "PM"
			if hr > 12:
				hr -= 12
		elif hr == 0:
			hr = 12
		last_synced_str = "%02d-%02d-%04d %02d:%02d:%02d %s" % [t.day, t.month, t.year, hr, t.minute, t.second, ampm]
		
	if player_data.get("pending_stats_sync", false) or player_data.get("pending_score_sync", false):
		last_synced_str += " [color=#ffaa44](Sync Pending...)[/color]"
		
	var uid_str = FirebaseManager.get_current_user_id()
	if uid_str == "":
		if FirebaseManager.consecutive_login_failures >= 3:
			uid_str = "Offline"
		else:
			uid_str = "Connecting..."
		
	var disclaimer_text = "UID: " + uid_str + "\n" + auth_status + "\nLast Synced: " + last_synced_str
	if profile_disclaimer:
		profile_disclaimer.bbcode_text = "[center]" + disclaimer_text + "[/center]"
		
	if btn_claim_profile:
		btn_claim_profile.visible = is_guest and FirebaseManager.is_logged_in
	if btn_manage_account:
		btn_manage_account.visible = not is_guest and FirebaseManager.is_logged_in
	if btn_reconnect:
		btn_reconnect.visible = not FirebaseManager.is_logged_in

func _on_ProfileButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	
	if active_panel_name == "profile":
		active_panel_name = ""
		var p = $UI / Control.get_node_or_null("ProfilePanel")
		if p: p.hide()
		_show_active_screen()
		return
	
	var was_panel_open = active_panel_name != ""
	
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if not profile_panel_node: return
	
	_update_profile_panel()
	
	_close_active_panel_only()

	
	if not was_panel_open:
		_hide_active_screen()
	
	active_panel_name = "profile"
	profile_panel_node.show()

func _on_CloseProfile_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	_close_onscreen_keyboard()
	
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node: profile_panel_node.hide()
	active_panel_name = ""
	_show_active_screen()

func show_storage_error(message: String):
	if is_instance_valid(error_sound):
		error_sound.play()
	var popup = $UI / Control.get_node_or_null("StorageErrorPanel")
	if popup:
		var msg_label = popup.get_node("MessageLabel")
		if msg_label:
			msg_label.text = message
		popup.show()
		popup.raise()

func _on_CloseStorageError_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	var popup = $UI / Control.get_node_or_null("StorageErrorPanel")
	if popup:
		popup.hide()

func _on_CircleButton_down(button):
	button.rect_scale = Vector2(0.85, 0.85)
	button.self_modulate = Color(0.7, 0.7, 0.7)

func _on_CircleButton_up(button):
	button.rect_scale = Vector2(1.0, 1.0)
	button.self_modulate = Color(1.0, 1.0, 1.0)

func _on_SettingsButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	
	if active_panel_name == "settings":
		active_panel_name = ""
		settings_panel.hide()
		_show_active_screen()
		return
	
	var was_panel_open = active_panel_name != ""
	_close_active_panel_only()
	
	if not was_panel_open:
		_hide_active_screen()
	
	active_panel_name = "settings"
	if is_instance_valid(settings_panel):
		var kb_toggle = settings_panel.get_node_or_null("KeyboardToggleAnchor/KeyboardToggle")
		if kb_toggle and kb_toggle.has_method("set_on"):
			kb_toggle.set_on(onscreen_keyboard_setting_enabled)
	settings_panel.show()

func _on_CloseSettings_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	save_hiscore(false)
	active_panel_name = ""
	settings_panel.hide()
	_show_active_screen()

func _on_MusicSlider_value_changed(value: float):
	music_volume = value
	var raw_db = linear2db(value) if value > 0.001 else - 80.0
	
	var db = raw_db - 10.0 if raw_db > - 79.0 else - 80.0
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.set_volume_db(db)
	save_hiscore(false)

func _apply_sfx_volume():
	var linear_vol = 1.0 if sfx_enabled else 0.0
	var db = linear2db(linear_vol) if linear_vol > 0.001 else - 80.0
	var sfx_nodes = [bird_jump, bird_collision, bird_fall, score_sound, bird_pop, level_change_sound, revive_sound, health_refill_sound, game_over_bgm]
	for node in sfx_nodes:
		if is_instance_valid(node):
			node.set_volume_db(db)

func _on_SfxToggle_toggled(button_pressed: bool):
	sfx_enabled = button_pressed
	_apply_sfx_volume()
	save_hiscore(false)
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
		
	
	player_data = {
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
	save_hiscore()
	update_score_display()
	
	music_volume = 0.5
	sfx_enabled = true
	onscreen_keyboard_setting_enabled = false
	_update_onscreen_keyboard_visibility()
	
	_apply_sfx_volume()
	var raw_db = linear2db(music_volume) if music_volume > 0.001 else - 80.0
	
	var db = raw_db - 10.0 if raw_db > - 79.0 else - 80.0
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.set_volume_db(db)
		
	
	if is_instance_valid(settings_panel):
		var slider = settings_panel.get_node_or_null("MusicSliderAnchor/MusicSlider")
		if slider and slider.has_method("set_value"):
			slider.set_value(music_volume)
			
		var toggle = settings_panel.get_node_or_null("SfxToggleAnchor/SfxToggle")
		if toggle and toggle.has_method("set_on"):
			toggle.set_on(sfx_enabled)
			
		var kb_toggle = settings_panel.get_node_or_null("KeyboardToggleAnchor/KeyboardToggle")
		if kb_toggle and kb_toggle.has_method("set_on"):
			kb_toggle.set_on(onscreen_keyboard_setting_enabled)

func increment_score(obstacle_position: Vector3 = Vector3.ZERO):
	var pts = 1
	if mode_level == 1:
		pts = int(max(1, current_speed_level))
		
	if game_playing:
		score += pts
	
	
	var floating_text = Label.new()
	floating_text.text = "+" + str(pts)
	floating_text.align = Label.ALIGN_CENTER
	floating_text.add_font_override("font", $UI / Control / Score.get_font("font"))
	
	
	floating_text.add_color_override("font_color", Color(1.0, 0.85, 0.2))
	floating_text.rect_scale = Vector2(0.1, 0.1)
	
	
	var camera = get_viewport().get_camera()
	var screen_pos = Vector2(get_viewport().size.x / 2, 150.0)
	if is_instance_valid(camera):
		
		screen_pos = camera.unproject_position(obstacle_position)
		
		screen_pos.y -= 20
		screen_pos.x -= 30
	
	floating_text.rect_position = screen_pos
	
	$UI.add_child(floating_text)
	
	
	yield(get_tree(), "idle_frame")
	if is_instance_valid(floating_text):
		floating_text.rect_pivot_offset = floating_text.rect_size / 2.0
		
		var ft_tween = Tween.new()
		floating_text.add_child(ft_tween)
		
		
		ft_tween.interpolate_property(floating_text, "rect_scale", Vector2(0.1, 0.1), Vector2(1.5, 1.5), 0.2, Tween.TRANS_BOUNCE, Tween.EASE_OUT)
		ft_tween.interpolate_property(floating_text, "rect_scale", Vector2(1.5, 1.5), Vector2(1.0, 1.0), 0.3, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.2)
		
		
		ft_tween.interpolate_property(floating_text, "rect_position:y", screen_pos.y, screen_pos.y - 120, 1.0, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		ft_tween.interpolate_property(floating_text, "modulate:a", 1.0, 0.0, 1.0, Tween.TRANS_CUBIC, Tween.EASE_IN)
		
		ft_tween.start()
		ft_tween.connect("tween_all_completed", floating_text, "queue_free")
	
	if is_instance_valid(score_sound):
		score_sound.play()
	
	update_score_display()

func trigger_hit_phase():
	if game_playing:
		if mode_level == 1:
			player_data["total_deaths"] += 1
		save_hiscore(false)
	
	game_playing = false
	$ObstacleSpawner.stop()
	$bg.stop()
	$ScrollingPlatform.stop()
	
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.stop()

func trigger_grounded_phase():
	if not $UI / Control / RestartButton.visible:
		is_game_over_active = true
		$UI / Control / RestartButton.show()
		$UI / Control / MainMenuButton.show()
		$UI / Control / Score.hide()
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
			
		if is_instance_valid(game_over_bottom_bar):
			game_over_bottom_bar.show()
		if is_instance_valid(game_over_leaderboard_button):
			game_over_leaderboard_button.show()
		if is_instance_valid(game_over_profile_button):
			game_over_profile_button.show()
		if is_instance_valid(game_over_settings_button):
			game_over_settings_button.show()
			
		if game_over_panel:
			if mode_level == 1:
				player_data["total_distance"] = player_data.get("total_distance", 0.0) + run_distance
				player_data["playtime"] = player_data.get("playtime", 0.0) + run_playtime
			
			save_hiscore()
				
			var score_str = String(score)
			if mode_level == 1:
				score_str += " (Lvl " + str(current_speed_level) + ")"
			game_over_panel.get_node("VBox/ScoreRow/Value").text = score_str
			
			var best_str = String(get_highscore(mode_level))
			if mode_level == 1:
				best_str += " (Lvl " + str(get_highest_level(mode_level)) + ")"
			game_over_panel.get_node("VBox/HighScoreRow/Value").text = best_str
			
			if mode_level == 1 and is_new_high_score and score > 0:
				_show_leaderboard_submit_prompt()
			
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
	
	func _init(initial_value: float = 0.5, p_width: float = 400.0):
		value = initial_value
		width = p_width
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
		fill_style.bg_color = Color(0.2, 0.65, 1.0)
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
		fill.rect_min_size.x = max(30, clamped_x)
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
			is_on = not is_on
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
			bg_style.bg_color = Color(0.4, 0.8, 0.2)
		else:
			bg_style.bg_color = Color(0.6, 0.2, 0.2)

func trigger_health_refill_animation():
	if mode_level == 0:
		return
		
	if current_health < max_health:
		current_health += 1
		
		
		
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
		health_refill_sound.play()
		
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
	float_txt.add_font_override("font", $UI / Control / MenuInfoLabel.get_font("font"))
	float_txt.add_color_override("font_color", Color(1.0, 0.4, 0.4))
	
	$UI.add_child(float_txt)
	
	
	var txt_tween = Tween.new()
	float_txt.add_child(txt_tween)
	
	
	txt_tween.interpolate_callback(self, 0.01, "_position_floating_text", float_txt, restored_icon, txt_tween)
	txt_tween.start()

func _position_floating_text(float_txt, restored_icon, txt_tween):
	if not is_instance_valid(float_txt) or not is_instance_valid(restored_icon):
		if is_instance_valid(float_txt): float_txt.queue_free()
		return
		
	var font = float_txt.get_font("font")
	if font == null:
		font = $UI / Control / MenuInfoLabel.get_font("font")
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
	var end_pos = start_pos + Vector2( - 60, 60)
	txt_tween.interpolate_property(float_txt, "rect_global_position", start_pos, end_pos, 1.2, Tween.TRANS_CUBIC, Tween.EASE_OUT)
	txt_tween.interpolate_property(float_txt, "modulate:a", 1.0, 0.0, 1.2, Tween.TRANS_SINE, Tween.EASE_IN)
	
	txt_tween.start()
	txt_tween.connect("tween_all_completed", float_txt, "queue_free")


var leaderboard_tabs: TabContainer
var tab_transition_tween: Tween
var all_time_vbox: VBoxContainer
var seasonal_vbox: VBoxContainer
var all_time_header_margin: MarginContainer
var seasonal_header_margin: MarginContainer
var all_time_scroll: ScrollContainer
var seasonal_scroll: ScrollContainer
var name_input: LineEdit
var name_submit_btn: Button
var name_cancel_btn: Button
var is_editing_name: bool = false
var manage_name_hint: Label
var game_over_name_prompt: Panel
var game_over_name_input: LineEdit
var game_over_prompt_msg: Label
var game_over_submit_btn: Button
var game_over_skip_btn: Button
var profile_disclaimer: RichTextLabel
var profile_avatar: TextureRect
var profile_name_label: Label
var profile_badge: Label
var profile_rank_alltime: Label
var profile_rank_season: Label
var profile_stats_vbox: VBoxContainer
var profile_stats_divider: Panel
var tex_avatar_verified = preload("res://assets/textures/avatar-verified.png")
var tex_avatar_guest = preload("res://assets/textures/avatar-guest.png")
var tex_avatar_developer = preload("res://assets/textures/avatar-dev.png")
var tex_close_button = preload("res://assets/textures/close_button.png")
var tex_verified_badge = preload("res://assets/textures/verified_badge.png")
var circle_bg_texture: ImageTexture

const DEVELOPER_UID = "DJYXVxnCVPNuaY41LfWu2NQ4Nc53"
var inspector_panel_node: Panel
var inspector_avatar: TextureRect
var inspector_name_label: Label
var inspector_badge: Label
var inspector_rank_alltime: Label
var inspector_rank_season: Label
var inspector_stats_divider: Panel
var inspector_vbox: VBoxContainer
var inspector_disclaimer: RichTextLabel
var generic_error_panel: Panel
var btn_reconnect: Button

func _setup_firebase_ui():
	
	if is_instance_valid(leaderboard_panel):
		leaderboard_panel.margin_left = - 525
		leaderboard_panel.margin_top = - 840
		leaderboard_panel.margin_right = 525
		leaderboard_panel.margin_bottom = 520
		var vbox = leaderboard_panel.get_node_or_null("VBox")
		if vbox:
			vbox.margin_top = 240
			vbox.margin_bottom = - 240

	
	var coming_soon = leaderboard_panel.get_node("VBox/ComingSoon")
	if coming_soon:
		coming_soon.queue_free()
	
	leaderboard_tabs = TabContainer.new()
	leaderboard_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var base_font = $UI / Control / MenuInfoLabel.get_font("font")
	var leaderboard_font = null
	if base_font:
		leaderboard_font = base_font.duplicate()
		leaderboard_font.outline_color = Color(0.17, 0.07, 0.0) # Dark Espresso Brown
	if leaderboard_font:
		leaderboard_tabs.add_font_override("font", leaderboard_font)
	
	
	var tab_panel_style = StyleBoxEmpty.new()
	leaderboard_tabs.add_stylebox_override("panel", tab_panel_style)
	
	var active_tab_style = StyleBoxFlat.new()
	active_tab_style.bg_color = Color(0.08, 0.13, 0.23, 1.0)
	active_tab_style.border_width_left = 2
	active_tab_style.border_width_top = 2
	active_tab_style.border_width_right = 2
	active_tab_style.border_width_bottom = 0
	active_tab_style.border_color = Color(0.11, 0.20, 0.33, 1.0)
	active_tab_style.corner_radius_top_left = 6
	active_tab_style.corner_radius_top_right = 6
	active_tab_style.content_margin_left = 15
	active_tab_style.content_margin_right = 15
	active_tab_style.content_margin_top = 8
	active_tab_style.content_margin_bottom = 8
	leaderboard_tabs.add_stylebox_override("tab_fg", active_tab_style)
	
	var inactive_tab_style = StyleBoxFlat.new()
	inactive_tab_style.bg_color = Color(0.04, 0.07, 0.13, 1.0)
	inactive_tab_style.border_width_left = 2
	inactive_tab_style.border_width_top = 2
	inactive_tab_style.border_width_right = 2
	inactive_tab_style.border_width_bottom = 2
	inactive_tab_style.border_color = Color(0.11, 0.20, 0.33, 1.0)
	inactive_tab_style.corner_radius_top_left = 6
	inactive_tab_style.corner_radius_top_right = 6
	inactive_tab_style.content_margin_left = 15
	inactive_tab_style.content_margin_right = 15
	inactive_tab_style.content_margin_top = 6
	inactive_tab_style.content_margin_bottom = 6
	leaderboard_tabs.add_stylebox_override("tab_bg", inactive_tab_style)
	
	leaderboard_tabs.add_color_override("font_color_bg", Color(0.36, 0.43, 0.55))
	leaderboard_tabs.add_color_override("font_color_fg", Color(1.0, 0.62, 0.25))
	
	
	var all_time_tab = VBoxContainer.new()
	all_time_tab.name = "All-Time"
	all_time_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_time_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	all_time_header_margin = _create_leaderboard_header(leaderboard_font)
	all_time_scroll = ScrollContainer.new()
	all_time_scroll.set_script(preload("res://scripts/ScrollContainerDrag.gd"))
	all_time_vbox = VBoxContainer.new()
	all_time_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_time_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	all_time_scroll.add_child(all_time_vbox)
	
	var all_time_table = _create_table_widget(all_time_header_margin, all_time_scroll)
	all_time_tab.add_child(all_time_table)
	
	all_time_scroll.get_v_scrollbar().connect("visibility_changed", self, "_on_all_time_scrollbar_changed")
	all_time_scroll.get_v_scrollbar().connect("item_rect_changed", self, "_on_all_time_scrollbar_changed")
	
	
	var seasonal_tab = VBoxContainer.new()
	seasonal_tab.name = "Seasonal"
	seasonal_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seasonal_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	seasonal_header_margin = _create_leaderboard_header(leaderboard_font)
	seasonal_scroll = ScrollContainer.new()
	seasonal_scroll.set_script(preload("res://scripts/ScrollContainerDrag.gd"))
	seasonal_vbox = VBoxContainer.new()
	seasonal_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seasonal_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	seasonal_scroll.add_child(seasonal_vbox)
	
	var seasonal_table = _create_table_widget(seasonal_header_margin, seasonal_scroll)
	seasonal_tab.add_child(seasonal_table)
	
	seasonal_scroll.get_v_scrollbar().connect("visibility_changed", self, "_on_seasonal_scrollbar_changed")
	seasonal_scroll.get_v_scrollbar().connect("item_rect_changed", self, "_on_seasonal_scrollbar_changed")
	
	leaderboard_tabs.add_child(all_time_tab)
	leaderboard_tabs.add_child(seasonal_tab)
	leaderboard_panel.get_node("VBox").add_child(leaderboard_tabs)
	leaderboard_panel.get_node("VBox").move_child(leaderboard_tabs, 0)
	
	if not leaderboard_tabs.is_connected("tab_changed", self, "_on_leaderboard_tab_changed"):
		leaderboard_tabs.connect("tab_changed", self, "_on_leaderboard_tab_changed")
		
	var old_timer = leaderboard_panel.get_node_or_null("SeasonalTimerLabel")
	if old_timer:
		old_timer.queue_free()
		
	var seasonal_timer = Label.new()
	seasonal_timer.name = "SeasonalTimerLabel"
	seasonal_timer.text = _get_seasonal_reset_time_string()
	seasonal_timer.align = Label.ALIGN_CENTER
	seasonal_timer.valign = Label.VALIGN_CENTER
	seasonal_timer.anchor_left = 0.0
	seasonal_timer.anchor_right = 1.0
	seasonal_timer.anchor_top = 1.0
	seasonal_timer.anchor_bottom = 1.0
	seasonal_timer.margin_left = 60
	seasonal_timer.margin_right = - 60
	seasonal_timer.margin_top = - 240
	seasonal_timer.margin_bottom = - 170
	
	var timer_font = DynamicFont.new()
	timer_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	timer_font.size = 34
	timer_font.outline_size = 2
	timer_font.outline_color = Color(0.05, 0.05, 0.1, 0.8)
	timer_font.use_filter = true
	seasonal_timer.add_font_override("font", timer_font)
	seasonal_timer.add_color_override("font_color", Color(0.9, 0.8, 0.4))
	seasonal_timer.visible = (leaderboard_tabs.current_tab == 1)
	leaderboard_panel.add_child(seasonal_timer)

	
	var old_disclaimer = leaderboard_panel.get_node_or_null("LeaderboardDisclaimer")
	if old_disclaimer:
		old_disclaimer.queue_free()
		
	var leaderboard_disclaimer = RichTextLabel.new()
	leaderboard_disclaimer.name = "LeaderboardDisclaimer"
	leaderboard_disclaimer.bbcode_enabled = true
	leaderboard_disclaimer.scroll_active = false
	leaderboard_disclaimer.anchor_left = 0.0
	leaderboard_disclaimer.anchor_top = 1.0
	leaderboard_disclaimer.anchor_right = 1.0
	leaderboard_disclaimer.anchor_bottom = 1.0
	leaderboard_disclaimer.margin_left = 60
	leaderboard_disclaimer.margin_right = - 60
	leaderboard_disclaimer.margin_top = - 180
	leaderboard_disclaimer.margin_bottom = - 60
	
	var disc_font = DynamicFont.new()
	disc_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	disc_font.size = 28
	disc_font.outline_size = 2
	disc_font.outline_color = Color(0.05, 0.05, 0.1, 0.8)
	disc_font.use_filter = false
	leaderboard_disclaimer.add_font_override("normal_font", disc_font)
	leaderboard_disclaimer.add_color_override("default_color", Color(0.75, 0.75, 0.8, 0.85))
	
	leaderboard_disclaimer.bbcode_text = "[center]Note: Guest accounts are automatically cleared from the leaderboard every 30 days.[/center]"
	leaderboard_panel.add_child(leaderboard_disclaimer)


	
	var music_label = settings_panel.get_node_or_null("MusicLabel")
	if music_label:
		music_label.margin_top = 340
		music_label.margin_bottom = 400
		
	var music_slider_anchor = settings_panel.get_node_or_null("MusicSliderAnchor")
	if music_slider_anchor:
		music_slider_anchor.margin_left = - 220
		music_slider_anchor.margin_right = 220
		music_slider_anchor.margin_top = 420
		music_slider_anchor.margin_bottom = 500
		
	var sfx_label = settings_panel.get_node_or_null("SfxLabel")
	if sfx_label:
		sfx_label.margin_top = 600
		sfx_label.margin_bottom = 660
		
	var sfx_toggle_anchor = settings_panel.get_node_or_null("SfxToggleAnchor")
	if sfx_toggle_anchor:
		sfx_toggle_anchor.margin_top = 680
		sfx_toggle_anchor.margin_bottom = 760
		
	var reset_btn = settings_panel.get_node_or_null("ResetButton")
	if reset_btn:
		reset_btn.hide()
		reset_btn.disabled = true
		
	var version_lbl = settings_panel.get_node_or_null("VersionLabel")
	if version_lbl:
		version_lbl.anchor_left = 0.5
		version_lbl.anchor_right = 0.5
		version_lbl.margin_left = - 200
		version_lbl.margin_right = 200
		version_lbl.margin_top = - 70
		version_lbl.margin_bottom = - 45
		
	var build_lbl = settings_panel.get_node_or_null("BuildLabel")
	if build_lbl:
		build_lbl.anchor_left = 0.5
		build_lbl.anchor_right = 0.5
		build_lbl.margin_left = - 200
		build_lbl.margin_right = 200
		build_lbl.margin_top = - 45
		build_lbl.margin_bottom = - 20
		
	var close_btn = settings_panel.get_node_or_null("CloseSettings")
	if close_btn:
		close_btn.margin_left = - 140
		close_btn.margin_right = 140
		close_btn.margin_top = - 180
		close_btn.margin_bottom = - 90

	
	game_over_name_prompt = Panel.new()
	game_over_name_prompt.visible = false
	game_over_name_prompt.anchor_right = 1.0
	game_over_name_prompt.anchor_bottom = 1.0
	game_over_name_prompt.margin_left = 0
	game_over_name_prompt.margin_top = 0
	game_over_name_prompt.margin_right = 0
	game_over_name_prompt.margin_bottom = 0
	game_over_name_prompt.add_stylebox_override("panel", StyleBoxEmpty.new())
	_add_blur_background(game_over_name_prompt)
	
	var card = Panel.new()
	card.name = "Card"
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.margin_left = - 460
	card.margin_top = - 340
	card.margin_right = 460
	card.margin_bottom = 340
	
	var prompt_style = StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.06, 0.09, 0.15, 1.0)
	prompt_style.corner_radius_top_left = 24
	prompt_style.corner_radius_top_right = 24
	prompt_style.corner_radius_bottom_right = 24
	prompt_style.corner_radius_bottom_left = 24
	prompt_style.corner_detail = 30
	prompt_style.anti_aliasing = true
	prompt_style.border_width_left = 4
	prompt_style.border_width_top = 4
	prompt_style.border_width_right = 4
	prompt_style.border_width_bottom = 4
	prompt_style.border_color = Color(0.18, 0.35, 0.55, 0.8)
	card.add_stylebox_override("panel", prompt_style)
	game_over_name_prompt.add_child(card)
		
	var prompt_title = Label.new()
	prompt_title.text = "🏆 NEW HIGH SCORE!"
	prompt_title.anchor_right = 1.0
	prompt_title.margin_top = 40
	prompt_title.margin_bottom = 130
	prompt_title.align = Label.ALIGN_CENTER
	prompt_title.valign = Label.VALIGN_CENTER
	
	var large_title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if large_title_font:
		large_title_font.size = 60
		large_title_font.outline_size = 3
		large_title_font.outline_color = Color(0.08, 0.1, 0.15)
		prompt_title.add_font_override("font", large_title_font)
	prompt_title.add_color_override("font_color", Color(1.0, 0.85, 0.2))
	card.add_child(prompt_title)
	
	var prompt_divider = Panel.new()
	prompt_divider.anchor_left = 0.1
	prompt_divider.anchor_right = 0.9
	prompt_divider.margin_top = 148
	prompt_divider.margin_bottom = 151
	var prompt_div_style = StyleBoxFlat.new()
	prompt_div_style.bg_color = Color(0.18, 0.35, 0.55, 0.7)
	prompt_divider.add_stylebox_override("panel", prompt_div_style)
	card.add_child(prompt_divider)
	
	game_over_prompt_msg = Label.new()
	game_over_prompt_msg.text = "Enter a name for the leaderboard:"
	game_over_prompt_msg.anchor_right = 1.0
	game_over_prompt_msg.margin_top = 175
	game_over_prompt_msg.margin_bottom = 270
	game_over_prompt_msg.align = Label.ALIGN_CENTER
	
	var msg_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if msg_font:
		msg_font.size = 48
		msg_font.outline_size = 2
		msg_font.outline_color = Color(0.08, 0.1, 0.15)
		game_over_prompt_msg.add_font_override("font", msg_font)
	game_over_prompt_msg.add_color_override("font_color", Color(0.85, 0.88, 0.95))
	card.add_child(game_over_prompt_msg)
	
	game_over_input_style = StyleBoxFlat.new()
	game_over_input_style.bg_color = Color(0.04, 0.06, 0.1, 0.95)
	game_over_input_style.border_width_left = 3
	game_over_input_style.border_width_top = 3
	game_over_input_style.border_width_right = 3
	game_over_input_style.border_width_bottom = 3
	game_over_input_style.border_color = Color(0.18, 0.35, 0.55, 0.6)
	game_over_input_style.corner_radius_top_left = 16
	game_over_input_style.corner_radius_top_right = 16
	game_over_input_style.corner_radius_bottom_right = 16
	game_over_input_style.corner_radius_bottom_left = 16
	game_over_input_style.content_margin_left = 20
	game_over_input_style.content_margin_right = 20
	
	game_over_input_focus = game_over_input_style.duplicate()
	game_over_input_focus.border_color = Color(0.4, 0.8, 0.2)
	
	game_over_name_input = LineEdit.new()
	game_over_name_input.placeholder_text = "Your Name"
	game_over_name_input.max_length = 20
	game_over_name_input.anchor_left = 0.15
	game_over_name_input.anchor_right = 0.85
	game_over_name_input.margin_top = 290
	game_over_name_input.margin_bottom = 370
	game_over_name_input.align = LineEdit.ALIGN_CENTER
	game_over_name_input.add_stylebox_override("normal", game_over_input_style)
	game_over_name_input.add_stylebox_override("focus", game_over_input_focus)
	game_over_name_input.add_color_override("placeholder_color", Color(0.5, 0.6, 0.7, 0.8))
	game_over_name_input.add_color_override("font_color", Color(0.95, 0.95, 0.95))
	game_over_name_input.add_color_override("cursor_color", Color(1, 1, 1))
	game_over_name_input.caret_blink = true
	game_over_name_input.caret_blink_speed = 0.65
	game_over_name_input.add_constant_override("caret_width", 3)
	game_over_name_input.connect("focus_entered", self, "_on_game_over_name_focus_entered")
	game_over_name_input.connect("focus_exited", self, "_on_game_over_name_focus_exited")
	game_over_name_input.connect("gui_input", self, "_on_LineEdit_gui_input", [game_over_name_input])
	
	var input_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if input_font:
		input_font.size = 48
		input_font.outline_size = 2
		input_font.outline_color = Color(0.08, 0.1, 0.15)
		game_over_name_input.add_font_override("font", input_font)
	card.add_child(game_over_name_input)
	
	var ref_btn = $UI / Control / ButtonTemplate
	var ref_font = ref_btn.get_font("font") if ref_btn else null
	
	game_over_submit_btn = Button.new()
	game_over_submit_btn.text = "Submit"
	game_over_submit_btn.anchor_left = 0.1
	game_over_submit_btn.anchor_right = 0.9
	game_over_submit_btn.margin_top = 400
	game_over_submit_btn.margin_bottom = 500
	if ref_font:
		var submit_font = ref_font.duplicate()
		submit_font.size = 45
		submit_font.outline_size = 3
		submit_font.outline_color = Color(0.15, 0.4, 0.08)
		game_over_submit_btn.add_font_override("font", submit_font)
	else:
		var submit_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
		if submit_font:
			submit_font.size = 45
			submit_font.outline_size = 3
			submit_font.outline_color = Color(0.15, 0.4, 0.08)
			game_over_submit_btn.add_font_override("font", submit_font)
			
	var green_btn_normal = StyleBoxFlat.new()
	green_btn_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_btn_normal.anti_aliasing = true
	green_btn_normal.corner_radius_top_left = 20
	green_btn_normal.corner_radius_top_right = 20
	green_btn_normal.corner_radius_bottom_right = 20
	green_btn_normal.corner_radius_bottom_left = 20
	green_btn_normal.border_width_bottom = 8
	green_btn_normal.border_color = Color(0.3, 0.6, 0.15)
	green_btn_normal.content_margin_left = 30
	green_btn_normal.content_margin_right = 30
	
	var green_btn_hover = green_btn_normal.duplicate()
	green_btn_hover.bg_color = Color(0.45, 0.85, 0.25)
	green_btn_hover.border_color = Color(0.35, 0.65, 0.18)
	
	var green_btn_pressed = green_btn_normal.duplicate()
	green_btn_pressed.bg_color = Color(0.35, 0.7, 0.15)
	green_btn_pressed.border_width_top = 4
	green_btn_pressed.border_width_bottom = 4
	green_btn_pressed.border_color = Color(0.25, 0.5, 0.12)
	
	game_over_submit_btn.add_stylebox_override("normal", green_btn_normal)
	game_over_submit_btn.add_stylebox_override("hover", green_btn_hover)
	game_over_submit_btn.add_stylebox_override("pressed", green_btn_pressed)
	game_over_submit_btn.add_color_override("font_color", Color(1, 1, 1))
	game_over_submit_btn.add_color_override("font_color_hover", Color(1, 1, 1))
	game_over_submit_btn.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	game_over_submit_btn.connect("pressed", self, "_on_submit_name_pressed")
	card.add_child(game_over_submit_btn)
	
	game_over_skip_btn = Button.new()
	game_over_skip_btn.text = "Cancel"
	game_over_skip_btn.anchor_left = 0.1
	game_over_skip_btn.anchor_right = 0.9
	game_over_skip_btn.margin_top = 530
	game_over_skip_btn.margin_bottom = 630
	if ref_font:
		var cancel_font = ref_font.duplicate()
		cancel_font.size = 45
		cancel_font.outline_size = 3
		cancel_font.outline_color = Color(0.4, 0.1, 0.1)
		game_over_skip_btn.add_font_override("font", cancel_font)
	else:
		var cancel_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
		if cancel_font:
			cancel_font.size = 45
			cancel_font.outline_size = 3
			cancel_font.outline_color = Color(0.4, 0.1, 0.1)
			game_over_skip_btn.add_font_override("font", cancel_font)
			
	var red_btn_normal = StyleBoxFlat.new()
	red_btn_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_btn_normal.anti_aliasing = true
	red_btn_normal.corner_radius_top_left = 20
	red_btn_normal.corner_radius_top_right = 20
	red_btn_normal.corner_radius_bottom_right = 20
	red_btn_normal.corner_radius_bottom_left = 20
	red_btn_normal.border_width_bottom = 8
	red_btn_normal.border_color = Color(0.65, 0.2, 0.2)
	red_btn_normal.content_margin_left = 30
	red_btn_normal.content_margin_right = 30
	
	var red_btn_hover = red_btn_normal.duplicate()
	red_btn_hover.bg_color = Color(0.85, 0.3, 0.35)
	red_btn_hover.border_color = Color(0.7, 0.25, 0.25)
	
	var red_btn_pressed = red_btn_normal.duplicate()
	red_btn_pressed.bg_color = Color(0.7, 0.2, 0.25)
	red_btn_pressed.border_width_top = 4
	red_btn_pressed.border_width_bottom = 4
	red_btn_pressed.border_color = Color(0.55, 0.15, 0.18)
	
	game_over_skip_btn.add_stylebox_override("normal", red_btn_normal)
	game_over_skip_btn.add_stylebox_override("hover", red_btn_hover)
	game_over_skip_btn.add_stylebox_override("pressed", red_btn_pressed)
	game_over_skip_btn.add_color_override("font_color", Color(1, 1, 1))
	game_over_skip_btn.add_color_override("font_color_hover", Color(1, 1, 1))
	game_over_skip_btn.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	game_over_skip_btn.connect("pressed", self, "_on_skip_submit_pressed")
	card.add_child(game_over_skip_btn)
	
	$UI / Control.add_child(game_over_name_prompt)
	
	
	FirebaseManager.connect("leaderboard_updated", self, "_on_leaderboard_updated")

func _create_leaderboard_header(base_font: Font) -> Control:
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_constant_override("separation", 0)
	
	var h_rank = Label.new()
	h_rank.text = "Rank"
	h_rank.rect_min_size = Vector2(120, 0)
	h_rank.align = Label.ALIGN_CENTER
	if base_font: h_rank.add_font_override("font", base_font)
	h_rank.add_color_override("font_color", Color(1.0, 0.77, 0.42))
	
	var h_player = Label.new()
	h_player.text = "Player"
	h_player.rect_min_size = Vector2(560, 0)
	h_player.align = Label.ALIGN_CENTER
	if base_font: h_player.add_font_override("font", base_font)
	h_player.add_color_override("font_color", Color(1.0, 0.77, 0.42))
	
	var h_score = Label.new()
	h_score.text = "Score"
	h_score.rect_min_size = Vector2(160, 0)
	h_score.align = Label.ALIGN_CENTER
	if base_font: h_score.add_font_override("font", base_font)
	h_score.add_color_override("font_color", Color(1.0, 0.77, 0.42))
	
	var h_lvl = Label.new()
	h_lvl.text = "Lvl"
	h_lvl.rect_min_size = Vector2(120, 0)
	h_lvl.align = Label.ALIGN_CENTER
	if base_font: h_lvl.add_font_override("font", base_font)
	h_lvl.add_color_override("font_color", Color(1.0, 0.77, 0.42))
	
	var left_spacer = Control.new()
	left_spacer.rect_min_size = Vector2(20, 0)
	header.add_child(left_spacer)
	
	header.add_child(h_rank)
	header.add_child(h_player)
	header.add_child(h_score)
	header.add_child(h_lvl)
	var header_panel = PanelContainer.new()
	header_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header_style = StyleBoxFlat.new()
	header_style.bg_color = Color(0.08, 0.13, 0.23, 1.0)
	header_style.content_margin_top = 10
	header_style.content_margin_bottom = 10
	header_style.content_margin_left = 0
	header_style.content_margin_right = 0
	header_panel.add_stylebox_override("panel", header_style)
	header_panel.add_child(header)
	
	var margin_container = MarginContainer.new()
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_container.add_constant_override("margin_top", 0)
	margin_container.add_constant_override("margin_bottom", 0)
	margin_container.add_constant_override("margin_left", 0)
	margin_container.add_constant_override("margin_right", 0)
	margin_container.add_child(header_panel)
	
	return margin_container
	
func _create_table_widget(header: Control, scroll: ScrollContainer) -> Control:
	var table_panel = PanelContainer.new()
	table_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var table_style = StyleBoxFlat.new()
	table_style.bg_color = Color(0.04, 0.07, 0.13, 1.0)
	table_style.border_width_left = 2
	table_style.border_width_top = 2
	table_style.border_width_right = 2
	table_style.border_width_bottom = 2
	table_style.border_color = Color(0.11, 0.20, 0.33, 1.0)
	table_style.corner_radius_top_left = 8
	table_style.corner_radius_top_right = 8
	table_style.corner_radius_bottom_left = 8
	table_style.corner_radius_bottom_right = 8
	table_style.content_margin_left = 0
	table_style.content_margin_right = 0
	table_style.content_margin_top = 0
	table_style.content_margin_bottom = 0
	table_panel.add_stylebox_override("panel", table_style)
	table_panel.rect_clip_content = true
	
	var table_vbox = VBoxContainer.new()
	table_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_vbox.add_constant_override("separation", 0)
	table_panel.add_child(table_vbox)
	
	table_vbox.add_child(header)
	
	var horizontal_divider = ColorRect.new()
	horizontal_divider.rect_min_size = Vector2(0, 2)
	horizontal_divider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_divider.color = Color(0.18, 0.21, 0.27, 1.0)
	table_vbox.add_child(horizontal_divider)
	
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_vbox.add_child(scroll)
	
	return table_panel

func _on_all_time_scrollbar_changed():
	if is_instance_valid(all_time_scroll) and is_instance_valid(all_time_header_margin):
		var scrollbar = all_time_scroll.get_v_scrollbar()
		var w = scrollbar.rect_size.x if scrollbar.visible else 0
		all_time_header_margin.add_constant_override("margin_right", w)

func _on_seasonal_scrollbar_changed():
	if is_instance_valid(seasonal_scroll) and is_instance_valid(seasonal_header_margin):
		var scrollbar = seasonal_scroll.get_v_scrollbar()
		var w = scrollbar.rect_size.x if scrollbar.visible else 0
		seasonal_header_margin.add_constant_override("margin_right", w)

func _on_name_input_changed(_new_text: String):
	pass

func _on_name_input_entered(_new_text: String):
	_on_name_submit_pressed()

func _on_name_input_focus_exited():
	pass

func _on_game_over_name_focus_entered():
	if is_instance_valid(game_over_name_input):
		game_over_name_input.align = LineEdit.ALIGN_LEFT
		game_over_name_input.text = game_over_name_input.text

func _on_game_over_name_focus_exited():
	if is_instance_valid(game_over_name_input):
		game_over_name_input.align = LineEdit.ALIGN_CENTER
		game_over_name_input.text = game_over_name_input.text

func _on_name_cancel_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	is_editing_name = false
	_close_onscreen_keyboard()
	_update_manage_account_name_ui()



func _on_name_submit_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	var is_registered = FirebaseManager.get_is_registered()
	var has_changed = bool(player_data.get("has_changed_name_logged_in", false))
	
	if is_registered and not has_changed:
		if not is_editing_name:
			is_editing_name = true
			_update_manage_account_name_ui()
			if is_instance_valid(name_input):
				if _is_onscreen_keyboard_active():
					_open_onscreen_keyboard_for_field(name_input)
				else:
					name_input.grab_focus()
					name_input.caret_position = name_input.text.length()
			return
			
	var typed_name = name_input.text.strip_edges() if name_input else ""
	if typed_name == "":
		return
		
	if typed_name == Global.player_name:
		is_editing_name = false
		_close_onscreen_keyboard()
		_update_manage_account_name_ui()
		return
		
	Global.player_name = typed_name
	
	if is_registered:
		player_data["has_changed_name_logged_in"] = true
		if Firebase.Auth.auth and Firebase.Auth.auth.has("idtoken"):
			Firebase.Auth.update_account(Firebase.Auth.auth.idtoken, Global.player_name, "", [], true)
	Global.has_changed_name = true
		
	is_editing_name = false
	_close_onscreen_keyboard()
	_update_manage_account_name_ui()
	_update_profile_panel()
		
	save_hiscore()
	var current_hiscore = get_highscore(1)
	if current_hiscore > 0:
		FirebaseManager.submit_score(current_hiscore, 1, Global.player_name, get_highest_level(1))

func _on_submit_name_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	_close_onscreen_keyboard()
	
	var is_name_already_set = Global.has_changed_name
	if not is_name_already_set:
		var new_name = game_over_name_input.text.strip_edges()
		if new_name != "":
			Global.player_name = new_name
			Global.has_changed_name = true
			if name_input:
				name_input.text = new_name
			save_hiscore()
		else:
			
			pass
	
	game_over_name_prompt.hide()
	
	
	FirebaseManager.submit_score(score, mode_level, Global.player_name, current_speed_level)

func _on_skip_submit_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	_close_onscreen_keyboard()
	game_over_name_prompt.hide()

func _show_leaderboard_submit_prompt():
	var is_name_already_set = Global.has_changed_name
	
	if is_name_already_set:
		
		game_over_prompt_msg.text = "Submit score to leaderboard as:\n" + Global.player_name
		game_over_prompt_msg.margin_top = 180
		game_over_prompt_msg.margin_bottom = 370
		
		game_over_name_input.visible = false
	else:
		
		game_over_prompt_msg.text = "Enter a name for the leaderboard:"
		game_over_prompt_msg.margin_top = 175
		game_over_prompt_msg.margin_bottom = 270
		
		game_over_name_input.visible = true
		game_over_name_input.text = ""
		
	game_over_name_prompt.show()
	game_over_name_prompt.raise()
	
	if game_over_name_input.visible and _is_onscreen_keyboard_active():
		_open_onscreen_keyboard_for_field(game_over_name_input)

func _on_stats_sync_finished(success: bool, timestamp: int):
	last_sync_attempted = true
	last_sync_success = success
	player_data["pending_stats_sync"] = not success
	if success:
		last_sync_timestamp = timestamp
	save_hiscore(false)
		
	
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node and profile_panel_node.visible:
		_update_profile_panel()

func _on_CloseInspector_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	if inspector_panel_node:
		inspector_panel_node.hide()
	leaderboard_panel.show()

func _on_leaderboard_player_clicked(uid: String, player_name: String):
	if is_instance_valid(all_time_scroll) and all_time_scroll.has_dragged:
		return
	if is_instance_valid(seasonal_scroll) and seasonal_scroll.has_dragged:
		return
		
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	var current_is_guest = true
	var current_email = ""
	if FirebaseManager.is_logged_in and Firebase.Auth.auth:
		current_email = Firebase.Auth.auth.get("email", "")
	if current_email != "":
		current_is_guest = false
		
	if current_is_guest:
		show_generic_error("Inspection Denied", "Guest accounts cannot inspect other players. Please link your account first.")
		return
	
	leaderboard_panel.hide()
	
	if inspector_panel_node:
		inspector_panel_node.show()
		inspector_panel_node.get_node("Title").text = "Inspect Profile"
		
		inspector_name_label.text = player_name
		inspector_avatar.texture = tex_avatar_guest
		inspector_badge.visible = false
		inspector_rank_alltime.text = "..."
		inspector_rank_season.text = "..."
		
		for child in inspector_vbox.get_children():
			child.queue_free()
			
		inspector_disclaimer.bbcode_text = "[center]Loading stats from Cloud...[/center]"
		
		var stats_loading = _create_vbox_spinner("")
		inspector_vbox.add_child(stats_loading)
		var stats_spinner = stats_loading.find_node("SpinnerIcon", true, false)
		_start_spinner_animation(stats_spinner)
		
		var collection = Firebase.Firestore.collection("player_data_rushybird")
		var task = collection.get_doc(uid)
		var doc = yield(task, "completed")
		
		if not inspector_panel_node.visible:
			return
			
		for child in inspector_vbox.get_children():
			child.queue_free()
			
		if doc == null or typeof(doc) != TYPE_OBJECT or not doc.has_method("get_value"):
			var err_lbl = Label.new()
			err_lbl.text = "Failed to load player stats.\n(Stats may not have synced yet)"
			err_lbl.align = Label.ALIGN_CENTER
			var base_font = $UI / Control / MenuInfoLabel.get_font("font")
			if base_font:
				var err_font = base_font.duplicate()
				err_font.size = 44
				err_font.outline_size = 2.5
				err_font.outline_color = Color(0.05, 0.05, 0.1)
				err_lbl.add_font_override("font", err_font)
			inspector_vbox.add_child(err_lbl)
			inspector_disclaimer.bbcode_text = "[center][color=#ff8888]Error: Profile offline[/color][/center]"
			inspector_rank_alltime.text = "Unranked"
			inspector_rank_season.text = "Unranked"
			return
			
		var is_registered = false
		if doc.has_method("get_value"):
			var reg_val = doc.get_value("is_registered")
			if reg_val != null:
				is_registered = bool(reg_val)
				
		var is_developer = (uid == DEVELOPER_UID)
		
		if not is_registered and not is_developer:
			if inspector_panel_node:
				inspector_panel_node.hide()
			leaderboard_panel.show()
			show_generic_error("Inspection Denied", "Guest accounts cannot be inspected.")
			return
		
		if is_developer:
			inspector_avatar.texture = tex_avatar_developer
		else:
			inspector_avatar.texture = tex_avatar_verified if is_registered else tex_avatar_guest
			
		var inspector_avatar_bg = inspector_panel_node.get_node_or_null("AvatarBg")
		if inspector_avatar_bg:
			if inspector_avatar_bg is TextureRect:
				if is_developer:
					inspector_avatar_bg.self_modulate = Color("#2a6feb")
				elif is_registered:
					inspector_avatar_bg.self_modulate = Color("#2a6feb")
				else:
					inspector_avatar_bg.self_modulate = Color("#577399")
			else:
				var bg_style = inspector_avatar_bg.get_stylebox("panel")
				if bg_style is StyleBoxFlat:
					if is_developer:
						bg_style.bg_color = Color("#2a6feb")
					elif is_registered:
						bg_style.bg_color = Color("#2a6feb")
					else:
						bg_style.bg_color = Color("#577399")
		
		inspector_badge.visible = true
		if is_developer:
			inspector_badge.text = "Developer"
			var badge_style = inspector_badge.get_stylebox("normal")
			if badge_style is StyleBoxFlat:
				badge_style.bg_color = Color(0.8, 0.3, 0.3, 0.95)
		elif is_registered:
			inspector_badge.text = "Verified Account"
			var badge_style = inspector_badge.get_stylebox("normal")
			if badge_style is StyleBoxFlat:
				badge_style.bg_color = Color(0.17, 0.45, 0.96, 0.95)
		else:
			inspector_badge.text = "Guest Account"
			var badge_style = inspector_badge.get_stylebox("normal")
			if badge_style is StyleBoxFlat:
				badge_style.bg_color = Color(0.42, 0.45, 0.5, 0.95)
				
		var all_time_rank_str = "Unranked"
		var idx = 0
		for entry in FirebaseManager._temp_all_time:
			if entry.get("uid", "") == uid:
				all_time_rank_str = "#" + str(idx + 1)
				break
			idx += 1
			
		var seasonal_rank_str = "Unranked"
		idx = 0
		for entry in FirebaseManager._temp_seasonal:
			if entry.get("uid", "") == uid:
				seasonal_rank_str = "#" + str(idx + 1)
				break
			idx += 1

		inspector_rank_alltime.text = all_time_rank_str
		inspector_rank_season.text = seasonal_rank_str

		var classic_hs = 0
		var escalation_hs = 0
		var highest_lvl = 1
		var total_games = 0
		var total_deaths = 0
		var total_revives = 0
		var total_distance = 0.0
		var playtime = 0.0
		
		if doc.has_method("get_value"):
			var val = doc.get_value("classic_highscore")
			if val != null: classic_hs = int(val)
			val = doc.get_value("escalation_highscore")
			if val != null: escalation_hs = int(val)
			val = doc.get_value("escalation_highest_level")
			if val != null: highest_lvl = int(val)
			val = doc.get_value("total_games")
			if val != null: total_games = int(val)
			val = doc.get_value("total_deaths")
			if val != null: total_deaths = int(val)
			val = doc.get_value("total_revives")
			if val != null: total_revives = int(val)
			val = doc.get_value("total_distance")
			if val != null: total_distance = float(val)
			val = doc.get_value("playtime")
			if val != null: playtime = float(val)
			
		var stats_labels = [
			["Total Games Played", str(total_games)], 
			["Classic High Score", str(classic_hs)], 
			["Escalation High Score", str(escalation_hs)], 
			["Highest Level", str(highest_lvl)], 
			["Total Death", str(total_deaths)], 
			["Total Revives", str(total_revives)], 
			["Distance Travel", "%.0f m" % total_distance], 
			["Playtime", "%.1f min" % (playtime / 60.0)]
		]
		
		var base_font = $UI / Control / MenuInfoLabel.get_font("font")
		var stat_label_font = base_font.duplicate() if base_font else null
		if stat_label_font:
			stat_label_font.size = 48
			stat_label_font.outline_size = 3
			stat_label_font.outline_color = Color(0.05, 0.05, 0.1)
		var stat_value_font = base_font.duplicate() if base_font else null
		if stat_value_font:
			stat_value_font.size = 48
			stat_value_font.outline_size = 3
			stat_value_font.outline_color = Color(0.05, 0.05, 0.1)
			
		for stat_pair in stats_labels:
			var row = HBoxContainer.new()
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var label1 = Label.new()
			label1.text = stat_pair[0]
			label1.size_flags_horizontal = Control.SIZE_FILL
			label1.add_color_override("font_color", Color(0.85, 0.88, 0.95))
			if stat_label_font: label1.add_font_override("font", stat_label_font)
			row.add_child(label1)
			
			var label2 = Label.new()
			label2.text = stat_pair[1]
			label2.align = Label.ALIGN_RIGHT
			label2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label2.add_color_override("font_color", Color(0.85, 0.88, 0.95))
			if stat_value_font: label2.add_font_override("font", stat_value_font)
			row.add_child(label2)
			
			inspector_vbox.add_child(row)
			
		var timestamp = 0
		if doc.has_method("get_value"):
			var ts_val = doc.get_value("last_updated")
			if ts_val != null:
				timestamp = int(ts_val)
				
		if timestamp > 0:
			var local_offset = get_local_timezone_offset()
			var t = OS.get_datetime_from_unix_time(timestamp + local_offset)
			var hour_12 = t.hour % 12
			if hour_12 == 0:
				hour_12 = 12
			var am_pm = "AM" if t.hour < 12 else "PM"
			inspector_disclaimer.bbcode_text = "[center]Last Active: %02d-%02d-%04d %02d:%02d %s[/center]" % [t.day, t.month, t.year, hour_12, t.minute, am_pm]
		else:
			inspector_disclaimer.bbcode_text = "[center]Last Active: Never[/center]"

func _on_auth_state_changed(is_logged_in: bool):
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node and profile_panel_node.visible:
		_update_profile_panel()
	
	if is_logged_in and not FirebaseManager.is_claiming_profile():
		check_and_sync_pending_data()
		
		if not player_data.get("pending_stats_sync", false):
			FirebaseManager.submit_stats(player_data)
		if not player_data.get("pending_score_sync", false):
			var escalation_hs = get_highscore(1)
			if escalation_hs > 0:
				FirebaseManager.submit_score(escalation_hs, 1, Global.player_name, get_highest_level(1))
			else:
				FirebaseManager.fetch_leaderboards()

func _get_seasonal_reset_time_string() -> String:
	var now = OS.get_datetime(true)
	
	
	var next_month = now.month + 1
	var next_year = now.year
	if next_month > 12:
		next_month = 1
		next_year += 1
		
	
	var target_time_dict = {
		"year": next_year, 
		"month": next_month, 
		"day": 1, 
		"hour": 0, 
		"minute": 0, 
		"second": 0
	}
	
	var now_unix = OS.get_unix_time()
	var target_unix = Time.get_unix_time_from_datetime_dict(target_time_dict)
	
	var diff_seconds = target_unix - now_unix
	if diff_seconds <= 0:
		return "Resetting Season..."
		
	var diff_days = diff_seconds / 86400
	if diff_days >= 1:
		if diff_days == 1:
			return "Season Resets In: 1 Day"
		else:
			return "Season Resets In: " + str(diff_days) + " Days"
	else:
		var diff_hours = int(ceil(float(diff_seconds) / 3600.0))
		if diff_hours <= 1:
			var diff_minutes = int(ceil(float(diff_seconds) / 60.0))
			if diff_minutes <= 1:
				return "Season Resets In: < 1 Minute"
			else:
				return "Season Resets In: " + str(diff_minutes) + " Minutes"
		else:
			return "Season Resets In: " + str(diff_hours) + " Hours"


var claim_profile_panel: Panel
var claim_email_input: LineEdit
var claim_pass_input: LineEdit
var btn_google_claim: Button
var btn_onscreen_keyboard: TextureButton
var lbl_onscreen_keyboard: Label
var indicator_arrow: Label
var onscreen_keyboard: Control
var btn_cancel_claim: Button
var btn_forgot_password: Button
var lbl_active_field: Label
var btn_switch_field: Button
var active_onscreen_keyboard_field: LineEdit
var line_edit_style: StyleBoxFlat
var line_edit_focus: StyleBoxFlat
var game_over_input_style: StyleBoxFlat
var game_over_input_focus: StyleBoxFlat



var conflict_panel: Panel
var btn_claim_profile: Button
var btn_manage_account: Button
var manage_account_panel: Panel
var card_device: Button
var card_cloud: Button
var btn_keep_selected: Button
var overwrite_confirm_panel: Panel
var selected_profile_type: String = ""

var lbl_device_name: Label
var lbl_device_classic: Label
var lbl_device_escalation: Label
var lbl_device_games: Label
var lbl_device_playtime: Label

var lbl_cloud_name: Label
var lbl_cloud_classic: Label
var lbl_cloud_escalation: Label
var lbl_cloud_games: Label
var lbl_cloud_playtime: Label
func _create_loading_overlay():
	loading_overlay = Panel.new()
	loading_overlay.name = "FullscreenLoadingOverlay"
	loading_overlay.anchor_right = 1.0
	loading_overlay.anchor_bottom = 1.0
	loading_overlay.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.05, 0.09, 0.88)
	loading_overlay.add_stylebox_override("panel", panel_style)
	
	var center_container = CenterContainer.new()
	center_container.anchor_right = 1.0
	center_container.anchor_bottom = 1.0
	loading_overlay.add_child(center_container)
	
	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 25)
	center_container.add_child(vbox)
	
	var center_spinner = CenterContainer.new()
	vbox.add_child(center_spinner)
	
	var spinner_container = Control.new()
	spinner_container.rect_min_size = Vector2(160, 160)
	center_spinner.add_child(spinner_container)
	
	
	var bg_circle = preload("res://addons/FontAwesome5/FontAwesome.gd").new()
	bg_circle.icon_type = "regular"
	bg_circle.icon_name = "circle"
	bg_circle.icon_size = 140
	bg_circle.rect_min_size = Vector2(140, 140)
	bg_circle.rect_size = Vector2(140, 140)
	bg_circle.rect_position = Vector2(10, 10)
	bg_circle.align = Label.ALIGN_CENTER
	bg_circle.valign = Label.VALIGN_CENTER
	bg_circle.add_color_override("font_color", Color(1.0, 1.0, 1.0, 0.15))
	spinner_container.add_child(bg_circle)
	
	
	loading_spinner_icon = preload("res://addons/FontAwesome5/FontAwesome.gd").new()
	loading_spinner_icon.name = "SpinnerIcon"
	loading_spinner_icon.icon_type = "solid"
	loading_spinner_icon.icon_name = "circle-notch"
	loading_spinner_icon.icon_size = 140
	loading_spinner_icon.rect_min_size = Vector2(140, 140)
	loading_spinner_icon.rect_size = Vector2(140, 140)
	loading_spinner_icon.rect_pivot_offset = Vector2(70, 70)
	loading_spinner_icon.rect_position = Vector2(10, 10)
	loading_spinner_icon.align = Label.ALIGN_CENTER
	loading_spinner_icon.valign = Label.VALIGN_CENTER
	loading_spinner_icon.add_color_override("font_color", Color(0.4, 0.8, 0.2))
	spinner_container.add_child(loading_spinner_icon)
	
	var loading_label = Label.new()
	loading_label.text = "Loading..."
	loading_label.align = Label.ALIGN_CENTER
	var loading_font = DynamicFont.new()
	loading_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	loading_font.size = 45
	loading_font.outline_size = 3
	loading_font.outline_color = Color(0.08, 0.1, 0.15)
	loading_label.add_font_override("font", loading_font)
	loading_label.add_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(loading_label)
	
	$UI / Control.add_child(loading_overlay)

func _show_loading(text: String = "Loading..."):
	if not is_instance_valid(loading_overlay):
		return
		
	var vbox = loading_overlay.get_child(0).get_child(0)
	var label = vbox.get_child(1)
	label.text = text
	
	loading_overlay.visible = true
	_start_spinner_animation(loading_spinner_icon)

func _hide_loading():
	if is_instance_valid(loading_overlay):
		loading_overlay.visible = false
		var anima = Anima.begin(loading_spinner_icon)
		anima.stop()

func _create_vbox_spinner(text: String) -> Control:
	var panel_container = PanelContainer.new()
	panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.05, 0.09, 0.65)
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.content_margin_left = 20
	panel_style.content_margin_top = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_bottom = 20
	panel_container.add_stylebox_override("panel", panel_style)
	
	var center_container = CenterContainer.new()
	center_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_container.add_child(center_container)
	
	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 15)
	center_container.add_child(vbox)
	
	var center_spinner = CenterContainer.new()
	vbox.add_child(center_spinner)
	
	var spinner_container = Control.new()
	spinner_container.rect_min_size = Vector2(100, 100)
	center_spinner.add_child(spinner_container)
	
	
	var bg = preload("res://addons/FontAwesome5/FontAwesome.gd").new()
	bg.icon_type = "regular"
	bg.icon_name = "circle"
	bg.icon_size = 80
	bg.rect_min_size = Vector2(80, 80)
	bg.rect_size = Vector2(80, 80)
	bg.rect_position = Vector2(10, 10)
	bg.align = Label.ALIGN_CENTER
	bg.valign = Label.VALIGN_CENTER
	bg.add_color_override("font_color", Color(1.0, 1.0, 1.0, 0.15))
	spinner_container.add_child(bg)
	
	
	var spinner = preload("res://addons/FontAwesome5/FontAwesome.gd").new()
	spinner.name = "SpinnerIcon"
	spinner.icon_type = "solid"
	spinner.icon_name = "circle-notch"
	spinner.icon_size = 80
	spinner.rect_min_size = Vector2(80, 80)
	spinner.rect_size = Vector2(80, 80)
	spinner.rect_pivot_offset = Vector2(40, 40)
	spinner.rect_position = Vector2(10, 10)
	spinner.align = Label.ALIGN_CENTER
	spinner.valign = Label.VALIGN_CENTER
	spinner.add_color_override("font_color", Color(0.4, 0.8, 0.2))
	spinner_container.add_child(spinner)
	
	if text != "":
		var label = Label.new()
		label.text = text
		label.align = Label.ALIGN_CENTER
		var loading_font = DynamicFont.new()
		loading_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
		loading_font.size = 32
		loading_font.outline_size = 2
		loading_font.outline_color = Color(0.08, 0.1, 0.15)
		label.add_font_override("font", loading_font)
		label.add_color_override("font_color", Color(1, 1, 1))
		vbox.add_child(label)
		
	return panel_container

func _start_spinner_animation(spinner: Control):
	var anima = Anima.begin(spinner)
	anima.clear()
	anima.then({
		node = spinner, 
		property = "rotation", 
		from = 0.0, 
		to = 360.0, 
		duration = 1.0, 
		easing = Anima.EASING.LINEAR
	})
	anima.loop()

func _add_blur_background(panel: Panel):
	var blocker_style = StyleBoxFlat.new()
	blocker_style.bg_color = Color(0.02, 0.03, 0.05, 0.5)
	panel.add_stylebox_override("panel", blocker_style)

func _create_claim_profile_panel():
	claim_profile_panel = Panel.new()
	claim_profile_panel.name = "ClaimProfilePanel"
	claim_profile_panel.anchor_right = 1.0
	claim_profile_panel.anchor_bottom = 1.0
	claim_profile_panel.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	claim_profile_panel.add_stylebox_override("panel", panel_style)
	
	var title = Label.new()
	title.text = "Link Account"
	title.align = Label.ALIGN_CENTER
	title.anchor_right = 1.0
	title.margin_top = 230
	title.margin_bottom = 330
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if title_font:
		title_font.size = 65
		title_font.outline_size = 4
		title_font.outline_color = Color(0.08, 0.1, 0.15)
		title.add_font_override("font", title_font)
	claim_profile_panel.add_child(title)
	
	
	var divider = Panel.new()
	divider.anchor_left = 0.1
	divider.anchor_right = 0.9
	divider.margin_top = 350
	divider.margin_bottom = 353
	var div_style = StyleBoxFlat.new()
	div_style.bg_color = Color(0.25, 0.3, 0.45, 0.7)
	divider.add_stylebox_override("panel", div_style)
	claim_profile_panel.add_child(divider)
	
	var input_font = DynamicFont.new()
	input_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	input_font.size = 50
	input_font.outline_size = 2
	input_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	
	line_edit_style = StyleBoxFlat.new()
	line_edit_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	line_edit_style.border_width_left = 3
	line_edit_style.border_width_top = 3
	line_edit_style.border_width_right = 3
	line_edit_style.border_width_bottom = 3
	line_edit_style.border_color = Color(0.2, 0.2, 0.3)
	line_edit_style.corner_radius_top_left = 20
	line_edit_style.corner_radius_top_right = 20
	line_edit_style.corner_radius_bottom_right = 20
	line_edit_style.corner_radius_bottom_left = 20
	line_edit_style.content_margin_left = 30
	line_edit_style.content_margin_right = 30
	
	line_edit_focus = line_edit_style.duplicate()
	line_edit_focus.border_color = Color(0.4, 0.8, 0.2)
	
	claim_email_input = LineEdit.new()
	claim_email_input.placeholder_text = "Email Address"
	claim_email_input.virtual_keyboard_enabled = false
	claim_email_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	claim_email_input.anchor_left = 0.15
	claim_email_input.anchor_right = 0.85
	claim_email_input.margin_top = 430
	claim_email_input.margin_bottom = 530
	claim_email_input.add_font_override("font", input_font)
	claim_email_input.add_stylebox_override("normal", line_edit_style)
	claim_email_input.add_stylebox_override("focus", line_edit_focus)
	claim_email_input.add_color_override("font_color", Color(1, 1, 1))
	claim_email_input.add_color_override("cursor_color", Color(1, 1, 1))
	claim_email_input.add_color_override("placeholder_color", Color(0.6, 0.6, 0.7))
	claim_email_input.caret_blink = true
	claim_email_input.caret_blink_speed = 0.65
	claim_email_input.add_constant_override("caret_width", 3)
	claim_profile_panel.add_child(claim_email_input)
	claim_email_input.connect("text_entered", self, "_on_Email_text_entered")
	claim_email_input.connect("focus_entered", self, "_on_input_focus_entered", [claim_email_input])
	claim_email_input.connect("gui_input", self, "_on_LineEdit_gui_input", [claim_email_input])
	
	claim_pass_input = LineEdit.new()
	claim_pass_input.placeholder_text = "Password"
	claim_pass_input.secret = true
	claim_pass_input.virtual_keyboard_enabled = false
	claim_pass_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	claim_pass_input.anchor_left = 0.15
	claim_pass_input.anchor_right = 0.85
	claim_pass_input.margin_top = 580
	claim_pass_input.margin_bottom = 680
	claim_pass_input.add_font_override("font", input_font)
	claim_pass_input.add_stylebox_override("normal", line_edit_style)
	claim_pass_input.add_stylebox_override("focus", line_edit_focus)
	claim_pass_input.add_color_override("font_color", Color(1, 1, 1))
	claim_pass_input.add_color_override("cursor_color", Color(1, 1, 1))
	claim_pass_input.add_color_override("placeholder_color", Color(0.6, 0.6, 0.7))
	claim_pass_input.caret_blink = true
	claim_pass_input.caret_blink_speed = 0.65
	claim_pass_input.add_constant_override("caret_width", 3)
	claim_profile_panel.add_child(claim_pass_input)
	claim_pass_input.connect("text_entered", self, "_on_Password_text_entered")
	claim_pass_input.connect("focus_entered", self, "_on_input_focus_entered", [claim_pass_input])
	claim_pass_input.connect("gui_input", self, "_on_LineEdit_gui_input", [claim_pass_input])

	btn_forgot_password = Button.new()
	btn_forgot_password.text = "Forgot Password?"
	btn_forgot_password.flat = true
	btn_forgot_password.align = Button.ALIGN_RIGHT
	btn_forgot_password.anchor_left = 0.4
	btn_forgot_password.anchor_right = 0.85
	btn_forgot_password.margin_top = 685
	btn_forgot_password.margin_bottom = 735
	btn_forgot_password.focus_mode = Control.FOCUS_NONE
	var ref_btn = $UI / Control / ButtonTemplate
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var forgot_font = ref_font.duplicate()
			forgot_font.size = 32
			forgot_font.outline_size = 2
			forgot_font.outline_color = Color(0.08, 0.1, 0.15)
			btn_forgot_password.add_font_override("font", forgot_font)
			
	btn_forgot_password.add_color_override("font_color", Color(0.7, 0.8, 1.0))
	btn_forgot_password.add_color_override("font_color_hover", Color(0.9, 0.95, 1.0))
	btn_forgot_password.add_color_override("font_color_pressed", Color(0.5, 0.6, 0.8))
	btn_forgot_password.connect("pressed", self, "_on_ForgotPassword_pressed")
	claim_profile_panel.add_child(btn_forgot_password)

	
	var btn_submit = Button.new()
	btn_submit.text = "Submit"
	btn_submit.anchor_left = 0.15
	btn_submit.anchor_right = 0.85
	btn_submit.margin_top = 740
	btn_submit.margin_bottom = 840
	btn_submit.connect("pressed", self, "_on_SubmitClaim_pressed")
	
	ref_btn = $UI / Control / ButtonTemplate
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var green_font = ref_font.duplicate()
			green_font.size = 45
			green_font.outline_size = 3
			green_font.outline_color = Color(0.15, 0.4, 0.08)
			btn_submit.add_font_override("font", green_font)
			
	var green_normal = StyleBoxFlat.new()
	green_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_normal.anti_aliasing = true
	green_normal.corner_radius_top_left = 20
	green_normal.corner_radius_top_right = 20
	green_normal.corner_radius_bottom_right = 20
	green_normal.corner_radius_bottom_left = 20
	green_normal.border_width_bottom = 8
	green_normal.border_color = Color(0.3, 0.6, 0.15)
	green_normal.shadow_color = Color(0, 0, 0, 0.2)
	green_normal.shadow_size = 4
	green_normal.shadow_offset = Vector2(0, 2)
	green_normal.content_margin_left = 30
	green_normal.content_margin_right = 30
	
	var green_hover = StyleBoxFlat.new()
	green_hover.bg_color = Color(0.45, 0.85, 0.25)
	green_hover.anti_aliasing = true
	green_hover.corner_radius_top_left = 20
	green_hover.corner_radius_top_right = 20
	green_hover.corner_radius_bottom_right = 20
	green_hover.corner_radius_bottom_left = 20
	green_hover.border_width_bottom = 8
	green_hover.border_color = Color(0.35, 0.65, 0.18)
	green_hover.shadow_color = Color(0, 0, 0, 0.25)
	green_hover.shadow_size = 6
	green_hover.shadow_offset = Vector2(0, 3)
	green_hover.content_margin_left = 30
	green_hover.content_margin_right = 30

	var green_pressed = StyleBoxFlat.new()
	green_pressed.bg_color = Color(0.35, 0.7, 0.15)
	green_pressed.anti_aliasing = true
	green_pressed.corner_radius_top_left = 20
	green_pressed.corner_radius_top_right = 20
	green_pressed.corner_radius_bottom_right = 20
	green_pressed.corner_radius_bottom_left = 20
	green_pressed.border_width_top = 4
	green_pressed.border_width_bottom = 4
	green_pressed.border_color = Color(0.25, 0.5, 0.1)
	green_pressed.shadow_color = Color(0, 0, 0, 0.15)
	green_pressed.shadow_size = 2
	green_pressed.shadow_offset = Vector2(0, 1)
	green_pressed.content_margin_left = 30
	green_pressed.content_margin_right = 30

	btn_submit.add_stylebox_override("normal", green_normal)
	btn_submit.add_stylebox_override("hover", green_hover)
	btn_submit.add_stylebox_override("pressed", green_pressed)
	btn_submit.add_color_override("font_color", Color(1, 1, 1))
	btn_submit.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_submit.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	claim_profile_panel.add_child(btn_submit)
	
	btn_google_claim = Button.new()
	btn_google_claim.text = "Link Google"
	btn_google_claim.anchor_left = 0.15
	btn_google_claim.anchor_right = 0.85
	btn_google_claim.connect("pressed", self, "_on_GoogleClaim_pressed")
	
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var google_font = ref_font.duplicate()
			google_font.size = 45
			google_font.outline_size = 3
			google_font.outline_color = Color(0.1, 0.2, 0.4)
			btn_google_claim.add_font_override("font", google_font)
			
	var google_normal = StyleBoxFlat.new()
	google_normal.bg_color = Color(0.26, 0.52, 0.96)
	google_normal.anti_aliasing = true
	google_normal.corner_radius_top_left = 20
	google_normal.corner_radius_top_right = 20
	google_normal.corner_radius_bottom_right = 20
	google_normal.corner_radius_bottom_left = 20
	google_normal.border_width_bottom = 8
	google_normal.border_color = Color(0.18, 0.4, 0.75)
	google_normal.shadow_color = Color(0, 0, 0, 0.2)
	google_normal.shadow_size = 4
	google_normal.shadow_offset = Vector2(0, 2)
	google_normal.content_margin_left = 30
	google_normal.content_margin_right = 30
	
	var google_hover = google_normal.duplicate()
	google_hover.bg_color = Color(0.3, 0.57, 0.98)
	google_hover.border_color = Color(0.2, 0.44, 0.78)
	google_hover.shadow_size = 6
	google_hover.shadow_offset = Vector2(0, 3)
	
	var google_pressed = google_normal.duplicate()
	google_pressed.bg_color = Color(0.22, 0.46, 0.88)
	google_pressed.border_width_top = 4
	google_pressed.border_width_bottom = 4
	google_pressed.border_color = Color(0.15, 0.35, 0.7)
	google_pressed.shadow_size = 2
	google_pressed.shadow_offset = Vector2(0, 1)
	
	btn_google_claim.add_stylebox_override("normal", google_normal)
	btn_google_claim.add_stylebox_override("hover", google_hover)
	btn_google_claim.add_stylebox_override("pressed", google_pressed)
	btn_google_claim.add_color_override("font_color", Color(1, 1, 1))
	btn_google_claim.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_google_claim.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	claim_profile_panel.add_child(btn_google_claim)
	btn_cancel_claim = Button.new()
	btn_cancel_claim.text = "Cancel"
	btn_cancel_claim.anchor_left = 0.15
	btn_cancel_claim.anchor_right = 0.85
	btn_cancel_claim.connect("pressed", self, "_on_CancelClaim_pressed")
	
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var cancel_font = ref_font.duplicate()
			cancel_font.size = 45
			cancel_font.outline_size = 3
			cancel_font.outline_color = Color(0.4, 0.1, 0.1)
			btn_cancel_claim.add_font_override("font", cancel_font)
			
	var red_normal = StyleBoxFlat.new()
	red_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_normal.anti_aliasing = true
	red_normal.corner_radius_top_left = 20
	red_normal.corner_radius_top_right = 20
	red_normal.corner_radius_bottom_right = 20
	red_normal.corner_radius_bottom_left = 20
	red_normal.border_width_bottom = 8
	red_normal.border_color = Color(0.65, 0.2, 0.2)
	red_normal.shadow_color = Color(0.85, 0.3, 0.35, 0.15)
	red_normal.shadow_size = 6
	red_normal.shadow_offset = Vector2(0, 2)
	red_normal.content_margin_left = 30
	red_normal.content_margin_right = 30
	
	var red_hover = StyleBoxFlat.new()
	red_hover.bg_color = Color(0.85, 0.3, 0.35)
	red_hover.anti_aliasing = true
	red_hover.corner_radius_top_left = 20
	red_hover.corner_radius_top_right = 20
	red_hover.corner_radius_bottom_right = 20
	red_hover.corner_radius_bottom_left = 20
	red_hover.border_width_bottom = 8
	red_hover.border_color = Color(0.7, 0.25, 0.25)
	red_hover.shadow_color = Color(0.85, 0.3, 0.35, 0.2)
	red_hover.shadow_size = 8
	red_hover.shadow_offset = Vector2(0, 3)
	red_hover.content_margin_left = 30
	red_hover.content_margin_right = 30
	
	var red_pressed = StyleBoxFlat.new()
	red_pressed.bg_color = Color(0.7, 0.2, 0.25)
	red_pressed.anti_aliasing = true
	red_pressed.corner_radius_top_left = 20
	red_pressed.corner_radius_top_right = 20
	red_pressed.corner_radius_bottom_right = 20
	red_pressed.corner_radius_bottom_left = 20
	red_pressed.border_width_top = 4
	red_pressed.border_width_bottom = 4
	red_pressed.border_color = Color(0.55, 0.15, 0.18)
	red_pressed.shadow_color = Color(0, 0, 0, 0.15)
	red_pressed.shadow_size = 2
	red_pressed.shadow_offset = Vector2(0, 1)
	red_pressed.content_margin_left = 30
	red_pressed.content_margin_right = 30
	
	btn_cancel_claim.add_stylebox_override("normal", red_normal)
	btn_cancel_claim.add_stylebox_override("hover", red_hover)
	btn_cancel_claim.add_stylebox_override("pressed", red_pressed)
	btn_cancel_claim.add_color_override("font_color", Color(1, 1, 1))
	btn_cancel_claim.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_cancel_claim.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	claim_profile_panel.add_child(btn_cancel_claim)
	var lilita = load("res://assets/fonts/LilitaOne-Regular.ttf")
	
	var OnscreenKeyboardClass = load("res://addons/onscreenkeyboard/onscreen_keyboard.gd")
	onscreen_keyboard = OnscreenKeyboardClass.new()
	onscreen_keyboard.name = "OnscreenKeyboard"
	onscreen_keyboard.autoShow = false
	onscreen_keyboard.custom_show_y = - 1.0
	onscreen_keyboard.custom_hide_y = - 1.0
	
	
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.1, 0.16, 0.95)
	bg_style.corner_radius_top_left = 24
	bg_style.corner_radius_top_right = 24
	bg_style.border_width_top = 4
	bg_style.border_color = Color(0.15, 0.2, 0.35, 0.8)
	onscreen_keyboard.styleBackground = bg_style
	
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.22, 0.3, 0.95)
	normal.corner_radius_top_left = 16
	normal.corner_radius_top_right = 16
	normal.corner_radius_bottom_right = 16
	normal.corner_radius_bottom_left = 16
	normal.border_width_bottom = 6
	normal.border_color = Color(0.1, 0.12, 0.18)
	normal.shadow_color = Color(0, 0, 0, 0.25)
	normal.shadow_size = 2
	normal.shadow_offset = Vector2(0, 2)
	onscreen_keyboard.styleNormal = normal
	
	var hover = normal.duplicate()
	hover.bg_color = Color(0.22, 0.28, 0.38)
	hover.border_color = Color(0.12, 0.16, 0.22)
	onscreen_keyboard.styleHover = hover
	
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.12, 0.15, 0.22)
	pressed.border_width_top = 3
	pressed.border_width_bottom = 3
	pressed.border_color = Color(0.08, 0.1, 0.15)
	onscreen_keyboard.stylePressed = pressed
	
	var special = StyleBoxFlat.new()
	special.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	special.corner_radius_top_left = 16
	special.corner_radius_top_right = 16
	special.corner_radius_bottom_right = 16
	special.corner_radius_bottom_left = 16
	special.border_width_bottom = 6
	special.border_color = Color(0.06, 0.08, 0.12)
	special.shadow_color = Color(0, 0, 0, 0.25)
	special.shadow_size = 2
	special.shadow_offset = Vector2(0, 2)
	onscreen_keyboard.styleSpecialKeys = special
	
	lilita = load("res://assets/fonts/LilitaOne-Regular.ttf")
	if lilita:
		var key_font = DynamicFont.new()
		key_font.font_data = lilita
		key_font.size = 52
		key_font.outline_size = 2
		key_font.outline_color = Color(0.05, 0.08, 0.15, 0.9)
		key_font.use_filter = true
		onscreen_keyboard.font = key_font
	
	onscreen_keyboard.fontColor = Color(1, 1, 1)
	onscreen_keyboard.fontColorHover = Color(1, 1, 1)
	onscreen_keyboard.fontColorPressed = Color(1, 1, 1)
	
	onscreen_keyboard.bottom_safety_margin = 80.0
	onscreen_keyboard.side_margin = 16.0
	onscreen_keyboard.anchor_left = 0.0
	onscreen_keyboard.anchor_right = 1.0
	onscreen_keyboard.anchor_top = 0.0
	onscreen_keyboard.anchor_bottom = 0.0
	onscreen_keyboard.margin_left = 0
	onscreen_keyboard.margin_top = 0
	onscreen_keyboard.margin_right = 0
	onscreen_keyboard.margin_bottom = 850
	$UI / Control.add_child(onscreen_keyboard)
	onscreen_keyboard.hide()
	onscreen_keyboard.visible = false
	onscreen_keyboard.connect("visibilityChanged", self, "_on_onscreen_keyboard_visibility_changed")
	onscreen_keyboard.connect("key_released", self, "_on_onscreen_keyboard_key_released")
	
	
	lbl_active_field = Label.new()
	lbl_active_field.name = "ActiveFieldLabel"
	lbl_active_field.text = "Editing: Email Address"
	lbl_active_field.align = Label.ALIGN_LEFT
	lbl_active_field.anchor_left = 0.0
	lbl_active_field.margin_left = 30
	lbl_active_field.margin_top = 28
	lbl_active_field.margin_bottom = 83
	
	if lilita:
		var active_field_font = DynamicFont.new()
		active_field_font.font_data = lilita
		active_field_font.size = 36
		active_field_font.outline_size = 2
		active_field_font.outline_color = Color(0.1, 0.1, 0.15, 1)
		active_field_font.use_filter = true
		lbl_active_field.add_font_override("font", active_field_font)
	onscreen_keyboard.add_child(lbl_active_field)
	
	
	btn_switch_field = Button.new()
	btn_switch_field.name = "SwitchFieldButton"
	btn_switch_field.text = "Switch Field"
	btn_switch_field.anchor_left = 1.0
	btn_switch_field.anchor_right = 1.0
	btn_switch_field.margin_left = - 280
	btn_switch_field.margin_right = - 30
	btn_switch_field.margin_top = 15
	btn_switch_field.margin_bottom = 85
	
	
	var blue_normal = StyleBoxFlat.new()
	blue_normal.bg_color = Color(0.2, 0.45, 0.75)
	blue_normal.anti_aliasing = true
	blue_normal.corner_radius_top_left = 16
	blue_normal.corner_radius_top_right = 16
	blue_normal.corner_radius_bottom_right = 16
	blue_normal.corner_radius_bottom_left = 16
	blue_normal.border_width_bottom = 6
	blue_normal.border_color = Color(0.12, 0.28, 0.5)
	blue_normal.content_margin_left = 16
	blue_normal.content_margin_right = 16
	
	var blue_hover = blue_normal.duplicate()
	blue_hover.bg_color = Color(0.25, 0.55, 0.85)
	blue_hover.border_color = Color(0.15, 0.35, 0.6)
	
	var blue_pressed = blue_normal.duplicate()
	blue_pressed.bg_color = Color(0.15, 0.35, 0.6)
	blue_pressed.border_width_top = 2
	blue_pressed.border_width_bottom = 2
	blue_pressed.border_color = Color(0.1, 0.22, 0.4)
	
	btn_switch_field.add_stylebox_override("normal", blue_normal)
	btn_switch_field.add_stylebox_override("hover", blue_hover)
	btn_switch_field.add_stylebox_override("pressed", blue_pressed)
	btn_switch_field.add_color_override("font_color", Color(1, 1, 1))
	btn_switch_field.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_switch_field.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	
	if lilita:
		var switch_btn_font = DynamicFont.new()
		switch_btn_font.font_data = lilita
		switch_btn_font.size = 34
		switch_btn_font.outline_size = 2
		switch_btn_font.outline_color = Color(0.1, 0.1, 0.15, 1)
		switch_btn_font.use_filter = true
		btn_switch_field.add_font_override("font", switch_btn_font)
		
	btn_switch_field.connect("pressed", self, "_on_SwitchField_pressed")
	onscreen_keyboard.add_child(btn_switch_field)

	
	
	if OS.has_feature("JavaScript") or OS.get_name() == "HTML5" or OS.get_name() == "Android":
		btn_google_claim.visible = false
	else:
		btn_google_claim.visible = true
		
	btn_cancel_claim.visible = true
	
	_update_onscreen_keyboard_visibility()
	$UI / Control.add_child(claim_profile_panel)
	
func _create_conflict_panel():
	conflict_panel = Panel.new()
	conflict_panel.name = "ConflictPanel"
	conflict_panel.anchor_right = 1.0
	conflict_panel.anchor_bottom = 1.0
	conflict_panel.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	conflict_panel.add_stylebox_override("panel", panel_style)
	
	
	var title = Label.new()
	title.text = "⚠️ CLOUD CONFLICT DETECTED"
	title.align = Label.ALIGN_CENTER
	title.anchor_right = 1.0
	title.margin_top = 80
	title.margin_bottom = 170
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if title_font:
		title_font.size = 65
		title_font.outline_size = 4
		title_font.outline_color = Color(0.08, 0.1, 0.15)
		title.add_font_override("font", title_font)
	title.add_color_override("font_color", Color(1.0, 0.85, 0.2))
	conflict_panel.add_child(title)
	
	
	var divider = Panel.new()
	divider.anchor_left = 0.1
	divider.anchor_right = 0.9
	divider.margin_top = 190
	divider.margin_bottom = 193
	var div_style = StyleBoxFlat.new()
	div_style.bg_color = Color(0.25, 0.3, 0.45, 0.7)
	divider.add_stylebox_override("panel", div_style)
	conflict_panel.add_child(divider)
	
	
	var subtitle = Label.new()
	subtitle.text = "An existing save file was found for this email.\nChoose which profile you want to keep:"
	subtitle.align = Label.ALIGN_CENTER
	subtitle.anchor_right = 1.0
	subtitle.margin_top = 215
	subtitle.margin_bottom = 335
	var sub_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if sub_font:
		sub_font.size = 50
		sub_font.outline_size = 3
		sub_font.outline_color = Color(0.08, 0.1, 0.15)
		subtitle.add_font_override("font", sub_font)
	subtitle.add_color_override("font_color", Color(0.85, 0.85, 0.95))
	conflict_panel.add_child(subtitle)
	
	
	var btn_group = ButtonGroup.new()
	
	
	var cards_vbox = VBoxContainer.new()
	cards_vbox.name = "CardsVBox"
	cards_vbox.anchor_left = 0.5
	cards_vbox.anchor_right = 0.5
	cards_vbox.margin_left = - 450
	cards_vbox.margin_right = 450
	cards_vbox.margin_top = 355
	cards_vbox.margin_bottom = 1375
	cards_vbox.alignment = BoxContainer.ALIGN_CENTER
	cards_vbox.set("custom_constants/separation", 20)
	conflict_panel.add_child(cards_vbox)
	
	
	var card_normal = StyleBoxFlat.new()
	card_normal.bg_color = Color(0.1, 0.12, 0.18, 0.9)
	card_normal.anti_aliasing = true
	card_normal.corner_radius_top_left = 15
	card_normal.corner_radius_top_right = 15
	card_normal.corner_radius_bottom_right = 15
	card_normal.corner_radius_bottom_left = 15
	card_normal.border_width_left = 3
	card_normal.border_width_top = 3
	card_normal.border_width_right = 3
	card_normal.border_width_bottom = 3
	card_normal.border_color = Color(0.2, 0.25, 0.35)
	
	var card_hover = card_normal.duplicate()
	card_hover.bg_color = Color(0.12, 0.15, 0.22, 0.9)
	card_hover.border_color = Color(0.3, 0.35, 0.45)
	
	var card_selected = card_normal.duplicate()
	card_selected.bg_color = Color(0.14, 0.16, 0.24, 0.95)
	card_selected.border_color = Color(1.0, 0.85, 0.2)
	card_selected.shadow_color = Color(1.0, 0.85, 0.2, 0.35)
	card_selected.shadow_size = 12
	card_selected.shadow_offset = Vector2(0, 0)
	
	var label_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if label_font:
		label_font.size = 44
		label_font.outline_size = 2
		label_font.outline_color = Color(0.08, 0.1, 0.15)
		
	var bold_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if bold_font:
		bold_font.size = 45
		bold_font.outline_size = 3
		bold_font.outline_color = Color(0.08, 0.1, 0.15)
		
	
	card_device = Button.new()
	card_device.toggle_mode = true
	card_device.group = btn_group
	card_device.rect_min_size = Vector2(900, 460)
	card_device.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_device.add_stylebox_override("normal", card_normal)
	card_device.add_stylebox_override("hover", card_hover)
	card_device.add_stylebox_override("pressed", card_selected)
	card_device.add_stylebox_override("focus", card_selected)
	card_device.connect("toggled", self, "_on_ProfileCard_toggled", ["device"])
	
	var vbox_dev = VBoxContainer.new()
	vbox_dev.anchor_right = 1.0
	vbox_dev.anchor_bottom = 1.0
	vbox_dev.margin_left = 30
	vbox_dev.margin_right = - 30
	vbox_dev.margin_top = 25
	vbox_dev.margin_bottom = - 25
	vbox_dev.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox_dev.alignment = BoxContainer.ALIGN_CENTER
	vbox_dev.set("custom_constants/separation", 15)
	card_device.add_child(vbox_dev)
	
	var header_dev = Label.new()
	header_dev.text = "📱 CURRENT DEVICE PROFILE"
	header_dev.align = Label.ALIGN_CENTER
	header_dev.mouse_filter = Control.MOUSE_FILTER_PASS
	if bold_font: header_dev.add_font_override("font", bold_font)
	header_dev.add_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox_dev.add_child(header_dev)
	
	lbl_device_name = Label.new()
	lbl_device_name.align = Label.ALIGN_CENTER
	lbl_device_name.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_device_name.add_font_override("font", label_font)
	lbl_device_name.add_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox_dev.add_child(lbl_device_name)
	
	lbl_device_classic = Label.new()
	lbl_device_classic.align = Label.ALIGN_CENTER
	lbl_device_classic.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_device_classic.add_font_override("font", label_font)
	lbl_device_classic.add_color_override("font_color", Color(0.85, 0.85, 0.95))
	vbox_dev.add_child(lbl_device_classic)
	
	lbl_device_escalation = Label.new()
	lbl_device_escalation.align = Label.ALIGN_CENTER
	lbl_device_escalation.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_device_escalation.add_font_override("font", label_font)
	lbl_device_escalation.add_color_override("font_color", Color(0.85, 0.85, 0.95))
	vbox_dev.add_child(lbl_device_escalation)
	
	var dev_row = HBoxContainer.new()
	dev_row.mouse_filter = Control.MOUSE_FILTER_PASS
	dev_row.alignment = BoxContainer.ALIGN_CENTER
	dev_row.set("custom_constants/separation", 40)
	vbox_dev.add_child(dev_row)
	
	lbl_device_games = Label.new()
	lbl_device_games.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_device_games.add_font_override("font", label_font)
	lbl_device_games.add_color_override("font_color", Color(0.75, 0.75, 0.85))
	dev_row.add_child(lbl_device_games)
	
	lbl_device_playtime = Label.new()
	lbl_device_playtime.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_device_playtime.add_font_override("font", label_font)
	lbl_device_playtime.add_color_override("font_color", Color(0.75, 0.75, 0.85))
	dev_row.add_child(lbl_device_playtime)
	
	cards_vbox.add_child(card_device)
	
	
	card_cloud = Button.new()
	card_cloud.toggle_mode = true
	card_cloud.group = btn_group
	card_cloud.rect_min_size = Vector2(900, 460)
	card_cloud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_cloud.add_stylebox_override("normal", card_normal)
	card_cloud.add_stylebox_override("hover", card_hover)
	card_cloud.add_stylebox_override("pressed", card_selected)
	card_cloud.add_stylebox_override("focus", card_selected)
	card_cloud.connect("toggled", self, "_on_ProfileCard_toggled", ["cloud"])
	
	var vbox_cld = VBoxContainer.new()
	vbox_cld.anchor_right = 1.0
	vbox_cld.anchor_bottom = 1.0
	vbox_cld.margin_left = 30
	vbox_cld.margin_right = - 30
	vbox_cld.margin_top = 25
	vbox_cld.margin_bottom = - 25
	vbox_cld.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox_cld.alignment = BoxContainer.ALIGN_CENTER
	vbox_cld.set("custom_constants/separation", 15)
	card_cloud.add_child(vbox_cld)
	
	var header_cld = Label.new()
	header_cld.text = "☁️ ONLINE CLOUD PROFILE"
	header_cld.align = Label.ALIGN_CENTER
	header_cld.mouse_filter = Control.MOUSE_FILTER_PASS
	if bold_font: header_cld.add_font_override("font", bold_font)
	header_cld.add_color_override("font_color", Color(0.5, 0.9, 0.6))
	vbox_cld.add_child(header_cld)
	
	lbl_cloud_name = Label.new()
	lbl_cloud_name.align = Label.ALIGN_CENTER
	lbl_cloud_name.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_cloud_name.add_font_override("font", label_font)
	lbl_cloud_name.add_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox_cld.add_child(lbl_cloud_name)
	
	lbl_cloud_classic = Label.new()
	lbl_cloud_classic.align = Label.ALIGN_CENTER
	lbl_cloud_classic.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_cloud_classic.add_font_override("font", label_font)
	lbl_cloud_classic.add_color_override("font_color", Color(0.85, 0.85, 0.95))
	vbox_cld.add_child(lbl_cloud_classic)
	
	lbl_cloud_escalation = Label.new()
	lbl_cloud_escalation.align = Label.ALIGN_CENTER
	lbl_cloud_escalation.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_cloud_escalation.add_font_override("font", label_font)
	lbl_cloud_escalation.add_color_override("font_color", Color(0.85, 0.85, 0.95))
	vbox_cld.add_child(lbl_cloud_escalation)
	
	var cld_row = HBoxContainer.new()
	cld_row.mouse_filter = Control.MOUSE_FILTER_PASS
	cld_row.alignment = BoxContainer.ALIGN_CENTER
	cld_row.set("custom_constants/separation", 40)
	vbox_cld.add_child(cld_row)
	
	lbl_cloud_games = Label.new()
	lbl_cloud_games.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_cloud_games.add_font_override("font", label_font)
	lbl_cloud_games.add_color_override("font_color", Color(0.75, 0.75, 0.85))
	cld_row.add_child(lbl_cloud_games)
	
	lbl_cloud_playtime = Label.new()
	lbl_cloud_playtime.mouse_filter = Control.MOUSE_FILTER_PASS
	if label_font: lbl_cloud_playtime.add_font_override("font", label_font)
	lbl_cloud_playtime.add_color_override("font_color", Color(0.75, 0.75, 0.85))
	cld_row.add_child(lbl_cloud_playtime)
	
	cards_vbox.add_child(card_cloud)
	
	
	var warn_lbl = Label.new()
	warn_lbl.text = "⚠️ Selecting a profile will permanently overwrite the unselected one."
	warn_lbl.align = Label.ALIGN_CENTER
	warn_lbl.anchor_left = 0.05
	warn_lbl.anchor_right = 0.95
	warn_lbl.margin_left = 0
	warn_lbl.margin_right = 0
	warn_lbl.margin_top = 1395
	warn_lbl.margin_bottom = 1505
	warn_lbl.autowrap = true
	var warn_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if warn_font:
		warn_font.size = 40
		warn_font.outline_size = 2
		warn_font.outline_color = Color(0.08, 0.1, 0.15)
		warn_lbl.add_font_override("font", warn_font)
	warn_lbl.add_color_override("font_color", Color(1.0, 0.6, 0.15))
	conflict_panel.add_child(warn_lbl)
	
	
	btn_keep_selected = Button.new()
	btn_keep_selected.text = "Keep Selected Save"
	btn_keep_selected.anchor_left = 0.5
	btn_keep_selected.anchor_right = 0.5
	btn_keep_selected.margin_left = - 450
	btn_keep_selected.margin_right = 450
	btn_keep_selected.margin_top = 1530
	btn_keep_selected.margin_bottom = 1630
	btn_keep_selected.connect("pressed", self, "_on_KeepSelected_pressed")
	btn_keep_selected.disabled = true
	btn_keep_selected.modulate.a = 0.5
	
	var ref_btn = $UI / Control / ButtonTemplate
	var ref_font = ref_btn.get_font("font") if ref_btn else null
	if ref_font:
		var green_font = ref_font.duplicate()
		green_font.size = 45
		green_font.outline_size = 3
		green_font.outline_color = Color(0.15, 0.4, 0.08)
		btn_keep_selected.add_font_override("font", green_font)
		
	var green_normal = StyleBoxFlat.new()
	green_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_normal.anti_aliasing = true
	green_normal.corner_radius_top_left = 20
	green_normal.corner_radius_top_right = 20
	green_normal.corner_radius_bottom_right = 20
	green_normal.corner_radius_bottom_left = 20
	green_normal.border_width_bottom = 8
	green_normal.border_color = Color(0.3, 0.6, 0.15)
	green_normal.content_margin_left = 30
	green_normal.content_margin_right = 30
	
	var green_hover = green_normal.duplicate()
	green_hover.bg_color = Color(0.45, 0.85, 0.25)
	green_hover.border_color = Color(0.35, 0.65, 0.18)
	
	var green_pressed = green_normal.duplicate()
	green_pressed.bg_color = Color(0.35, 0.7, 0.15)
	green_pressed.border_width_top = 4
	green_pressed.border_width_bottom = 4
	green_pressed.border_color = Color(0.25, 0.5, 0.1)
	
	btn_keep_selected.add_stylebox_override("normal", green_normal)
	btn_keep_selected.add_stylebox_override("hover", green_hover)
	btn_keep_selected.add_stylebox_override("pressed", green_pressed)
	btn_keep_selected.add_color_override("font_color", Color(1, 1, 1))
	btn_keep_selected.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_keep_selected.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	conflict_panel.add_child(btn_keep_selected)
	
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel Linking"
	btn_cancel.anchor_left = 0.5
	btn_cancel.anchor_right = 0.5
	btn_cancel.margin_left = - 450
	btn_cancel.margin_right = 450
	btn_cancel.margin_top = 1650
	btn_cancel.margin_bottom = 1750
	btn_cancel.connect("pressed", self, "_on_ConflictCancel_pressed")
	if ref_font:
		var cancel_font = ref_font.duplicate()
		cancel_font.size = 45
		cancel_font.outline_size = 3
		cancel_font.outline_color = Color(0.4, 0.1, 0.1)
		btn_cancel.add_font_override("font", cancel_font)
		
	var red_normal = StyleBoxFlat.new()
	red_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_normal.anti_aliasing = true
	red_normal.corner_radius_top_left = 20
	red_normal.corner_radius_top_right = 20
	red_normal.corner_radius_bottom_right = 20
	red_normal.corner_radius_bottom_left = 20
	red_normal.border_width_bottom = 8
	red_normal.border_color = Color(0.65, 0.2, 0.2)
	red_normal.content_margin_left = 30
	red_normal.content_margin_right = 30
	
	var red_hover = StyleBoxFlat.new()
	red_hover.bg_color = Color(0.85, 0.3, 0.35)
	red_hover.anti_aliasing = true
	red_hover.corner_radius_top_left = 20
	red_hover.corner_radius_top_right = 20
	red_hover.corner_radius_bottom_right = 20
	red_hover.corner_radius_bottom_left = 20
	red_hover.border_width_bottom = 8
	red_hover.border_color = Color(0.7, 0.25, 0.25)
	red_hover.shadow_color = Color(0.85, 0.3, 0.35, 0.2)
	red_hover.shadow_size = 8
	red_hover.shadow_offset = Vector2(0, 3)
	red_hover.content_margin_left = 30
	red_hover.content_margin_right = 30

	var red_pressed = StyleBoxFlat.new()
	red_pressed.bg_color = Color(0.7, 0.2, 0.25)
	red_pressed.anti_aliasing = true
	red_pressed.corner_radius_top_left = 20
	red_pressed.corner_radius_top_right = 20
	red_pressed.corner_radius_bottom_right = 20
	red_pressed.corner_radius_bottom_left = 20
	red_pressed.border_width_top = 4
	red_pressed.border_width_bottom = 4
	red_pressed.border_color = Color(0.55, 0.15, 0.18)
	red_pressed.shadow_color = Color(0, 0, 0, 0.15)
	red_pressed.shadow_size = 2
	red_pressed.shadow_offset = Vector2(0, 1)
	red_pressed.content_margin_left = 30
	red_pressed.content_margin_right = 30

	btn_cancel.add_stylebox_override("normal", red_normal)
	btn_cancel.add_stylebox_override("hover", red_hover)
	btn_cancel.add_stylebox_override("pressed", red_pressed)
	btn_cancel.add_color_override("font_color", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	conflict_panel.add_child(btn_cancel)
	
	$UI / Control.add_child(conflict_panel)

func _on_ClaimProfile_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.hide()
	if is_instance_valid(onscreen_keyboard):
		onscreen_keyboard.visible = false
		onscreen_keyboard.rect_position.y = get_viewport().get_visible_rect().size.y + 10
	claim_profile_panel.visible = true


func _reposition_claim_profile_buttons():
	if not is_instance_valid(claim_profile_panel):
		return
		
	var current_y = 850.0
	
	if is_instance_valid(btn_google_claim):
		if btn_google_claim.visible:
			btn_google_claim.margin_top = current_y
			btn_google_claim.margin_bottom = current_y + 100.0
			current_y += 125.0
			
	if is_instance_valid(btn_cancel_claim):
		if btn_cancel_claim.visible:
			btn_cancel_claim.margin_top = current_y
			btn_cancel_claim.margin_bottom = current_y + 100.0
			current_y += 125.0
			
	var ok_active = _is_onscreen_keyboard_active()
	if is_instance_valid(btn_onscreen_keyboard):
		btn_onscreen_keyboard.visible = ok_active
		if ok_active:
			btn_onscreen_keyboard.margin_top = current_y
			btn_onscreen_keyboard.margin_bottom = current_y + 150.0
			current_y += 160.0
			
	if is_instance_valid(lbl_onscreen_keyboard):
		lbl_onscreen_keyboard.visible = ok_active
		if ok_active:
			lbl_onscreen_keyboard.margin_top = current_y
			lbl_onscreen_keyboard.margin_bottom = current_y + 40.0


func _is_pc_device() -> bool:
	var is_pc = OS.get_name() in ["Windows", "OSX", "X11"]
	if OS.has_feature("HTML5") or OS.has_feature("JavaScript"):
		var js_is_desktop = JavaScript.eval("/Windows|Macintosh|Linux/i.test(navigator.userAgent) && !/Mobi|Android|Tablet|iPad|iPhone/i.test(navigator.userAgent)")
		if js_is_desktop:
			is_pc = true
		else:
			is_pc = false
	return is_pc





func _is_onscreen_keyboard_active() -> bool:
	if OS.get_name() in ["Android", "iOS"]:
		return false
	if not _is_pc_device():
		return true
	return onscreen_keyboard_setting_enabled

func _update_onscreen_keyboard_visibility():
	var ok_active = _is_onscreen_keyboard_active()
	
	_reposition_claim_profile_buttons()

	var target_focus = Control.FOCUS_NONE if ok_active else Control.FOCUS_ALL
	if is_instance_valid(claim_email_input):
		claim_email_input.virtual_keyboard_enabled = not ok_active
		claim_email_input.focus_mode = target_focus
	if is_instance_valid(claim_pass_input):
		claim_pass_input.virtual_keyboard_enabled = not ok_active
		claim_pass_input.focus_mode = target_focus
	if is_instance_valid(name_input):
		name_input.virtual_keyboard_enabled = not ok_active
		name_input.focus_mode = target_focus
	if is_instance_valid(game_over_name_input):
		game_over_name_input.virtual_keyboard_enabled = not ok_active
		game_over_name_input.focus_mode = target_focus
	
	if not ok_active:
		_close_onscreen_keyboard()
		if is_instance_valid(onscreen_keyboard):
			onscreen_keyboard.visible = false

func _on_KeyboardToggle_toggled(button_pressed: bool):
	onscreen_keyboard_setting_enabled = button_pressed
	_update_onscreen_keyboard_visibility()
	save_hiscore(false)
	if is_instance_valid(ui_button_click):
		ui_button_click.play()

func _open_onscreen_keyboard_for_field(field: LineEdit):
	if not is_instance_valid(onscreen_keyboard):
		return
		
	var ok_active = _is_onscreen_keyboard_active()
	if not ok_active:
		return
		
	var focus_owner = $UI / Control.get_focus_owner() if is_instance_valid($UI / Control) else null
	if focus_owner:
		focus_owner.release_focus()
		
	OS.hide_virtual_keyboard()
	
	if is_instance_valid(claim_email_input):
		claim_email_input.virtual_keyboard_enabled = false
		claim_email_input.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(claim_pass_input):
		claim_pass_input.virtual_keyboard_enabled = false
		claim_pass_input.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(name_input):
		name_input.virtual_keyboard_enabled = false
		name_input.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(game_over_name_input):
		game_over_name_input.virtual_keyboard_enabled = false
		game_over_name_input.focus_mode = Control.FOCUS_NONE
		
	onscreen_keyboard.visible = true
	onscreen_keyboard.raise()
	onscreen_keyboard.show()
	
	if is_instance_valid(indicator_arrow):
		indicator_arrow.visible = (field == claim_email_input or field == claim_pass_input)
	if is_instance_valid(btn_onscreen_keyboard):
		btn_onscreen_keyboard.modulate = Color(0.7, 1.0, 0.7) if (field == claim_email_input or field == claim_pass_input) else Color(1, 1, 1)
		

			
	if is_instance_valid(game_over_name_prompt) and field == game_over_name_input:
		var card = game_over_name_prompt.get_node_or_null("Card")
		if card:
			card.margin_top = - 650
			card.margin_bottom = 30
			
	_set_active_onscreen_keyboard_field(field)
	_reposition_claim_profile_buttons()


func _close_onscreen_keyboard():
	active_onscreen_keyboard_field = null
	
	if is_instance_valid(game_over_name_prompt):
		var card = game_over_name_prompt.get_node_or_null("Card")
		if card:
			card.margin_top = - 340
			card.margin_bottom = 340
	
	var target_focus = Control.FOCUS_NONE if _is_onscreen_keyboard_active() else Control.FOCUS_ALL
	
	if is_instance_valid(claim_email_input):
		claim_email_input.focus_mode = target_focus
		claim_email_input.add_stylebox_override("normal", line_edit_style)
	if is_instance_valid(claim_pass_input):
		claim_pass_input.focus_mode = target_focus
		claim_pass_input.add_stylebox_override("normal", line_edit_style)
	if is_instance_valid(name_input):
		name_input.focus_mode = target_focus
		name_input.add_stylebox_override("normal", line_edit_style)
	if is_instance_valid(game_over_name_input):
		game_over_name_input.focus_mode = target_focus
		game_over_name_input.add_stylebox_override("normal", game_over_input_style)
		game_over_name_input.align = LineEdit.ALIGN_CENTER
		
	if is_instance_valid(indicator_arrow):
		indicator_arrow.visible = false
	if is_instance_valid(btn_onscreen_keyboard):
		btn_onscreen_keyboard.modulate = Color(1, 1, 1)
	if is_instance_valid(btn_cancel_claim):
		btn_cancel_claim.visible = true
	if is_instance_valid(btn_google_claim):
		if not (OS.has_feature("JavaScript") or OS.get_name() == "HTML5" or OS.get_name() == "Android"):
			btn_google_claim.visible = true
			
	_reposition_claim_profile_buttons()
	if is_instance_valid(onscreen_keyboard):
		onscreen_keyboard.active_field = null
	if is_instance_valid(onscreen_keyboard):
		onscreen_keyboard.hide()
		
		var t = get_tree().create_timer(0.25)
		yield(t, "timeout")
		if is_instance_valid(onscreen_keyboard) and active_onscreen_keyboard_field == null:
			onscreen_keyboard.visible = false

func _on_onscreen_keyboard_visibility_changed(is_visible: bool):
	if not is_visible and active_onscreen_keyboard_field != null:
		_close_onscreen_keyboard()

func _set_active_onscreen_keyboard_field(field: LineEdit):
	active_onscreen_keyboard_field = field
	if is_instance_valid(lbl_active_field):
		if field == claim_email_input:
			lbl_active_field.text = "Editing: Email Address"
		elif field == claim_pass_input:
			lbl_active_field.text = "Editing: Password"
		elif field == name_input or field == game_over_name_input:
			lbl_active_field.text = "Editing: Player Name"
			
	
	if is_instance_valid(claim_email_input) and is_instance_valid(claim_pass_input):
		if field == claim_email_input:
			claim_email_input.add_stylebox_override("normal", line_edit_focus)
			claim_pass_input.add_stylebox_override("normal", line_edit_style)
		elif field == claim_pass_input:
			claim_email_input.add_stylebox_override("normal", line_edit_style)
			claim_pass_input.add_stylebox_override("normal", line_edit_focus)
		else:
			claim_email_input.add_stylebox_override("normal", line_edit_style)
			claim_pass_input.add_stylebox_override("normal", line_edit_style)
			
	if is_instance_valid(name_input):
		if field == name_input:
			name_input.add_stylebox_override("normal", line_edit_focus)
		else:
			name_input.add_stylebox_override("normal", line_edit_style)
			
	if is_instance_valid(game_over_name_input):
		if field == game_over_name_input:
			game_over_name_input.add_stylebox_override("normal", game_over_input_focus)
		else:
			game_over_name_input.add_stylebox_override("normal", game_over_input_style)
			
	var ok_active = _is_onscreen_keyboard_active()
	if ok_active:
		var focus_owner = $UI / Control.get_focus_owner() if is_instance_valid($UI / Control) else null
		if focus_owner:
			focus_owner.release_focus()
	else:
		if is_instance_valid(field) and not field.has_focus():
			field.grab_focus()
			
	if is_instance_valid(onscreen_keyboard):
		onscreen_keyboard.active_field = field
func _on_input_focus_entered(field: LineEdit):
	var ok_active = _is_onscreen_keyboard_active()
	if ok_active:
		field.release_focus()
		return
		
	active_onscreen_keyboard_field = field
	if is_instance_valid(lbl_active_field):
		if field == claim_email_input:
			lbl_active_field.text = "Editing: Email Address"
		elif field == claim_pass_input:
			lbl_active_field.text = "Editing: Password"
		elif field == name_input or field == game_over_name_input:
			lbl_active_field.text = "Editing: Player Name"

func _on_SwitchField_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	if active_onscreen_keyboard_field == claim_email_input:
		_set_active_onscreen_keyboard_field(claim_pass_input)
	elif active_onscreen_keyboard_field == claim_pass_input:
		_set_active_onscreen_keyboard_field(claim_email_input)

func _on_LineEdit_gui_input(event: InputEvent, field: LineEdit):
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		var ok_active = _is_onscreen_keyboard_active()
		if ok_active:
			_open_onscreen_keyboard_for_field(field)
			if is_instance_valid(onscreen_keyboard):
				onscreen_keyboard.handle_input_click(field, event.position.x)

func _on_onscreen_keyboard_key_released(key_value: String):
	if not is_instance_valid(active_onscreen_keyboard_field):
		return
		
	var field = active_onscreen_keyboard_field
	if key_value == "Return":
		if field == claim_email_input:
			_set_active_onscreen_keyboard_field(claim_pass_input)
		elif field == claim_pass_input:
			_on_SubmitClaim_pressed()
		elif field == name_input:
			_on_name_submit_pressed()
		elif field == game_over_name_input:
			_on_submit_name_pressed()

func _on_Email_text_entered(_new_text):
	if _is_onscreen_keyboard_active():
		_set_active_onscreen_keyboard_field(claim_pass_input)
	else:
		claim_pass_input.grab_focus()

func _on_Password_text_entered(_new_text):
	_on_SubmitClaim_pressed()

func _on_CancelClaim_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	_close_onscreen_keyboard()
	claim_profile_panel.visible = false
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.show()

func _on_SubmitClaim_pressed():
	var email = claim_email_input.text.strip_edges()
	var password = claim_pass_input.text.strip_edges()
	if email == "" or password == "":
		return
	_close_onscreen_keyboard()
	FirebaseManager.start_profile_claim_email(email, password, player_data)
	claim_profile_panel.visible = false
	_show_loading("Checking Account...")

func _on_GoogleClaim_pressed():
	_close_onscreen_keyboard()
	FirebaseManager.start_google_login(player_data)
	claim_profile_panel.visible = false
	_show_loading("Checking Account...")

func _on_claim_status_changed(status_text: String):
	var text_to_show = "Loading..."
	if status_text == "Checking account...":
		text_to_show = "Checking Account..."
	elif status_text == "Linking account...":
		text_to_show = "Linking Account..."
	elif status_text == "Creating new account...":
		text_to_show = "Creating New Account..."
	_show_loading(text_to_show)

func _on_profile_claim_conflict(_guest_stats, _cloud_stats):
	_hide_loading()
	
	selected_profile_type = ""
	if card_device:
		card_device.pressed = false
	if card_cloud:
		card_cloud.pressed = false
	if btn_keep_selected:
		btn_keep_selected.disabled = true
		btn_keep_selected.modulate.a = 0.5
		
	
	var dev_name = str(FirebaseManager.cached_guest_stats.get("player_name", ""))
	if dev_name == "": dev_name = "Guest"
	var dev_classic = int(FirebaseManager.cached_guest_stats.get("classic_highscore", 0))
	var dev_escalation = int(FirebaseManager.cached_guest_stats.get("escalation_highscore", 0))
	var dev_level = int(FirebaseManager.cached_guest_stats.get("escalation_highest_level", 1))
	var dev_games = int(FirebaseManager.cached_guest_stats.get("total_games", 0))
	var dev_playtime_sec = float(FirebaseManager.cached_guest_stats.get("playtime", 0.0))
	
	var dev_hours = int(dev_playtime_sec / 3600.0)
	var dev_mins = int((int(dev_playtime_sec) % 3600) / 60.0)
	var dev_playtime_str = ""
	if dev_hours > 0:
		dev_playtime_str = str(dev_hours) + "h " + str(dev_mins) + "m"
	else:
		dev_playtime_str = str(dev_mins) + "m"
		
	if lbl_device_name:
		lbl_device_name.text = "Name: " + dev_name
	if lbl_device_classic:
		lbl_device_classic.text = "Classic High Score: " + str(dev_classic)
	if lbl_device_escalation:
		lbl_device_escalation.text = "Escalation High Score: " + str(dev_escalation) + " (Lvl " + str(dev_level) + ")"
	if lbl_device_games:
		lbl_device_games.text = "Games Played: " + str(dev_games)
	if lbl_device_playtime:
		lbl_device_playtime.text = "Playtime: " + dev_playtime_str
		
	
	var cld_name = str(FirebaseManager.cached_cloud_stats.get("player_name", ""))
	if cld_name == "": cld_name = "Cloud Player"
	var cld_classic = int(FirebaseManager.cached_cloud_stats.get("classic_highscore", 0))
	var cld_escalation = int(FirebaseManager.cached_cloud_stats.get("escalation_highscore", 0))
	var cld_level = int(FirebaseManager.cached_cloud_stats.get("escalation_highest_level", 1))
	var cld_games = int(FirebaseManager.cached_cloud_stats.get("total_games", 0))
	var cld_playtime_sec = float(FirebaseManager.cached_cloud_stats.get("playtime", 0.0))
	
	var cld_hours = int(cld_playtime_sec / 3600.0)
	var cld_mins = int((int(cld_playtime_sec) % 3600) / 60.0)
	var cld_playtime_str = ""
	if cld_hours > 0:
		cld_playtime_str = str(cld_hours) + "h " + str(cld_mins) + "m"
	else:
		cld_playtime_str = str(cld_mins) + "m"
		
	if lbl_cloud_name:
		lbl_cloud_name.text = "Name: " + cld_name
	if lbl_cloud_classic:
		lbl_cloud_classic.text = "Classic High Score: " + str(cld_classic)
	if lbl_cloud_escalation:
		lbl_cloud_escalation.text = "Escalation High Score: " + str(cld_escalation) + " (Lvl " + str(cld_level) + ")"
	if lbl_cloud_games:
		lbl_cloud_games.text = "Games Played: " + str(cld_games)
	if lbl_cloud_playtime:
		lbl_cloud_playtime.text = "Playtime: " + cld_playtime_str
		
	conflict_panel.visible = true

func _on_ConflictCancel_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	conflict_panel.visible = false
	FirebaseManager.resolve_conflict_cancel()
	
	
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.hide()
	active_panel_name = ""
	_show_active_screen()

func _on_profile_claim_succeeded(cloud_stats = {}):
	_hide_loading()
	if typeof(cloud_stats) == TYPE_DICTIONARY and not cloud_stats.empty():
		set_highscore(0, int(cloud_stats.get("classic_highscore", 0)))
		set_highscore(1, int(cloud_stats.get("escalation_highscore", 0)))
		set_highest_level(0, 1)
		set_highest_level(1, int(cloud_stats.get("escalation_highest_level", 1)))
		player_data["total_games"] = int(cloud_stats.get("total_games", 0))
		
		player_data["playtime"] = float(cloud_stats.get("playtime", 0.0))
		player_data["total_deaths"] = int(cloud_stats.get("total_deaths", 0))
		player_data["total_revives"] = int(cloud_stats.get("total_revives", 0))
		player_data["total_distance"] = float(cloud_stats.get("total_distance", 0.0))
		player_data["has_changed_name_logged_in"] = bool(cloud_stats.get("has_changed_name_logged_in", false))
		
		var c_name = cloud_stats.get("player_name", "")
		if c_name != "":
			Global.player_name = c_name
			Global.has_changed_name = true
			
		save_hiscore(false)
		update_score_display()
	else:
		save_hiscore(false)
		update_score_display()

	FirebaseManager.fetch_leaderboards(true)

	if FirebaseManager.get_is_registered() and Global.player_name != "":
		if Firebase.Auth.auth and Firebase.Auth.auth.has("idtoken"):
			Firebase.Auth.update_account(Firebase.Auth.auth.idtoken, Global.player_name, "", [], true)

	if active_panel_name == "profile":
		active_panel_name = ""
		_on_ProfileButton_pressed()
	
	print("Profile Claim Succeeded!")

func _on_profile_claim_failed(reason):
	_hide_loading()
	print("Profile Claim Failed: ", reason)
	var user_message = "An error occurred during authentication."
	var reason_str = str(reason)
	if "EMAIL_EXISTS" in reason_str:
		user_message = "The email address is already in use by another account."
	elif "INVALID_EMAIL" in reason_str:
		user_message = "The email address is badly formatted."
	elif "WEAK_PASSWORD" in reason_str:
		user_message = "The password is too weak. It must be at least 6 characters."
	elif "INVALID_PASSWORD" in reason_str or "EMAIL_NOT_FOUND" in reason_str:
		user_message = "Incorrect email address or password."
	elif "USER_DISABLED" in reason_str:
		user_message = "This user account has been disabled."
	elif "Connection error" in reason_str or "Error connecting" in reason_str or "timeout" in reason_str:
		user_message = "Connection error. Please check your internet connection and try again."
	else:
		user_message = reason_str
		
	show_generic_error("Link Account Failed", user_message)
	if is_instance_valid(claim_profile_panel):
		claim_profile_panel.show()

func _on_ForgotPassword_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	var email = claim_email_input.text.strip_edges()
	if email == "":
		show_generic_error("Password Reset Failed", "Please enter your email address first.")
		return
		
	if not "@" in email or not "." in email:
		show_generic_error("Password Reset Failed", "Please enter a valid email address.")
		return
		
	_close_onscreen_keyboard()
	claim_profile_panel.visible = false
	_show_loading("Sending Reset Email...")
	FirebaseManager.send_password_reset(email)

func _on_password_reset_finished(success: bool, error_message: String):
	_hide_loading()
	if success:
		var email = claim_email_input.text.strip_edges()
		show_generic_error("Password Reset Sent", "A password reset link has been sent to " + email + ". Please check your inbox.")
		if is_instance_valid(claim_profile_panel):
			claim_profile_panel.show()
	else:
		var user_message = error_message
		if "EMAIL_NOT_FOUND" in error_message:
			user_message = "This email address is not registered."
		elif "INVALID_EMAIL" in error_message:
			user_message = "The email address is badly formatted."
		else:
			user_message = error_message
		show_generic_error("Password Reset Failed", user_message)
		if is_instance_valid(claim_profile_panel):
			claim_profile_panel.show()

func _update_manage_account_name_ui():
	if not is_instance_valid(name_input):
		return
		
	var is_registered = FirebaseManager.get_is_registered()
	if not is_registered:
		name_input.editable = false
		name_input.anchor_right = 0.85
		name_input.margin_right = 0
		name_input.align = LineEdit.ALIGN_CENTER
		if is_instance_valid(name_submit_btn):
			name_submit_btn.visible = false
			name_submit_btn.disabled = true
		if is_instance_valid(name_cancel_btn):
			name_cancel_btn.visible = false
		if is_instance_valid(manage_name_hint):
			manage_name_hint.visible = false
	else:
		var has_changed = bool(player_data.get("has_changed_name_logged_in", false))
		if has_changed:
			name_input.editable = false
			name_input.anchor_right = 0.85
			name_input.margin_right = 0
			name_input.align = LineEdit.ALIGN_CENTER
			if is_instance_valid(name_submit_btn):
				name_submit_btn.visible = false
				name_submit_btn.disabled = true
			if is_instance_valid(name_cancel_btn):
				name_cancel_btn.visible = false
			if is_instance_valid(manage_name_hint):
				manage_name_hint.visible = false
		else:
			name_input.anchor_right = 0.6
			name_input.margin_right = 0
			name_input.editable = is_editing_name
			name_input.align = LineEdit.ALIGN_LEFT if is_editing_name else LineEdit.ALIGN_CENTER
			
			if is_instance_valid(name_submit_btn):
				name_submit_btn.visible = true
				name_submit_btn.disabled = false
				if is_editing_name:
					name_submit_btn.text = "Set"
				else:
					name_submit_btn.text = "Edit"
			if is_instance_valid(name_cancel_btn):
				name_cancel_btn.visible = is_editing_name
			if is_instance_valid(manage_name_hint):
				manage_name_hint.visible = true
				manage_name_hint.text = "You can change your player name once."
				manage_name_hint.add_color_override("font_color", Color(0.4, 0.8, 0.2))

	
	if not is_editing_name:
		name_input.text = Global.player_name
	else:
		name_input.text = name_input.text

func _create_manage_account_panel():
	manage_account_panel = Panel.new()
	manage_account_panel.name = "ManageAccountPanel"
	manage_account_panel.anchor_right = 1.0
	manage_account_panel.anchor_bottom = 1.0
	manage_account_panel.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	manage_account_panel.add_stylebox_override("panel", panel_style)
	
	var title = Label.new()
	title.text = "Manage Account"
	title.align = Label.ALIGN_CENTER
	title.anchor_right = 1.0
	title.margin_top = 230
	title.margin_bottom = 330
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if title_font:
		title_font.size = 65
		title_font.outline_size = 4
		title_font.outline_color = Color(0.08, 0.1, 0.15)
		title.add_font_override("font", title_font)
	manage_account_panel.add_child(title)
	
	
	var divider = Panel.new()
	divider.anchor_left = 0.1
	divider.anchor_right = 0.9
	divider.margin_top = 350
	divider.margin_bottom = 353
	var div_style = StyleBoxFlat.new()
	div_style.bg_color = Color(0.25, 0.3, 0.45, 0.7)
	divider.add_stylebox_override("panel", div_style)
	manage_account_panel.add_child(divider)
	
	var ref_btn = $UI / Control / ButtonTemplate
	var ref_font = null
	if ref_btn:
		ref_font = ref_btn.get_font("font")
		
	
	var name_label = Label.new()
	name_label.text = "Player Name"
	name_label.align = Label.ALIGN_CENTER
	name_label.anchor_left = 0.15
	name_label.anchor_right = 0.85
	name_label.margin_top = 420
	name_label.margin_bottom = 490
	if ref_font:
		var name_label_font = ref_font.duplicate()
		name_label_font.size = 50
		name_label_font.outline_size = 3
		name_label_font.outline_color = Color(0.08, 0.1, 0.15)
		name_label.add_font_override("font", name_label_font)
	manage_account_panel.add_child(name_label)
	
	
	var input_font = DynamicFont.new()
	input_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	input_font.size = 50
	input_font.outline_size = 2
	input_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	
	name_input = LineEdit.new()
	name_input.max_length = 20
	name_input.placeholder_text = "Enter name..."
	name_input.anchor_left = 0.15
	name_input.anchor_right = 0.85
	name_input.margin_right = 0
	name_input.margin_top = 510
	name_input.margin_bottom = 610
	name_input.add_font_override("font", input_font)
	name_input.add_stylebox_override("normal", line_edit_style)
	name_input.add_stylebox_override("focus", line_edit_focus)
	name_input.add_color_override("font_color", Color(1, 1, 1))
	name_input.add_color_override("cursor_color", Color(1, 1, 1))
	name_input.add_color_override("placeholder_color", Color(0.6, 0.6, 0.7))
	name_input.caret_blink = true
	name_input.caret_blink_speed = 0.65
	name_input.add_constant_override("caret_width", 3)
	name_input.connect("text_changed", self, "_on_name_input_changed")
	name_input.connect("text_entered", self, "_on_name_input_entered")
	name_input.connect("focus_exited", self, "_on_name_input_focus_exited")
	name_input.connect("gui_input", self, "_on_LineEdit_gui_input", [name_input])
	manage_account_panel.add_child(name_input)
	
	
	name_submit_btn = Button.new()
	name_submit_btn.text = "Set"
	name_submit_btn.anchor_left = 0.65
	name_submit_btn.anchor_right = 0.85
	name_submit_btn.margin_top = 510
	name_submit_btn.margin_bottom = 610
	if ref_font:
		var name_submit_font = ref_font.duplicate()
		name_submit_font.size = 45
		name_submit_font.outline_size = 3
		name_submit_font.outline_color = Color(0.08, 0.1, 0.15)
		name_submit_btn.add_font_override("font", name_submit_font)
		
	var set_normal = StyleBoxFlat.new()
	set_normal.bg_color = Color(0.15, 0.4, 0.75)
	set_normal.corner_radius_top_left = 20
	set_normal.corner_radius_top_right = 20
	set_normal.corner_radius_bottom_right = 20
	set_normal.corner_radius_bottom_left = 20
	set_normal.border_width_bottom = 6
	set_normal.border_color = Color(0.1, 0.3, 0.6)
	
	var set_hover = set_normal.duplicate()
	set_hover.bg_color = Color(0.2, 0.48, 0.85)
	set_hover.border_color = Color(0.12, 0.35, 0.65)
	
	var set_pressed = set_normal.duplicate()
	set_pressed.bg_color = Color(0.1, 0.3, 0.6)
	set_pressed.border_width_bottom = 2
	set_pressed.border_width_top = 4
	
	name_submit_btn.add_stylebox_override("normal", set_normal)
	name_submit_btn.add_stylebox_override("hover", set_hover)
	name_submit_btn.add_stylebox_override("pressed", set_pressed)
	name_submit_btn.add_color_override("font_color", Color(1, 1, 1))
	name_submit_btn.add_color_override("font_color_hover", Color(1, 1, 1))
	name_submit_btn.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	name_submit_btn.connect("pressed", self, "_on_name_submit_pressed")
	manage_account_panel.add_child(name_submit_btn)
	
	
	name_cancel_btn = Button.new()
	name_cancel_btn.text = "Cancel"
	name_cancel_btn.anchor_left = 0.65
	name_cancel_btn.anchor_right = 0.85
	name_cancel_btn.margin_top = 630
	name_cancel_btn.margin_bottom = 710
	name_cancel_btn.visible = false
	if ref_font:
		var name_cancel_font = ref_font.duplicate()
		name_cancel_font.size = 45
		name_cancel_font.outline_size = 3
		name_cancel_font.outline_color = Color(0.08, 0.1, 0.15)
		name_cancel_btn.add_font_override("font", name_cancel_font)
		
	var cancel_normal = StyleBoxFlat.new()
	cancel_normal.bg_color = Color(0.55, 0.2, 0.2)
	cancel_normal.corner_radius_top_left = 20
	cancel_normal.corner_radius_top_right = 20
	cancel_normal.corner_radius_bottom_right = 20
	cancel_normal.corner_radius_bottom_left = 20
	cancel_normal.border_width_bottom = 6
	cancel_normal.border_color = Color(0.4, 0.15, 0.15)
	
	var cancel_hover = cancel_normal.duplicate()
	cancel_hover.bg_color = Color(0.65, 0.25, 0.25)
	cancel_hover.border_color = Color(0.48, 0.18, 0.18)
	
	var cancel_pressed = cancel_normal.duplicate()
	cancel_pressed.bg_color = Color(0.4, 0.15, 0.15)
	cancel_pressed.border_width_bottom = 2
	cancel_pressed.border_width_top = 4
	
	name_cancel_btn.add_stylebox_override("normal", cancel_normal)
	name_cancel_btn.add_stylebox_override("hover", cancel_hover)
	name_cancel_btn.add_stylebox_override("pressed", cancel_pressed)
	name_cancel_btn.add_color_override("font_color", Color(1, 1, 1))
	name_cancel_btn.add_color_override("font_color_hover", Color(1, 1, 1))
	name_cancel_btn.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	name_cancel_btn.connect("pressed", self, "_on_name_cancel_pressed")
	manage_account_panel.add_child(name_cancel_btn)
	
	
	manage_name_hint = Label.new()
	manage_name_hint.align = Label.ALIGN_LEFT
	manage_name_hint.anchor_left = 0.15
	manage_name_hint.anchor_right = 0.6
	manage_name_hint.margin_right = 0
	manage_name_hint.margin_top = 630
	manage_name_hint.margin_bottom = 685
	if ref_font:
		var hint_font = ref_font.duplicate()
		hint_font.size = 30
		hint_font.outline_size = 0
		hint_font.outline_color = Color(0.08, 0.1, 0.15)
		manage_name_hint.add_font_override("font", hint_font)
	manage_account_panel.add_child(manage_name_hint)
		
	var btn_unlink = Button.new()
	btn_unlink.text = "Unlink Account"
	btn_unlink.anchor_left = 0.5
	btn_unlink.anchor_right = 0.5
	btn_unlink.margin_left = - 450
	btn_unlink.margin_right = 450
	btn_unlink.margin_top = 730
	btn_unlink.margin_bottom = 830
	btn_unlink.disabled = true
	if ref_font:
		var unlink_font = ref_font.duplicate()
		unlink_font.size = 45
		unlink_font.outline_size = 3
		unlink_font.outline_color = Color(0.2, 0.2, 0.25)
		btn_unlink.add_font_override("font", unlink_font)
	manage_account_panel.add_child(btn_unlink)
	
	var btn_logout = Button.new()
	btn_logout.text = "Logout"
	btn_logout.anchor_left = 0.5
	btn_logout.anchor_right = 0.5
	btn_logout.margin_left = - 450
	btn_logout.margin_right = 450
	btn_logout.margin_top = 870
	btn_logout.margin_bottom = 970
	btn_logout.connect("pressed", self, "_on_Logout_pressed")
	if ref_font:
		var logout_font = ref_font.duplicate()
		logout_font.size = 45
		logout_font.outline_size = 3
		logout_font.outline_color = Color(0.4, 0.1, 0.1)
		btn_logout.add_font_override("font", logout_font)
		
	var red_normal = StyleBoxFlat.new()
	red_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_normal.anti_aliasing = true
	red_normal.corner_radius_top_left = 20
	red_normal.corner_radius_top_right = 20
	red_normal.corner_radius_bottom_right = 20
	red_normal.corner_radius_bottom_left = 20
	red_normal.border_width_bottom = 8
	red_normal.border_color = Color(0.65, 0.2, 0.2)
	red_normal.shadow_color = Color(0.85, 0.3, 0.35, 0.15)
	red_normal.shadow_size = 6
	red_normal.shadow_offset = Vector2(0, 2)
	red_normal.content_margin_left = 30
	red_normal.content_margin_right = 30
	
	var red_hover = StyleBoxFlat.new()
	red_hover.bg_color = Color(0.85, 0.3, 0.35)
	red_hover.anti_aliasing = true
	red_hover.corner_radius_top_left = 20
	red_hover.corner_radius_top_right = 20
	red_hover.corner_radius_bottom_right = 20
	red_hover.corner_radius_bottom_left = 20
	red_hover.border_width_bottom = 8
	red_hover.border_color = Color(0.7, 0.25, 0.25)
	red_hover.shadow_color = Color(0.85, 0.3, 0.35, 0.2)
	red_hover.shadow_size = 8
	red_hover.shadow_offset = Vector2(0, 3)
	red_hover.content_margin_left = 30
	red_hover.content_margin_right = 30
	
	var red_pressed = StyleBoxFlat.new()
	red_pressed.bg_color = Color(0.7, 0.2, 0.25)
	red_pressed.anti_aliasing = true
	red_pressed.corner_radius_top_left = 20
	red_pressed.corner_radius_top_right = 20
	red_pressed.corner_radius_bottom_right = 20
	red_pressed.corner_radius_bottom_left = 20
	red_pressed.border_width_top = 4
	red_pressed.border_width_bottom = 4
	red_pressed.border_color = Color(0.55, 0.15, 0.18)
	red_pressed.shadow_color = Color(0, 0, 0, 0.15)
	red_pressed.shadow_size = 2
	red_pressed.shadow_offset = Vector2(0, 1)
	red_pressed.content_margin_left = 30
	red_pressed.content_margin_right = 30
	
	btn_logout.add_stylebox_override("normal", red_normal)
	btn_logout.add_stylebox_override("hover", red_hover)
	btn_logout.add_stylebox_override("pressed", red_pressed)
	btn_logout.add_color_override("font_color", Color(1, 1, 1))
	btn_logout.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_logout.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	manage_account_panel.add_child(btn_logout)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Back"
	btn_cancel.anchor_left = 0.5
	btn_cancel.anchor_right = 0.5
	btn_cancel.margin_left = - 450
	btn_cancel.margin_right = 450
	btn_cancel.margin_top = 1000
	btn_cancel.margin_bottom = 1100
	btn_cancel.connect("pressed", self, "_on_CancelManage_pressed")
	if ref_font:
		var cancel_font = ref_font.duplicate()
		cancel_font.size = 45
		cancel_font.outline_size = 3
		cancel_font.outline_color = Color(0.1, 0.35, 0.15)
		btn_cancel.add_font_override("font", cancel_font)
		
	var green_normal = StyleBoxFlat.new()
	green_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_normal.anti_aliasing = true
	green_normal.corner_radius_top_left = 20
	green_normal.corner_radius_top_right = 20
	green_normal.corner_radius_bottom_right = 20
	green_normal.corner_radius_bottom_left = 20
	green_normal.border_width_bottom = 8
	green_normal.border_color = Color(0.3, 0.65, 0.15)
	green_normal.shadow_color = Color(0.4, 0.8, 0.2, 0.15)
	green_normal.shadow_size = 6
	green_normal.shadow_offset = Vector2(0, 2)
	green_normal.content_margin_left = 30
	green_normal.content_margin_right = 30
	
	var green_hover = green_normal.duplicate()
	green_hover.bg_color = Color(0.45, 0.85, 0.25)
	green_hover.border_color = Color(0.32, 0.7, 0.18)
	
	var green_pressed = green_normal.duplicate()
	green_pressed.bg_color = Color(0.3, 0.65, 0.15)
	green_pressed.border_width_top = 4
	green_pressed.border_width_bottom = 4
		
	btn_cancel.add_stylebox_override("normal", green_normal)
	btn_cancel.add_stylebox_override("hover", green_hover)
	btn_cancel.add_stylebox_override("pressed", green_pressed)
	btn_cancel.add_color_override("font_color", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	manage_account_panel.add_child(btn_cancel)
	
	$UI / Control.add_child(manage_account_panel)

func _on_ManageAccount_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.hide()
	is_editing_name = false
	_update_manage_account_name_ui()
	manage_account_panel.visible = true

func _on_CancelManage_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	manage_account_panel.visible = false
	_update_profile_panel()
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.show()

func _on_Logout_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	
	Firebase.Auth.logout()
	FirebaseManager.is_logged_in = false
	FirebaseManager.user_id = ""
		
	
	player_data = {
		"player_name": "", 
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
	Global.player_name = ""
	Global.has_changed_name = false
	
	randomize()
	Global.player_name = "Player" + str(randi() % 900000 + 100000)
	
	var dir = Directory.new()
	if dir.file_exists("user://user.auth"):
		dir.remove("user://user.auth")
		
	save_hiscore(false)
	update_score_display()
	
	Firebase.Auth.login_anonymous()
	
	manage_account_panel.visible = false
	active_panel_name = ""
	_show_active_screen()

func _create_overwrite_confirm_panel():
	overwrite_confirm_panel = Panel.new()
	overwrite_confirm_panel.name = "OverwriteConfirmPanel"
	overwrite_confirm_panel.anchor_right = 1.0
	overwrite_confirm_panel.anchor_bottom = 1.0
	overwrite_confirm_panel.visible = false
	
	overwrite_confirm_panel.add_stylebox_override("panel", StyleBoxEmpty.new())
	_add_blur_background(overwrite_confirm_panel)
	
	var card = Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.margin_left = - 460
	card.margin_right = 460
	card.margin_top = - 340
	card.margin_bottom = 340
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.06, 0.09, 0.15, 1.0)
	card_style.corner_radius_top_left = 24
	card_style.corner_radius_top_right = 24
	card_style.corner_radius_bottom_right = 24
	card_style.corner_radius_bottom_left = 24
	card_style.corner_detail = 30
	card_style.anti_aliasing = true
	card_style.border_width_left = 4
	card_style.border_width_top = 4
	card_style.border_width_right = 4
	card_style.border_width_bottom = 4
	card_style.border_color = Color(0.18, 0.35, 0.55, 0.8)
	card.add_stylebox_override("panel", card_style)
	overwrite_confirm_panel.add_child(card)
	
	var title = Label.new()
	title.text = "⚠️ OVERWRITE PROFILE?"
	title.align = Label.ALIGN_CENTER
	title.anchor_right = 1.0
	title.margin_left = 40
	title.margin_right = - 40
	title.margin_top = 40
	title.margin_bottom = 130
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if title_font:
		title_font.size = 60
		title_font.outline_size = 3
		title_font.outline_color = Color(0.08, 0.1, 0.15)
		title.add_font_override("font", title_font)
	title.add_color_override("font_color", Color(1, 1, 1))
	card.add_child(title)
	
	var ow_divider = Panel.new()
	ow_divider.anchor_left = 0.1
	ow_divider.anchor_right = 0.9
	ow_divider.margin_top = 148
	ow_divider.margin_bottom = 151
	var ow_div_style = StyleBoxFlat.new()
	ow_div_style.bg_color = Color(0.18, 0.35, 0.55, 0.7)
	ow_divider.add_stylebox_override("panel", ow_div_style)
	card.add_child(ow_divider)
	
	var msg = Label.new()
	msg.text = "Permanently overwrite your profile?\nThis cannot be undone."
	msg.align = Label.ALIGN_CENTER
	msg.anchor_right = 1.0
	msg.margin_left = 40
	msg.margin_right = - 40
	msg.margin_top = 170
	msg.margin_bottom = 330
	var msg_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if msg_font:
		msg_font.size = 48
		msg_font.outline_size = 2
		msg_font.outline_color = Color(0.08, 0.1, 0.15)
		msg.add_font_override("font", msg_font)
	msg.add_color_override("font_color", Color(0.85, 0.88, 0.95))
	card.add_child(msg)
	
	var ref_btn = $UI / Control / ButtonTemplate
	var ref_font = ref_btn.get_font("font") if ref_btn else null
	
	var btn_confirm = Button.new()
	btn_confirm.text = "OVERWRITE"
	btn_confirm.anchor_left = 0.1
	btn_confirm.anchor_right = 0.9
	btn_confirm.margin_top = 400
	btn_confirm.margin_bottom = 500
	btn_confirm.connect("pressed", self, "_on_OverwriteConfirm_pressed")
	if ref_font:
		var confirm_font = ref_font.duplicate()
		confirm_font.size = 45
		confirm_font.outline_size = 3
		confirm_font.outline_color = Color(0.4, 0.1, 0.1)
		btn_confirm.add_font_override("font", confirm_font)
		
	var red_normal = StyleBoxFlat.new()
	red_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_normal.anti_aliasing = true
	red_normal.corner_radius_top_left = 20
	red_normal.corner_radius_top_right = 20
	red_normal.corner_radius_bottom_right = 20
	red_normal.corner_radius_bottom_left = 20
	red_normal.border_width_bottom = 8
	red_normal.border_color = Color(0.65, 0.2, 0.2)
	red_normal.content_margin_left = 30
	red_normal.content_margin_right = 30
	
	var red_hover = red_normal.duplicate()
	red_hover.bg_color = Color(0.85, 0.3, 0.35)
	red_hover.border_color = Color(0.7, 0.25, 0.25)
	
	var red_pressed = red_normal.duplicate()
	red_pressed.bg_color = Color(0.7, 0.2, 0.25)
	red_pressed.border_width_top = 4
	red_pressed.border_width_bottom = 4
	red_pressed.border_color = Color(0.55, 0.15, 0.18)
	
	btn_confirm.add_stylebox_override("normal", red_normal)
	btn_confirm.add_stylebox_override("hover", red_hover)
	btn_confirm.add_stylebox_override("pressed", red_pressed)
	btn_confirm.add_color_override("font_color", Color(1, 1, 1))
	btn_confirm.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_confirm.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	card.add_child(btn_confirm)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "CANCEL"
	btn_cancel.anchor_left = 0.1
	btn_cancel.anchor_right = 0.9
	btn_cancel.margin_top = 530
	btn_cancel.margin_bottom = 630
	btn_cancel.connect("pressed", self, "_on_OverwriteCancel_pressed")
	if ref_font:
		var green_font = ref_font.duplicate()
		green_font.size = 45
		green_font.outline_size = 3
		green_font.outline_color = Color(0.15, 0.4, 0.08)
		btn_cancel.add_font_override("font", green_font)
		
	var green_normal = StyleBoxFlat.new()
	green_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_normal.anti_aliasing = true
	green_normal.corner_radius_top_left = 20
	green_normal.corner_radius_top_right = 20
	green_normal.corner_radius_bottom_right = 20
	green_normal.corner_radius_bottom_left = 20
	green_normal.border_width_bottom = 8
	green_normal.border_color = Color(0.3, 0.6, 0.15)
	green_normal.content_margin_left = 30
	green_normal.content_margin_right = 30
	
	var green_hover = green_normal.duplicate()
	green_hover.bg_color = Color(0.45, 0.85, 0.25)
	green_hover.border_color = Color(0.35, 0.65, 0.18)
	
	var green_pressed = green_normal.duplicate()
	green_pressed.bg_color = Color(0.35, 0.7, 0.15)
	green_pressed.border_width_top = 4
	green_pressed.border_width_bottom = 4
	green_pressed.border_color = Color(0.25, 0.5, 0.1)
	
	btn_cancel.add_stylebox_override("normal", green_normal)
	btn_cancel.add_stylebox_override("hover", green_hover)
	btn_cancel.add_stylebox_override("pressed", green_pressed)
	btn_cancel.add_color_override("font_color", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	card.add_child(btn_cancel)
	
	$UI / Control.add_child(overwrite_confirm_panel)

func _on_ProfileCard_toggled(button_pressed, profile_type):
	if is_instance_valid(ui_button_click) and button_pressed:
		ui_button_click.play()
	if button_pressed:
		selected_profile_type = profile_type
		btn_keep_selected.disabled = false
		btn_keep_selected.modulate.a = 1.0
	else:
		if not card_device.pressed and not card_cloud.pressed:
			selected_profile_type = ""
			btn_keep_selected.disabled = true
			btn_keep_selected.modulate.a = 0.5

func _on_KeepSelected_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	if selected_profile_type != "":
		overwrite_confirm_panel.visible = true
		overwrite_confirm_panel.raise()

func _on_OverwriteCancel_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	overwrite_confirm_panel.visible = false

func _on_OverwriteConfirm_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	overwrite_confirm_panel.visible = false
	conflict_panel.visible = false
	_show_loading("Overwriting Data...")
	if selected_profile_type == "device":
		FirebaseManager.resolve_conflict_overwrite_cloud()
	elif selected_profile_type == "cloud":
		FirebaseManager.resolve_conflict_discard_guest()


func _on_token_refresh_done(success: bool):
	if is_instance_valid(loading_overlay) and loading_overlay.visible:
		_hide_loading()
		if not success:
			show_generic_error("Connection Failed", "Unable to connect to the game server. Please check your internet connection and try again.")
		else:
			_update_profile_panel()

func _on_Reconnect_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	_show_loading("Connecting to Server...")
	if OS.is_debug_build():
		print("[Debug Sync] Manual reconnection retry triggered.")
	FirebaseManager.retry_connection()

func _create_generic_error_panel():
	generic_error_panel = Panel.new()
	generic_error_panel.name = "GenericErrorPanel"
	generic_error_panel.visible = false
	generic_error_panel.anchor_right = 1.0
	generic_error_panel.anchor_bottom = 1.0
	
	generic_error_panel.add_stylebox_override("panel", StyleBoxEmpty.new())
	_add_blur_background(generic_error_panel)
	
	var card = Panel.new()
	card.name = "Card"
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.margin_left = - 460
	card.margin_top = - 340
	card.margin_right = 460
	card.margin_bottom = 340
	
	var err_panel_style = StyleBoxFlat.new()
	err_panel_style.bg_color = Color(0.06, 0.09, 0.15, 1.0)
	err_panel_style.corner_radius_top_left = 24
	err_panel_style.corner_radius_top_right = 24
	err_panel_style.corner_radius_bottom_right = 24
	err_panel_style.corner_radius_bottom_left = 24
	err_panel_style.corner_detail = 30
	err_panel_style.anti_aliasing = true
	err_panel_style.border_width_left = 4
	err_panel_style.border_width_top = 4
	err_panel_style.border_width_right = 4
	err_panel_style.border_width_bottom = 4
	err_panel_style.border_color = Color(0.18, 0.35, 0.55, 0.8)
	card.add_stylebox_override("panel", err_panel_style)
	generic_error_panel.add_child(card)
	
	$UI / Control.add_child(generic_error_panel)
	
	var err_title = Label.new()
	err_title.name = "TitleLabel"
	err_title.text = "Error"
	err_title.anchor_right = 1.0
	err_title.margin_top = 40
	err_title.margin_bottom = 130
	err_title.align = Label.ALIGN_CENTER
	err_title.valign = Label.VALIGN_CENTER
	err_title.add_color_override("font_color", Color(1.0, 0.3, 0.3))
	var err_title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if err_title_font:
		err_title_font.size = 60
		err_title_font.outline_size = 3
		err_title_font.outline_color = Color(0.08, 0.1, 0.15)
		err_title.add_font_override("font", err_title_font)
	card.add_child(err_title)
	
	var err_divider = Panel.new()
	err_divider.name = "Divider"
	err_divider.anchor_left = 0.1
	err_divider.anchor_right = 0.9
	err_divider.margin_top = 148
	err_divider.margin_bottom = 151
	var err_div_style = StyleBoxFlat.new()
	err_div_style.bg_color = Color(0.18, 0.35, 0.55, 0.7)
	err_divider.add_stylebox_override("panel", err_div_style)
	card.add_child(err_divider)

	var err_msg = Label.new()
	err_msg.name = "MessageLabel"
	err_msg.text = ""
	err_msg.autowrap = true
	err_msg.align = Label.ALIGN_CENTER
	err_msg.valign = Label.VALIGN_CENTER
	err_msg.anchor_left = 0.05
	err_msg.anchor_right = 0.95
	err_msg.margin_top = 175
	err_msg.margin_bottom = 510
	var msg_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if msg_font:
		msg_font.size = 48
		msg_font.outline_size = 2
		msg_font.outline_color = Color(0.08, 0.1, 0.15)
		err_msg.add_font_override("font", msg_font)
	err_msg.add_color_override("font_color", Color(0.85, 0.88, 0.95))
	card.add_child(err_msg)
	
	var ref_btn = $UI / Control / ButtonTemplate
	var ref_font = ref_btn.get_font("font") if ref_btn else null
	
	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.anchor_left = 0.5
	ok_btn.anchor_top = 1.0
	ok_btn.anchor_right = 0.5
	ok_btn.anchor_bottom = 1.0
	ok_btn.margin_left = - 200
	ok_btn.margin_top = - 140
	ok_btn.margin_right = 200
	ok_btn.margin_bottom = - 40
	ok_btn.connect("pressed", self, "_on_CloseGenericError_pressed")
	
	if ref_font:
		var ok_font = ref_font.duplicate()
		ok_font.size = 45
		ok_font.outline_size = 3
		ok_font.outline_color = Color(0.15, 0.4, 0.08)
		ok_btn.add_font_override("font", ok_font)
	else:
		var ok_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
		if ok_font:
			ok_font.size = 45
			ok_font.outline_size = 3
			ok_font.outline_color = Color(0.15, 0.4, 0.08)
			ok_btn.add_font_override("font", ok_font)
			
	var ok_style = StyleBoxFlat.new()
	ok_style.bg_color = Color(0.4, 0.8, 0.2)
	ok_style.corner_radius_top_left = 20
	ok_style.corner_radius_top_right = 20
	ok_style.corner_radius_bottom_right = 20
	ok_style.corner_radius_bottom_left = 20
	ok_style.border_width_bottom = 8
	ok_style.border_color = Color(0.3, 0.6, 0.15)
	ok_style.content_margin_left = 30
	ok_style.content_margin_right = 30
	
	var ok_hover = ok_style.duplicate()
	ok_hover.bg_color = Color(0.45, 0.85, 0.25)
	ok_hover.border_color = Color(0.35, 0.65, 0.18)
	
	var ok_pressed = ok_style.duplicate()
	ok_pressed.bg_color = Color(0.35, 0.7, 0.15)
	ok_pressed.border_width_top = 4
	ok_pressed.border_width_bottom = 4
	ok_pressed.border_color = Color(0.25, 0.5, 0.12)
	
	ok_btn.add_stylebox_override("normal", ok_style)
	ok_btn.add_stylebox_override("hover", ok_hover)
	ok_btn.add_stylebox_override("pressed", ok_pressed)
	ok_btn.add_color_override("font_color", Color(1, 1, 1))
	ok_btn.add_color_override("font_color_hover", Color(1, 1, 1))
	ok_btn.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	card.add_child(ok_btn)

func show_generic_error(title: String, message: String):
	if not is_instance_valid(generic_error_panel):
		_create_generic_error_panel()
	
	var title_lbl = generic_error_panel.get_node("Card/TitleLabel")
	var is_success = false
	if title_lbl:
		title_lbl.text = title
		var title_lower = title.to_lower()
		is_success = ("success" in title_lower or "sent" in title_lower or "completed" in title_lower or "reset" in title_lower) and not ("failed" in title_lower or "error" in title_lower or "fail" in title_lower)
		if is_success:
			title_lbl.add_color_override("font_color", Color(0.4, 0.8, 0.2))
		else:
			title_lbl.add_color_override("font_color", Color(1.0, 0.3, 0.3))
			
		var font = title_lbl.get_font("font")
		if font is DynamicFont:
			var new_font = font.duplicate()
			new_font.outline_color = Color(0.08, 0.1, 0.15)
			title_lbl.add_font_override("font", new_font)
				
		# Keep unified border and divider colors.
		pass
	
	if not is_success:
		if is_instance_valid(error_sound):
			error_sound.play()
	
	var msg_lbl = generic_error_panel.get_node("Card/MessageLabel")
	if msg_lbl:
		msg_lbl.text = message
		
	generic_error_panel.show()
	generic_error_panel.raise()

func _on_CloseGenericError_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	if is_instance_valid(generic_error_panel):
		generic_error_panel.hide()

func _on_score_sync_finished(success: bool):
	player_data["pending_score_sync"] = not success
	save_hiscore(false)
	
	
	var profile_panel_node = $UI / Control.get_node_or_null("ProfilePanel")
	if profile_panel_node and profile_panel_node.visible:
		_update_profile_panel()

func check_and_sync_pending_data():
	if not FirebaseManager.is_logged_in:
		return
	var stats_pending = player_data.get("pending_stats_sync", false)
	var score_pending = player_data.get("pending_score_sync", false)
	if OS.is_debug_build() and (stats_pending or score_pending):
		print("[Debug Sync] Syncing pending data: stats = ", stats_pending, ", score = ", score_pending)
	if stats_pending:
		FirebaseManager.submit_stats(player_data)
	if score_pending:
		var escalation_hs = get_highscore(1)
		if escalation_hs > 0:
			FirebaseManager.submit_score(escalation_hs, 1, Global.player_name, get_highest_level(1))


func _create_circle_texture(size: int) -> ImageTexture:
	var img = Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()
	var center = (size - 1) / 2.0
	var radius = size / 2.0
	for y in range(size):
		for x in range(size):
			var dx = x - center
			var dy = y - center
			var dist = sqrt(dx*dx + dy*dy)
			if dist <= radius - 1.5:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
			elif dist < radius:
				var alpha = clamp((radius - dist) / 1.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, alpha))
			else:
				img.set_pixel(x, y, Color(1, 1, 1, 0))
	img.unlock()
	var tex = ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	return tex
