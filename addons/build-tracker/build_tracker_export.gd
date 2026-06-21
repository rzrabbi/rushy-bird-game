tool
extends EditorExportPlugin

func _export_begin(features: PoolStringArray, is_debug: bool, path: String, flags: int):
	var platform = "unknown"
	var platform_code = "95" # Default code for unknown platforms
	
	if features.has("HTML5"):
		platform = "web"
		platform_code = "25" # Unique platform code for Web (HTML5)
	elif features.has("Windows"):
		platform = "windows"
		platform_code = "15" # Unique platform code for Windows
	elif features.has("X11") or features.has("Linux"):
		platform = "linux"
		platform_code = "55" # Unique platform code for Linux
	elif features.has("Android"):
		platform = "android"
		platform_code = "35" # Unique platform code for Android
	elif features.has("OSX") or features.has("macOS"):
		platform = "macos"
		platform_code = "45" # Unique platform code for macOS
	elif features.has("iOS"):
		platform = "ios"
		platform_code = "65" # Unique platform code for iOS
		
	var config = ConfigFile.new()
	var err = config.load("res://build_number.cfg")
	
	var count = 0
	if err == OK:
		count = config.get_value(platform, "count", 0)
		
	count += 1
	config.set_value(platform, "count", count)
	
	# Get two digit export count
	var count_str = "%02d" % (count % 100)
	
	# Get two digit month
	var datetime = OS.get_datetime()
	var month_str = "%02d" % datetime.month
	
	# Get last two digits of the year
	var year_str = str(datetime.year).substr(2, 2)
	
	# Format: [Platform Code (2)] + [Export Count (2)] + [Month (2)] + [Year (2)]
	var build_str = platform_code + count_str + month_str + year_str
	config.set_value("current", "build", build_str)
	
	config.save("res://build_number.cfg")
	
	var f = File.new()
	if f.open("res://build_number.cfg", File.READ) == OK:
		var bytes = f.get_buffer(f.get_len())
		f.close()
		add_file("res://build_number.cfg", bytes, false)
		print("[Build Tracker] Added build_number.cfg to export package.")
		
	print("[Build Tracker] Incremented build for " + platform + ": " + build_str)
