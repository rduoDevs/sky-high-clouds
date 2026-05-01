cmake_minimum_required(VERSION 3.16)

# Sets project name
project(skyhigh LANGUAGES CXX C)

set(CMAKE_INCLUDE_CURRENT_DIR ON)

set(CMAKE_AUTOUIC ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Sets C++ standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# find_package(OpenGL REQUIRED)

# GLFW
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)

add_subdirectory(dependencies/glfw)

set(WEBGPU_BACKEND "DAWN")
# target_compile_definitions(${PROJECT_NAME} PRIVATE WEBGPU_BACKEND_DAWN)

add_library(dawn_webgpu SHARED IMPORTED)

if (WIN32)
    set_target_properties(dawn_webgpu PROPERTIES
        IMPORTED_LOCATION "${CMAKE_SOURCE_DIR}/dawn_precompiled_windows/bin/webgpu_dawn.dll" # or .so/.dylib
        IMPORTED_IMPLIB "${CMAKE_SOURCE_DIR}/dawn_precompiled_windows/lib/webgpu_dawn.lib"  # Windows only
        INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_SOURCE_DIR}/dawn_precompiled_windows/include"
    )
elseif (APPLE)
    # throw unimplemented error for now
    MESSAGE(FATAL_ERROR "Dawn precompiled for macOS not done yet")
endif()

add_library(webgpu INTERFACE)
target_link_libraries(webgpu INTERFACE dawn_webgpu)


# define IMGUI_IMPL_WEBGPU_BACKEND_WGPU for ImGui to use the Dawn backend implementation
add_compile_definitions(IMGUI_IMPL_WEBGPU_BACKEND_DAWN)

# use this to do uncapped fps
option(ENABLED_UNCAPPED_FPS "When ON, the application will run with uncapped FPS. When OFF, the application will run with VSync enabled." OFF)
if (ENABLED_UNCAPPED_FPS)
    add_compile_definitions(UNCAPPED_FPS)
endif()

# ImGui
add_library(imgui
    dependencies/imgui/imgui.cpp
    dependencies/imgui/imgui_draw.cpp
    dependencies/imgui/imgui_tables.cpp
    dependencies/imgui/imgui_widgets.cpp
    dependencies/imgui/backends/imgui_impl_glfw.cpp
    # dependencies/imgui/backends/imgui_impl_opengl3.cpp
    dependencies/imgui/backends/imgui_impl_wgpu.cpp
)

target_include_directories(imgui PUBLIC
    dependencies/imgui
    dependencies/imgui/backends
    dependencies/glfw/include
)
target_link_libraries(imgui PUBLIC webgpu)

add_subdirectory(glfw3webgpu)

# add_subdirectory(glm)


# Allows you to include files from within those directories, without prefixing their filepaths
include_directories(src)
include_directories(libs)

# Specifies .cpp and .h files to be passed to the compiler
# add_executable(${PROJECT_NAME}
#     src/main.cpp
#     src/grid.cpp
#     src/simulation.cpp
#     src/gridrenderer.cpp
#     src/graphics/camera.cpp
#     src/graphics/graphicsdebug.cpp
#     src/graphics/shader.cpp
#     src/graphics/shape.cpp

#     src/grid.h
#     src/simulation.h
#     src/gridrenderer.h
#     src/window.cpp
#     src/window.h
#     src/graphics/camera.h
#     src/graphics/graphicsdebug.h
#     src/graphics/shader.h
#     src/graphics/shape.h

#     util/tiny_obj_loader.h
#     util/unsupportedeigenthing/OpenGLSupport
# )
add_executable(${PROJECT_NAME}
    src/main.cpp
    src/Application.h
    src/Application.cpp
	src/ResourceManager.h
	src/ResourceManager.cpp
    src/gpuData.h
    src/Application_gpuData.cpp

    resources/ray.wgsl
    resources/present.wgsl
    src/tiny_obj_loader.h

)

# Specifies libraries to be linked (Imgui, glfw, webgpu)
target_link_libraries(${PROJECT_NAME} PRIVATE
    glfw
    imgui
    webgpu
    glfw3webgpu
)

set_source_files_properties(
    resources/ray.wgsl
    resources/present.wgsl
    PROPERTIES HEADER_FILE_ONLY TRUE
)


# find_package(glm CONFIG REQUIRED)
# target_link_libraries(main PRIVATE glm::glm)

# This allows you to `#include "Eigen/..."`
target_include_directories(${PROJECT_NAME} PRIVATE
    Eigen
    dependencies/imgui
    dependencies/imgui/backends
    glm
)

# target_include_directories(webgpu INTERFACE
#     ${WGPU_DIR}/include
# )

# Set this flag to silence warnings on Windows
if (MSVC OR MSYS OR MINGW)
  set(CMAKE_CXX_FLAGS "-Wno-volatile")
endif()

# Set this flag to silence warnings on MacOS
if (APPLE)
  set(CMAKE_CXX_FLAGS "-Wno-deprecated-volatile")
endif()

# windows specific
# add_custom_command(TARGET skyhigh POST_BUILD
#     COMMAND ${CMAKE_COMMAND} -E copy_if_different
#         "${WGPU_DIR}/lib/wgpu_native.dll"
#         $<TARGET_FILE_DIR:skyhigh>
# )
# target_copy_webgpu_binaries(skyhigh "${WEBGPU_RUNTIME_LIB}")

if (WIN32)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/dawn_precompiled_windows/bin/webgpu_dawn.dll"
            $<TARGET_FILE_DIR:${PROJECT_NAME}>
    )
endif()
