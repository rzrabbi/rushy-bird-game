tool
extends EditorExportPlugin

func _export_begin(features: PoolStringArray, is_debug: bool, path: String, flags: int):
	# Pack secret_config.cfg to the exported PCK if it exists locally
	var config_file = File.new()
	if config_file.file_exists("res://secret_config.cfg"):
		if config_file.open("res://secret_config.cfg", File.READ) == OK:
			var data = config_file.get_buffer(config_file.get_len())
			config_file.close()
			add_file("res://secret_config.cfg", data, false)
			print("Local Server: Successfully packaged res://secret_config.cfg to export.")
		else:
			printerr("Local Server: Failed to read res://secret_config.cfg for packaging.")

	# Only execute this copy routine if exporting an HTML5 build
	if path.ends_with(".html"):
		var base_dir = path.get_base_dir()
		var dir = Directory.new()
		
		# Copy and customize serve.js
		var source_file = File.new()
		if source_file.open("res://addons/local_server/serve.js", File.READ) == OK:
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
		if bat_source.open("res://addons/local_server/play.bat", File.READ) == OK:
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
