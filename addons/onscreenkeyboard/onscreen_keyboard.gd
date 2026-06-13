tool
extends Panel



###########################
## SETTINGS
###########################

export (bool) var autoShow = true
export (float) var custom_show_y = -1.0
export (float) var custom_hide_y = -1.0
export (float) var bottom_safety_margin = 80.0
export (float) var side_margin = 16.0
export (String, FILE, "*.json") var customLayoutFile = null
export (StyleBoxFlat) var styleBackground = null
export (StyleBoxFlat) var styleHover = null
export (StyleBoxFlat) var stylePressed = null
export (StyleBoxFlat) var styleNormal = null
export (StyleBoxFlat) var styleSpecialKeys = null
export (DynamicFont) var font = null
export (Color) var fontColor = Color(1,1,1)
export (Color) var fontColorHover = Color(1,1,1)
export (Color) var fontColorPressed = Color(1,1,1)

var active_field: LineEdit = null setget set_active_field

###########################
## SIGNALS
###########################

signal visibilityChanged
signal layoutChanged
signal key_released(keyValue)


###########################
## PANEL 
###########################

func _enter_tree():
	get_tree().get_root().connect("size_changed", self, "size_changed")
	_initKeyboard()
	set_process(true)
	
	# Instantiate Audio Player for key click sounds
	click_sound = AudioStreamPlayer.new()
	click_sound.stream = load("res://assets/sounds/ui_button_click.wav")
	click_sound.volume_db = -6.0
	add_child(click_sound)

func _exit_tree():
	if get_tree() and get_tree().get_root().is_connected("size_changed", self, "size_changed"):
		get_tree().get_root().disconnect("size_changed", self, "size_changed")


###########################
##  FOCUS PROCESS & CARET TRACKING (MODIFIED)
###########################
# NOTE: Custom caret/cursor tracking implemented to support both onscreen and native physical keyboard input.
# Default native cursor/caret is buggy across platforms (Windows, Linux, Android, iOS), so the native
# cursor color is overridden to transparent and a custom blinking caret is drawn instead.



var last_focused_field: LineEdit = null

func _process(delta):
	_update_carets_for_focus()

func _update_carets_for_focus():
	var focus_owner = get_focus_owner()
	var current_focused: LineEdit = null
	
	if focus_owner and focus_owner.get_class() == "LineEdit":
		current_focused = focus_owner
		
	if last_focused_field != current_focused:
		var old = last_focused_field
		last_focused_field = current_focused
		if is_instance_valid(old):
			_update_custom_caret_for_field(old)
			
	if is_instance_valid(current_focused):
		_update_custom_caret_for_field(current_focused)
		
	if is_instance_valid(active_field) and active_field != current_focused:
		_update_custom_caret_for_field(active_field)

func _input(event):
	_updateAutoDisplayOnInput(event)
	
	if visible and is_instance_valid(active_field) and event is InputEventKey and event.pressed:
		var scancode = event.scancode
		if scancode == KEY_LEFT:
			_process_key_input_for_field(active_field, "LeftArrow")
			get_tree().set_input_as_handled()
		elif scancode == KEY_RIGHT:
			_process_key_input_for_field(active_field, "RightArrow")
			get_tree().set_input_as_handled()
		elif scancode == KEY_BACKSPACE:
			_process_key_input_for_field(active_field, "Backspace")
			get_tree().set_input_as_handled()
		elif scancode == KEY_ENTER:
			_process_key_input_for_field(active_field, "Return")
			emit_signal("key_released", "Return")
			get_tree().set_input_as_handled()
		elif event.unicode != 0 and event.unicode >= 32 and event.unicode != 127:
			var char_str = char(event.unicode)
			_process_key_input_for_field(active_field, char_str)
			get_tree().set_input_as_handled()

func size_changed():
	if autoShow:
		_hideKeyboard()


###########################
## INIT
###########################
var KeyboardButton
var KeyListHandler
var click_sound

var layouts = []
var keys = []
var capslockKeys = []
var uppercase = false

var tweenPosition
var tweenSpeed = .2

func _initKeyboard():

	if customLayoutFile == null:
		var defaultLayout = preload("default_layout.gd").new()
		_createKeyboard(defaultLayout.data)
	else:
		_createKeyboard(_loadJSON(customLayoutFile))
	
	tweenPosition = Tween.new()
	add_child(tweenPosition)
	
	if autoShow:
		_hideKeyboard()


###########################
## HIDE/SHOW
###########################

var focusObject = null

func show():
	_showKeyboard()
	
func hide():
	_hideKeyboard()

var released = true
func _updateAutoDisplayOnInput(event):
	if autoShow == false:
		return
	
	if event is InputEventMouseButton:
		released = !released
		if released == false:
			return
		
		var focusObject = get_focus_owner()
		if focusObject != null:
			var clickOnInput = Rect2(focusObject.rect_global_position,focusObject.rect_size).has_point(get_global_mouse_position())
			var clickOnKeyboard = Rect2(rect_global_position,rect_size).has_point(get_global_mouse_position())
			
			if clickOnInput:
				if isKeyboardFocusObject(focusObject):
					_showKeyboard()
			elif clickOnKeyboard:
				_showKeyboard()
			else:
				_hideKeyboard()
					
	if event is InputEventKey:
		var focusObject = get_focus_owner()
		if focusObject != null:
			if event.scancode == KEY_ENTER:
				if isKeyboardFocusObjectCompleteOnEnter(focusObject):
					_hideKeyboard()


func _hideKeyboard(keyData=null):
	var target_y = custom_hide_y
	if target_y < 0:
		target_y = get_viewport().get_visible_rect().size.y + 10
	if is_instance_valid(tweenPosition):
		tweenPosition.interpolate_property(self,"rect_position",rect_position, Vector2(rect_position.x, target_y), tweenSpeed, Tween.TRANS_SINE, Tween.EASE_OUT)
		tweenPosition.start()
	else:
		rect_position.y = target_y
	#grab_focus()
	
	if is_instance_valid(active_field):
		var caret = active_field.get_node_or_null("CustomCaret")
		if caret:
			caret.visible = false
			var timer = caret.get_node_or_null("BlinkTimer")
			if timer:
				timer.stop()
	active_field = null
	
	_setCapsLock(false)
	emit_signal("visibilityChanged",false)


func _showKeyboard(keyData=null):
	var target_y = custom_show_y
	if target_y < 0:
		target_y = get_viewport().get_visible_rect().size.y - rect_size.y
	if is_instance_valid(tweenPosition):
		tweenPosition.interpolate_property(self,"rect_position",rect_position, Vector2(rect_position.x, target_y), tweenSpeed, Tween.TRANS_SINE, Tween.EASE_OUT)
		tweenPosition.start()
	else:
		rect_position.y = target_y
	emit_signal("visibilityChanged",true)
	if is_instance_valid(active_field):
		_update_custom_caret_for_field(active_field)


###########################
##  KEY LAYOUT
###########################

var prevPrevLayout = null
var previousLayout = null
var currentLayout = null

func setActiveLayoutByName(name):
	for layout in layouts:
		if layout.hint_tooltip == str(name):
			_showLayout(layout)
		else:
			_hideLayout(layout)


func _showLayout(layout):
	layout.show()
	currentLayout = layout
	


func _hideLayout(layout):
	layout.hide()


func _switchLayout(keyData):	
	prevPrevLayout = previousLayout
	previousLayout = currentLayout
	emit_signal("layoutChanged", keyData.get("layout-name"))
	
	for layout in layouts:
		_hideLayout(layout)
	
	if keyData.get("layout-name") == "PREVIOUS-LAYOUT":
		if prevPrevLayout != null:
			_showLayout(prevPrevLayout)
			return
	
	for layout in layouts:
		if layout.hint_tooltip == keyData.get("layout-name"):
			_showLayout(layout)
			return
	
	_setCapsLock(false)
	
	

###########################
## KEY EVENTS
###########################

func _setCapsLock(value):
	uppercase = value
	for key in capslockKeys:
		if value:
			if key.get_draw_mode() != BaseButton.DRAW_PRESSED:
				key.pressed = !key.pressed
		else:
			if key.get_draw_mode() == BaseButton.DRAW_PRESSED:
				key.pressed = !key.pressed
				
	for key in keys:
		key.changeUppercase(value)


func _triggerUppercase(keyData):
	uppercase = !uppercase
	_setCapsLock(uppercase)


func _keyReleased(keyData):
	if is_instance_valid(click_sound):
		click_sound.play()
	
	if keyData.has("output"):
		var keyValue = keyData.get("output")
		emit_signal("key_released", keyValue)
		
		if is_instance_valid(active_field):
			_process_key_input_for_field(active_field, keyValue)
		else:
			###########################
			## DISPATCH InputEvent 
			###########################
			var inputEventKey = InputEventKey.new()
			inputEventKey.shift = uppercase
			inputEventKey.alt = false
			inputEventKey.meta = false
			inputEventKey.command = false
			inputEventKey.pressed = true
			
			var keyUnicode = KeyListHandler.getUnicodeFromString(keyValue)
			if uppercase==false and KeyListHandler.hasLowercase(keyValue):
				keyUnicode +=32
			inputEventKey.unicode = keyUnicode
			inputEventKey.scancode = KeyListHandler.getScancodeFromString(keyValue)
			get_tree().input_event(inputEventKey)
		
		###########################
		## DISABLE CAPSLOCK AFTER 
		###########################
		_setCapsLock(false)


###########################
## CONSTRUCT KEYBOARD
###########################

func _setKeyStyle(styleName, key, style):
	if style != null:
		key.set('custom_styles/'+styleName, style)

func _createKeyboard(layoutData):
	if layoutData == null:
		print("ERROR. No layout file found")
		return
	
	KeyListHandler = preload("keylist.gd").new()
	KeyboardButton = preload("keyboard_button.gd")
	
	var ICON_DELETE = preload("icons/delete.png")
	var ICON_SHIFT = preload("icons/shift.png")
	var ICON_LEFT = preload("icons/left.png")
	var ICON_RIGHT = preload("icons/right.png")
	var ICON_HIDE = preload("icons/hide.png")
	var ICON_ENTER = preload("icons/enter.png")
	
	var data = layoutData
	
	if styleBackground != null:
		set('custom_styles/panel', styleBackground)
	
	var index = 0
	for layout in data.get("layouts"):

		var layoutContainer = PanelContainer.new()
		
		var empty_style = StyleBoxEmpty.new()
		layoutContainer.set('custom_styles/panel', empty_style)
		
		# SHOW FIRST LAYOUT ON DEFAULT
		if index > 0:
			layoutContainer.hide()
		else:
			currentLayout = layoutContainer
		
		layoutContainer.hint_tooltip = layout.get("name")
		layoutContainer.anchor_left = 0.0
		layoutContainer.anchor_right = 1.0
		layoutContainer.anchor_top = 0.0
		layoutContainer.anchor_bottom = 1.0
		layoutContainer.margin_top = 100
		layoutContainer.margin_bottom = -bottom_safety_margin
		layoutContainer.margin_left = side_margin
		layoutContainer.margin_right = -side_margin
		layouts.push_back(layoutContainer)
		add_child(layoutContainer)
		
		var baseVbox = VBoxContainer.new()
		baseVbox.size_flags_horizontal = SIZE_EXPAND_FILL
		baseVbox.size_flags_vertical = SIZE_EXPAND_FILL
		baseVbox.add_constant_override("separation", 14)
		
		for row in layout.get("rows"):

			var keyRow = HBoxContainer.new()
			keyRow.size_flags_horizontal = SIZE_EXPAND_FILL
			keyRow.size_flags_vertical = SIZE_EXPAND_FILL
			keyRow.add_constant_override("separation", 12)
			
			for key in row.get("keys"):
				var newKey = KeyboardButton.new(key)
				
				_setKeyStyle("normal",newKey, styleNormal)
				_setKeyStyle("hover",newKey, styleHover)
				_setKeyStyle("pressed",newKey, stylePressed)
					
				if font != null:
					newKey.set('custom_fonts/font', font)
				if fontColor != null:
					newKey.set('custom_colors/font_color', fontColor)
					newKey.set('custom_colors/font_color_hover', fontColorHover)
					newKey.set('custom_colors/font_color_pressed', fontColorPressed)
					newKey.set('custom_colors/font_color_disabled', fontColor)
					
				newKey.connect("released",self,"_keyReleased")
				
				if key.has("type"):
					if key.get("type") == "switch-layout":
						newKey.connect("released",self,"_switchLayout")
						_setKeyStyle("normal",newKey, styleSpecialKeys)
					elif key.get("type") == "special":
						_setKeyStyle("normal",newKey, styleSpecialKeys)
					elif key.get("type") == "special-shift":
						newKey.connect("released",self,"_triggerUppercase")
						newKey.toggle_mode = true
						capslockKeys.push_back(newKey)
						_setKeyStyle("normal",newKey, styleSpecialKeys)
					elif key.get("type") == "special-hide-keyboard":
						newKey.connect("released",self,"_hideKeyboard")
						_setKeyStyle("normal",newKey, styleSpecialKeys)
				
				# SET ICONS
				if key.has("display-icon"):
					var iconData = str(key.get("display-icon")).split(":")
					# PREDEFINED
					if str(iconData[0])=="PREDEFINED":
						if str(iconData[1])=="DELETE":
							newKey.setIcon(ICON_DELETE)
						elif str(iconData[1])=="SHIFT":
							newKey.setIcon(ICON_SHIFT)
						elif str(iconData[1])=="LEFT":
							newKey.setIcon(ICON_LEFT)
						elif str(iconData[1])=="RIGHT":
							newKey.setIcon(ICON_RIGHT)
						elif str(iconData[1])=="HIDE":
							newKey.setIcon(ICON_HIDE)
						elif str(iconData[1])=="ENTER":
							newKey.setIcon(ICON_ENTER)
					# CUSTOM
					if str(iconData[0])=="res":
						print(key.get("display-icon"))
						var texture = load(key.get("display-icon"))
						newKey.setIcon(texture)
						
					if fontColor != null:
						newKey.setIconColor(fontColor)
				
				keyRow.add_child(newKey)
				keys.push_back(newKey)
				
			baseVbox.add_child(keyRow)
		
		layoutContainer.add_child(baseVbox)
		index+=1


###########################
## LOAD SETTINGS
###########################

func _loadJSON(filePath):
	var content = JSON.parse(_loadFile(filePath))
	
	if content.error == OK:
		return content.result
	else:
		print("!JSON PARSE ERROR!")
		return null


func _loadFile(filePath):
	var file = File.new()
	var error = file.open(filePath, file.READ)
	
	if error != 0:
		print("Error loading File. Error: "+str(error))
	
	var content = file.get_as_text()
	file.close()
	return content


###########################
## HELPER
###########################

func isKeyboardFocusObjectCompleteOnEnter(focusObject):
	if focusObject.get_class() == "LineEdit":
		return true
	return false

func isKeyboardFocusObject(focusObject):
	if focusObject.get_class() == "LineEdit" or focusObject.get_class() == "TextEdit":
		return true
	return false


###########################
##  CUSTOM CARET & BLINKING (MODIFIED)
###########################

func set_active_field(field: LineEdit):
	if active_field == field:
		_update_custom_caret_for_field(active_field)
		return
		
	var old_field = active_field
	active_field = field
	
	if is_instance_valid(old_field):
		_update_custom_caret_for_field(old_field)
	if is_instance_valid(active_field):
		_update_custom_caret_for_field(active_field)

func _process_key_input_for_field(field: LineEdit, key_value: String):
	var text = field.text
	var cursor_pos = field.caret_position
	
	if key_value == "Backspace":
		if cursor_pos > 0:
			var left = text.substr(0, cursor_pos - 1)
			var right = text.substr(cursor_pos)
			field.text = left + right
			field.caret_position = cursor_pos - 1
			field.emit_signal("text_changed", field.text)
	elif key_value == "Return":
		field.emit_signal("text_entered", field.text)
	elif key_value == "Space":
		var left = text.substr(0, cursor_pos)
		var right = text.substr(cursor_pos)
		field.text = left + " " + right
		field.caret_position = cursor_pos + 1
		field.emit_signal("text_changed", field.text)
	elif key_value == "LeftArrow":
		if cursor_pos > 0:
			field.caret_position = cursor_pos - 1
	elif key_value == "RightArrow":
		if cursor_pos < text.length():
			field.caret_position = cursor_pos + 1
	else:
		# Standard character, check uppercase
		var actual_char = key_value
		if key_value.length() == 1:
			if uppercase:
				actual_char = key_value.to_upper()
			else:
				actual_char = key_value.to_lower()
				
		var left = text.substr(0, cursor_pos)
		var right = text.substr(cursor_pos)
		field.text = left + actual_char + right
		field.caret_position = cursor_pos + actual_char.length()
		field.emit_signal("text_changed", field.text)

	_update_custom_caret_for_field(field)

func _update_custom_caret_for_field(field: LineEdit):
	if not is_instance_valid(field):
		return
		
	var caret = field.get_node_or_null("CustomCaret")
	var is_active = (active_field == field and visible)
	var is_focused = field.has_focus()
	var should_show = (is_active or is_focused) and field.is_visible_in_tree()
	
	if not should_show:
		if caret:
			caret.visible = false
			var timer = caret.get_node_or_null("BlinkTimer")
			if timer:
				timer.stop()
		return
		
	# Hide native cursor
	field.add_color_override("cursor_color", Color(0, 0, 0, 0))
	
	if not caret:
		caret = ColorRect.new()
		caret.name = "CustomCaret"
		caret.rect_min_size = Vector2(3, 0)
		caret.color = Color(1, 1, 1)
		caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
		field.add_child(caret)
		
		var blink_timer = Timer.new()
		blink_timer.name = "BlinkTimer"
		blink_timer.wait_time = 0.5
		blink_timer.autostart = true
		caret.add_child(blink_timer)
		blink_timer.connect("timeout", self, "_on_custom_caret_blink_timeout", [caret])
	
	# Start timer if stopped
	var timer = caret.get_node_or_null("BlinkTimer")
	if timer:
		var last_pos = caret.get_meta("last_pos") if caret.has_meta("last_pos") else -1
		var last_text = caret.get_meta("last_text") if caret.has_meta("last_text") else ""
		if last_pos != field.caret_position or last_text != field.text:
			timer.start()
			caret.visible = true
			caret.set_meta("last_pos", field.caret_position)
			caret.set_meta("last_text", field.text)
		elif timer.is_stopped():
			timer.start()
			caret.visible = true
			
	# Position calculation
	var font = field.get_font("font")
	if not font:
		return
		
	var text = field.text
	var caret_pos = clamp(field.caret_position, 0, text.length())
	var substring = text.substr(0, caret_pos)
	if "secret" in field and field.secret:
		var mask_char = field.secret_character if ("secret_character" in field) else "*"
		substring = ""
		for i in range(caret_pos):
			substring += mask_char
	var text_width = font.get_string_size(substring).x
	if font is DynamicFont:
		text_width -= font.outline_size * 0.27 * caret_pos
	
	var start_x = 0.0
	if field.align == LineEdit.ALIGN_LEFT:
		var stylebox = field.get_stylebox("normal")
		if stylebox:
			start_x = stylebox.content_margin_left
		else:
			start_x = 30.0
	elif field.align == LineEdit.ALIGN_CENTER:
		var total_text_width = font.get_string_size(substring if "secret" in field and field.secret else text).x
		if "secret" in field and field.secret:
			var mask_char = field.secret_character if ("secret_character" in field) else "*"
			var secret_text = ""
			for i in range(text.length()):
				secret_text += mask_char
			total_text_width = font.get_string_size(secret_text).x
		start_x = (field.rect_size.x - total_text_width) / 2.0
	elif field.align == LineEdit.ALIGN_RIGHT:
		var total_text_width = font.get_string_size(substring if "secret" in field and field.secret else text).x
		if "secret" in field and field.secret:
			var mask_char = field.secret_character if ("secret_character" in field) else "*"
			var secret_text = ""
			for i in range(text.length()):
				secret_text += mask_char
			total_text_width = font.get_string_size(secret_text).x
		var margin_right = 30.0
		var stylebox = field.get_stylebox("normal")
		if stylebox:
			margin_right = stylebox.content_margin_right
		start_x = field.rect_size.x - total_text_width - margin_right
		
	var caret_height = font.get_height()
	if caret_height <= 0:
		caret_height = font.size
		
	var caret_y = (field.rect_size.y - caret_height) / 2.0
	caret.rect_size = Vector2(3, caret_height)
	caret.rect_position = Vector2(start_x + text_width, caret_y)

func _on_custom_caret_blink_timeout(caret: ColorRect):
	if is_instance_valid(caret) and caret.is_inside_tree():
		var parent = caret.get_parent()
		if parent and parent.is_visible_in_tree():
			caret.visible = not caret.visible

func handle_input_click(field: LineEdit, local_x: float):
	if not is_instance_valid(field):
		return
		
	var font = field.get_font("font")
	if not font:
		return
		
	var text = field.text
	var text_to_measure = text
	if "secret" in field and field.secret:
		var mask_char = field.secret_character if ("secret_character" in field) else "*"
		text_to_measure = ""
		for i in range(text.length()):
			text_to_measure += mask_char
			
	var start_x = 0.0
	if field.align == LineEdit.ALIGN_LEFT:
		var stylebox = field.get_stylebox("normal")
		if stylebox:
			start_x = stylebox.content_margin_left
		else:
			start_x = 30.0
	elif field.align == LineEdit.ALIGN_CENTER:
		var total_text_width = font.get_string_size(text_to_measure).x
		start_x = (field.rect_size.x - total_text_width) / 2.0
	elif field.align == LineEdit.ALIGN_RIGHT:
		var total_text_width = font.get_string_size(text_to_measure).x
		var margin_right = 30.0
		var stylebox = field.get_stylebox("normal")
		if stylebox:
			margin_right = stylebox.content_margin_right
		start_x = field.rect_size.x - total_text_width - margin_right
		
	var best_index = 0
	var min_diff = 999999.0
	
	for i in range(text_to_measure.length() + 1):
		var substring = text_to_measure.substr(0, i)
		var char_x = start_x + font.get_string_size(substring).x
		if font is DynamicFont:
			char_x -= font.outline_size * 0.27 * i
		var diff = abs(char_x - local_x)
		if diff < min_diff:
			min_diff = diff
			best_index = i
		else:
			break
			
	field.caret_position = best_index
	_update_custom_caret_for_field(field)




