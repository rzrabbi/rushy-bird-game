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
	"has_changed_name_logged_in": false
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

func get_local_datetime_string(timestamp: int) -> String:
	var local_offset = get_local_timezone_offset()
	var local_time = OS.get_datetime_from_unix_time(timestamp + local_offset)
	return "%02d-%02d-%04d %02d:%02d:%02d" % [local_time.day, local_time.month, local_time.year, local_time.hour, local_time.minute, local_time.second]

func get_local_datetime_short_string(timestamp: int) -> String:
	var local_offset = get_local_timezone_offset()
	var local_time = OS.get_datetime_from_unix_time(timestamp + local_offset)
	return "%02d-%02d-%04d %02d:%02d" % [local_time.day, local_time.month, local_time.year, local_time.hour, local_time.minute]
var game_playing = false
var is_game_over_active: bool = false
var mode_level = 0 # 0: Classic, 1: Escalation
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
var start_label: Label
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
var active_panel_name: String = "" # Tracks which panel is open: "", "leaderboard", "profile", "settings"


var music_volume: float = 1.0
var sfx_enabled: bool = true
var cheats_used: bool = false

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

var loading_overlay: Panel
var loading_spinner_icon: Control

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
		[$UI/Control/SpeedLabel, "LEVEL UP!CLASSIC MODE classic rules pure skill Escalation It gets faster Good luck"],
		[$UI/Control/MenuInfoLabel, "-1 HEALTH! YOUR BEST: (Lvl 1) Classic"],
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
	$UI/Control/ProfileButton.connect("pressed", self, "_on_ProfileButton_pressed")
	$UI/Control/ProfileButton.connect("button_down", self, "_on_CircleButton_down", [$UI/Control/ProfileButton])
	$UI/Control/ProfileButton.connect("button_up", self, "_on_CircleButton_up", [$UI/Control/ProfileButton])
	$UI/Control/RestartButton.connect("pressed", self, "_on_Button2_pressed")
	$UI/Control/RestartButton.connect("button_down", self, "_on_CircleButton_down", [$UI/Control/RestartButton])
	$UI/Control/RestartButton.connect("button_up", self, "_on_CircleButton_up", [$UI/Control/RestartButton])
	$UI/Control/MainMenuButton.connect("pressed", self, "_on_Button3_pressed")
	$UI/Control/MainMenuButton.connect("button_down", self, "_on_CircleButton_down", [$UI/Control/MainMenuButton])
	$UI/Control/MainMenuButton.connect("button_up", self, "_on_CircleButton_up", [$UI/Control/MainMenuButton])
	
	$UI/Control/SettingsButton.connect("pressed", self, "_on_SettingsButton_pressed")
	$UI/Control/SettingsButton.connect("button_down", self, "_on_CircleButton_down", [$UI/Control/SettingsButton])
	$UI/Control/SettingsButton.connect("button_up", self, "_on_CircleButton_up", [$UI/Control/SettingsButton])
	
	$UI/Control/LeaderboardPanel/CloseLeaderboard.connect("pressed", self, "_on_CloseLeaderboard_pressed")
	$UI/Control/SettingsPanel/CloseSettings.connect("pressed", self, "_on_CloseSettings_pressed")
	$UI/Control/SettingsPanel/ResetButton.connect("pressed", self, "_on_RequestReset_pressed")
	$UI/Control/SettingsPanel/ConfirmPanel/YesButton.connect("pressed", self, "_on_ConfirmReset_Yes")
	$UI/Control/SettingsPanel/ConfirmPanel/NoButton.connect("pressed", self, "_on_ConfirmReset_No")
	FirebaseManager.connect("stats_sync_finished", self, "_on_stats_sync_finished")
	FirebaseManager.connect("auth_state_changed", self, "_on_auth_state_changed")
	FirebaseManager.connect("profile_claim_succeeded", self, "_on_profile_claim_succeeded")
	FirebaseManager.connect("profile_claim_failed", self, "_on_profile_claim_failed")
	FirebaseManager.connect("profile_claim_conflict", self, "_on_profile_claim_conflict")
	
	_create_claim_profile_panel()
	_create_loading_overlay()
	_create_manage_account_panel()
	_create_conflict_panel()
	_create_overwrite_confirm_panel()
	var music_slider = CustomSlider.new(music_volume, 700.0)
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
		for _i in range(max_health):
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
	profile_button = $UI/Control/ProfileButton
	bottom_bar = $UI/Control/BottomBar
	version_label = null # moved to SettingsPanel
	
	game_over_bottom_bar = $UI/Control.get_node_or_null("GameOverBottomBar")
	game_over_leaderboard_button = $UI/Control.get_node_or_null("GameOverLeaderboardButton")
	game_over_profile_button = $UI/Control.get_node_or_null("GameOverProfileButton")
	game_over_settings_button = $UI/Control.get_node_or_null("GameOverSettingsButton")
	
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
	version_label = null # moved to SettingsPanel
	
	_setup_firebase_ui()

	var profile_panel_node = Panel.new()
	profile_panel_node.name = "ProfilePanel"
	profile_panel_node.visible = false
	profile_panel_node.anchor_left = 0.5
	profile_panel_node.anchor_top = 0.5
	profile_panel_node.anchor_right = 0.5
	profile_panel_node.anchor_bottom = 0.5
	profile_panel_node.margin_left = -525
	profile_panel_node.margin_top = -840
	profile_panel_node.margin_right = 525
	profile_panel_node.margin_bottom = 520
	$UI/Control.add_child(profile_panel_node)
	
	var profile_title = Label.new()
	profile_title.text = "Player Profile"
	profile_title.anchor_right = 1.0
	profile_title.margin_top = 30
	profile_title.margin_bottom = 90
	profile_title.align = Label.ALIGN_CENTER
	profile_title.valign = Label.VALIGN_CENTER
	var title_font = $UI/Control/LeaderboardPanel/Title.get_font("font")
	if title_font: profile_title.add_font_override("font", title_font)
	profile_panel_node.add_child(profile_title)
	
	var profile_divider = Panel.new()
	profile_divider.name = "Divider"
	profile_divider.anchor_left = 0.1
	profile_divider.anchor_right = 0.9
	profile_divider.margin_top = 110
	profile_divider.margin_bottom = 113
	var ref_div = $UI/Control/LeaderboardPanel/Divider
	if ref_div:
		var div_style = ref_div.get_stylebox("panel")
		if div_style:
			profile_divider.add_stylebox_override("panel", div_style)
	profile_panel_node.add_child(profile_divider)
	
	var profile_vbox = VBoxContainer.new()
	profile_vbox.name = "VBox"
	profile_vbox.anchor_right = 1.0
	profile_vbox.anchor_bottom = 1.0
	profile_vbox.margin_left = 50
	profile_vbox.margin_right = -50
	profile_vbox.margin_top = 140
	profile_vbox.margin_bottom = -470
	profile_vbox.add_constant_override("separation", 15)
	profile_panel_node.add_child(profile_vbox)
	
	var close_profile = Button.new()
	close_profile.text = "Close"
	close_profile.anchor_left = 0.5
	close_profile.anchor_top = 1.0
	close_profile.anchor_right = 0.5
	close_profile.anchor_bottom = 1.0
	close_profile.margin_left = -140
	close_profile.margin_top = -120
	close_profile.margin_right = 140
	close_profile.margin_bottom = -30
	close_profile.connect("pressed", self, "_on_CloseProfile_pressed")
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	if ref_btn:
		var close_font = $UI/Control/LeaderboardPanel/CloseLeaderboard.get_font("font")
		if close_font:
			close_profile.add_font_override("font", close_font)
		else:
			var ref_font = ref_btn.get_font("font")
			if ref_font:
				close_profile.add_font_override("font", ref_font)
		
		var style_hover = ref_btn.get_stylebox("hover")
		if style_hover:
			close_profile.add_stylebox_override("hover", style_hover)
		
		var style_pressed = ref_btn.get_stylebox("pressed")
		if style_pressed:
			close_profile.add_stylebox_override("pressed", style_pressed)
			
		var style_normal = ref_btn.get_stylebox("normal")
		if style_normal:
			close_profile.add_stylebox_override("normal", style_normal)
			
	profile_panel_node.add_child(close_profile)

	profile_disclaimer = RichTextLabel.new()
	profile_disclaimer.bbcode_enabled = true
	profile_disclaimer.scroll_active = false
	profile_disclaimer.anchor_left = 0.0
	profile_disclaimer.anchor_top = 1.0
	profile_disclaimer.anchor_right = 1.0
	profile_disclaimer.anchor_bottom = 1.0
	profile_disclaimer.margin_left = 20
	profile_disclaimer.margin_right = -20
	profile_disclaimer.margin_top = -450
	profile_disclaimer.margin_bottom = -260
	
	var desc_font = DynamicFont.new()
	desc_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	desc_font.size = 30
	desc_font.outline_size = 2
	desc_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	profile_disclaimer.add_font_override("normal_font", desc_font)
	profile_disclaimer.add_color_override("default_color", Color(0.7, 0.7, 0.7, 0.8))
	profile_panel_node.add_child(profile_disclaimer)

	btn_claim_profile = Button.new()
	btn_claim_profile.text = "Link Account to Save Progress"
	btn_claim_profile.anchor_left = 0.5
	btn_claim_profile.anchor_top = 1.0
	btn_claim_profile.anchor_right = 0.5
	btn_claim_profile.anchor_bottom = 1.0
	btn_claim_profile.margin_left = -400
	btn_claim_profile.margin_top = -240
	btn_claim_profile.margin_right = 400
	btn_claim_profile.margin_bottom = -140
	btn_claim_profile.connect("pressed", self, "_on_ClaimProfile_pressed")
	
	if ref_btn:
		var close_font = $UI/Control/LeaderboardPanel/CloseLeaderboard.get_font("font")
		var ref_font = close_font if close_font else ref_btn.get_font("font")
		if ref_font:
			var green_font = ref_font.duplicate()
			green_font.outline_color = Color(0.2, 0.5, 0.1)
			if green_font is DynamicFont:
				green_font.size = 45
			btn_claim_profile.add_font_override("font", green_font)
			
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
	btn_manage_account.margin_left = -400
	btn_manage_account.margin_top = -240
	btn_manage_account.margin_right = 400
	btn_manage_account.margin_bottom = -140
	btn_manage_account.connect("pressed", self, "_on_ManageAccount_pressed")
	
	if ref_btn:
		var close_font = $UI/Control/LeaderboardPanel/CloseLeaderboard.get_font("font")
		var ref_font = close_font if close_font else ref_btn.get_font("font")
		if ref_font:
			var green_font = ref_font.duplicate()
			green_font.outline_color = Color(0.2, 0.5, 0.1) # Green outline matching Start button
			if green_font is DynamicFont:
				green_font.size = 45
			btn_manage_account.add_font_override("font", green_font)
			
	btn_manage_account.add_stylebox_override("normal", green_normal)
	btn_manage_account.add_stylebox_override("hover", green_hover)
	btn_manage_account.add_stylebox_override("pressed", green_pressed)
	btn_manage_account.add_color_override("font_color", Color(1, 1, 1))
	btn_manage_account.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_manage_account.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
			
	profile_panel_node.add_child(btn_manage_account)

	inspector_panel_node = Panel.new()
	inspector_panel_node.name = "InspectorPanel"
	inspector_panel_node.visible = false
	inspector_panel_node.anchor_left = 0.5
	inspector_panel_node.anchor_top = 0.5
	inspector_panel_node.anchor_right = 0.5
	inspector_panel_node.anchor_bottom = 0.5
	inspector_panel_node.margin_left = -525
	inspector_panel_node.margin_top = -840
	inspector_panel_node.margin_right = 525
	inspector_panel_node.margin_bottom = 520
	
	if has_node("UI/Control/SettingsPanel/ConfirmPanel"):
		var warning_style = $UI/Control/SettingsPanel/ConfirmPanel.get_stylebox("panel")
		if warning_style:
			inspector_panel_node.add_stylebox_override("panel", warning_style)
	$UI/Control.add_child(inspector_panel_node)
	
	var inspector_title = Label.new()
	inspector_title.name = "Title"
	inspector_title.text = "Player Profile"
	inspector_title.anchor_left = 0.0
	inspector_title.anchor_right = 1.0
	inspector_title.margin_left = 40
	inspector_title.margin_top = 30
	inspector_title.margin_right = -40
	inspector_title.margin_bottom = 100
	inspector_title.align = Label.ALIGN_CENTER
	inspector_title.valign = Label.VALIGN_CENTER
	inspector_title.autowrap = true
	if title_font:
		inspector_title.add_font_override("font", title_font)
	inspector_panel_node.add_child(inspector_title)
	
	var inspector_divider = Panel.new()
	inspector_divider.anchor_left = 0.1
	inspector_divider.anchor_right = 0.9
	inspector_divider.margin_top = 118
	inspector_divider.margin_bottom = 121
	var insp_div_style = StyleBoxFlat.new()
	insp_div_style.bg_color = Color(0.25, 0.3, 0.45, 0.7)
	inspector_divider.add_stylebox_override("panel", insp_div_style)
	inspector_panel_node.add_child(inspector_divider)
	
	inspector_vbox = VBoxContainer.new()
	inspector_vbox.name = "VBox"
	inspector_vbox.anchor_right = 1.0
	inspector_vbox.anchor_bottom = 1.0
	inspector_vbox.margin_left = 50
	inspector_vbox.margin_right = -50
	inspector_vbox.margin_top = 145
	inspector_vbox.margin_bottom = -470
	inspector_vbox.add_constant_override("separation", 15)
	inspector_panel_node.add_child(inspector_vbox)
	
	var close_inspector = Button.new()
	close_inspector.text = "Close"
	close_inspector.anchor_left = 0.5
	close_inspector.anchor_top = 1.0
	close_inspector.anchor_right = 0.5
	close_inspector.anchor_bottom = 1.0
	close_inspector.margin_left = -140
	close_inspector.margin_top = -120
	close_inspector.margin_right = 140
	close_inspector.margin_bottom = -30
	close_inspector.connect("pressed", self, "_on_CloseInspector_pressed")
	
	if ref_btn:
		var r_font = ref_btn.get_font("font")
		if r_font: close_inspector.add_font_override("font", r_font)
		var s_hover = ref_btn.get_stylebox("hover")
		if s_hover: close_inspector.add_stylebox_override("hover", s_hover)
		var s_pressed = ref_btn.get_stylebox("pressed")
		if s_pressed: close_inspector.add_stylebox_override("pressed", s_pressed)
		var s_normal = ref_btn.get_stylebox("normal")
		if s_normal: close_inspector.add_stylebox_override("normal", s_normal)
	inspector_panel_node.add_child(close_inspector)
	
	inspector_disclaimer = RichTextLabel.new()
	inspector_disclaimer.bbcode_enabled = true
	inspector_disclaimer.scroll_active = false
	inspector_disclaimer.anchor_left = 0.0
	inspector_disclaimer.anchor_top = 1.0
	inspector_disclaimer.anchor_right = 1.0
	inspector_disclaimer.anchor_bottom = 1.0
	inspector_disclaimer.margin_left = 20
	inspector_disclaimer.margin_right = -20
	inspector_disclaimer.margin_top = -450
	inspector_disclaimer.margin_bottom = -260
	if desc_font:
		inspector_disclaimer.add_font_override("normal_font", desc_font)
	inspector_disclaimer.add_color_override("default_color", Color(0.7, 0.7, 0.7, 0.8))
	inspector_panel_node.add_child(inspector_disclaimer)

	if OS.is_debug_build():
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
	err_panel.margin_left = -400
	err_panel.margin_top = -320
	err_panel.margin_right = 400
	err_panel.margin_bottom = 320
	
	var err_panel_style = StyleBoxFlat.new()
	err_panel_style.bg_color = Color(0.08, 0.1, 0.16, 0.97)
	err_panel_style.corner_radius_top_left = 24
	err_panel_style.corner_radius_top_right = 24
	err_panel_style.corner_radius_bottom_right = 24
	err_panel_style.corner_radius_bottom_left = 24
	err_panel_style.border_width_left = 4
	err_panel_style.border_width_top = 4
	err_panel_style.border_width_right = 4
	err_panel_style.border_width_bottom = 4
	err_panel_style.border_color = Color(0.6, 0.2, 0.2, 0.8)
	err_panel.add_stylebox_override("panel", err_panel_style)
			
	$UI/Control.add_child(err_panel)
	
	var err_title = Label.new()
	err_title.text = "Storage Error"
	err_title.anchor_right = 1.0
	err_title.margin_top = 40
	err_title.margin_bottom = 130
	err_title.align = Label.ALIGN_CENTER
	err_title.valign = Label.VALIGN_CENTER
	err_title.add_color_override("font_color", Color(1.0, 0.3, 0.3))
	var err_title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if err_title_font:
		err_title_font.size = 65
		err_title_font.outline_size = 4
		err_title_font.outline_color = Color(0.3, 0.08, 0.08)
		err_title.add_font_override("font", err_title_font)
	err_panel.add_child(err_title)
	
	var err_divider = Panel.new()
	err_divider.anchor_left = 0.1
	err_divider.anchor_right = 0.9
	err_divider.margin_top = 148
	err_divider.margin_bottom = 151
	var err_div_style = StyleBoxFlat.new()
	err_div_style.bg_color = Color(0.5, 0.2, 0.2, 0.7)
	err_divider.add_stylebox_override("panel", err_div_style)
	err_panel.add_child(err_divider)

	var err_msg = Label.new()
	err_msg.name = "MessageLabel"
	err_msg.text = ""
	err_msg.autowrap = true
	err_msg.align = Label.ALIGN_CENTER
	err_msg.valign = Label.VALIGN_CENTER
	err_msg.anchor_left = 0.05
	err_msg.anchor_right = 0.95
	err_msg.margin_top = 175
	err_msg.margin_bottom = 450
	var msg_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if msg_font:
		msg_font.size = 50
		msg_font.outline_size = 3
		msg_font.outline_color = Color(0.08, 0.1, 0.15)
		err_msg.add_font_override("font", msg_font)
	err_panel.add_child(err_msg)
	
	var ok_btn = Button.new()
	ok_btn.text = "OK"
	ok_btn.anchor_left = 0.5
	ok_btn.anchor_top = 1.0
	ok_btn.anchor_right = 0.5
	ok_btn.anchor_bottom = 1.0
	ok_btn.margin_left = -200
	ok_btn.margin_top = -130
	ok_btn.margin_right = 200
	ok_btn.margin_bottom = -30
	ok_btn.connect("pressed", self, "_on_CloseStorageError_pressed")
	var ok_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if ok_font:
		ok_font.size = 45
		ok_font.outline_size = 3
		ok_font.outline_color = Color(0.08, 0.1, 0.15)
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
	ok_btn.add_stylebox_override("normal", ok_style)
	ok_btn.add_color_override("font_color", Color(1, 1, 1))
	err_panel.add_child(ok_btn)

	update_mode_button_text()
	update_score_display()
	
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
		"has_changed_name": Global.has_changed_name,
		"last_sync_timestamp": last_sync_timestamp
	}
	file.store_var(data)
	file.close()
	
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
			
		if content.has("has_changed_name"):
			Global.has_changed_name = content.get("has_changed_name")
			
		if content.has("last_sync_timestamp"):
			last_sync_timestamp = content.get("last_sync_timestamp")
			
		if player_data.has("player_name"):
			Global.player_name = player_data["player_name"]
	
	file.close()

func _process(delta):
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
	if mode_level == 0: return "Classic"
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
		var end_pos = start_pos + Vector2(-40, 60) # Drift down and left like it's falling away
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
		
		progression_pause_timer = 2.5 / max(game_speed, 1.0) # Pause progression until pipes arrive
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
	$UI/Control/Score.text = String(score)
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
		$UI/Control/Score.modulate = Color(1.0, 1.0, 1.0)
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

	$UI/Control/PlayButton.hide()
	if start_label: start_label.hide()
	$UI/Control/ModeButton.hide()
	$UI/Control/LeaderboardButton.hide()
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
		$UI/Control/RestartButton.hide()
		$UI/Control/MainMenuButton.hide()
		# Keep bottom bar and its nav buttons visible when a panel opens on game over screen
		if is_instance_valid(logo_rect): logo_rect.hide()
	else:
		# Always hide home content (Start, Mode, Logo, BestScore) when any panel opens
		$UI/Control/PlayButton.hide()
		if start_label: start_label.hide()
		$UI/Control/ModeButton.hide()
		if menu_info_label: menu_info_label.hide()
		if version_label: version_label.hide()
		if is_instance_valid(logo_rect): logo_rect.hide()
		# Keep bottom_bar, LeaderboardButton, ProfileButton, SettingsButton visible

# Closes whichever panel is currently open WITHOUT touching home/game-over screen content.
# Call this before opening a different panel (panel switching).
func _close_active_panel_only():
	if active_panel_name == "leaderboard":
		if leaderboard_panel: leaderboard_panel.hide()
	elif active_panel_name == "profile":
		var p = $UI/Control.get_node_or_null("ProfilePanel")
		if p: p.hide()
	elif active_panel_name == "settings":
		if settings_panel: settings_panel.hide()
	if inspector_panel_node:
		inspector_panel_node.hide()
	active_panel_name = ""

func _show_active_screen():
	if is_game_over_active:
		if game_over_panel: game_over_panel.show()
		$UI/Control/RestartButton.show()
		$UI/Control/MainMenuButton.show()
		if is_instance_valid(game_over_bottom_bar): game_over_bottom_bar.show()
		if is_instance_valid(game_over_leaderboard_button): game_over_leaderboard_button.show()
		if is_instance_valid(game_over_profile_button): game_over_profile_button.show()
		if is_instance_valid(game_over_settings_button): game_over_settings_button.show()
		if is_instance_valid(logo_rect): logo_rect.show()
		if version_label: version_label.show()
	else:
		$UI/Control/PlayButton.show()
		if start_label: start_label.show()
		$UI/Control/ModeButton.show()
		$UI/Control/LeaderboardButton.show()
		if profile_button: profile_button.show()
		if is_instance_valid(settings_button): settings_button.show()
		if menu_info_label: menu_info_label.show()
		if version_label: version_label.show()
		if bottom_bar: bottom_bar.show()
		if is_instance_valid(logo_rect): logo_rect.show()

func _on_LeaderboardButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	# Toggle: tapping the same button again closes the panel and restores home screen
	if active_panel_name == "leaderboard":
		if inspector_panel_node and inspector_panel_node.visible:
			inspector_panel_node.hide()
			leaderboard_panel.show()
			return
		active_panel_name = ""
		leaderboard_panel.hide()
		_show_active_screen()
		return
	
	# Switching from another open panel — close it without restoring home screen first
	var was_panel_open = active_panel_name != ""
	_close_active_panel_only()
	
	# Only hide home/game-over screen content when opening for the first time
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
	var base_font = $UI/Control/MenuInfoLabel.get_font("font")
	
	if vbox == seasonal_vbox:
		var timer_label = Label.new()
		timer_label.text = _get_seasonal_reset_time_string()
		timer_label.align = Label.ALIGN_CENTER
		if base_font:
			var timer_font = base_font.duplicate()
			timer_font.size = 28
			timer_label.add_font_override("font", timer_font)
		timer_label.add_color_override("font_color", Color(0.9, 0.8, 0.4)) # Soft gold
		vbox.add_child(timer_label)
		
		var sep = Control.new()
		sep.rect_min_size = Vector2(0, 15)
		vbox.add_child(sep)
	if data == null:
		var offline = Label.new()
		offline.text = "Offline Mode.\nLeaderboard is disabled."
		offline.align = Label.ALIGN_CENTER
		if base_font: offline.add_font_override("font", base_font)
		vbox.add_child(offline)
		return
		
	if data.empty():
		var empty = Label.new()
		empty.text = "No scores yet!"
		empty.align = Label.ALIGN_CENTER
		if base_font: empty.add_font_override("font", base_font)
		vbox.add_child(empty)
		return
		
	var rank = 1
	for entry in data:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_constant_override("separation", 0)
		
		var rank_lbl = Label.new()
		rank_lbl.text = "#" + str(rank)
		rank_lbl.rect_min_size = Vector2(120, 0)
		rank_lbl.align = Label.ALIGN_CENTER
		if base_font: rank_lbl.add_font_override("font", base_font)
		
		var name_container = HBoxContainer.new()
		name_container.rect_min_size = Vector2(560, 0)
		name_container.alignment = BoxContainer.ALIGN_CENTER
		
		var name_btn = LinkButton.new()
		var p_name = entry.get("player_name", "Unknown")
		if p_name.length() > 20:
			p_name = p_name.substr(0, 17) + "..."
		name_btn.text = p_name
		name_btn.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		if base_font: name_btn.add_font_override("font", base_font)
		
		var uid = entry.get("uid", "")
		var is_current_user = (uid != "" and uid == FirebaseManager.get_current_user_id())
		if uid != "":
			name_btn.connect("pressed", self, "_on_leaderboard_player_clicked", [uid, entry.get("player_name", "Unknown")])
		
		name_container.add_child(name_btn)
		
		if bool(entry.get("is_registered", false)):
			var check_spacer = Control.new()
			check_spacer.rect_min_size = Vector2(8, 0)
			name_container.add_child(check_spacer)
			
			var check_icon = preload("res://addons/FontAwesome5/FontAwesome.gd").new()
			check_icon.icon_type = "solid"
			check_icon.icon_name = "check"
			if base_font:
				check_icon.icon_size = int(base_font.size * 0.65)
			else:
				check_icon.icon_size = 18
			check_icon.valign = Label.VALIGN_CENTER
			check_icon.add_color_override("font_color", Color(0.22, 0.79, 0.45)) # Modern emerald green
			name_container.add_child(check_icon)
		
		var score_lbl = Label.new()
		score_lbl.text = str(entry.get("score", 0))
		score_lbl.align = Label.ALIGN_CENTER
		score_lbl.rect_min_size = Vector2(160, 0)
		if base_font: score_lbl.add_font_override("font", base_font)
		
		var lvl_lbl = Label.new()
		var level_val = entry.get("level")
		if level_val != null:
			lvl_lbl.text = str(level_val)
		else:
			lvl_lbl.text = "-"
		lvl_lbl.align = Label.ALIGN_CENTER
		lvl_lbl.rect_min_size = Vector2(120, 0)
		if base_font: lvl_lbl.add_font_override("font", base_font)
		
		var left_spacer = Control.new()
		left_spacer.rect_min_size = Vector2(20, 0)
		row.add_child(left_spacer)
		
		row.add_child(rank_lbl)
		row.add_child(name_container)
		row.add_child(score_lbl)
		row.add_child(lvl_lbl)
		
		var row_margin = MarginContainer.new()
		row_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_margin.add_constant_override("margin_left", 0)
		row_margin.add_constant_override("margin_right", 0)
		
		if is_current_user:
			# Highlight self
			var highlight = PanelContainer.new()
			highlight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var highlight_style = StyleBoxFlat.new()
			highlight_style.bg_color = Color(0.4, 0.8, 0.2, 0.15) # Translucent green
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
			
		# Gap between entries
		var item_spacer = Control.new()
		item_spacer.rect_min_size = Vector2(0, 12)
		vbox.add_child(item_spacer)
		
		rank += 1

func _on_CloseLeaderboard_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	active_panel_name = ""
	leaderboard_panel.hide()
	_show_active_screen()

func _on_SettingsButton_down():
	settings_button.rect_scale = Vector2(0.85, 0.85)
	settings_button.self_modulate = Color(0.7, 0.7, 0.7)

func _on_SettingsButton_up():
	settings_button.rect_scale = Vector2(1.0, 1.0)
	settings_button.self_modulate = Color(1.0, 1.0, 1.0)

func _update_profile_panel():
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if not profile_panel_node: return
	
	var vbox = profile_panel_node.get_node("VBox")
	for child in vbox.get_children():
		child.queue_free()
	
	var p_name = Global.player_name
	if p_name == "":
		p_name = "[None - Will prompt on next High Score]"
		
	# Dynamic ranks from local top-50 memory arrays
	var my_uid = FirebaseManager.get_current_user_id()
	
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
		
	var stats_labels = [
		["Player Name", p_name],
		["All-Time Rank", all_time_rank_str],
		["Seasonal Rank", seasonal_rank_str],
		["Total Games Played", str(player_data["total_games"])],
		["High Score", str(get_highscore(mode_level))],
		["Highest Level", str(get_highest_level(mode_level))],
		["Total Deaths", str(player_data["total_deaths"])],
		["Total Revives", str(player_data.get("total_revives", 0))],
		["Distance Traveled", "%.0f m" % player_data.get("total_distance", 0.0)],
		["Playtime", "%.1f min" % (player_data["playtime"] / 60.0)]
	]
	
	var base_font = $UI/Control/MenuInfoLabel.get_font("font")
	var font = base_font.duplicate() if base_font else null
	if font:
		font.size = 50 # matches leaderboard content size
		
	for stat_pair in stats_labels:
		var row = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var label1 = Label.new()
		label1.text = stat_pair[0]
		label1.size_flags_horizontal = Control.SIZE_FILL
		if font: label1.add_font_override("font", font)
		row.add_child(label1)
		
		var label2 = Label.new()
		label2.text = stat_pair[1]
		label2.align = Label.ALIGN_RIGHT
		label2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		if stat_pair[0] == "Player Name":
			var name_font = base_font.duplicate() if base_font else null
			if name_font:
				name_font.size = 50
				label2.add_font_override("font", name_font)
		else:
			if font: label2.add_font_override("font", font)
			
		row.add_child(label2)
		vbox.add_child(row)
		
	var auth_status = ""
	var is_guest = true
	var email = ""
	if FirebaseManager.is_logged_in and Firebase.Auth.auth:
		email = Firebase.Auth.auth.get("email", "")
		
	if email != "":
		is_guest = false
		
	if FirebaseManager.is_logged_in:
		if email != "":
			auth_status = "Authentication Status: [color=#88ff88]Authenticated (" + email + ")[/color]"
		else:
			auth_status = "Authentication Status: [color=#88ff88]Authenticated (Guest)[/color]"
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
		
	var uid_str = FirebaseManager.get_current_user_id()
	if uid_str == "":
		uid_str = "Connecting..."
		
	var disclaimer_text = "UID: " + uid_str + "\n" + auth_status + "\nLast Synced: " + last_synced_str
	if is_guest:
		disclaimer_text += "\n[color=#aaaaaa]Note: Guest user data will be reset if the browser data is cleared.[/color]"
	if profile_disclaimer:
		profile_disclaimer.bbcode_text = "[center]" + disclaimer_text + "[/center]"
		
	if btn_claim_profile:
		btn_claim_profile.visible = is_guest and FirebaseManager.is_logged_in
	if btn_manage_account:
		btn_manage_account.visible = not is_guest and FirebaseManager.is_logged_in

func _on_ProfileButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	# Toggle: tapping the same button again closes the panel and restores home screen
	if active_panel_name == "profile":
		active_panel_name = ""
		var p = $UI/Control.get_node_or_null("ProfilePanel")
		if p: p.hide()
		_show_active_screen()
		return
	
	var was_panel_open = active_panel_name != ""
	
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if not profile_panel_node: return
	
	_update_profile_panel()
	
	_close_active_panel_only()

	# Only hide home/game-over content when opening from a clean screen
	if not was_panel_open:
		_hide_active_screen()
	
	active_panel_name = "profile"
	profile_panel_node.show()

func _on_CloseProfile_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node: profile_panel_node.hide()
	active_panel_name = ""
	_show_active_screen()

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

func _on_CircleButton_down(button):
	button.rect_scale = Vector2(0.85, 0.85)
	button.self_modulate = Color(0.7, 0.7, 0.7)

func _on_CircleButton_up(button):
	button.rect_scale = Vector2(1.0, 1.0)
	button.self_modulate = Color(1.0, 1.0, 1.0)

func _on_SettingsButton_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	# Toggle: tapping the same button again closes the panel
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
	var raw_db = linear2db(value) if value > 0.001 else -80.0
	# Apply standard -10 dB offset to prevent background music from overpowering the game
	var db = raw_db - 10.0 if raw_db > -79.0 else -80.0
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.volume_db = db
	save_hiscore(false)

func _apply_sfx_volume():
	var db = 0.0 if sfx_enabled else -80.0
	var sfx_nodes = [bird_jump, bird_collision, bird_fall, score_sound, bird_pop, level_change_sound, revive_sound, health_refill_sound, game_over_bgm]
	for node in sfx_nodes:
		if is_instance_valid(node):
			node.volume_db = db

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
		
	# Reset scores and stats
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
	
	music_volume = 1.0
	sfx_enabled = true
	
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
			player_data["total_deaths"] += 1
		save_hiscore(false)
	
	game_playing = false
	$ObstacleSpawner.stop()
	$bg.stop()
	$ScrollingPlatform.stop()
	
	if is_instance_valid(main_menu_bgm):
		main_menu_bgm.stop()

func trigger_grounded_phase():
	if not $UI/Control/RestartButton.visible:
		is_game_over_active = true
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

# --- FIREBASE UI SETUP ---
var leaderboard_tabs: TabContainer
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
var inspector_panel_node: Panel
var inspector_vbox: VBoxContainer
var inspector_disclaimer: RichTextLabel

func _setup_firebase_ui():
	# Resize Leaderboard Panel to give more space for separate level rows
	if is_instance_valid(leaderboard_panel):
		leaderboard_panel.margin_left = -525
		leaderboard_panel.margin_top = -840
		leaderboard_panel.margin_right = 525
		leaderboard_panel.margin_bottom = 520

	# 1. Leaderboard Panel Tabs
	var coming_soon = leaderboard_panel.get_node("VBox/ComingSoon")
	if coming_soon:
		coming_soon.queue_free()
	
	leaderboard_tabs = TabContainer.new()
	leaderboard_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var base_font = $UI/Control/MenuInfoLabel.get_font("font")
	if base_font:
		leaderboard_tabs.add_font_override("font", base_font)
	
	# Style the TabContainer tabs
	var tab_panel_style = StyleBoxEmpty.new()
	leaderboard_tabs.add_stylebox_override("panel", tab_panel_style)
	
	var active_tab_style = StyleBoxFlat.new()
	active_tab_style.bg_color = Color(0.15, 0.18, 0.23, 1.0) # Matches #272d3d (original theme)
	active_tab_style.border_width_left = 2
	active_tab_style.border_width_top = 2
	active_tab_style.border_width_right = 2
	active_tab_style.border_width_bottom = 0
	active_tab_style.border_color = Color(0.18, 0.21, 0.27, 1.0) # Matches #2f3545 (original theme border)
	active_tab_style.corner_radius_top_left = 6
	active_tab_style.corner_radius_top_right = 6
	active_tab_style.content_margin_left = 15
	active_tab_style.content_margin_right = 15
	active_tab_style.content_margin_top = 8
	active_tab_style.content_margin_bottom = 8
	leaderboard_tabs.add_stylebox_override("tab_fg", active_tab_style)
	
	var inactive_tab_style = StyleBoxFlat.new()
	inactive_tab_style.bg_color = Color(0.08, 0.1, 0.12, 1.0) # Matches #15171d (very dark)
	inactive_tab_style.border_width_left = 2
	inactive_tab_style.border_width_top = 2
	inactive_tab_style.border_width_right = 2
	inactive_tab_style.border_width_bottom = 2
	inactive_tab_style.border_color = Color(0.13, 0.15, 0.18, 1.0)
	inactive_tab_style.corner_radius_top_left = 6
	inactive_tab_style.corner_radius_top_right = 6
	inactive_tab_style.content_margin_left = 15
	inactive_tab_style.content_margin_right = 15
	inactive_tab_style.content_margin_top = 6
	inactive_tab_style.content_margin_bottom = 6
	leaderboard_tabs.add_stylebox_override("tab_bg", inactive_tab_style)
	
	leaderboard_tabs.add_color_override("font_color_bg", Color(0.53, 0.55, 0.61)) # original inactive tab text
	leaderboard_tabs.add_color_override("font_color_fg", Color(1.0, 1.0, 1.0)) # original active tab text
	
	# --- All-Time Tab ---
	var all_time_tab = VBoxContainer.new()
	all_time_tab.name = "All-Time"
	all_time_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_time_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	all_time_header_margin = _create_leaderboard_header(base_font)
	all_time_scroll = ScrollContainer.new()
	all_time_vbox = VBoxContainer.new()
	all_time_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_time_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	all_time_scroll.add_child(all_time_vbox)
	
	var all_time_table = _create_table_widget(all_time_header_margin, all_time_scroll)
	all_time_tab.add_child(all_time_table)
	
	all_time_scroll.get_v_scrollbar().connect("visibility_changed", self, "_on_all_time_scrollbar_changed")
	all_time_scroll.get_v_scrollbar().connect("item_rect_changed", self, "_on_all_time_scrollbar_changed")
	
	# --- Seasonal Tab ---
	var seasonal_tab = VBoxContainer.new()
	seasonal_tab.name = "Seasonal"
	seasonal_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seasonal_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	seasonal_header_margin = _create_leaderboard_header(base_font)
	seasonal_scroll = ScrollContainer.new()
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

	# Adjust existing Settings Panel controls dynamically to prevent overlap
	var music_label = settings_panel.get_node_or_null("MusicLabel")
	if music_label:
		music_label.margin_top = 200
		music_label.margin_bottom = 260
		
	var music_slider_anchor = settings_panel.get_node_or_null("MusicSliderAnchor")
	if music_slider_anchor:
		music_slider_anchor.margin_left = -350
		music_slider_anchor.margin_right = 350
		music_slider_anchor.margin_top = 280
		music_slider_anchor.margin_bottom = 360
		
	var sfx_label = settings_panel.get_node_or_null("SfxLabel")
	if sfx_label:
		sfx_label.margin_top = 460
		sfx_label.margin_bottom = 520
		
	var sfx_toggle_anchor = settings_panel.get_node_or_null("SfxToggleAnchor")
	if sfx_toggle_anchor:
		sfx_toggle_anchor.margin_top = 540
		sfx_toggle_anchor.margin_bottom = 620
		
	var reset_btn = settings_panel.get_node_or_null("ResetButton")
	if reset_btn:
		reset_btn.hide()
		reset_btn.disabled = true
		
	var version_lbl = settings_panel.get_node_or_null("VersionLabel")
	if version_lbl:
		version_lbl.margin_top = -170
		version_lbl.margin_bottom = -145
		
	var close_btn = settings_panel.get_node_or_null("CloseSettings")
	if close_btn:
		close_btn.margin_left = -140
		close_btn.margin_right = 140
		close_btn.margin_top = -120
		close_btn.margin_bottom = -30

	# 3. Game Over Name Prompt
	game_over_name_prompt = Panel.new()
	game_over_name_prompt.visible = false
	game_over_name_prompt.anchor_left = 0.5
	game_over_name_prompt.anchor_top = 0.5
	game_over_name_prompt.anchor_right = 0.5
	game_over_name_prompt.anchor_bottom = 0.5
	game_over_name_prompt.margin_left = -400
	game_over_name_prompt.margin_top = -250
	game_over_name_prompt.margin_right = 400
	game_over_name_prompt.margin_bottom = 250
	
	var prompt_style = StyleBoxFlat.new()
	prompt_style.bg_color = Color(0.06, 0.08, 0.14, 0.98) # Dark blue/grey translucent background
	prompt_style.border_width_left = 4
	prompt_style.border_width_top = 4
	prompt_style.border_width_right = 4
	prompt_style.border_width_bottom = 4
	prompt_style.border_color = Color(1.0, 0.85, 0.2, 0.9) # Glowing gold border for high score!
	prompt_style.corner_radius_top_left = 24
	prompt_style.corner_radius_top_right = 24
	prompt_style.corner_radius_bottom_right = 24
	prompt_style.corner_radius_bottom_left = 24
	prompt_style.shadow_size = 24
	prompt_style.shadow_color = Color(0, 0, 0, 0.6)
	game_over_name_prompt.add_stylebox_override("panel", prompt_style)
		
	var prompt_title = Label.new()
	prompt_title.text = "🏆 NEW HIGH SCORE!"
	prompt_title.anchor_right = 1.0
	prompt_title.margin_top = 40
	prompt_title.margin_bottom = 110
	prompt_title.align = Label.ALIGN_CENTER
	prompt_title.valign = Label.VALIGN_CENTER
	
	var large_title_font = DynamicFont.new()
	large_title_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	large_title_font.size = 54
	large_title_font.outline_size = 3
	large_title_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	large_title_font.use_filter = true
	prompt_title.add_font_override("font", large_title_font)
	prompt_title.add_color_override("font_color", Color(1.0, 0.85, 0.2)) # Pure Gold
	game_over_name_prompt.add_child(prompt_title)
	
	game_over_prompt_msg = Label.new()
	game_over_prompt_msg.text = "Enter a name for the leaderboard:"
	game_over_prompt_msg.anchor_right = 1.0
	game_over_prompt_msg.margin_top = 120
	game_over_prompt_msg.margin_bottom = 170
	game_over_prompt_msg.align = Label.ALIGN_CENTER
	
	var msg_font = DynamicFont.new()
	msg_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	msg_font.size = 34
	msg_font.outline_size = 2
	msg_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	msg_font.use_filter = true
	game_over_prompt_msg.add_font_override("font", msg_font)
	game_over_prompt_msg.add_color_override("font_color", Color(0.9, 0.9, 0.95))
	game_over_name_prompt.add_child(game_over_prompt_msg)
	
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	input_style.border_width_left = 3
	input_style.border_width_top = 3
	input_style.border_width_right = 3
	input_style.border_width_bottom = 3
	input_style.border_color = Color(0.2, 0.2, 0.3)
	input_style.corner_radius_top_left = 12
	input_style.corner_radius_top_right = 12
	input_style.corner_radius_bottom_right = 12
	input_style.corner_radius_bottom_left = 12
	input_style.content_margin_left = 20
	input_style.content_margin_right = 20
	
	var input_focus = input_style.duplicate()
	input_focus.border_color = Color(0.4, 0.8, 0.2)
	
	game_over_name_input = LineEdit.new()
	game_over_name_input.placeholder_text = "Your Name"
	game_over_name_input.max_length = 20
	game_over_name_input.anchor_left = 0.15
	game_over_name_input.anchor_right = 0.85
	game_over_name_input.margin_top = 200
	game_over_name_input.margin_bottom = 280
	game_over_name_input.align = LineEdit.ALIGN_CENTER
	game_over_name_input.add_stylebox_override("normal", input_style)
	game_over_name_input.add_stylebox_override("focus", input_focus)
	game_over_name_input.add_color_override("placeholder_color", Color(0.6, 0.6, 0.7))
	game_over_name_input.add_color_override("font_color", Color(0.95, 0.95, 0.95))
	game_over_name_input.add_color_override("cursor_color", Color(1, 1, 1))
	game_over_name_input.caret_blink = true
	game_over_name_input.caret_blink_speed = 0.65
	game_over_name_input.add_constant_override("caret_width", 3)
	game_over_name_input.connect("focus_entered", self, "_on_game_over_name_focus_entered")
	game_over_name_input.connect("focus_exited", self, "_on_game_over_name_focus_exited")
	
	var input_font = DynamicFont.new()
	input_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	input_font.size = 36
	input_font.outline_size = 2
	input_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	input_font.use_filter = true
	game_over_name_input.add_font_override("font", input_font)
	game_over_name_prompt.add_child(game_over_name_input)
	
	var green_btn_normal = StyleBoxFlat.new()
	green_btn_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_btn_normal.corner_radius_top_left = 16
	green_btn_normal.corner_radius_top_right = 16
	green_btn_normal.corner_radius_bottom_right = 16
	green_btn_normal.corner_radius_bottom_left = 16
	green_btn_normal.shadow_size = 4
	green_btn_normal.shadow_color = Color(0, 0, 0, 0.3)
	
	var green_btn_pressed = green_btn_normal.duplicate()
	green_btn_pressed.bg_color = Color(0.3, 0.65, 0.15)
	
	var green_btn_hover = green_btn_normal.duplicate()
	green_btn_hover.bg_color = Color(0.45, 0.85, 0.25)
	
	var red_btn_normal = StyleBoxFlat.new()
	red_btn_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_btn_normal.corner_radius_top_left = 16
	red_btn_normal.corner_radius_top_right = 16
	red_btn_normal.corner_radius_bottom_right = 16
	red_btn_normal.corner_radius_bottom_left = 16
	red_btn_normal.shadow_size = 4
	red_btn_normal.shadow_color = Color(0, 0, 0, 0.3)
	
	var red_btn_pressed = red_btn_normal.duplicate()
	red_btn_pressed.bg_color = Color(0.65, 0.2, 0.25)
	
	var red_btn_hover = red_btn_normal.duplicate()
	red_btn_hover.bg_color = Color(0.85, 0.3, 0.35)
	
	var submit_font = DynamicFont.new()
	submit_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	submit_font.size = 38
	submit_font.outline_size = 3
	submit_font.outline_color = Color(0.2, 0.5, 0.1) # Green outline
	submit_font.use_filter = true
	
	var cancel_font = DynamicFont.new()
	cancel_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	cancel_font.size = 38
	cancel_font.outline_size = 3
	cancel_font.outline_color = Color(0.5, 0.1, 0.1) # Red outline
	cancel_font.use_filter = true
	
	game_over_submit_btn = Button.new()
	game_over_submit_btn.text = "Submit"
	game_over_submit_btn.anchor_left = 0.1
	game_over_submit_btn.anchor_top = 1.0
	game_over_submit_btn.anchor_right = 0.45
	game_over_submit_btn.anchor_bottom = 1.0
	game_over_submit_btn.margin_top = -130
	game_over_submit_btn.margin_bottom = -40
	game_over_submit_btn.add_font_override("font", submit_font)
	game_over_submit_btn.add_color_override("font_color", Color(1, 1, 1))
	game_over_submit_btn.add_stylebox_override("normal", green_btn_normal)
	game_over_submit_btn.add_stylebox_override("hover", green_btn_hover)
	game_over_submit_btn.add_stylebox_override("pressed", green_btn_pressed)
	game_over_submit_btn.connect("pressed", self, "_on_submit_name_pressed")
	game_over_name_prompt.add_child(game_over_submit_btn)
	
	game_over_skip_btn = Button.new()
	game_over_skip_btn.text = "Cancel"
	game_over_skip_btn.anchor_left = 0.55
	game_over_skip_btn.anchor_top = 1.0
	game_over_skip_btn.anchor_right = 0.9
	game_over_skip_btn.anchor_bottom = 1.0
	game_over_skip_btn.margin_top = -130
	game_over_skip_btn.margin_bottom = -40
	game_over_skip_btn.add_font_override("font", cancel_font)
	game_over_skip_btn.add_color_override("font_color", Color(1, 1, 1))
	game_over_skip_btn.add_stylebox_override("normal", red_btn_normal)
	game_over_skip_btn.add_stylebox_override("hover", red_btn_hover)
	game_over_skip_btn.add_stylebox_override("pressed", red_btn_pressed)
	game_over_skip_btn.connect("pressed", self, "_on_skip_submit_pressed")
	game_over_name_prompt.add_child(game_over_skip_btn)
	
	$UI/Control.add_child(game_over_name_prompt)
	
	# Connect to Firebase signals
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
	
	var h_player = Label.new()
	h_player.text = "Player"
	h_player.rect_min_size = Vector2(560, 0)
	h_player.align = Label.ALIGN_CENTER
	if base_font: h_player.add_font_override("font", base_font)
	
	var h_score = Label.new()
	h_score.text = "Score"
	h_score.rect_min_size = Vector2(160, 0)
	h_score.align = Label.ALIGN_CENTER
	if base_font: h_score.add_font_override("font", base_font)
	
	var h_lvl = Label.new()
	h_lvl.text = "Lvl"
	h_lvl.rect_min_size = Vector2(120, 0)
	h_lvl.align = Label.ALIGN_CENTER
	if base_font: h_lvl.add_font_override("font", base_font)
	
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
	header_style.bg_color = Color(0.15, 0.18, 0.23, 1.0) # Matches #272d3d (original theme)
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
	table_style.bg_color = Color(0.13, 0.15, 0.18, 1.0) # Matches #20232a (original theme background)
	table_style.border_width_left = 2
	table_style.border_width_top = 2
	table_style.border_width_right = 2
	table_style.border_width_bottom = 2
	table_style.border_color = Color(0.18, 0.21, 0.27, 1.0) # Matches #2f3545 (original theme border)
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
	pass # Save will happen when pressing Set or closing panel

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
				name_input.grab_focus()
				name_input.caret_position = name_input.text.length()
			return
			
	var typed_name = name_input.text.strip_edges() if name_input else ""
	if typed_name == "":
		return
		
	if typed_name == Global.player_name:
		is_editing_name = false
		_update_manage_account_name_ui()
		return
		
	Global.player_name = typed_name
	
	if is_registered:
		player_data["has_changed_name_logged_in"] = true
	Global.has_changed_name = true
		
	is_editing_name = false
	_update_manage_account_name_ui()
		
	save_hiscore()
	var current_hiscore = get_highscore(1)
	if current_hiscore > 0:
		FirebaseManager.submit_score(current_hiscore, 1, Global.player_name, get_highest_level(1))

func _on_submit_name_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
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
			# If left blank, submit using current default PlayerXXXXXX name, but do not set has_changed_name to true
			pass
	
	game_over_name_prompt.hide()
	
	# Submit score now that we have/confirmed the name
	FirebaseManager.submit_score(score, mode_level, Global.player_name, current_speed_level)

func _on_skip_submit_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	game_over_name_prompt.hide()

func _show_leaderboard_submit_prompt():
	var is_name_already_set = Global.has_changed_name
	
	if is_name_already_set:
		# Name is set. Just ask permission to submit.
		game_over_prompt_msg.text = "Submit score to leaderboard as:\n" + Global.player_name
		game_over_prompt_msg.margin_top = 180
		game_over_prompt_msg.margin_bottom = 300
		
		game_over_name_input.visible = false
	else:
		# Name is NOT set. Ask for a name.
		game_over_prompt_msg.text = "Enter a name for the leaderboard:"
		game_over_prompt_msg.margin_top = 120
		game_over_prompt_msg.margin_bottom = 170
		
		game_over_name_input.visible = true
		game_over_name_input.text = "" # Clear previous inputs
		
	game_over_name_prompt.show()

func _on_stats_sync_finished(success: bool, timestamp: int):
	last_sync_attempted = true
	last_sync_success = success
	if success:
		last_sync_timestamp = timestamp
		save_hiscore(false)
		
	# Live-refresh the Stats Panel if it's currently open
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node and profile_panel_node.visible:
		_update_profile_panel()

func _on_CloseInspector_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	if inspector_panel_node:
		inspector_panel_node.hide()
	leaderboard_panel.show()

func _on_leaderboard_player_clicked(uid: String, player_name: String):
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	
	leaderboard_panel.hide()
	
	if inspector_panel_node:
		inspector_panel_node.show()
		inspector_panel_node.get_node("Title").text = player_name + "'s Profile"
		
		# Clear old VBox contents
		for child in inspector_vbox.get_children():
			child.queue_free()
			
		inspector_disclaimer.bbcode_text = "[center]Loading stats from Cloud...[/center]"
		
		var stats_loading = _create_vbox_spinner("")
		inspector_vbox.add_child(stats_loading)
		var stats_spinner = stats_loading.find_node("SpinnerIcon", true, false)
		_start_spinner_animation(stats_spinner)
		
		# Fetch from firestore
		var collection = Firebase.Firestore.collection("player_data_rushybird")
		var task = collection.get_doc(uid)
		var doc = yield(task, "completed")
		
		# Make sure panel is still open
		if not inspector_panel_node.visible:
			return
			
		for child in inspector_vbox.get_children():
			child.queue_free()
			
		if doc == null or typeof(doc) != TYPE_OBJECT or not doc.has_method("get_value"):
			var err_lbl = Label.new()
			err_lbl.text = "Failed to load player stats.\n(Stats may not have synced yet)"
			err_lbl.align = Label.ALIGN_CENTER
			var base_font = $UI/Control/MenuInfoLabel.get_font("font")
			if base_font: err_lbl.add_font_override("font", base_font)
			inspector_vbox.add_child(err_lbl)
			inspector_disclaimer.bbcode_text = "[center][color=#ff8888]Error: Profile offline[/color][/center]"
			return
			
		# Determine ranks from cached lists
		var all_time_rank_str = "Unranked (50+)"
		var idx = 0
		for entry in FirebaseManager._temp_all_time:
			if entry.get("uid", "") == uid:
				all_time_rank_str = "#" + str(idx + 1)
				break
			idx += 1
			
		var seasonal_rank_str = "Unranked (50+)"
		idx = 0
		for entry in FirebaseManager._temp_seasonal:
			if entry.get("uid", "") == uid:
				seasonal_rank_str = "#" + str(idx + 1)
				break
			idx += 1

		# Populate stats
		var stats_labels = [
			["All-Time Rank", all_time_rank_str],
			["Seasonal Rank", seasonal_rank_str],
			["Classic High Score", str(doc.get_value("classic_highscore"))],
			["Escalation High Score", str(doc.get_value("escalation_highscore"))],
			["Highest Level", str(doc.get_value("escalation_highest_level"))],
			["Total Games Played", str(doc.get_value("total_games"))],
			["Total Deaths", str(doc.get_value("total_deaths"))],
			["Total Revives", str(doc.get_value("total_revives"))],
			["Distance Traveled", "%.0f m" % float(doc.get_value("total_distance"))],
			["Playtime", "%.1f min" % (float(doc.get_value("playtime")) / 60.0)]
		]
		
		var base_font = $UI/Control/MenuInfoLabel.get_font("font")
		var font = base_font.duplicate() if base_font else null
		if font:
			font.size = 46
			
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
			
			inspector_vbox.add_child(row)
			
		var timestamp = int(doc.get_value("last_updated"))
		var local_offset = get_local_timezone_offset()
		var t = OS.get_datetime_from_unix_time(timestamp + local_offset)
		var hour_12 = t.hour % 12
		if hour_12 == 0:
			hour_12 = 12
		var am_pm = "AM" if t.hour < 12 else "PM"
		inspector_disclaimer.bbcode_text = "[center]Last Active: %02d-%02d-%04d %02d:%02d %s[/center]" % [t.day, t.month, t.year, hour_12, t.minute, am_pm]

func _on_auth_state_changed(is_logged_in: bool):
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node and profile_panel_node.visible:
		_on_ProfileButton_pressed()
	
	if is_logged_in and not FirebaseManager.is_claiming_profile():
		# Re-sync stats in case they were updated
		FirebaseManager.submit_stats(player_data)
		var escalation_hs = get_highscore(1)
		if escalation_hs > 0:
			FirebaseManager.submit_score(escalation_hs, 1, Global.player_name, get_highest_level(1))
		else:
			FirebaseManager.fetch_leaderboards()

func _get_seasonal_reset_time_string() -> String:
	var now = OS.get_datetime(true)
	
	# Determine next month and year
	var next_month = now.month + 1
	var next_year = now.year
	if next_month > 12:
		next_month = 1
		next_year += 1
		
	# Target datetime (first day of next month, 00:00:00)
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

# --- Profile Claiming UI ---
var claim_profile_panel: Panel
var claim_email_input: LineEdit
var claim_pass_input: LineEdit
var btn_google_claim: Button


var conflict_panel: Panel
var conflict_details: RichTextLabel
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
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.85) # Solid dark translucent background
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
	
	# Background track (still)
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
	
	# Foreground spinner (rotating)
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
	loading_spinner_icon.add_color_override("font_color", Color(0.4, 0.8, 0.2)) # Premium accent green
	spinner_container.add_child(loading_spinner_icon)
	
	var loading_label = Label.new()
	loading_label.text = "Loading..."
	loading_label.align = Label.ALIGN_CENTER
	var base_font = $UI/Control/MenuInfoLabel.get_font("font")
	if base_font:
		var font_dup = base_font.duplicate()
		font_dup.size = 36
		loading_label.add_font_override("font", font_dup)
	loading_label.add_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(loading_label)
	
	$UI/Control.add_child(loading_overlay)

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
	var center_container = CenterContainer.new()
	center_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 10)
	center_container.add_child(vbox)
	
	var center_spinner = CenterContainer.new()
	vbox.add_child(center_spinner)
	
	var spinner_container = Control.new()
	spinner_container.rect_min_size = Vector2(100, 100)
	center_spinner.add_child(spinner_container)
	
	# Background track (still)
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
	
	# Foreground spinner (rotating)
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
		var base_font = $UI/Control/MenuInfoLabel.get_font("font")
		if base_font:
			var font_dup = base_font.duplicate()
			font_dup.size = 28
			label.add_font_override("font", font_dup)
		label.add_color_override("font_color", Color(0.8, 0.8, 0.8))
		vbox.add_child(label)
		
	return center_container

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

func _create_claim_profile_panel():
	claim_profile_panel = Panel.new()
	claim_profile_panel.name = "ClaimProfilePanel"
	claim_profile_panel.anchor_right = 1.0
	claim_profile_panel.anchor_bottom = 1.0
	claim_profile_panel.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.95) # Translucent dark background matching theme
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
	
	# Divider
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
	
	var line_edit_style = StyleBoxFlat.new()
	line_edit_style.bg_color = Color(0.1, 0.1, 0.15, 0.9) # Dark blue/grey input box
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
	
	var line_edit_focus = line_edit_style.duplicate()
	line_edit_focus.border_color = Color(0.4, 0.8, 0.2) # Active green border on focus
	
	claim_email_input = LineEdit.new()
	claim_email_input.placeholder_text = "Email Address"
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
	
	claim_pass_input = LineEdit.new()
	claim_pass_input.placeholder_text = "Password"
	claim_pass_input.secret = true
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
	
	var btn_submit = Button.new()
	btn_submit.text = "Link Account"
	btn_submit.anchor_left = 0.15
	btn_submit.anchor_right = 0.85
	btn_submit.margin_top = 740
	btn_submit.margin_bottom = 840
	btn_submit.connect("pressed", self, "_on_SubmitClaim_pressed")
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var green_font = ref_font.duplicate()
			green_font.size = 45
			green_font.outline_size = 3
			green_font.outline_color = Color(0.15, 0.4, 0.08) # Green outline matching Start button
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
	btn_google_claim.text = "Sign in with Google"
	btn_google_claim.anchor_left = 0.15
	btn_google_claim.anchor_right = 0.85
	btn_google_claim.connect("pressed", self, "_on_GoogleClaim_pressed")
	
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var google_font = ref_font.duplicate()
			google_font.size = 45
			google_font.outline_size = 3
			google_font.outline_color = Color(0.1, 0.2, 0.4) # Blue outline
			btn_google_claim.add_font_override("font", google_font)
			
	var google_normal = StyleBoxFlat.new()
	google_normal.bg_color = Color(0.26, 0.52, 0.96) # Google Blue
	google_normal.anti_aliasing = true
	google_normal.corner_radius_top_left = 20
	google_normal.corner_radius_top_right = 20
	google_normal.corner_radius_bottom_right = 20
	google_normal.corner_radius_bottom_left = 20
	google_normal.border_width_bottom = 8
	google_normal.border_color = Color(0.18, 0.4, 0.75) # Darker Google Blue
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
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.anchor_left = 0.15
	btn_cancel.anchor_right = 0.85
	btn_cancel.connect("pressed", self, "_on_CancelClaim_pressed")
	
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var cancel_font = ref_font.duplicate()
			cancel_font.size = 45
			cancel_font.outline_size = 3
			cancel_font.outline_color = Color(0.4, 0.1, 0.1) # Burgundy red outline
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

	btn_cancel.add_stylebox_override("normal", red_normal)
	btn_cancel.add_stylebox_override("hover", red_hover)
	btn_cancel.add_stylebox_override("pressed", red_pressed)
	btn_cancel.add_color_override("font_color", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	claim_profile_panel.add_child(btn_cancel)
	
	# Platform specific visibility and positioning
	if OS.has_feature("JavaScript") or OS.get_name() == "HTML5" or OS.get_name() == "Android":
		btn_google_claim.visible = false
		btn_cancel.margin_top = 900
		btn_cancel.margin_bottom = 1000
	else:
		btn_google_claim.visible = true
		btn_google_claim.margin_top = 880
		btn_google_claim.margin_bottom = 980
		btn_cancel.margin_top = 1020
		btn_cancel.margin_bottom = 1120
	
	$UI/Control.add_child(claim_profile_panel)
	
func _create_conflict_panel():
	conflict_panel = Panel.new()
	conflict_panel.name = "ConflictPanel"
	conflict_panel.anchor_right = 1.0
	conflict_panel.anchor_bottom = 1.0
	conflict_panel.visible = false
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.95) # Translucent dark background
	conflict_panel.add_stylebox_override("panel", panel_style)
	
	# Title
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
	title.add_color_override("font_color", Color(1.0, 0.85, 0.2)) # Glowing gold/yellow title
	conflict_panel.add_child(title)
	
	# Divider
	var divider = Panel.new()
	divider.anchor_left = 0.1
	divider.anchor_right = 0.9
	divider.margin_top = 190
	divider.margin_bottom = 193
	var div_style = StyleBoxFlat.new()
	div_style.bg_color = Color(0.25, 0.3, 0.45, 0.7)
	divider.add_stylebox_override("panel", div_style)
	conflict_panel.add_child(divider)
	
	# Subtitle
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
	
	# Button Group for mutual exclusion
	var btn_group = ButtonGroup.new()
	
	# VBox container for cards
	var cards_vbox = VBoxContainer.new()
	cards_vbox.name = "CardsVBox"
	cards_vbox.anchor_left = 0.5
	cards_vbox.anchor_right = 0.5
	cards_vbox.margin_left = -450
	cards_vbox.margin_right = 450
	cards_vbox.margin_top = 355
	cards_vbox.margin_bottom = 1375
	cards_vbox.alignment = BoxContainer.ALIGN_CENTER
	cards_vbox.set("custom_constants/separation", 20)
	conflict_panel.add_child(cards_vbox)
	
	# Styleboxes
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
		
	# Card 1: Device
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
	vbox_dev.margin_right = -30
	vbox_dev.margin_top = 25
	vbox_dev.margin_bottom = -25
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
	
	# Card 2: Cloud
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
	vbox_cld.margin_right = -30
	vbox_cld.margin_top = 25
	vbox_cld.margin_bottom = -25
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
	
	# Warning
	var warn_lbl = Label.new()
	warn_lbl.text = "⚠️ Selecting a profile will permanently overwrite the unselected one."
	warn_lbl.align = Label.ALIGN_CENTER
	warn_lbl.anchor_right = 1.0
	warn_lbl.margin_top = 1395
	warn_lbl.margin_bottom = 1460
	var warn_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if warn_font:
		warn_font.size = 40
		warn_font.outline_size = 2
		warn_font.outline_color = Color(0.08, 0.1, 0.15)
		warn_lbl.add_font_override("font", warn_font)
	warn_lbl.add_color_override("font_color", Color(1.0, 0.6, 0.15))
	conflict_panel.add_child(warn_lbl)
	
	# Keep Selected Save Button
	btn_keep_selected = Button.new()
	btn_keep_selected.text = "Keep Selected Save"
	btn_keep_selected.anchor_left = 0.5
	btn_keep_selected.anchor_right = 0.5
	btn_keep_selected.margin_left = -450
	btn_keep_selected.margin_right = 450
	btn_keep_selected.margin_top = 1480
	btn_keep_selected.margin_bottom = 1580
	btn_keep_selected.connect("pressed", self, "_on_KeepSelected_pressed")
	btn_keep_selected.disabled = true
	btn_keep_selected.modulate.a = 0.5
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
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
	
	# Cancel Button
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel Linking"
	btn_cancel.anchor_left = 0.5
	btn_cancel.anchor_right = 0.5
	btn_cancel.margin_left = -450
	btn_cancel.margin_right = 450
	btn_cancel.margin_top = 1600
	btn_cancel.margin_bottom = 1700
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
	
	$UI/Control.add_child(conflict_panel)

func _on_ClaimProfile_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.hide()
	claim_profile_panel.visible = true

func _on_CancelClaim_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	claim_profile_panel.visible = false
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.show()

func _on_SubmitClaim_pressed():
	var email = claim_email_input.text.strip_edges()
	var password = claim_pass_input.text.strip_edges()
	if email == "" or password == "":
		return
	FirebaseManager.start_profile_claim_email(email, password, player_data)
	claim_profile_panel.visible = false
	_show_loading("Linking Account...")

func _on_GoogleClaim_pressed():
	FirebaseManager.start_google_login(player_data)
	claim_profile_panel.visible = false
	_show_loading("Linking Account...")

func _on_profile_claim_conflict(_guest_stats, _cloud_stats):
	_hide_loading()
	# 1. Reset selection states
	selected_profile_type = ""
	if card_device:
		card_device.pressed = false
	if card_cloud:
		card_cloud.pressed = false
	if btn_keep_selected:
		btn_keep_selected.disabled = true
		btn_keep_selected.modulate.a = 0.5
		
	# 2. Format Device Stats
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
		
	# 3. Format Cloud Stats
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
	
	# Clean up UI - close panels and return to main screen
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
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

	if active_panel_name == "profile":
		active_panel_name = ""
		_on_ProfileButton_pressed()
	
	print("Profile Claim Succeeded!")

func _on_profile_claim_failed(reason):
	_hide_loading()
	print("Profile Claim Failed: ", reason)
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.show()

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
				manage_name_hint.add_color_override("font_color", Color(0.7, 0.7, 0.8))

	# Re-assigning text AFTER changing alignment forces Godot to recalculate character click bounds!
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
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.95) # Translucent dark background matching theme
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
	
	# Divider
	var divider = Panel.new()
	divider.anchor_left = 0.1
	divider.anchor_right = 0.9
	divider.margin_top = 350
	divider.margin_bottom = 353
	var div_style = StyleBoxFlat.new()
	div_style.bg_color = Color(0.25, 0.3, 0.45, 0.7)
	divider.add_stylebox_override("panel", div_style)
	manage_account_panel.add_child(divider)
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	var ref_font = null
	if ref_btn:
		ref_font = ref_btn.get_font("font")
		
	# Player Name Label
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
	
	# Player Name Input
	var input_font = DynamicFont.new()
	input_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	input_font.size = 50
	input_font.outline_size = 2
	input_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	
	var line_edit_style = StyleBoxFlat.new()
	line_edit_style.bg_color = Color(0.1, 0.1, 0.15, 0.9) # Dark blue/grey input box
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
	
	var line_edit_focus = line_edit_style.duplicate()
	line_edit_focus.border_color = Color(0.4, 0.8, 0.2) # Active green border on focus

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
	manage_account_panel.add_child(name_input)
	
	# Player Name Submit Button
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
	set_normal.bg_color = Color(0.15, 0.4, 0.75) # Premium blue
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
	
	# Player Name Cancel Button
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
	
	# Player Name Hint Label
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
		manage_name_hint.add_font_override("font", hint_font)
	manage_account_panel.add_child(manage_name_hint)
		
	var btn_unlink = Button.new()
	btn_unlink.text = "Unlink Account"
	btn_unlink.anchor_left = 0.5
	btn_unlink.anchor_right = 0.5
	btn_unlink.margin_left = -450
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
	btn_logout.margin_left = -450
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
	btn_cancel.margin_left = -450
	btn_cancel.margin_right = 450
	btn_cancel.margin_top = 1000
	btn_cancel.margin_bottom = 1100
	btn_cancel.connect("pressed", self, "_on_CancelManage_pressed")
	if ref_font:
		var cancel_font = ref_font.duplicate()
		cancel_font.size = 45
		cancel_font.outline_size = 3
		cancel_font.outline_color = Color(0.1, 0.35, 0.15) # Dark green outline
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
	
	$UI/Control.add_child(manage_account_panel)

func _on_ManageAccount_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
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
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.show()

func _on_Logout_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	# Logout from firebase & clear credentials
	Firebase.Auth.logout()
	FirebaseManager.is_logged_in = false
	FirebaseManager.user_id = ""
		
	# Reset local variables
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
	
	# Dark full-screen translucent blocker
	var blocker_style = StyleBoxFlat.new()
	blocker_style.bg_color = Color(0.0, 0.0, 0.0, 0.8)
	overwrite_confirm_panel.add_stylebox_override("panel", blocker_style)
	
	# Centered card
	var card = Panel.new()
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.margin_left = -400
	card.margin_right = 400
	card.margin_top = -320
	card.margin_bottom = 320
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.1, 0.16, 0.95) # Dark card matching settings
	card_style.corner_radius_top_left = 20
	card_style.corner_radius_top_right = 20
	card_style.corner_radius_bottom_right = 20
	card_style.corner_radius_bottom_left = 20
	card_style.border_width_left = 4
	card_style.border_width_top = 4
	card_style.border_width_right = 4
	card_style.border_width_bottom = 4
	card_style.border_color = Color(0.2, 0.25, 0.35)
	card.add_stylebox_override("panel", card_style)
	overwrite_confirm_panel.add_child(card)
	
	# Title
	var title = Label.new()
	title.text = "⚠️ OVERWRITE PROFILE?"
	title.align = Label.ALIGN_CENTER
	title.anchor_right = 1.0
	title.margin_top = 40
	title.margin_bottom = 130
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if title_font:
		title_font.size = 65
		title_font.outline_size = 4
		title_font.outline_color = Color(0.4, 0.1, 0.1) # Danger red/burgundy outline
		title.add_font_override("font", title_font)
	title.add_color_override("font_color", Color(0.9, 0.3, 0.3)) # Danger red
	card.add_child(title)
	
	# Divider
	var ow_divider = Panel.new()
	ow_divider.anchor_left = 0.1
	ow_divider.anchor_right = 0.9
	ow_divider.margin_top = 148
	ow_divider.margin_bottom = 151
	var ow_div_style = StyleBoxFlat.new()
	ow_div_style.bg_color = Color(0.5, 0.2, 0.2, 0.7)
	ow_divider.add_stylebox_override("panel", ow_div_style)
	card.add_child(ow_divider)
	
	# Msg
	var msg = Label.new()
	msg.text = "Permanently overwrite your profile?\nThis cannot be undone."
	msg.align = Label.ALIGN_CENTER
	msg.anchor_right = 1.0
	msg.margin_top = 170
	msg.margin_bottom = 330
	var msg_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if msg_font:
		msg_font.size = 50
		msg_font.outline_size = 3
		msg_font.outline_color = Color(0.08, 0.1, 0.15) # Dark outline for white text
		msg.add_font_override("font", msg_font)
	msg.add_color_override("font_color", Color(0.85, 0.85, 0.9))
	card.add_child(msg)
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	var ref_font = ref_btn.get_font("font") if ref_btn else null
	
	# Overwrite button (Red)
	var btn_confirm = Button.new()
	btn_confirm.text = "OVERWRITE"
	btn_confirm.anchor_left = 0.1
	btn_confirm.anchor_right = 0.9
	btn_confirm.margin_top = 380
	btn_confirm.margin_bottom = 480
	btn_confirm.connect("pressed", self, "_on_OverwriteConfirm_pressed")
	if ref_font:
		var confirm_font = ref_font.duplicate()
		confirm_font.size = 45
		confirm_font.outline_size = 3
		confirm_font.outline_color = Color(0.4, 0.1, 0.1) # Burgundy outline for Red button
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
	
	# Cancel button (Green)
	var btn_cancel = Button.new()
	btn_cancel.text = "CANCEL"
	btn_cancel.anchor_left = 0.1
	btn_cancel.anchor_right = 0.9
	btn_cancel.margin_top = 500
	btn_cancel.margin_bottom = 600
	btn_cancel.connect("pressed", self, "_on_OverwriteCancel_pressed")
	if ref_font:
		var green_font = ref_font.duplicate()
		green_font.size = 45
		green_font.outline_size = 3
		green_font.outline_color = Color(0.15, 0.4, 0.08) # Green outline
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
	
	$UI/Control.add_child(overwrite_confirm_panel)

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
