extends AudioStreamPlayer

var sound_name: String
var _is_playing: bool = false

func _ready():
	if OS.has_feature("HTML5") and AudioManager.enable:
		AudioManager.connect("audioEnd", self, "_on_audio_ended")

func _on_audio_ended(audio_name: String):
	if audio_name == sound_name:
		_is_playing = false
		emit_signal("finished")

func _should_loop() -> bool:
	if not stream:
		return false
	if "loop" in stream:
		return stream.loop
	elif stream is AudioStreamSample:
		return stream.loop_mode != AudioStreamSample.LOOP_DISABLED
	return false

func play(from_position: float = 0.0):
	_is_playing = true
	if OS.has_feature("HTML5") and AudioManager.enable:
		var config = {}
		if _should_loop():
			config["loop"] = true
		
		if AudioManager.isLoaddedAllAudios:
			AudioManager.play(sound_name, config)
		else:
			yield(AudioManager, "loadedAllAudios")
			if _is_playing:
				AudioManager.play(sound_name, config)
	else:
		.play(from_position)

func stop():
	_is_playing = false
	if OS.has_feature("HTML5") and AudioManager.enable:
		AudioManager.stop(sound_name)
	else:
		.stop()

func set_volume_db(val: float):
	.set_volume_db(val)
	if OS.has_feature("HTML5") and AudioManager.enable:
		var adjusted_val = val
		if sound_name == "main_menu_bgm.mp3":
			adjusted_val += 10.0
		AudioManager.update_config_audio({"volume": adjusted_val}, sound_name)
