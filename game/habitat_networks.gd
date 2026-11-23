class_name HabitatNetworks
extends RefCounted

var _groups: Array[Array] = []
var _by_room: Dictionary[HabitatRoom, Array] = {}


static func discover(world: BlockWorld, first: Rect2i) -> Array[Rect2i]:
	var rooms: Array[Rect2i] = [first]
	var found := {first: true}
	var index := 0
	while index < rooms.size():
		var area := rooms[index]
		index += 1
		for panel in HabitatRoom.side_airlocks(world, area):
			var outside := panel + (Vector2i.LEFT if panel.x < area.position.x else Vector2i.RIGHT)
			var survey := HabitatRoom.survey_from(world, outside)
			if not survey.has("bounds"):
				continue
			var other: Rect2i = survey.bounds
			if not other.has_point(outside + Vector2i.DOWN) or found.has(other):
				continue
			found[other] = true
			rooms.append(other)
	return rooms


func rebuild(world: BlockWorld, rooms: Array) -> void:
	_groups.clear()
	_by_room.clear()
	var neighbors: Dictionary[HabitatRoom, Array] = {}
	var doors: Dictionary[Vector2i, HabitatRoom] = {}
	for room: HabitatRoom in rooms:
		neighbors[room] = []
		for panel in HabitatRoom.side_airlocks(world, room.bounds):
			if not room.connects_at(panel):
				continue
			var other: HabitatRoom = doors.get(panel)
			if other == null:
				doors[panel] = room
			else:
				neighbors[room].append(other)
				neighbors[other].append(room)
	for room: HabitatRoom in rooms:
		if _by_room.has(room):
			continue
		var group: Array[HabitatRoom] = [room]
		_by_room[room] = group
		var index := 0
		while index < group.size():
			var chamber := group[index]
			index += 1
			for other: HabitatRoom in neighbors[chamber]:
				if not _by_room.has(other):
					_by_room[other] = group
					group.append(other)
		# Keep storage priority stable when the player commissions a room from either end.
		group.sort_custom(func(a: HabitatRoom, b: HabitatRoom) -> bool:
			return a.bounds.position.x < b.bounds.position.x if a.bounds.position.x != b.bounds.position.x \
					else a.bounds.position.y < b.bounds.position.y)
		_groups.append(group)


func members(room: HabitatRoom) -> Array:
	return _by_room.get(room, [])


func advance_to(now: float) -> void:
	for group in _groups:
		HabitatRoom.advance_network(group, now)
