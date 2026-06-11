extends Spatial

var score = 0
var hiscores = {0: 0, 1: 0}
var highest_levels = {0: 1, 1: 1}
var game_speed = 1.0

var stats = {
	"total_games": 0,
	"high_score": 0,
	"playtime": 0.0,
	"total_deaths": 0,
	"total_revives": 0,
	"total_distance": 0.0
}
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
var game_over_level_label: Label
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
	_create_manage_account_panel()
	_create_conflict_panel()
	_create_overwrite_confirm_panel()
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
	
	game_over_level_label = $UI/Control.get_node_or_null("GameOverLevelLabel")
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
	profile_panel_node.margin_left = -320
	profile_panel_node.margin_top = -540
	profile_panel_node.margin_right = 320
	profile_panel_node.margin_bottom = 540
	$UI/Control.add_child(profile_panel_node)
	
	var profile_title = Label.new()
	profile_title.text = "Player Profile"
	profile_title.anchor_right = 1.0
	profile_title.margin_top = 40
	profile_title.margin_bottom = 100
	profile_title.align = Label.ALIGN_CENTER
	profile_title.valign = Label.VALIGN_CENTER
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button")
	if title_font: profile_title.add_font_override("font", title_font)
	profile_panel_node.add_child(profile_title)
	
	var profile_vbox = VBoxContainer.new()
	profile_vbox.name = "VBox"
	profile_vbox.anchor_right = 1.0
	profile_vbox.anchor_bottom = 1.0
	profile_vbox.margin_left = 40
	profile_vbox.margin_right = -40
	profile_vbox.margin_top = 120
	profile_vbox.margin_bottom = -370
	profile_vbox.add_constant_override("separation", 15)
	profile_panel_node.add_child(profile_vbox)
	
	var close_profile = Button.new()
	close_profile.text = "Close"
	close_profile.anchor_left = 0.5
	close_profile.anchor_top = 1.0
	close_profile.anchor_right = 0.5
	close_profile.anchor_bottom = 1.0
	close_profile.margin_left = -140
	close_profile.margin_top = -220
	close_profile.margin_right = 140
	close_profile.margin_bottom = -130
	close_profile.connect("pressed", self, "_on_CloseProfile_pressed")
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	if ref_btn:
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
	profile_disclaimer.margin_top = -120
	profile_disclaimer.margin_bottom = -20
	
	var desc_font = DynamicFont.new()
	desc_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	desc_font.size = 24
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
	btn_claim_profile.margin_left = -220
	btn_claim_profile.margin_top = -340
	btn_claim_profile.margin_right = 220
	btn_claim_profile.margin_bottom = -250
	btn_claim_profile.connect("pressed", self, "_on_ClaimProfile_pressed")
	
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var green_font = ref_font.duplicate()
			green_font.outline_color = Color(0.2, 0.5, 0.1) # Green outline matching Start button
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
	btn_manage_account.margin_left = -220
	btn_manage_account.margin_top = -340
	btn_manage_account.margin_right = 220
	btn_manage_account.margin_bottom = -250
	btn_manage_account.connect("pressed", self, "_on_ManageAccount_pressed")
	
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var green_font = ref_font.duplicate()
			green_font.outline_color = Color(0.2, 0.5, 0.1) # Green outline matching Start button
			btn_manage_account.add_font_override("font", green_font)
			
	btn_manage_account.add_stylebox_override("normal", green_normal)
	btn_manage_account.add_stylebox_override("hover", green_hover)
	btn_manage_account.add_stylebox_override("pressed", green_pressed)
	btn_manage_account.add_color_override("font_color", Color(1, 1, 1))
	btn_manage_account.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_manage_account.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
			
	profile_panel_node.add_child(btn_manage_account)

	# Dynamic creation of InspectorPanel
	inspector_panel_node = Panel.new()
	inspector_panel_node.name = "InspectorPanel"
	inspector_panel_node.visible = false
	inspector_panel_node.anchor_left = 0.5
	inspector_panel_node.anchor_top = 0.5
	inspector_panel_node.anchor_right = 0.5
	inspector_panel_node.anchor_bottom = 0.5
	inspector_panel_node.margin_left = -320
	inspector_panel_node.margin_top = -480
	inspector_panel_node.margin_right = 320
	inspector_panel_node.margin_bottom = 480
	
	if has_node("UI/Control/SettingsPanel/ConfirmPanel"):
		var warning_style = $UI/Control/SettingsPanel/ConfirmPanel.get_stylebox("panel")
		if warning_style:
			inspector_panel_node.add_stylebox_override("panel", warning_style)
	$UI/Control.add_child(inspector_panel_node)
	
	var inspector_title = Label.new()
	inspector_title.name = "Title"
	inspector_title.text = "Player Profile"
	inspector_title.anchor_right = 1.0
	inspector_title.margin_top = 40
	inspector_title.margin_bottom = 100
	inspector_title.align = Label.ALIGN_CENTER
	inspector_title.valign = Label.VALIGN_CENTER
	if title_font:
		inspector_title.add_font_override("font", title_font)
	inspector_panel_node.add_child(inspector_title)
	
	inspector_vbox = VBoxContainer.new()
	inspector_vbox.name = "VBox"
	inspector_vbox.anchor_right = 1.0
	inspector_vbox.anchor_bottom = 1.0
	inspector_vbox.margin_left = 40
	inspector_vbox.margin_right = -40
	inspector_vbox.margin_top = 150
	inspector_vbox.margin_bottom = -200
	inspector_vbox.add_constant_override("separation", 20)
	inspector_panel_node.add_child(inspector_vbox)
	
	var close_inspector = Button.new()
	close_inspector.text = "Close"
	close_inspector.anchor_left = 0.5
	close_inspector.anchor_top = 1.0
	close_inspector.anchor_right = 0.5
	close_inspector.anchor_bottom = 1.0
	close_inspector.margin_left = -140
	close_inspector.margin_top = -180
	close_inspector.margin_right = 140
	close_inspector.margin_bottom = -95
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
	inspector_disclaimer.margin_top = -105
	inspector_disclaimer.margin_bottom = -10
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
	
func save_hiscore(sync_to_cloud: bool = true):
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
		"stats": stats,
		"player_name": Global.player_name,
		"has_changed_name": Global.has_changed_name
	}
	file.store_var(data)
	file.close()
	
	if sync_to_cloud:
		FirebaseManager.submit_stats(stats, hiscores, highest_levels, Global.player_name)

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
		# Always start in Classic mode, so we don't load the saved mode_level
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
		if content.has("player_name"):
			Global.player_name = content.get("player_name")
		if content.has("has_changed_name"):
			Global.has_changed_name = content.get("has_changed_name")
	else:
		# Fallback to older integer format
		file.seek(0)
		var old_content = file.get_64()
		if old_content != null:
			hiscores[0] = old_content # Assume Classic
			
	stats["high_score"] = hiscores[mode_level]
	file.close()
	
	if Global.player_name == "":
		randomize()
		Global.player_name = "Player" + str(randi() % 900000 + 100000)
	save_hiscore(false)

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
	if not cheats_used:
		if score > hiscores[mode_level]:
			is_new_high_score = true
		if score >= hiscores[mode_level]:
			hiscores[mode_level] = score
		stats["high_score"] = hiscores[mode_level]
	if menu_info_label:
		if mode_level == 1:
			menu_info_label.text = "YOUR BEST: " + String(hiscores[mode_level]) + " (Lvl " + str(highest_levels[mode_level]) + ")"
		else:
			menu_info_label.text = "YOUR BEST: " + String(hiscores[mode_level])

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
		stats["total_games"] = stats.get("total_games", 0) + 1
		
	run_distance = 0.0
	run_max_speed = 1.0
	run_playtime = 0.0
	
	save_hiscore()

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
	
	if is_instance_valid(game_over_level_label): game_over_level_label.hide()
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
		if is_instance_valid(game_over_level_label): game_over_level_label.hide()
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
		if is_instance_valid(game_over_level_label) and mode_level == 1:
			game_over_level_label.show()
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
		
	var loading = Label.new()
	loading.text = "Loading..."
	loading.align = Label.ALIGN_CENTER
	var base_font = $UI/Control/MenuInfoLabel.get_font("font")
	if base_font: loading.add_font_override("font", base_font)
	
	all_time_vbox.add_child(loading)
	seasonal_vbox.add_child(loading.duplicate())

func _on_leaderboard_updated(all_time, seasonal):
	for child in all_time_vbox.get_children():
		child.queue_free()
	for child in seasonal_vbox.get_children():
		child.queue_free()
		
	_populate_leaderboard(all_time_vbox, all_time)
	_populate_leaderboard(seasonal_vbox, seasonal)

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
		
		var rank_lbl = Label.new()
		rank_lbl.text = "#" + str(rank)
		rank_lbl.rect_min_size = Vector2(80, 0)
		if base_font: rank_lbl.add_font_override("font", base_font)
		
		var name_container = HBoxContainer.new()
		name_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_btn = LinkButton.new()
		var p_name = entry.get("player_name", "Unknown")
		if p_name.length() > 20:
			p_name = p_name.substr(0, 17) + "..."
		name_btn.text = p_name
		name_btn.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		if base_font: name_btn.add_font_override("font", base_font)
		
		var uid = entry.get("uid", "")
		if uid != "":
			name_btn.connect("pressed", self, "_on_leaderboard_player_clicked", [uid, entry.get("player_name", "Unknown")])
		
		name_container.add_child(name_btn)
		
		var is_registered = entry.get("is_registered", false)
		var is_current_user = (uid != "" and uid == FirebaseManager.get_current_user_id())
		var is_current_user_registered = false
		if is_current_user and FirebaseManager.is_logged_in and Firebase.Auth.auth:
			var email = Firebase.Auth.auth.get("email", "")
			if email != "":
				is_current_user_registered = true
				
		if is_registered or is_current_user_registered:
			var check_spacer = Control.new()
			check_spacer.rect_min_size = Vector2(8, 0)
			name_container.add_child(check_spacer)
			
			var check_icon = preload("res://addons/FontAwesome5/FontAwesome.gd").new()
			check_icon.icon_type = "solid"
			check_icon.icon_name = "check"
			if base_font:
				check_icon.icon_size = base_font.size
			else:
				check_icon.icon_size = 28
			check_icon.add_color_override("font_color", Color(0.2, 0.9, 0.2)) # Bright green
			name_container.add_child(check_icon)
		
		var score_lbl = Label.new()
		score_lbl.text = str(entry.get("score", 0))
		score_lbl.align = Label.ALIGN_RIGHT
		score_lbl.rect_min_size = Vector2(100, 0)
		if base_font: score_lbl.add_font_override("font", base_font)
		
		row.add_child(rank_lbl)
		row.add_child(name_container)
		row.add_child(score_lbl)
		vbox.add_child(row)
		rank += 1

func _on_CloseLeaderboard_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	active_panel_name = ""
	leaderboard_panel.hide()
	_show_active_screen()

func _on_SettingsButton_down():
	settings_button.rect_scale = Vector2(0.85, 0.85)
	settings_button.self_modulate = Color(0.7, 0.7, 0.7) # Dim slightly when pressed

func _on_SettingsButton_up():
	settings_button.rect_scale = Vector2(1.0, 1.0)
	settings_button.self_modulate = Color(1.0, 1.0, 1.0) # Back to original color

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
	
	var vbox = profile_panel_node.get_node("VBox")
	for child in vbox.get_children():
		child.queue_free()
	
	stats["high_score"] = hiscores[mode_level]
	
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
		["Total Games Played", str(stats["total_games"])],
		["High Score", str(stats["high_score"])],
		["Highest Level", str(highest_levels[1])],
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
				name_font.size = 32
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
		var t = OS.get_datetime_from_unix_time(last_sync_timestamp)
		last_synced_str = "%02d-%02d-%04d %02d:%02d:%02d" % [t.day, t.month, t.year, t.hour, t.minute, t.second]
		
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
	
	if name_input:
		name_input.text = Global.player_name
		var is_name_already_set = Global.has_changed_name
		name_input.editable = not is_name_already_set
		if name_submit_btn:
			name_submit_btn.visible = not is_name_already_set
			name_submit_btn.disabled = is_name_already_set
			if is_name_already_set:
				name_input.anchor_right = 0.9
			else:
				name_input.anchor_right = 0.6
	
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
		
	# Reset scores
	hiscores = {0: 0, 1: 0}
	highest_levels = {0: 1, 1: 1}
	stats = {
		"total_games": 0,
		"high_score": 0,
		"playtime": 0.0,
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
			
		if is_instance_valid(game_over_level_label):
			if mode_level == 1:
				game_over_level_label.text = "LEVEL " + str(current_speed_level)
				game_over_level_label.show()
			else:
				game_over_level_label.hide()
			
		if game_over_panel:
			if mode_level == 1:
				stats["total_distance"] = stats.get("total_distance", 0.0) + run_distance
				stats["playtime"] = stats.get("playtime", 0.0) + run_playtime
			stats["high_score"] = hiscores[mode_level]
			save_hiscore()
				
			var score_str = String(score)
			if mode_level == 1:
				score_str += " (Lvl " + str(current_speed_level) + ")"
			game_over_panel.get_node("VBox/ScoreRow/Value").text = score_str
			
			var best_str = String(hiscores[mode_level])
			if mode_level == 1:
				best_str += " (Lvl " + str(highest_levels[mode_level]) + ")"
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

# --- FIREBASE UI SETUP ---
var leaderboard_tabs: TabContainer
var all_time_vbox: VBoxContainer
var seasonal_vbox: VBoxContainer
var name_input: LineEdit
var name_submit_btn: Button
var game_over_name_prompt: Panel
var game_over_name_input: LineEdit
var game_over_prompt_msg: Label
var game_over_submit_btn: Button
var game_over_skip_btn: Button
var profile_disclaimer: RichTextLabel
var inspector_panel_node: Panel
var inspector_vbox: VBoxContainer
var inspector_disclaimer: RichTextLabel
var settings_uid_label: Label

func _setup_firebase_ui():
	# 1. Leaderboard Panel Tabs
	var coming_soon = leaderboard_panel.get_node("VBox/ComingSoon")
	if coming_soon:
		coming_soon.queue_free()
	
	leaderboard_tabs = TabContainer.new()
	leaderboard_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var base_font = $UI/Control/MenuInfoLabel.get_font("font")
	if base_font:
		leaderboard_tabs.add_font_override("font", base_font)
	
	var all_time_tab = ScrollContainer.new()
	all_time_tab.name = "All-Time"
	
	all_time_vbox = VBoxContainer.new()
	all_time_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_time_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	all_time_tab.add_child(all_time_vbox)
	
	var seasonal_tab = ScrollContainer.new()
	seasonal_tab.name = "Seasonal"
	
	seasonal_vbox = VBoxContainer.new()
	seasonal_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seasonal_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	seasonal_tab.add_child(seasonal_vbox)
	
	leaderboard_tabs.add_child(all_time_tab)
	leaderboard_tabs.add_child(seasonal_tab)
	leaderboard_panel.get_node("VBox").add_child(leaderboard_tabs)
	leaderboard_panel.get_node("VBox").move_child(leaderboard_tabs, 0)

	# Adjust existing Settings Panel controls dynamically to prevent overlap
	var music_label = settings_panel.get_node_or_null("MusicLabel")
	if music_label:
		music_label.margin_top = 130
		music_label.margin_bottom = 170
		
	var music_slider_anchor = settings_panel.get_node_or_null("MusicSliderAnchor")
	if music_slider_anchor:
		music_slider_anchor.margin_top = 180
		music_slider_anchor.margin_bottom = 240
		
	var sfx_label = settings_panel.get_node_or_null("SfxLabel")
	if sfx_label:
		sfx_label.margin_top = 260
		sfx_label.margin_bottom = 300
		
	var sfx_toggle_anchor = settings_panel.get_node_or_null("SfxToggleAnchor")
	if sfx_toggle_anchor:
		sfx_toggle_anchor.margin_top = 310
		sfx_toggle_anchor.margin_bottom = 370
		
	var reset_btn = settings_panel.get_node_or_null("ResetButton")
	if reset_btn:
		reset_btn.hide()
		reset_btn.disabled = true
		
	var close_btn = settings_panel.get_node_or_null("CloseSettings")
	if close_btn:
		close_btn.margin_top = -110
		close_btn.margin_bottom = -30

	# 2. Settings Panel: Player Name Input
	var name_label = Label.new()
	name_label.text = "Player Name"
	name_label.align = Label.ALIGN_CENTER
	name_label.margin_top = 390
	name_label.margin_bottom = 420
	name_label.anchor_left = 0.1
	name_label.anchor_right = 0.9
	if base_font: name_label.add_font_override("font", base_font)
	settings_panel.add_child(name_label)
	
	name_input = LineEdit.new()
	name_input.text = Global.player_name
	var is_name_already_set = Global.has_changed_name
	name_input.editable = not is_name_already_set
	name_input.placeholder_text = "Enter your name..."
	name_input.anchor_left = 0.1
	name_input.anchor_right = 0.9 if is_name_already_set else 0.6
	name_input.margin_top = 430
	name_input.margin_bottom = 480
	name_input.align = LineEdit.ALIGN_CENTER
	if base_font: name_input.add_font_override("font", base_font)
	name_input.connect("text_changed", self, "_on_name_input_changed")
	name_input.connect("text_entered", self, "_on_name_input_entered")
	name_input.connect("focus_exited", self, "_on_name_input_focus_exited")
	settings_panel.add_child(name_input)
 
	name_submit_btn = Button.new()
	name_submit_btn.text = "Set"
	name_submit_btn.anchor_left = 0.65
	name_submit_btn.anchor_right = 0.9
	name_submit_btn.margin_top = 430
	name_submit_btn.margin_bottom = 480
	name_submit_btn.visible = not is_name_already_set
	name_submit_btn.disabled = is_name_already_set
	if base_font: name_submit_btn.add_font_override("font", base_font)
	if close_btn:
		name_submit_btn.add_stylebox_override("normal", close_btn.get_stylebox("normal"))
		name_submit_btn.add_stylebox_override("hover", close_btn.get_stylebox("hover"))
		name_submit_btn.add_stylebox_override("pressed", close_btn.get_stylebox("pressed"))
	name_submit_btn.connect("pressed", self, "_on_name_submit_pressed")
	settings_panel.add_child(name_submit_btn)

	# 2.5 Settings Panel: Player UID Label
	settings_uid_label = Label.new()
	settings_uid_label.align = Label.ALIGN_CENTER
	settings_uid_label.valign = Label.VALIGN_CENTER
	settings_uid_label.margin_top = 500
	settings_uid_label.margin_bottom = 530
	settings_uid_label.anchor_left = 0.1
	settings_uid_label.anchor_right = 0.9
	var uid_font = DynamicFont.new()
	uid_font.font_data = load("res://assets/fonts/Lucida Console Regular.ttf")
	uid_font.size = 18
	settings_uid_label.add_font_override("font", uid_font)
	settings_uid_label.add_color_override("font_color", Color(0.5, 0.9, 0.5))
	settings_panel.add_child(settings_uid_label)
	_update_settings_uid_display()

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
	game_over_name_input.max_length = 25
	game_over_name_input.anchor_left = 0.15
	game_over_name_input.anchor_right = 0.85
	game_over_name_input.margin_top = 200
	game_over_name_input.margin_bottom = 280
	game_over_name_input.align = LineEdit.ALIGN_CENTER
	game_over_name_input.add_stylebox_override("normal", input_style)
	game_over_name_input.add_stylebox_override("focus", input_focus)
	game_over_name_input.add_color_override("placeholder_color", Color(0.6, 0.6, 0.7))
	
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

func _on_name_input_changed(new_text: String):
	pass

func _on_name_input_entered(_new_text: String):
	_on_name_submit_pressed()

func _on_name_input_focus_exited():
	pass # Save will happen when pressing Set or closing panel



func _on_name_submit_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	var typed_name = name_input.text.strip_edges() if name_input else ""
	if typed_name == "" or typed_name == Global.player_name:
		return
		
	Global.player_name = typed_name
	Global.has_changed_name = true
	if name_input:
		name_input.editable = false
		name_input.anchor_right = 0.9
	if name_submit_btn:
		name_submit_btn.disabled = true
		name_submit_btn.visible = false
		
	save_hiscore()
	var current_hiscore = hiscores.get(1, 0)
	if current_hiscore > 0:
		FirebaseManager.submit_score(current_hiscore, 1, Global.player_name)

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
	FirebaseManager.submit_score(score, mode_level, Global.player_name)

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
		
	# Live-refresh the Stats Panel if it's currently open
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node and profile_panel_node.visible:
		_on_ProfileButton_pressed()

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
		
		# Fetch from firestore
		var collection = Firebase.Firestore.collection("rushybird_player_stats")
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
			font.size = 42
			
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
		var t = OS.get_datetime_from_unix_time(timestamp)
		inspector_disclaimer.bbcode_text = "[center]Last Active: %02d-%02d-%04d %02d:%02d[/center]" % [t.day, t.month, t.year, t.hour, t.minute]

func _on_auth_state_changed(is_logged_in: bool):
	_update_settings_uid_display()
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node and profile_panel_node.visible:
		_on_ProfileButton_pressed()
	
	if is_logged_in and not FirebaseManager.is_claiming_profile():
		# Auto-sync stats and scores on startup/login
		FirebaseManager.submit_stats(stats, hiscores, highest_levels, Global.player_name)
		var escalation_hs = hiscores.get(1, 0)
		if escalation_hs > 0:
			FirebaseManager.submit_score(escalation_hs, 1, Global.player_name)

func _update_settings_uid_display():
	if is_instance_valid(settings_uid_label):
		var uid = FirebaseManager.get_current_user_id()
		if uid != "":
			settings_uid_label.text = "UID: " + uid
		else:
			settings_uid_label.text = "UID: Connecting..."

func _get_seasonal_reset_time_string() -> String:
	var now = OS.get_datetime()
	
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
	var target_unix = OS.get_unix_time_from_datetime(target_time_dict)
	
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

var lbl_device_classic: Label
var lbl_device_escalation: Label
var lbl_device_games: Label
var lbl_device_playtime: Label

var lbl_cloud_classic: Label
var lbl_cloud_escalation: Label
var lbl_cloud_games: Label
var lbl_cloud_playtime: Label

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
	title.margin_top = 120
	title.margin_bottom = 220
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button")
	if title_font: title.add_font_override("font", title_font)
	claim_profile_panel.add_child(title)
	
	var input_font = DynamicFont.new()
	input_font.font_data = load("res://assets/fonts/LilitaOne-Regular.ttf")
	input_font.size = 36
	input_font.outline_size = 2
	input_font.outline_color = Color(0.1, 0.1, 0.1, 0.8)
	
	var line_edit_style = StyleBoxFlat.new()
	line_edit_style.bg_color = Color(0.1, 0.1, 0.15, 0.9) # Dark blue/grey input box
	line_edit_style.border_width_left = 3
	line_edit_style.border_width_top = 3
	line_edit_style.border_width_right = 3
	line_edit_style.border_width_bottom = 3
	line_edit_style.border_color = Color(0.2, 0.2, 0.3)
	line_edit_style.corner_radius_top_left = 12
	line_edit_style.corner_radius_top_right = 12
	line_edit_style.corner_radius_bottom_right = 12
	line_edit_style.corner_radius_bottom_left = 12
	line_edit_style.content_margin_left = 20
	line_edit_style.content_margin_right = 20
	
	var line_edit_focus = line_edit_style.duplicate()
	line_edit_focus.border_color = Color(0.4, 0.8, 0.2) # Active green border on focus
	
	claim_email_input = LineEdit.new()
	claim_email_input.placeholder_text = "Email Address"
	claim_email_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	claim_email_input.anchor_left = 0.15
	claim_email_input.anchor_right = 0.85
	claim_email_input.margin_top = 300
	claim_email_input.margin_bottom = 380
	claim_email_input.add_font_override("font", input_font)
	claim_email_input.add_stylebox_override("normal", line_edit_style)
	claim_email_input.add_stylebox_override("focus", line_edit_focus)
	claim_email_input.add_color_override("font_color", Color(1, 1, 1))
	claim_email_input.add_color_override("placeholder_color", Color(0.6, 0.6, 0.7))
	claim_profile_panel.add_child(claim_email_input)
	
	claim_pass_input = LineEdit.new()
	claim_pass_input.placeholder_text = "Password"
	claim_pass_input.secret = true
	claim_pass_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD
	claim_pass_input.anchor_left = 0.15
	claim_pass_input.anchor_right = 0.85
	claim_pass_input.margin_top = 420
	claim_pass_input.margin_bottom = 500
	claim_pass_input.add_font_override("font", input_font)
	claim_pass_input.add_stylebox_override("normal", line_edit_style)
	claim_pass_input.add_stylebox_override("focus", line_edit_focus)
	claim_pass_input.add_color_override("font_color", Color(1, 1, 1))
	claim_pass_input.add_color_override("placeholder_color", Color(0.6, 0.6, 0.7))
	claim_profile_panel.add_child(claim_pass_input)
	
	var btn_submit = Button.new()
	btn_submit.text = "Link Account"
	btn_submit.anchor_left = 0.15
	btn_submit.anchor_right = 0.85
	btn_submit.margin_top = 560
	btn_submit.margin_bottom = 640
	btn_submit.connect("pressed", self, "_on_SubmitClaim_pressed")
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			var green_font = ref_font.duplicate()
			green_font.outline_color = Color(0.2, 0.5, 0.1) # Green outline matching Start button
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

	btn_submit.add_stylebox_override("normal", green_normal)
	btn_submit.add_stylebox_override("hover", green_hover)
	btn_submit.add_stylebox_override("pressed", green_pressed)
	btn_submit.add_color_override("font_color", Color(1, 1, 1))
	btn_submit.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_submit.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	claim_profile_panel.add_child(btn_submit)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.anchor_left = 0.15
	btn_cancel.anchor_right = 0.85
	btn_cancel.margin_top = 680
	btn_cancel.margin_bottom = 760
	btn_cancel.connect("pressed", self, "_on_CancelClaim_pressed")
	
	if ref_btn:
		var ref_font = ref_btn.get_font("font")
		if ref_font:
			btn_cancel.add_font_override("font", ref_font)
			
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

	btn_cancel.add_stylebox_override("normal", red_normal)
	btn_cancel.add_stylebox_override("hover", red_hover)
	btn_cancel.add_stylebox_override("pressed", red_pressed)
	btn_cancel.add_color_override("font_color", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_cancel.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	claim_profile_panel.add_child(btn_cancel)
	
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
	title.margin_bottom = 140
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if title_font:
		title_font.size = 56
		title.add_font_override("font", title_font)
	title.add_color_override("font_color", Color(1.0, 0.85, 0.2)) # Glowing gold/yellow title
	conflict_panel.add_child(title)
	
	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "An existing save file was found for this email.\nChoose which profile you want to keep:"
	subtitle.align = Label.ALIGN_CENTER
	subtitle.anchor_right = 1.0
	subtitle.margin_top = 150
	subtitle.margin_bottom = 230
	var sub_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if sub_font:
		sub_font.size = 32
		subtitle.add_font_override("font", sub_font)
	subtitle.add_color_override("font_color", Color(0.8, 0.8, 0.9))
	conflict_panel.add_child(subtitle)
	
	# Button Group for mutual exclusion
	var btn_group = ButtonGroup.new()
	
	# VBox container for cards
	var cards_vbox = VBoxContainer.new()
	cards_vbox.name = "CardsVBox"
	cards_vbox.anchor_left = 0.5
	cards_vbox.anchor_right = 0.5
	cards_vbox.margin_left = -320
	cards_vbox.margin_right = 320
	cards_vbox.margin_top = 250
	cards_vbox.margin_bottom = 770
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
		label_font.size = 28
		
	var bold_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if bold_font:
		bold_font.size = 32
		
	# Card 1: Device
	card_device = Button.new()
	card_device.toggle_mode = true
	card_device.group = btn_group
	card_device.rect_min_size = Vector2(640, 240)
	card_device.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_device.add_stylebox_override("normal", card_normal)
	card_device.add_stylebox_override("hover", card_hover)
	card_device.add_stylebox_override("pressed", card_selected)
	card_device.add_stylebox_override("focus", card_selected)
	card_device.connect("toggled", self, "_on_ProfileCard_toggled", ["device"])
	
	var vbox_dev = VBoxContainer.new()
	vbox_dev.anchor_right = 1.0
	vbox_dev.anchor_bottom = 1.0
	vbox_dev.margin_left = 25
	vbox_dev.margin_right = -25
	vbox_dev.margin_top = 25
	vbox_dev.margin_bottom = -25
	vbox_dev.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox_dev.alignment = BoxContainer.ALIGN_CENTER
	vbox_dev.set("custom_constants/separation", 10)
	card_device.add_child(vbox_dev)
	
	var header_dev = Label.new()
	header_dev.text = "📱 CURRENT DEVICE PROFILE"
	header_dev.align = Label.ALIGN_CENTER
	header_dev.mouse_filter = Control.MOUSE_FILTER_PASS
	if bold_font: header_dev.add_font_override("font", bold_font)
	header_dev.add_color_override("font_color", Color(0.4, 0.8, 1.0))
	vbox_dev.add_child(header_dev)
	
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
	card_cloud.rect_min_size = Vector2(640, 240)
	card_cloud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_cloud.add_stylebox_override("normal", card_normal)
	card_cloud.add_stylebox_override("hover", card_hover)
	card_cloud.add_stylebox_override("pressed", card_selected)
	card_cloud.add_stylebox_override("focus", card_selected)
	card_cloud.connect("toggled", self, "_on_ProfileCard_toggled", ["cloud"])
	
	var vbox_cld = VBoxContainer.new()
	vbox_cld.anchor_right = 1.0
	vbox_cld.anchor_bottom = 1.0
	vbox_cld.margin_left = 25
	vbox_cld.margin_right = -25
	vbox_cld.margin_top = 25
	vbox_cld.margin_bottom = -25
	vbox_cld.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox_cld.alignment = BoxContainer.ALIGN_CENTER
	vbox_cld.set("custom_constants/separation", 10)
	card_cloud.add_child(vbox_cld)
	
	var header_cld = Label.new()
	header_cld.text = "☁️ ONLINE CLOUD PROFILE"
	header_cld.align = Label.ALIGN_CENTER
	header_cld.mouse_filter = Control.MOUSE_FILTER_PASS
	if bold_font: header_cld.add_font_override("font", bold_font)
	header_cld.add_color_override("font_color", Color(0.5, 0.9, 0.6))
	vbox_cld.add_child(header_cld)
	
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
	warn_lbl.margin_top = 790
	warn_lbl.margin_bottom = 840
	var warn_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if warn_font:
		warn_font.size = 26
		warn_lbl.add_font_override("font", warn_font)
	warn_lbl.add_color_override("font_color", Color(0.9, 0.6, 0.2))
	conflict_panel.add_child(warn_lbl)
	
	# Keep Selected Save Button
	btn_keep_selected = Button.new()
	btn_keep_selected.text = "Keep Selected Save"
	btn_keep_selected.anchor_left = 0.15
	btn_keep_selected.anchor_right = 0.85
	btn_keep_selected.margin_top = 855
	btn_keep_selected.margin_bottom = 935
	btn_keep_selected.connect("pressed", self, "_on_KeepSelected_pressed")
	btn_keep_selected.disabled = true
	btn_keep_selected.modulate.a = 0.5
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	var ref_font = ref_btn.get_font("font") if ref_btn else null
	if ref_font:
		var green_font = ref_font.duplicate()
		green_font.outline_color = Color(0.2, 0.5, 0.1)
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
	btn_cancel.anchor_left = 0.15
	btn_cancel.anchor_right = 0.85
	btn_cancel.margin_top = 955
	btn_cancel.margin_bottom = 1035
	btn_cancel.connect("pressed", self, "_on_ConflictCancel_pressed")
	if ref_font:
		btn_cancel.add_font_override("font", ref_font)
		
	var red_normal = StyleBoxFlat.new()
	red_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_normal.anti_aliasing = true
	red_normal.corner_radius_top_left = 20
	red_normal.corner_radius_top_right = 20
	red_normal.corner_radius_bottom_right = 20
	red_normal.corner_radius_bottom_left = 20
	red_normal.border_width_bottom = 8
	red_normal.border_color = Color(0.65, 0.2, 0.2)
	
	var red_hover = red_normal.duplicate()
	red_hover.bg_color = Color(0.85, 0.3, 0.35)
	red_hover.border_color = Color(0.7, 0.25, 0.25)
	
	var red_pressed = red_normal.duplicate()
	red_pressed.bg_color = Color(0.7, 0.2, 0.25)
	red_pressed.border_width_top = 4
	red_pressed.border_width_bottom = 4
	red_pressed.border_color = Color(0.55, 0.15, 0.18)
	
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
	FirebaseManager.start_profile_claim_email(email, password, stats, hiscores, highest_levels, Global.player_name)
	claim_profile_panel.visible = false

func _on_GoogleClaim_pressed():
	FirebaseManager.start_google_login(stats, hiscores, highest_levels, Global.player_name)
	claim_profile_panel.visible = false

func _on_profile_claim_conflict(_guest_stats, _cloud_stats):
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
	var dev_classic = int(FirebaseManager.cached_guest_hiscores.get(0, 0))
	var dev_escalation = int(FirebaseManager.cached_guest_hiscores.get(1, 0))
	var dev_level = int(FirebaseManager.cached_guest_highest_levels.get(1, 1))
	var dev_games = int(FirebaseManager.cached_guest_stats.get("total_games", 0))
	var dev_playtime_sec = float(FirebaseManager.cached_guest_stats.get("playtime", 0.0))
	
	var dev_hours = int(dev_playtime_sec / 3600.0)
	var dev_mins = int((int(dev_playtime_sec) % 3600) / 60.0)
	var dev_playtime_str = ""
	if dev_hours > 0:
		dev_playtime_str = str(dev_hours) + "h " + str(dev_mins) + "m"
	else:
		dev_playtime_str = str(dev_mins) + "m"
		
	if lbl_device_classic:
		lbl_device_classic.text = "Classic High Score: " + str(dev_classic)
	if lbl_device_escalation:
		lbl_device_escalation.text = "Escalation High Score: " + str(dev_escalation) + " (Lvl " + str(dev_level) + ")"
	if lbl_device_games:
		lbl_device_games.text = "Games Played: " + str(dev_games)
	if lbl_device_playtime:
		lbl_device_playtime.text = "Playtime: " + dev_playtime_str
		
	# 3. Format Cloud Stats
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

func _on_profile_claim_succeeded(cloud_stats = {}):
	if typeof(cloud_stats) == TYPE_DICTIONARY and not cloud_stats.empty():
		hiscores[0] = int(cloud_stats.get("classic_highscore", 0))
		hiscores[1] = int(cloud_stats.get("escalation_highscore", 0))
		highest_levels[0] = 1
		highest_levels[1] = int(cloud_stats.get("escalation_highest_level", 1))
		stats["total_games"] = int(cloud_stats.get("total_games", 0))
		stats["high_score"] = hiscores[mode_level]
		stats["playtime"] = float(cloud_stats.get("playtime", 0.0))
		stats["total_deaths"] = int(cloud_stats.get("total_deaths", 0))
		stats["total_revives"] = int(cloud_stats.get("total_revives", 0))
		stats["total_distance"] = float(cloud_stats.get("total_distance", 0.0))
		
		var c_name = cloud_stats.get("player_name", "")
		if c_name != "":
			Global.player_name = c_name
			Global.has_changed_name = true
			
		save_hiscore()
		update_score_display()
	else:
		save_hiscore()
		update_score_display()

	if active_panel_name == "profile":
		active_panel_name = ""
		_on_ProfileButton_pressed()
	
	print("Profile Claim Succeeded!")

func _on_profile_claim_failed(reason):
	print("Profile Claim Failed: ", reason)
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.show()

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
	title.margin_top = 120
	title.margin_bottom = 220
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button")
	if title_font: title.add_font_override("font", title_font)
	manage_account_panel.add_child(title)
	
	var ref_btn = $UI/Control/SettingsPanel/CloseSettings
	var ref_font = null
	if ref_btn:
		ref_font = ref_btn.get_font("font")
		
	var btn_unlink = Button.new()
	btn_unlink.text = "Unlink Account"
	btn_unlink.anchor_left = 0.15
	btn_unlink.anchor_right = 0.85
	btn_unlink.margin_top = 300
	btn_unlink.margin_bottom = 380
	btn_unlink.disabled = true
	if ref_font:
		btn_unlink.add_font_override("font", ref_font)
	manage_account_panel.add_child(btn_unlink)
	
	var btn_logout = Button.new()
	btn_logout.text = "Logout"
	btn_logout.anchor_left = 0.15
	btn_logout.anchor_right = 0.85
	btn_logout.margin_top = 430
	btn_logout.margin_bottom = 510
	btn_logout.connect("pressed", self, "_on_Logout_pressed")
	if ref_font:
		btn_logout.add_font_override("font", ref_font)
		
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

	btn_logout.add_stylebox_override("normal", red_normal)
	btn_logout.add_stylebox_override("hover", red_hover)
	btn_logout.add_stylebox_override("pressed", red_pressed)
	btn_logout.add_color_override("font_color", Color(1, 1, 1))
	btn_logout.add_color_override("font_color_hover", Color(1, 1, 1))
	btn_logout.add_color_override("font_color_pressed", Color(0.9, 0.9, 0.9))
	manage_account_panel.add_child(btn_logout)
	
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancel"
	btn_cancel.anchor_left = 0.15
	btn_cancel.anchor_right = 0.85
	btn_cancel.margin_top = 560
	btn_cancel.margin_bottom = 640
	btn_cancel.connect("pressed", self, "_on_CancelManage_pressed")
	if ref_font:
		btn_cancel.add_font_override("font", ref_font)
		
	btn_cancel.add_stylebox_override("normal", red_normal)
	btn_cancel.add_stylebox_override("hover", red_hover)
	btn_cancel.add_stylebox_override("pressed", red_pressed)
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
	manage_account_panel.visible = true

func _on_CancelManage_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
	manage_account_panel.visible = false
	var profile_panel_node = $UI/Control.get_node_or_null("ProfilePanel")
	if profile_panel_node:
		profile_panel_node.show()

func _on_Logout_pressed():
	if is_instance_valid(ui_button_click):
		ui_button_click.play()
		
	# Reset local variables
	hiscores = {0: 0, 1: 0}
	highest_levels = {0: 1, 1: 1}
	stats = {
		"total_games": 0,
		"high_score": 0,
		"playtime": 0.0,
		"total_deaths": 0,
		"total_revives": 0,
		"total_distance": 0.0
	}
	Global.player_name = ""
	Global.has_changed_name = false
	
	randomize()
	Global.player_name = "Player" + str(randi() % 900000 + 100000)
	
	# Logout from firebase & clear credentials
	Firebase.Auth.logout()
	FirebaseManager.is_logged_in = false
	FirebaseManager.user_id = ""
	
	var dir = Directory.new()
	if dir.file_exists("user://user.auth"):
		dir.remove("user://user.auth")
		
	save_hiscore()
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
	card.margin_left = -300
	card.margin_right = 300
	card.margin_top = -210
	card.margin_bottom = 210
	
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
	title.margin_bottom = 90
	var title_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if title_font:
		title_font.size = 42
		title.add_font_override("font", title_font)
	title.add_color_override("font_color", Color(0.9, 0.3, 0.3)) # Danger red
	card.add_child(title)
	
	# Msg
	var msg = Label.new()
	msg.text = "Permanently overwrite your profile?\nThis cannot be undone."
	msg.align = Label.ALIGN_CENTER
	msg.anchor_right = 1.0
	msg.margin_top = 110
	msg.margin_bottom = 200
	var msg_font = load("res://resources/Theme.tres").get_font("font", "Button").duplicate()
	if msg_font:
		msg_font.size = 30
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
	btn_confirm.margin_top = 220
	btn_confirm.margin_bottom = 295
	btn_confirm.connect("pressed", self, "_on_OverwriteConfirm_pressed")
	if ref_font:
		btn_confirm.add_font_override("font", ref_font)
		
	var red_normal = StyleBoxFlat.new()
	red_normal.bg_color = Color(0.8, 0.25, 0.3)
	red_normal.anti_aliasing = true
	red_normal.corner_radius_top_left = 15
	red_normal.corner_radius_top_right = 15
	red_normal.corner_radius_bottom_right = 15
	red_normal.corner_radius_bottom_left = 15
	red_normal.border_width_bottom = 6
	red_normal.border_color = Color(0.65, 0.2, 0.2)
	
	var red_hover = red_normal.duplicate()
	red_hover.bg_color = Color(0.85, 0.3, 0.35)
	red_hover.border_color = Color(0.7, 0.25, 0.25)
	
	var red_pressed = red_normal.duplicate()
	red_pressed.bg_color = Color(0.7, 0.2, 0.25)
	red_pressed.border_width_top = 3
	red_pressed.border_width_bottom = 3
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
	btn_cancel.margin_top = 310
	btn_cancel.margin_bottom = 385
	btn_cancel.connect("pressed", self, "_on_OverwriteCancel_pressed")
	if ref_font:
		var green_font = ref_font.duplicate()
		green_font.outline_color = Color(0.2, 0.5, 0.1)
		btn_cancel.add_font_override("font", green_font)
		
	var green_normal = StyleBoxFlat.new()
	green_normal.bg_color = Color(0.4, 0.8, 0.2)
	green_normal.anti_aliasing = true
	green_normal.corner_radius_top_left = 15
	green_normal.corner_radius_top_right = 15
	green_normal.corner_radius_bottom_right = 15
	green_normal.corner_radius_bottom_left = 15
	green_normal.border_width_bottom = 6
	green_normal.border_color = Color(0.3, 0.6, 0.15)
	
	var green_hover = green_normal.duplicate()
	green_hover.bg_color = Color(0.45, 0.85, 0.25)
	green_hover.border_color = Color(0.35, 0.65, 0.18)
	
	var green_pressed = green_normal.duplicate()
	green_pressed.bg_color = Color(0.35, 0.7, 0.15)
	green_pressed.border_width_top = 3
	green_pressed.border_width_bottom = 3
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
	if selected_profile_type == "device":
		FirebaseManager.resolve_conflict_overwrite_cloud()
	elif selected_profile_type == "cloud":
		FirebaseManager.resolve_conflict_discard_guest()
