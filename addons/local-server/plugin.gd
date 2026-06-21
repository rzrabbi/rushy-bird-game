tool
extends EditorPlugin

var export_plugin

func _enter_tree():
	export_plugin = preload("local_server_export.gd").new()
	add_export_plugin(export_plugin)

func _exit_tree():
	remove_export_plugin(export_plugin)
