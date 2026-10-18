class_name BombitCLI
extends SceneTree

## Editor/development entry point (Godot --script).
## Exported builds use the CliBootstrap autoload instead, because release
## exports do not reliably accept --script for project resources.

const App = preload("res://scripts/cli/CliApp.gd")

func _initialize() -> void:
	var app = App.new()
	quit(app.run(OS.get_cmdline_user_args()))
