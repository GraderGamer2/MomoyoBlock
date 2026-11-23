class_name HabitatNetworks
extends RefCounted

const B := BlockWorld.Block
const PANEL_OUTPUT := 1.2
const SKY_DEPTH := 32
const SKY_WEIGHTS := [0.225, 0.55, 0.225]

var _groups: Array[Array] = []
var _by_room: Dictionary[HabitatRoom, Array] = {}
var _panel_light: Dictionary[Vector2i, float] = {}
var _solar_watch: Dictionary[Vector2i, bool] = {}


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
	refresh_solar(world)


func refresh_solar(world: BlockWorld) -> void:
	_panel_light.clear()
	_solar_watch.clear()
	for room: HabitatRoom in _by_room:
		room.solar_panels = 0
		room.solar_output = 0.0
		for x in range(room.bounds.position.x, room.bounds.end.x):
			var roof := Vector2i(x, room.bounds.position.y - 1)
			if not BlockWorld.is_airtight(world.material_at(roof)):
				continue
			var mount := roof + Vector2i.UP
			_solar_watch[mount] = true
			while world.material_at(mount) == B.SOLAR_MAST:
				mount.y -= 1
				_solar_watch[mount] = true
			if world.material_at(mount) == B.SOLAR_PANEL:
				var light := _sunlight(world, mount, _solar_watch)
				_panel_light[mount] = light
				room.solar_panels += 1
				room.solar_output += light * PANEL_OUTPUT


func solar_affected(cell: Vector2i) -> bool:
	return _solar_watch.has(cell)


func panel_reading(world: BlockWorld, cell: Vector2i) -> String:
	var linked := _panel_light.has(cell)
	var light := _panel_light[cell] if linked else _sunlight(world, cell, {})
	var reading := "Solar panel · %d%% light" % roundi(light * 100.0)
	if linked:
		return "%s · %.2f u/s" % [reading, light * PANEL_OUTPUT]
	return reading + "\nMount above a commissioned habitat roof."


static func _sunlight(world: BlockWorld, cell: Vector2i, watched: Dictionary[Vector2i, bool]) -> float:
	var exposure := 0.0
	# Sample straight up and diagonally for light from the sky around overhangs.
	for lane in SKY_WEIGHTS.size():
		var step := Vector2i(lane - 1, -1)
		var light: float = SKY_WEIGHTS[lane]
		for distance in range(1, SKY_DEPTH + 1):
			var sample := cell + step * distance
			watched[sample] = true
			match world.material_at(sample):
				B.EMPTY:
					continue
				B.GLASS:
					light *= 0.65
				B.FRAME, B.SOLAR_MAST:
					light *= 0.85
				_:
					light = 0.0
					break
		exposure += light
	return exposure


func members(room: HabitatRoom) -> Array:
	return _by_room.get(room, [])


func advance_to(now: float) -> void:
	for group in _groups:
		HabitatRoom.advance_network(group, now)
