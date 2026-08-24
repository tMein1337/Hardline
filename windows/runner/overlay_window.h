// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef RUNNER_OVERLAY_WINDOW_H_
#define RUNNER_OVERLAY_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <memory>
#include <string>
#include <vector>

// A borderless, always-on-top, click-through window hosting a second Flutter
// view, for drawing over a game.
//
// Deliberately not a `Win32Window`. That class registers one window class for
// the whole application and its `WM_GETMINMAXINFO` handler enforces the app's
// 940x560 minimum, which an overlay must not inherit -- and it creates its
// window with `CreateWindow`, so there is no way to pass the extended styles
// that make a window layered, topmost and transparent to the mouse.
//
// The Flutter view it hosts runs on its **own engine**, entered at the Dart
// function `overlayMain`. That is forced rather than chosen: Flutter's
// multi-view API is `@internal` and main-channel-only on 3.44, so a second
// window means a second engine.
//
// It registers **no plugins at all**. flutter_webrtc's Windows plugin keeps a
// process-global `g_shared_instance` that the most recent registration
// overwrites, so registering it twice would leave the app's own calls talking
// to the overlay's plugin instance. The overlay needs nothing but the message
// channel the bridge gives it.
class OverlayWindow {
 public:
  // One monitor, as reported to Dart so the settings pane can offer a choice.
  struct Monitor {
    std::string id;      // The device name, e.g. "\\\\.\\DISPLAY1".
    std::string label;   // Something a person can pick from a list.
    RECT bounds;         // Virtual-screen coordinates, physical pixels.
    bool primary;
  };

  explicit OverlayWindow(const flutter::DartProject& project);
  ~OverlayWindow();

  OverlayWindow(OverlayWindow const&) = delete;
  OverlayWindow& operator=(OverlayWindow const&) = delete;

  // Creates the window and its engine, hidden. Returns false if either failed,
  // in which case the overlay is simply unavailable and the app carries on.
  bool Create();

  // Whether the window and its engine exist.
  bool ok() const { return controller_ != nullptr; }

  // The overlay engine's messenger, for the bridge to relay state over.
  // Null until Create has succeeded.
  flutter::BinaryMessenger* messenger() const;

  void Show();
  void Hide();
  bool visible() const { return visible_; }

  // Whether the mouse falls through to whatever is underneath.
  //
  // On while the overlay is only being looked at, off while it is being laid
  // out. Turning it off also drops WS_EX_NOACTIVATE and takes the foreground,
  // because an editor that cannot receive a key press is not an editor.
  void SetClickThrough(bool click_through);

  // Moves the overlay onto one monitor, covering it entirely.
  //
  // An empty id means the primary monitor, which is also the fallback when the
  // named one has been unplugged since the layout was saved.
  void SetMonitor(const std::string& monitor_id);

  // Keeps the overlay out of screen captures, so a shared screen does not
  // contain the sharer's own HUD. Windows 10 2004 and later; older builds fail
  // the call and simply keep showing it, which is a cosmetic loss rather than
  // a broken feature.
  void SetExcludedFromCapture(bool excluded);

  static std::vector<Monitor> EnumerateMonitors();

 private:
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) noexcept;
  LRESULT MessageHandler(HWND window, UINT message, WPARAM wparam,
                         LPARAM lparam) noexcept;

  // Asks DWM to treat the window's own alpha as real, so a Flutter scene
  // painted on a transparent background shows what is behind it.
  void ApplyTransparency();

  // Re-asserts HWND_TOPMOST. Other topmost windows -- a game's own overlay, a
  // volume OSD -- push us down as they come and go, and there is no event for
  // "somebody else went on top of you".
  void ReassertTopmost();

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> controller_;

  HWND window_ = nullptr;
  bool visible_ = false;
  bool click_through_ = true;
  bool excluded_from_capture_ = true;
  std::string monitor_id_;
  UINT_PTR topmost_timer_ = 0;
};

#endif  // RUNNER_OVERLAY_WINDOW_H_
