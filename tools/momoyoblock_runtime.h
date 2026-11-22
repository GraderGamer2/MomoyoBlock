#ifndef MOMOYOBLOCK_RUNTIME_H
#define MOMOYOBLOCK_RUNTIME_H

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>

namespace MomoyoRuntime {

// Godot and the graphics driver read these before the game script can run.
inline bool prepare(int argc, char *const argv[]) {
	for (int i = 1; i < argc && std::strcmp(argv[i], "--") != 0; ++i) {
		if (std::strcmp(argv[i], "--log-file") == 0) {
			return false;
		}
	}

	const char *home = std::getenv("HOME");
	if (home == nullptr || home[0] != '/') {
		return false;
	}
	const std::string root = std::string(home) + "/.MomoyoBlock";
	const std::string cache = root + "/cache";
	const std::string temp = root + "/tmp";
	std::error_code error;
	for (const std::string *path : { &cache, &temp }) {
		std::filesystem::create_directories(*path, error);
		if (error) {
			return false;
		}
	}
	if (setenv("XDG_DATA_HOME", root.c_str(), 1) != 0 ||
			setenv("XDG_CONFIG_HOME", (root + "/config").c_str(), 1) != 0 ||
			setenv("XDG_STATE_HOME", (root + "/state").c_str(), 1) != 0 ||
			setenv("XDG_CACHE_HOME", cache.c_str(), 1) != 0 ||
			setenv("MESA_SHADER_CACHE_DIR", cache.c_str(), 1) != 0 ||
			setenv("__GL_SHADER_DISK_CACHE_PATH", cache.c_str(), 1) != 0 ||
			setenv("TMPDIR", temp.c_str(), 1) != 0) {
		return false;
	}
	return std::freopen("/dev/null", "w", stdout) != nullptr &&
			std::freopen("/dev/null", "w", stderr) != nullptr;
}

} // namespace MomoyoRuntime

#endif // MOMOYOBLOCK_RUNTIME_H
