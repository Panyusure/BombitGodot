class_name MatchState
extends RefCounted

var mode = "adventure"
var time_limit = 180.0
var remaining = 0.0
var scores = {"p1": 0, "p2": 0}
var target_score = Cfg.VERSUS_TARGET
var over = false
var winner = ""
var title = ""
var subtitle = ""
var round = 1
var level = 1
var level_clear_at = 0.0
var sudden = false
var round_ends_at = 0.0
var elapsed = 0.0
var start_bricks = 0
var total_explosions = 0
var max_chain = 0
