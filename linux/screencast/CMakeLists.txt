# SPDX-FileCopyrightText: 2026 Mein1337
# SPDX-License-Identifier: AGPL-3.0-or-later

# Wayland screen sharing (xdg-desktop-portal + PipeWire), see
# screencast_plugin.h. Included after the generated plugin rules, because it
# builds against flutter_webrtc's headers and libwebrtc.so.
#
# Without the PipeWire, EGL or GLES headers this still builds, as a stub whose
# `isAvailable` answers false; the app then says sharing is unavailable on
# Wayland instead of failing to build.

add_library(hardline_screencast STATIC "screencast_plugin.cc")
apply_standard_settings(hardline_screencast)
set_target_properties(hardline_screencast PROPERTIES
  CXX_STANDARD 17
  POSITION_INDEPENDENT_CODE ON)
target_link_libraries(hardline_screencast PRIVATE flutter PkgConfig::GTK)

pkg_check_modules(SCREENCAST_DEPS IMPORTED_TARGET
  libpipewire-0.3 egl glesv2 gio-unix-2.0)

if(SCREENCAST_DEPS_FOUND AND TARGET flutter_webrtc_plugin)
  get_target_property(WEBRTC_PLUGIN_DIR flutter_webrtc_plugin SOURCE_DIR)
  target_sources(hardline_screencast PRIVATE
    "egl_dmabuf.cc"
    "i420.cc"
    "pipewire_capture.cc"
    "portal_session.cc"
    "webrtc_bridge.cc"
  )
  # RTC_DESKTOP_DEVICE changes the layout of libwebrtc's factory interface;
  # it must match what flutter_webrtc was built with. The forced <cstdint>
  # is flutter_webrtc's own workaround for libwebrtc's headers.
  target_compile_definitions(hardline_screencast PRIVATE
    HARDLINE_SCREENCAST RTC_DESKTOP_DEVICE)
  target_compile_options(hardline_screencast PRIVATE -include cstdint)
  target_include_directories(hardline_screencast PRIVATE
    "${WEBRTC_PLUGIN_DIR}"
    "${WEBRTC_PLUGIN_DIR}/flutter/include"
    "${WEBRTC_PLUGIN_DIR}/../common/cpp/include"
    "${WEBRTC_PLUGIN_DIR}/../third_party/libwebrtc/include"
  )
  target_link_libraries(hardline_screencast PRIVATE
    PkgConfig::SCREENCAST_DEPS
    flutter_webrtc_plugin
    "${WEBRTC_PLUGIN_DIR}/../third_party/libwebrtc/lib/libwebrtc.so"
  )
  message(STATUS "hardline: Wayland screen sharing enabled")
else()
  message(WARNING "hardline: libpipewire-0.3, egl, glesv2 or gio-unix-2.0 "
    "not found -- screen sharing on Wayland disabled.")
endif()
