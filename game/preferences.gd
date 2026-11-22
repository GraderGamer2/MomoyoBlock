class_name GamePreferences
extends RefCounted

const PATH := "user://settings.cfg"
const FPS_OPTIONS: Array[int] = [30, 60, 90, 120, 144, 165, 240, 0]
const RENDERERS: Array[String] = ["gl_compatibility", "mobile"]

var fps_limit := 60
var vsync := true
var volume := 1.0
var renderer := "gl_compatibility"


func load_settings() -> void:
	var config := ConfigFile.new()
	if not FileAccess.file_exists(PATH) or config.load(PATH) != OK:
		return
	var fps: Variant = config.get_value("video", "fps_limit", fps_limit)
	if fps is int and FPS_OPTIONS.has(fps):
		fps_limit = fps
	var sync: Variant = config.get_value("video", "vsync", vsync)
	if sync is bool:
		vsync = sync
	var method: Variant = config.get_value("video", "renderer", renderer)
	if method is String and RENDERERS.has(method):
		renderer = method
	var level: Variant = config.get_value("audio", "volume", volume)
	if (level is float or level is int) and is_finite(float(level)):
		volume = clampf(float(level), 0.0, 1.0)


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("video", "fps_limit", fps_limit)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "renderer", renderer)
	config.set_value("audio", "volume", volume)
	var temp := "user://.settings-%d.tmp" % OS.get_process_id()
	var result := config.save(temp)
	if result == OK:
		result = DirAccess.rename_absolute(temp, PATH)
	if result != OK:
		DirAccess.remove_absolute(temp)
	return result


func apply_live() -> void:
	Engine.max_fps = fps_limit
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_mute(0, volume <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, volume)))
