cmake_minimum_required(VERSION 3.8)
project(ratmp)

file(GLOB sources src/app/*.h src/app/*.cpp src/app/audio_clients/*.cpp src/app/resources.rc src/thirdparty/*.cpp src/thirdparty/*.c imgui/*.cpp imgui/*.h 
	imgui/backends/imgui_impl_dx10.* imgui/backends/imgui_impl_win32.* imgui/misc/freetype/imgui_freetype.*)
file(GLOB data data/*)

add_executable(ratmp WIN32 ${sources})
target_include_directories(ratmp PRIVATE src/thirdparty imgui)
target_link_libraries(ratmp PRIVATE winmm comdlg32 ole32 d3d10 shlwapi)
add_compile_definitions(_CRT_SECURE_NO_WARNINGS IMGUI_ENABLE_FREETYPE)

set_target_properties(ratmp PROPERTIES
	VS_DEBUGGER_WORKING_DIRECTORY "$<CONFIG>"
	LINK_FLAGS_DEBUG "/SUBSYSTEM:CONSOLE"
	LINK_FLAGS_RELEASE "/SUBSYSTEM:WINDOWS"
)

install(DIRECTORY data/ DESTINATION ${CMAKE_BINARY_DIR}/Release CONFIGURATIONS Release)
install(DIRECTORY data/ DESTINATION ${CMAKE_BINARY_DIR}/Debug CONFIGURATIONS Debug)

find_package(FFMPEG REQUIRED)
target_include_directories(ratmp PRIVATE ${FFMPEG_INCLUDE_DIRS})
target_link_directories(ratmp PRIVATE ${FFMPEG_LIBRARY_DIRS})
target_link_libraries(ratmp PRIVATE ${FFMPEG_LIBRARIES})

find_package(Freetype REQUIRED)
target_link_libraries(ratmp PRIVATE Freetype::Freetype)

find_package(GLEW REQUIRED)
target_link_libraries(ratmp PRIVATE GLEW::GLEW)
