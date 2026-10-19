extends "res://scripts/net/LanSession.gd"

## Test-only transport: 150ms each way, jitter, input loss, duplication and reordering.
var outgoing: Array = []
var input_packets := 0
var state_packets := 0
var dropped_packets := 0

func _send_inputs(match_epoch: int, generation: int, packet: PackedInt32Array) -> void:
	input_packets += 1
	if input_packets % 5 == 0:
		dropped_packets += 1
		return
	var delay := 150 + (input_packets % 3) * 17 + (80 if input_packets % 9 == 0 else 0)
	outgoing.append({"at": Time.get_ticks_msec() + delay, "epoch": match_epoch, "generation": generation, "packet": packet.duplicate(), "input": true})
	if input_packets % 7 == 0:
		outgoing.append({"at": Time.get_ticks_msec() + delay + 30, "epoch": match_epoch, "generation": generation, "packet": packet.duplicate(), "input": true})

func _send_snapshot(match_epoch: int, packet: PackedByteArray) -> void:
	state_packets += 1
	outgoing.append({"at": Time.get_ticks_msec() + 150 + (state_packets % 4) * 19,
		"epoch": match_epoch, "packet": packet.duplicate(), "input": false})

func _process(delta: float) -> void:
	super._process(delta)
	if phase != "playing":
		outgoing.clear()
		return
	for i in range(outgoing.size() - 1, -1, -1):
		var delivery: Dictionary = outgoing[i]
		if int(delivery["at"]) > Time.get_ticks_msec():
			continue
		outgoing.remove_at(i)
		if delivery["epoch"] != epoch:
			continue
		if delivery["input"]:
			super._send_inputs(delivery["epoch"], delivery["generation"], delivery["packet"])
		else:
			super._send_snapshot(delivery["epoch"], delivery["packet"])
