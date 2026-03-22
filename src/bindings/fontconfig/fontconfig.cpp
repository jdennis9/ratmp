#include <fontconfig/fontconfig.h>

// Helper functions to create FcObjectSet without using C variadic arguments

extern "C" FcObjectSet *fontconfig_object_set_build_family_file() {
	return FcObjectSetBuild(FC_FILE, FC_FULLNAME, nullptr);
}

