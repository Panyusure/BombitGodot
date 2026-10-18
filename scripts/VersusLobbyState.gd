extends RefCounted

## State only: no UI, shared focus, scene loading, or input event listeners.
signal changed

class PlayerChoice extends RefCounted:
	var player_id: String
	var device_id := -1
	var selected_character := 0
	var is_character_confirmed := false
	var is_ready := false
	var has_control := false
	var route_signature := ""
	var control_mode := "auto"
	var keyboard_allowed := true
	func _init(id: String, character: int) -> void:
		player_id = id
		selected_character = character
	func cancel_ready() -> void:
		is_character_confirmed = false
		is_ready = false

var players: Array[PlayerChoice] = []
var active := false
var game_starting := false
var changed_slots: Array[int] = []

func open(selections: Array = [0, 1]) -> void:
	players = [PlayerChoice.new("p1", clampi(int(selections[0]), 0, Cfg.CHAR_IDS.size() - 1)),
		PlayerChoice.new("p2", clampi(int(selections[1]), 0, Cfg.CHAR_IDS.size() - 1))]
	if players[0].selected_character == players[1].selected_character:
		players[1].selected_character = (players[0].selected_character + 1) % Cfg.CHAR_IDS.size()
	active = true
	game_starting = false
	refresh_routes()
	changed.emit()

func close() -> void:
	active = false
	game_starting = false
	for choice in players:
		choice.cancel_ready()
	changed.emit()

func refresh_routes() -> bool:
	var dirty := false
	changed_slots.clear()
	for slot in players.size():
		var choice := players[slot]
		var route := InputSettings.lobby_route(choice.player_id)
		if choice.route_signature != String(route["signature"]):
			choice.cancel_ready()
			choice.route_signature = String(route["signature"])
			changed_slots.append(slot)
			dirty = true
		choice.device_id = int(route["device_id"])
		choice.has_control = bool(route["valid"])
		choice.control_mode = String(route["mode"])
		choice.keyboard_allowed = bool(route["keyboard"])
	if dirty:
		changed.emit()
	return dirty

func select_character(slot: int, index: int) -> bool:
	if not active or game_starting or slot not in [0, 1] or index < 0 or index >= Cfg.CHAR_IDS.size():
		return false
	if index == players[1 - slot].selected_character:
		return false
	var choice := players[slot]
	if choice.selected_character == index:
		return false
	choice.selected_character = index
	choice.cancel_ready()
	changed.emit()
	return true

func cycle_character(slot: int, direction: int) -> bool:
	if slot not in [0, 1] or direction == 0:
		return false
	var index := players[slot].selected_character
	for attempt in Cfg.CHAR_IDS.size():
		index = posmod(index + signi(direction), Cfg.CHAR_IDS.size())
		if index != players[1 - slot].selected_character:
			return select_character(slot, index)
	return false

func ready_player(slot: int) -> bool:
	refresh_routes()
	if not active or game_starting or slot not in [0, 1] or not players[slot].has_control:
		return false
	var choice := players[slot]
	if choice.selected_character < 0 or choice.selected_character >= Cfg.CHAR_IDS.size():
		return false
	choice.is_character_confirmed = true
	choice.is_ready = true
	changed.emit()
	return true

func cancel_player(slot: int) -> void:
	if not active or game_starting or slot not in [0, 1]:
		return
	players[slot].cancel_ready()
	changed.emit()

func _conditions_met() -> bool:
	if not active or players.size() != 2:
		return false
	for choice in players:
		if not choice.has_control or not choice.is_ready or not choice.is_character_confirmed:
			return false
		if choice.selected_character < 0 or choice.selected_character >= Cfg.CHAR_IDS.size():
			return false
	return players[0].selected_character != players[1].selected_character

func can_start_game() -> bool:
	return not game_starting and _conditions_met()

func begin_game() -> Array:
	refresh_routes()
	if not can_start_game():
		return []
	game_starting = true  # Lock before emitting any scene transition signal.
	changed.emit()
	return [Cfg.CHAR_IDS[players[0].selected_character], Cfg.CHAR_IDS[players[1].selected_character]]

func start_authorized(c1: String, c2: String) -> bool:
	refresh_routes()
	return game_starting and _conditions_met() and c1 == Cfg.CHAR_IDS[players[0].selected_character] and c2 == Cfg.CHAR_IDS[players[1].selected_character]
