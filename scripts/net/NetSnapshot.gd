extends RefCounted

## Primitive values only: never deserialize objects or run client simulation.
const WORLD_FIELDS = ["mode", "input_mode", "theme", "map", "spawns", "time", "frame", "flames", "poison", "items", "stats", "landmark", "brick_variants", "boss_battle", "time_stop", "skill_effects", "map_revision", "map_identity", "hard_revision", "seed_text"]
var bomb_ids := {}
var next_bomb := 1
var remote_bombs := {}

static func fields(object: Object) -> Dictionary:
	var data := {}
	for property in object.get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			data[property.name] = object.get(property.name)
	return data

static func restore(object: Object, data: Dictionary) -> void:
	for property in object.get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and data.has(property.name):
			object.set(property.name, data[property.name])

func pack(w: World) -> Dictionary:
	var data := {}
	for key in WORLD_FIELDS:
		data[key] = w.get(key)
	data["players"] = w.players.map(func(p): return fields(p))
	data["match"] = fields(w.match)
	var bombs := []
	var keep := {}
	for bomb in w.bombs:
		var instance: int = bomb.get_instance_id()
		if not bomb_ids.has(instance):
			bomb_ids[instance] = next_bomb
			next_bomb += 1
		keep[instance] = bomb_ids[instance]
		bombs.append({"id": bomb_ids[instance], "state": fields(bomb)})
	bomb_ids = keep
	data["bombs"] = bombs
	return data.duplicate(true)

func apply(w: World, data: Dictionary) -> void:
	var new_map: bool = w.map_identity != int(data["map_identity"])
	for key in WORLD_FIELDS:
		w.set(key, data[key])
	if w.match == null:
		w.match = MatchState.new()
	restore(w.match, data["match"])
	var actors := []
	for state in data["players"]:
		var actor = w.player_by_id(state["id"])
		var fresh: bool = actor == null
		if fresh:
			actor = Actor.new()
		var previous := Vector2(actor.x, actor.y)
		restore(actor, state)
		if not fresh and not new_map and previous.distance_to(Vector2(actor.x, actor.y)) < Cfg.TILE * 3:
			actor.px = previous.x
			actor.py = previous.y
		else:
			actor.px = actor.x
			actor.py = actor.y
		actors.append(actor)
	w.players = actors
	var keep := {}
	w.bombs = []
	for entry in data["bombs"]:
		var id: int = entry["id"]
		var bomb: Bomb = remote_bombs.get(id, Bomb.new())
		restore(bomb, entry["state"])
		keep[id] = bomb
		w.bombs.append(bomb)
	remote_bombs = keep
