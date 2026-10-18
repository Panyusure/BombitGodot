extends Node

## 音频管理：菜单 / 关卡 / BOSS 配乐淡入淡出 + 合成音效池。

const MUSIC_DB = -11.0
const SFX_DB = -5.0
const MUSIC_TRACKS = {
	"menu": "res://assets/audio/music/menu.mp3",
	"level-1": "res://assets/audio/music/level-1.mp3",
	"level-2": "res://assets/audio/music/level-2.mp3",
	"boss-1": "res://assets/audio/music/boss-1.mp3",
	"boss-2": "res://assets/audio/music/boss-2.mp3",
}
const SFX_NAMES = [
	"ui_move", "ui_click", "bomb_place", "explode", "item_pickup", "powerup",
	"hurt", "death", "shield", "shield_break", "skill", "boss_phase",
	"poison", "sudden_death", "level_clear", "win", "lose", "carousel", "fruit",
]

var muted = false
var sfx_level = 1.0
var music_level = 1.0
var _music_players: Array = []
var _active_music: AudioStreamPlayer = null
var _current_track = ""
var _tween: Tween
var _sfx_players: Array = []
var _sfx_streams = {}
var _music_streams = {}
var _sfx_index = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p = AudioStreamPlayer.new()
		p.volume_db = MUSIC_DB
		add_child(p)
		_music_players.append(p)
	for i in 10:
		var p = AudioStreamPlayer.new()
		p.volume_db = SFX_DB
		add_child(p)
		_sfx_players.append(p)
	for name in SFX_NAMES:
		var path = "res://assets/audio/sfx/%s.wav" % name
		if ResourceLoader.exists(path):
			_sfx_streams[name] = load(path)
	for key in MUSIC_TRACKS.keys():
		var path: String = MUSIC_TRACKS[key]
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream is AudioStreamMP3:
				stream.loop = true
			_music_streams[key] = stream
	_apply_volumes()

func play_music(track: String) -> void:
	if track == _current_track:
		return
	if not _music_streams.has(track):
		return
	_current_track = track
	var next: AudioStreamPlayer = _music_players[0]
	if _active_music == _music_players[0]:
		next = _music_players[1]
	next.stream = _music_streams[track]
	next.volume_db = -40.0
	next.play()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	if _active_music != null:
		_tween.tween_property(_active_music, "volume_db", -40.0, 0.45)
	_tween.tween_property(next, "volume_db", MUSIC_DB + linear_to_db(maxf(music_level, 0.001)), 0.7)
	var old = _active_music
	_tween.chain().tween_callback(func(): if old != null and is_instance_valid(old): old.stop())
	_active_music = next

func set_sfx_level(value: float) -> void:
	sfx_level = clampf(value, 0.0, 1.0)
	_apply_volumes()

func set_music_level(value: float) -> void:
	music_level = clampf(value, 0.0, 1.0)
	_apply_volumes()

func _apply_volumes() -> void:
	for p in _sfx_players:
		p.volume_db = SFX_DB + linear_to_db(maxf(sfx_level, 0.001))
	if _active_music != null and (_tween == null or not _tween.is_valid()):
		_active_music.volume_db = MUSIC_DB + linear_to_db(maxf(music_level, 0.001))

func stop_music(fade: float = 0.5) -> void:
	_current_track = ""
	if _active_music == null:
		return
	var old = _active_music
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(old, "volume_db", -50.0, fade)
	_tween.tween_callback(func(): if is_instance_valid(old): old.stop())
	_active_music = null

func play_sfx(name: String) -> void:
	if muted:
		return
	if not _sfx_streams.has(name):
		return
	var player: AudioStreamPlayer = null
	for p in _sfx_players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = _sfx_players[_sfx_index % _sfx_players.size()]
		_sfx_index += 1
	player.volume_db = SFX_DB + linear_to_db(maxf(sfx_level, 0.001))
	player.stream = _sfx_streams[name]
	player.play()

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)

func toggle_muted() -> bool:
	set_muted(not muted)
	return muted
