tool
extends EditorExportPlugin

func _export_begin(features: PoolStringArray, is_debug: bool, path: String, flags: int):
	# Only execute this copy routine if exporting an HTML5 build
	if path.ends_with(".html"):
		var base_dir = path.get_base_dir()
		var dir = Directory.new()
		
		# Copy and customize serve.js
		var source_file = File.new()
		if source_file.open("res://addons/local-server/serve.js", File.READ) == OK:
			var content = source_file.get_as_text()
			source_file.close()
			
			var game_name = ProjectSettings.get_setting("application/config/name")
			if game_name == null or game_name == "":
				game_name = "Godot Web Game"
				
			var game_version = ProjectSettings.get_setting("application/config/version")
			if game_version == null or game_version == "":
				game_version = "1.0.0"
				
			var godot_version = Engine.get_version_info().string
				
			var datetime = OS.get_datetime()
			var build_time = "%04d-%02d-%02d %02d:%02d:%02d" % [datetime.year, datetime.month, datetime.day, datetime.hour, datetime.minute, datetime.second]
			
			content = content.replace("{{GAME_NAME}}", game_name)
			content = content.replace("{{GAME_VERSION}}", game_version)
			content = content.replace("{{GODOT_VERSION}}", godot_version)
			content = content.replace("{{BUILD_TIME}}", build_time)
			
			var dest_file = File.new()
			if dest_file.open(base_dir + "/serve.js", File.WRITE) == OK:
				dest_file.store_string(content)
				dest_file.close()
				print("Local Server: Successfully copied and customized serve.js in " + base_dir)
			else:
				printerr("Local Server: Failed to write serve.js in " + base_dir)
		else:
			printerr("Local Server: Failed to open source serve.js")
		
		# Copy and customize play.bat
		var bat_source = File.new()
		if bat_source.open("res://addons/local-server/play.bat", File.READ) == OK:
			var content = bat_source.get_as_text()
			bat_source.close()
			
			var game_name = ProjectSettings.get_setting("application/config/name")
			if game_name == null or game_name == "":
				game_name = "Godot Web Game"
				
			content = content.replace("{{GAME_NAME}}", game_name)
			
			var bat_dest = File.new()
			if bat_dest.open(base_dir + "/play.bat", File.WRITE) == OK:
				bat_dest.store_string(content)
				bat_dest.close()
				print("Local Server: Successfully copied and customized play.bat in " + base_dir)
			else:
				printerr("Local Server: Failed to write play.bat in " + base_dir)
		else:
			printerr("Local Server: Failed to open source play.bat")
		
		# Copy the assets/sounds directory recursively
		var sound_src = "res://assets/sounds"
		var sound_dest = base_dir + "/assets/sounds"
		print("Local Server: Copying sounds from " + sound_src + " to " + sound_dest)
		var copy_err = copy_dir(sound_src, sound_dest)
		if copy_err == OK:
			print("Local Server: Successfully copied sounds directory.")
		else:
			printerr("Local Server: Failed to copy sounds directory, error code: " + str(copy_err))
			
		# Copy splash-web.png to the root of HTML5 export
		var splash_src = "res://assets/brand/splash-web.png"
		var splash_dest = base_dir + "/splash-web.png"
		var splash_err = dir.copy(splash_src, splash_dest)
		if splash_err == OK:
			print("Local Server: Successfully copied splash-web.png to HTML5 build root.")
		else:
			printerr("Local Server: Failed to copy splash-web.png, error: " + str(splash_err))


func copy_dir(from_dir: String, to_dir: String) -> int:
	var dir = Directory.new()
	if not dir.dir_exists(to_dir):
		var err = dir.make_dir_recursive(to_dir)
		if err != OK:
			printerr("Local Server Export: Failed to create directory: " + to_dir)
			return err
			
	if dir.open(from_dir) == OK:
		dir.list_dir_begin(true, true)
		var file_name = dir.get_next()
		while file_name != "":
			var source_path = from_dir.plus_file(file_name)
			var dest_path = to_dir.plus_file(file_name)
			if dir.current_is_dir():
				var err = copy_dir(source_path, dest_path)
				if err != OK:
					return err
			else:
				if not file_name.ends_with(".import"):
					var err = dir.copy(source_path, dest_path)
					if err != OK:
						printerr("Local Server Export: Failed to copy " + source_path + " to " + dest_path)
						return err
			file_name = dir.get_next()
		dir.list_dir_end()
		return OK
	else:
		printerr("Local Server Export: Failed to open source directory: " + from_dir)
		return ERR_CANT_OPEN
