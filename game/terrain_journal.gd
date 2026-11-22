class_name TerrainJournal
extends RefCounted

const EDIT_BYTES := 9
const MAX_BYTES := 64 * 1024 * 1024


static func pack(blocks: Dictionary, harvested: Dictionary) -> PackedByteArray:
	if blocks.is_empty() and harvested.is_empty():
		return PackedByteArray()

	var raw := PackedByteArray()
	raw.resize(8 + blocks.size() * EDIT_BYTES + harvested.size() * 4)
	raw.encode_u32(0, blocks.size())
	raw.encode_u32(4, harvested.size())
	var offset := 8
	for cell: Vector2i in blocks:
		raw.encode_s32(offset, cell.x)
		raw.encode_s32(offset + 4, cell.y)
		raw[offset + 8] = blocks[cell]
		offset += EDIT_BYTES
	for column: int in harvested:
		raw.encode_s32(offset, column)
		offset += 4

	var packet := PackedByteArray()
	packet.resize(4)
	packet.encode_u32(0, raw.size())
	if raw.size() >= 256:
		var compressed := raw.compress(FileAccess.COMPRESSION_ZSTD)
		if not compressed.is_empty() and compressed.size() < raw.size():
			packet.append_array(compressed)
			return packet
	packet.append_array(raw)
	return packet


static func unpack(packet: PackedByteArray, allow_harvest: bool) -> Dictionary:
	var blocks: Dictionary[Vector2i, int] = {}
	var harvested: Dictionary[int, bool] = {}
	if packet.is_empty():
		return {"blocks": blocks, "harvested": harvested}
	if packet.size() <= 4:
		return {}
	var raw_size := packet.decode_u32(0)
	if raw_size < 8 or raw_size > MAX_BYTES or packet.size() - 4 > raw_size:
		return {}

	var raw := packet.slice(4)
	if raw.size() < raw_size:
		raw = raw.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != raw_size:
		return {}
	var block_count := raw.decode_u32(0)
	var harvest_count := raw.decode_u32(4)
	if 8 + block_count * EDIT_BYTES + harvest_count * 4 != raw.size() or (not allow_harvest and harvest_count != 0):
		return {}

	var offset := 8
	for i in block_count:
		var cell := Vector2i(raw.decode_s32(offset), raw.decode_s32(offset + 4))
		var material := raw[offset + 8]
		if BlockWorld.is_pad(cell) or not BlockWorld.is_valid_edit(material) or blocks.has(cell):
			return {}
		blocks[cell] = material
		offset += EDIT_BYTES
	for i in harvest_count:
		var column := raw.decode_s32(offset)
		if harvested.has(column):
			return {}
		harvested[column] = true
		offset += 4
	return {"blocks": blocks, "harvested": harvested}
