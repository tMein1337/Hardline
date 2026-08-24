// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef RUNNER_OVERLAY_BRIDGE_H_
#define RUNNER_OVERLAY_BRIDGE_H_

#include <flutter/binary_messenger.h>
#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <string>

#include "overlay_window.h"

// Everything the overlay needs from Win32, and the wire between the two
// engines.
//
// Three jobs that all want the same message loop, which is why they are one
// class rather than three:
//
//  * **The control channel.** `hardline/overlay` on the app engine: show, hide,
//    click-through, monitor, capture exclusion, hotkeys.
//  * **The relay.** State pushed from the app engine is forwarded to the
//    overlay engine, and events from the overlay come back. Both engines are in
//    this process, so this is a pointer hop rather than IPC -- but they are
//    different isolates and cannot see each other's memory, so it still has to
//    be a message.
//  * **The watches.** Which application is in the foreground, and the global
//    hotkeys. Both arrive as Win32 messages on the main thread and have nowhere
//    else to be handled.
//
// The overlay engine is created lazily, on the first `show`. Somebody who never
// turns the overlay on never pays for a second Flutter engine.
class OverlayBridge {
 public:
  // `project` is the app's own DartProject; the overlay's copy differs only in
  // its entry point, which OverlayWindow sets.
  explicit OverlayBridge(flutter::BinaryMessenger* app_messenger,
                         const flutter::DartProject& project);
  ~OverlayBridge();

  OverlayBridge(OverlayBridge const&) = delete;
  OverlayBridge& operator=(OverlayBridge const&) = delete;

 private:
  using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

  void HandleCall(const MethodCall& call, std::unique_ptr<MethodResult> result);

  // Brings the overlay engine up if it is not already. Returns false when the
  // window or engine could not be created, which leaves the overlay simply
  // unavailable rather than taking the app down with it.
  bool EnsureOverlay();

  // Sends the overlay engine a state payload, dropping it if there is no
  // overlay yet -- the next push after `show` carries the whole state anyway.
  void PushState(const std::string& payload);

  // Tells the app engine something happened out here.
  void Emit(const std::string& method, flutter::EncodableValue arguments);

  void ReportForeground(HWND foreground);

  // A hidden window, purely to have somewhere for WM_HOTKEY to be delivered.
  // The overlay window would do, except that it does not exist until the
  // overlay is first shown, and a hotkey has to work before then.
  bool CreateMessageWindow();
  static LRESULT CALLBACK MessageWindowProc(HWND window, UINT message,
                                            WPARAM wparam,
                                            LPARAM lparam) noexcept;
  static void CALLBACK ForegroundHook(HWINEVENTHOOK hook, DWORD event,
                                      HWND window, LONG object_id,
                                      LONG child_id, DWORD thread,
                                      DWORD timestamp);

  flutter::BinaryMessenger* app_messenger_ = nullptr;
  flutter::DartProject project_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> control_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> events_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> to_overlay_;

  std::unique_ptr<OverlayWindow> overlay_;

  HWND message_window_ = nullptr;
  HWINEVENTHOOK foreground_hook_ = nullptr;

  // The last executable reported, so a window change within one application
  // does not re-push a layout that has not changed.
  std::string last_executable_;
};

#endif  // RUNNER_OVERLAY_BRIDGE_H_
