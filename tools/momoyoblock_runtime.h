#ifndef MOMOYOBLOCK_RUNTIME_H
#define MOMOYOBLOCK_RUNTIME_H

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace MomoyoRuntime {

// Godot and the graphics driver read these before the game script can run.
inline bool prepare(int &argc, char **&argv) {
	bool use_renderer_preference = true;
	for (int i = 1; i < argc; ++i) {
		const std::string argument = argv[i];
		if (argument == "--" || argument == "++") {
			break;
		}
		if (argument == "--log-file") {
			return false;
		}
		if (argument == "--display-driver" && i + 1 < argc) {
			const std::string driver = argv[i + 1];
			if (driver != "wayland" && driver != "headless") {
				return false;
			}
			if (driver == "headless") {
				use_renderer_preference = false;
			}
		}
		if (argument == "--headless" || argument == "--rendering-method" || argument == "--rendering-driver") {
			use_renderer_preference = false;
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
	if (use_renderer_preference) {
		std::ifstream settings(root + "/profile/settings.cfg");
		std::string line;
		while (std::getline(settings, line)) {
			if (line == "renderer=\"mobile\"") {
				static char flag[] = "--rendering-method";
				static char method[] = "mobile";
				static std::vector<char *> arguments;
				arguments = { argv[0], flag, method };
				arguments.insert(arguments.end(), argv + 1, argv + argc + 1);
				argc += 2;
				argv = arguments.data();
				break;
			}
		}
	}
	return std::freopen("/dev/null", "w", stdout) != nullptr &&
			std::freopen("/dev/null", "w", stderr) != nullptr;
}

} // namespace MomoyoRuntime

#endif // MOMOYOBLOCK_RUNTIME_H
