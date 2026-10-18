extends Node

## Exported-build CLI/MCP entry point.
##
## Release exports do not reliably run `--script` project resources, but
## autoloads are always instantiated. Normal game launches (no CLI flag)
## return immediately; CLI launches are dispatched here before the main
## scene can start.
##
##   BombitGodot.exe --headless --no-header -- --mcp
##   BombitGodot.exe --headless --no-header -- --serve --memory
##   BombitGodot.exe --headless --no-header -- --cli rules --json

const App = preload("res://scripts/cli/CliApp.gd")

func _ready() -> void:
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		return
	var mode = String(args[0])
	var forwarded: Array = []
	if mode == "--mcp" or mode == "mcp":
		forwarded = ["--mcp"]
	elif mode == "--serve" or mode == "serve":
		forwarded = ["serve"]
		if args.has("--memory"):
			forwarded.append("--memory")
	elif mode == "--cli" or mode == "cli":
		forwarded = args.slice(1)
	else:
		return
	if forwarded.is_empty():
		forwarded = ["help"]
	var app = App.new()
	var code = int(app.run(forwarded))
	get_tree().quit(code)
