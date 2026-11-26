// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef HARDLINE_SCREENCAST_PLUGIN_H_
#define HARDLINE_SCREENCAST_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

// Screen sharing on Wayland, through the xdg-desktop-portal and PipeWire.
//
// flutter_webrtc's bundled libwebrtc only captures X11 screens. This answers
// the "hardline/screencast" method channel instead: `isAvailable`, `start`
// (shows the desktop's own picker, returns the ids of a local video track
// registered with flutter_webrtc) and `stop`. "hardline/screencast/events"
// reports a share that ended from outside the app.
//
// Built without PipeWire or EGL headers, the channel still answers, with
// `isAvailable` false.
void hardline_screencast_register(FlPluginRegistry* registry);

#endif  // HARDLINE_SCREENCAST_PLUGIN_H_
