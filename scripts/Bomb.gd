class_name Bomb
extends RefCounted

var cx = 0
var cy = 0
var has_pos = false
var x = 0.0
var y = 0.0
var power = 1
var fuse = Cfg.FUSE
var fuse_total = Cfg.FUSE
var owner_id = ""
var pass_for: Array = []
var free_for = ""
var color = Color.WHITE
var slide: Dictionary = {}      # {dc, dr}
var by_enemy = false
var break_hard = false

func _init(c: int = 0, r: int = 0) -> void:
    cx = c
    cy = r
