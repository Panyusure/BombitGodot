extends RefCounted

## One command equals one server physics tick. Never accept client positions/dt.
const WIDTH := 6
const MAX_PENDING := 180
const REDUNDANCY := 48 # 1152 bytes plus RPC framing, below the ENet MTU.
var acknowledged := 0
var commands := {}
var bomb_serial := 0
var skill_serial := 0

func receive(packet: PackedInt32Array) -> bool:
	if packet.is_empty() or packet.size() % WIDTH != 0 or packet.size() > WIDTH * REDUNDANCY:
		return false
	var previous := -1
	for offset in range(0, packet.size(), WIDTH):
		var sequence := packet[offset]
		if sequence <= previous or sequence < 1 or sequence > acknowledged + MAX_PENDING \
			or abs(packet[offset + 1]) > 1 or abs(packet[offset + 2]) > 1 \
			or packet[offset + 3] < 0 or packet[offset + 4] < 0 or packet[offset + 5] not in [0, 1]:
			return false
		previous = sequence
	for offset in range(0, packet.size(), WIDTH):
		var sequence := packet[offset]
		if sequence > acknowledged and not commands.has(sequence):
			commands[sequence] = packet.slice(offset, offset + WIDTH)
	return true

func consume() -> Dictionary:
	if not commands.has(acknowledged + 1):
		return {} # Missing commands are resent; do not repeat/ack a stale direction.
	acknowledged += 1
	var command: PackedInt32Array = commands[acknowledged]
	commands.erase(acknowledged)
	if command[3] < bomb_serial or command[3] > bomb_serial + 1 \
		or command[4] < skill_serial or command[4] > skill_serial + 1:
		return {}
	var action := {"hx": command[1], "hy": command[2], "axis_pref": "x" if command[5] == 0 else "y",
		"bomb": command[3] > bomb_serial, "skill": command[4] > skill_serial}
	bomb_serial = command[3]
	skill_serial = command[4]
	return action
