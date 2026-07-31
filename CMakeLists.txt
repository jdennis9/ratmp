cmake_minimum_required(VERSION 4.0)

cmake_policy(SET CMP0156 NEW)

project(ratmp)

find_package(Qt6Core CONFIG REQUIRED)
qt_standard_project_setup()

file(GLOB objects lib/*.obj)

qt_add_executable(RATMP 
	src/main/qt_client/main.cpp
	src/main/qt_client/main_window.h
	src/main/qt_client/track_table.h
	src/main/qt_client/spectrum_window.h
)

target_link_libraries(RATMP PRIVATE Qt6::Core)

set_property(TARGET RATMP PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

target_link_directories(RATMP PRIVATE src/bindings)
target_link_libraries(RATMP PRIVATE bindings)
target_link_libraries(RATMP PRIVATE ${objects})

find_package(FFTW3f CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE FFTW3::fftw3f)

find_package(taglib CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE TagLib::tag TagLib::tag_c TagLib::TagLib)

find_package(Qt6Widgets CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE Qt6::Widgets)

find_package(Qt6Svg CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE Qt6::Svg)

find_package(Qt6SvgWidgets CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE Qt6::SvgWidgets)

find_package(Qt6OpenGL CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE Qt6::OpenGL)

find_package(qtadvanceddocking-qt6 CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE ads::qtadvanceddocking-qt6)

find_package(FFMPEG REQUIRED)
target_include_directories(RATMP PRIVATE ${FFMPEG_INCLUDE_DIRS})
target_link_directories(RATMP PRIVATE ${FFMPEG_LIBRARY_DIRS})
target_link_libraries(RATMP PRIVATE ${FFMPEG_LIBRARIES})

find_package(taglib CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE TagLib::tag TagLib::tag_c TagLib::TagLib)

find_package(SampleRate CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE SampleRate::samplerate)

find_package(lz4 CONFIG REQUIRED)
target_link_libraries(RATMP PRIVATE lz4::lz4)

qt_finalize_project()
