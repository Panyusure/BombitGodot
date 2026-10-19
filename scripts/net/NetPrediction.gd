extends RefCounted

## A render-only local actor. Authoritative World, rewards, bombs and health stay untouched.
const Inputs = preload("res://scripts/net/NetInputs.gd")
const Codec = preload("res://scripts/net/NetSnapshot.gd")
const STEP := 1.0 / 60.0
const MAX_SPECULATION := 45
var actor: Actor
var pending: Array = []
var generation := 0
var acknowledged := 0
var visual_offset := Vector2.ZERO
var scratch := World.new()

func reset() -> void:
	actor = null
	pending.clear()
	generation = 0
	acknowledged = 0
	visual_offset = Vector2.ZERO
	scratch = World.new()

func initialize(w: World, new_generation: int) -> void:
	reset()
	generation = new_generation
	actor = Actor.new()
	Codec.restore(actor, Codec.fields(w.player_by_id("p2")))
	actor.px = actor.x
	actor.py = actor.y
	copy_collision(w)

func copy_collision(w: World) -> void:
	scratch.map = w.map
	scratch.landmark = w.landmark
	scratch.bombs = []
	for source in w.bombs:
		var bomb := Bomb.new()
		Codec.restore(bomb, Codec.fields(source).duplicate(true))
		scratch.bombs.append(bomb)

func enqueue(w: World, command: PackedInt32Array) -> void:
	if pending.size() >= Inputs.MAX_PENDING:
		return
	pending.append(command)
	if pending.size() <= MAX_SPECULATION:
		advance(w, command)
	else:
		actor.px = actor.x
		actor.py = actor.y
		actor.moving = false

func packet() -> PackedInt32Array:
	var data := PackedInt32Array()
	for i in mini(pending.size(), Inputs.REDUNDANCY):
		data.append_array(pending[i])
	return data

func advance(w: World, command: PackedInt32Array) -> void:
	actor.px = actor.x
	actor.py = actor.y
	if not actor.alive or w.match.over:
		actor.moving = false
		return
	# Motion reads collision geometry only; use a private world so no gameplay
	# events or carousel rewards can leak out of replayed speculative movement.
	scratch.map = w.map
	scratch.landmark = w.landmark
	for bomb in scratch.bombs:
		if not Grid.bomb_overlaps_player(bomb, actor):
			bomb.pass_for.erase(actor.id)
			if bomb.free_for == actor.id:
				bomb.free_for = ""
	for timer in ["insight_time", "slow_time", "soul_slow_time"]:
		actor.set(timer, maxf(0, float(actor.get(timer)) - STEP))
	actor.axis_pref = "x" if command[5] == 0 else "y"
	var rewarded: bool = actor.carousel_rewarded
	actor.carousel_rewarded = true
	actor.moving = Motion.step(scratch, actor, command[1], command[2], STEP)
	actor.carousel_rewarded = rewarded

func reconcile(w: World, ack: int, new_generation: int) -> void:
	if actor == null or new_generation != generation:
		initialize(w, new_generation)
		return
	if ack < acknowledged:
		return
	var old_position := Vector2(actor.x, actor.y) + visual_offset
	acknowledged = ack
	pending = pending.filter(func(command): return command[0] > ack)
	Codec.restore(actor, Codec.fields(w.player_by_id("p2")))
	copy_collision(w)
	for i in mini(pending.size(), MAX_SPECULATION):
		advance(w, pending[i])
	actor.px = actor.x
	actor.py = actor.y
	var correction := old_position - Vector2(actor.x, actor.y)
	visual_offset = correction if actor.alive and correction.length() < Cfg.TILE \
		and Grid.can_stand(scratch, old_position.x, old_position.y, Cfg.BOX, actor.id) else Vector2.ZERO

func draw_offset(w: World, delta: float) -> Vector2:
	visual_offset *= exp(-20.0 * delta)
	scratch.map = w.map
	var draw_position := Vector2(actor.x, actor.y) + visual_offset
	if not Grid.can_stand(scratch, draw_position.x, draw_position.y, Cfg.BOX, actor.id):
		visual_offset = Vector2.ZERO
	return visual_offset
