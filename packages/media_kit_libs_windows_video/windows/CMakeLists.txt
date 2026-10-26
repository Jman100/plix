# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

# Deal with MSVC incompatibility
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# Detect architecture
if("${CMAKE_SYSTEM_PROCESSOR}" MATCHES "(ARM64|aarch64)" OR "${CMAKE_GENERATOR_PLATFORM}" MATCHES "(ARM64|arm64)" OR "${FLUTTER_TARGET_PLATFORM}" STREQUAL "windows-arm64")
  set(IS_ARM64 TRUE)
else()
  set(IS_ARM64 FALSE)
endif()

# Find archive extractors
find_program(SEVENZ_EXECUTABLE NAMES 7z 7za)
find_program(TAR_EXECUTABLE NAMES tar PATHS "C:/Windows/System32" "$ENV{SystemRoot}/System32")

# ------------------------------------------------------------------------------
function(download_and_verify url hash_type hash_val archive_path)
  if(EXISTS "${archive_path}")
    file(${hash_type} "${archive_path}" CURRENT_HASH)
    if(NOT "${hash_val}" STREQUAL "${CURRENT_HASH}")
      file(REMOVE "${archive_path}")
      message(STATUS "Hash mismatch for ${archive_path}. File deleted.")
    endif()
  endif()

  if(NOT EXISTS "${archive_path}")
    message(STATUS "Downloading ${url}...")
    file(
      DOWNLOAD
      "${url}"
      "${archive_path}"
      EXPECTED_HASH "${hash_type}=${hash_val}"
      STATUS DOWNLOAD_STATUS
      TLS_VERIFY ON
      TIMEOUT 300
    )
    list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
    list(GET DOWNLOAD_STATUS 1 STATUS_MSG)
    if(NOT STATUS_CODE EQUAL 0)
      file(REMOVE "${archive_path}")
      message(FATAL_ERROR "Download failed: ${STATUS_MSG}")
    endif()
  endif()
endfunction()

# ------------------------------------------------------------------------------
if(IS_ARM64)
  message(STATUS "Configuring media_kit_libs_windows_video for ARM64")
  set(LIBMPV "mpv-dev-aarch64-20261023-git-41f6a64506.7z")
  set(LIBMPV_URL "https://github.com/Carapacik/libmpv-win32-video-cmake/releases/download/20261023/${LIBMPV}")
  set(LIBMPV_HASH_TYPE "SHA256")
  set(LIBMPV_HASH "66b89e6e34d5970f596bb8e4f480b9110652cd3d289b7421e510f1d8fa9c8e8e")

  set(ANGLE "ANGLE-9fe55a5-windows-arm64.7z")
  set(ANGLE_URL "https://github.com/Carapacik/flutter-windows-ANGLE-OpenGL-ES/releases/download/v8078/${ANGLE}")
  set(ANGLE_HASH_TYPE "SHA256")
  set(ANGLE_HASH "f2a2acd39f9d989717d6b6c308230ca0f9f0f2ff4ca082f75836957c4283589b")
else()
  message(STATUS "Configuring media_kit_libs_windows_video for x64")
  set(LIBMPV "mpv-dev-x86_64-20230924-git-652a1dd.7z")
  set(LIBMPV_URL "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${LIBMPV}")
  set(LIBMPV_HASH_TYPE "MD5")
  set(LIBMPV_HASH "a832ef24b3a6ff97cd2560b5b9d04cd8")

  set(ANGLE "ANGLE.7z")
  set(ANGLE_URL "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/${ANGLE}")
  set(ANGLE_HASH_TYPE "MD5")
  set(ANGLE_HASH "e866f13e8d552348058afaafe869b1ed")
endif()

# ------------------------------------------------------------------------------
# Extract libmpv
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")

download_and_verify(
  "${LIBMPV_URL}"
  "${LIBMPV_HASH_TYPE}"
  "${LIBMPV_HASH}"
  "${LIBMPV_ARCHIVE}"
)

if(NOT EXISTS "${LIBMPV_SRC}/libmpv.dll.a")
  message(STATUS "Extracting ${LIBMPV} to ${LIBMPV_SRC}...")
  file(REMOVE_RECURSE "${LIBMPV_SRC}")
  file(MAKE_DIRECTORY "${LIBMPV_SRC}")

  if(SEVENZ_EXECUTABLE)
    message(STATUS "Using 7zip for libmpv extraction: ${SEVENZ_EXECUTABLE}")
    execute_process(
      COMMAND "${SEVENZ_EXECUTABLE}" x -y "${LIBMPV_ARCHIVE}"
      WORKING_DIRECTORY "${LIBMPV_SRC}"
      RESULT_VARIABLE EXTRACT_RES
    )
  elseif(TAR_EXECUTABLE)
    message(STATUS "Using tar for libmpv extraction: ${TAR_EXECUTABLE}")
    execute_process(
      COMMAND "${TAR_EXECUTABLE}" -xf "${LIBMPV_ARCHIVE}" -C "${LIBMPV_SRC}"
      RESULT_VARIABLE EXTRACT_RES
    )
  else()
    message(STATUS "Using cmake -E tar for libmpv extraction")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E tar xvf "${LIBMPV_ARCHIVE}"
      WORKING_DIRECTORY "${LIBMPV_SRC}"
      RESULT_VARIABLE EXTRACT_RES
    )
  endif()

  if(NOT EXTRACT_RES EQUAL 0)
    message(FATAL_ERROR "Failed to extract ${LIBMPV_ARCHIVE}")
  endif()

  # Flatten include headers so both <client.h> and <mpv/client.h> work
  if(EXISTS "${LIBMPV_SRC}/include/mpv" AND NOT EXISTS "${LIBMPV_SRC}/include/client.h")
    file(GLOB MPV_HEADERS "${LIBMPV_SRC}/include/mpv/*")
    foreach(hdr IN LISTS MPV_HEADERS)
      file(COPY "${hdr}" DESTINATION "${LIBMPV_SRC}/include")
    endforeach()
  endif()
endif()

# ------------------------------------------------------------------------------
# Extract ANGLE
set(ANGLE_ARCHIVE "${CMAKE_BINARY_DIR}/${ANGLE}")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

download_and_verify(
  "${ANGLE_URL}"
  "${ANGLE_HASH_TYPE}"
  "${ANGLE_HASH}"
  "${ANGLE_ARCHIVE}"
)

if(NOT EXISTS "${ANGLE_SRC}/lib/libEGL.dll.lib")
  message(STATUS "Extracting ${ANGLE} to ${ANGLE_SRC}...")
  file(REMOVE_RECURSE "${ANGLE_SRC}")
  file(MAKE_DIRECTORY "${ANGLE_SRC}")

  if(SEVENZ_EXECUTABLE)
    message(STATUS "Using 7zip for ANGLE extraction: ${SEVENZ_EXECUTABLE}")
    execute_process(
      COMMAND "${SEVENZ_EXECUTABLE}" x -y "${ANGLE_ARCHIVE}"
      WORKING_DIRECTORY "${ANGLE_SRC}"
      RESULT_VARIABLE ANGLE_EXTRACT_RES
    )
  elseif(TAR_EXECUTABLE)
    message(STATUS "Using tar for ANGLE extraction: ${TAR_EXECUTABLE}")
    execute_process(
      COMMAND "${TAR_EXECUTABLE}" -xf "${ANGLE_ARCHIVE}" -C "${ANGLE_SRC}"
      RESULT_VARIABLE ANGLE_EXTRACT_RES
    )
  else()
    message(STATUS "Using cmake -E tar for ANGLE extraction")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E tar xvf "${ANGLE_ARCHIVE}"
      WORKING_DIRECTORY "${ANGLE_SRC}"
      RESULT_VARIABLE ANGLE_EXTRACT_RES
    )
  endif()

  if(NOT ANGLE_EXTRACT_RES EQUAL 0)
    message(FATAL_ERROR "Failed to extract ${ANGLE_ARCHIVE}")
  endif()

  # On ARM64 ANGLE, runtime DLLs are placed in lib/, copy them to ANGLE_SRC root
  file(GLOB ANGLE_DLLS "${ANGLE_SRC}/lib/*.dll")
  foreach(dll IN LISTS ANGLE_DLLS)
    file(COPY "${dll}" DESTINATION "${ANGLE_SRC}")
  endforeach()

  # Ensure EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE is defined for media_kit_video compatibility
  if(EXISTS "${ANGLE_SRC}/include/EGL/eglext_angle.h")
    file(READ "${ANGLE_SRC}/include/EGL/eglext_angle.h" EGLEXT_CONTENT)
    if(NOT EGLEXT_CONTENT MATCHES "EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE")
      file(APPEND "${ANGLE_SRC}/include/EGL/eglext_angle.h" "\n#ifndef EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE\n#define EGL_PLATFORM_ANGLE_TYPE_D3D9_ANGLE 0x3207\n#endif\n")
    endif()
  endif()
endif()

# ------------------------------------------------------------------------------
set(PLUGIN_NAME "media_kit_libs_windows_video_plugin")

add_library(
  ${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
)
if(EXISTS "${ANGLE_SRC}/zlib.dll")
  list(APPEND media_kit_libs_windows_video_bundled_libraries "${ANGLE_SRC}/zlib.dll")
endif()
if(EXISTS "${ANGLE_SRC}/lib/vk_swiftshader_icd.json")
  list(APPEND media_kit_libs_windows_video_bundled_libraries "${ANGLE_SRC}/lib/vk_swiftshader_icd.json")
endif()
set(media_kit_libs_windows_video_bundled_libraries "${media_kit_libs_windows_video_bundled_libraries}" PARENT_SCOPE)
