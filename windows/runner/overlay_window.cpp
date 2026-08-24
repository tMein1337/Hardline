// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "overlay_window.h"

#include <dwmapi.h>

namespace {

constexpr wchar_t kOverlayWindowClass[] = L"HARDLINE_OVERLAY_WINDOW";

// How often HWND_TOPMOST is re-asserted, in milliseconds.
//
// Slow enough to be free, fast enough that a window which has jumped over the
// overlay is back underneath before anybody reaches for the mouse.
constexpr UINT kTopmostInterval = 2000;

// Windows 10 2004 and later. Declared here because the SDK this builds against
// may predate it, and the call is made through GetProcAddress anyway.
#ifndef WDA_EXCLUDEFROMCAPTURE
constexpr DWORD WDA_EXCLUDEFROMCAPTURE = 0x00000011;
#endif

// ---------------------------------------------------------------------------
// SetWindowCompositionAttribute
//
// Undocumented, and the only thing on Windows that makes a Flutter window
// per-pixel transparent. `flutter_acrylic` and `bitsdojo_window` both reach for
// it for the same reason; there is no supported alternative that composites a
// D3D swapchain against the desktop with alpha.
//
// Resolved at runtime rather than linked: it is not in any import library, and
// a missing export must degrade to an opaque overlay rather than a process that
// will not start.
// ---------------------------------------------------------------------------

enum AccentState {
  ACCENT_DISABLED = 0,
  ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
};

struct AccentPolicy {
  AccentState state;
  DWORD flags;
  DWORD gradient_colour;  // AABBGGRR; the alpha is what does the work.
  DWORD animation_id;
};

struct WindowCompositionAttributeData {
  DWORD attribute;  // 19 == WCA_ACCENT_POLICY
  PVOID data;
  SIZE_T size;
};

using SetWindowCompositionAttributeFn =
    BOOL(WINAPI*)(HWND, WindowCompositionAttributeData*);

SetWindowCompositionAttributeFn ResolveComposition() {
  static SetWindowCompositionAttributeFn resolved = [] {
    HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
    if (!user32) return static_cast<SetWindowCompositionAttributeFn>(nullptr);
    return reinterpret_cast<SetWindowCompositionAttributeFn>(
        ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  }();
  return resolved;
}

using SetWindowDisplayAffinityFn = BOOL(WINAPI*)(HWND, DWORD);

SetWindowDisplayAffinityFn ResolveDisplayAffinity() {
  static SetWindowDisplayAffinityFn resolved = [] {
    HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
    if (!user32) return static_cast<SetWindowDisplayAffinityFn>(nullptr);
    return reinterpret_cast<SetWindowDisplayAffinityFn>(
        ::GetProcAddress(user32, "SetWindowDisplayAffinity"));
  }();
  return resolved;
}

std::string Narrow(const wchar_t* wide) {
  if (!wide || !*wide) return std::string();
  int size = ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr,
                                   nullptr);
  if (size <= 1) return std::string();
  std::string out(static_cast<size_t>(size - 1), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), size, nullptr,
                        nullptr);
  return out;
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM param) {
  auto* out = reinterpret_cast<std::vector<OverlayWindow::Monitor>*>(param);

  MONITORINFOEXW info = {};
  info.cbSize = sizeof(info);
  if (!::GetMonitorInfoW(monitor, &info)) return TRUE;

  const bool primary = (info.dwFlags & MONITORINFOF_PRIMARY) != 0;
  const LONG width = info.rcMonitor.right - info.rcMonitor.left;
  const LONG height = info.rcMonitor.bottom - info.rcMonitor.top;

  std::string label = std::to_string(width) + "x" + std::to_string(height);
  if (primary) label += " (primary)";

  out->push_back({Narrow(info.szDevice), label, info.rcMonitor, primary});
  return TRUE;
}

}  // namespace

OverlayWindow::OverlayWindow(const flutter::DartProject& project)
    : project_(project) {
  // The engine looks the entry point up by name in the library that holds
  // `main`, so `overlayMain` lives in lib/main.dart and carries
  // `@pragma('vm:entry-point')` -- without it AOT drops the function as
  // unreachable and the overlay engine starts into nothing.
  project_.set_dart_entrypoint("overlayMain");
}

OverlayWindow::~OverlayWindow() {
  if (topmost_timer_ != 0 && window_) {
    ::KillTimer(window_, topmost_timer_);
  }
  controller_ = nullptr;
  if (window_) {
    ::DestroyWindow(window_);
    window_ = nullptr;
  }
}

bool OverlayWindow::Create() {
  static bool registered = false;
  if (!registered) {
    WNDCLASSW window_class = {};
    window_class.lpszClassName = kOverlayWindowClass;
    window_class.lpfnWndProc = OverlayWindow::WndProc;
    window_class.hInstance = ::GetModuleHandle(nullptr);
    window_class.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
    // No background brush, so nothing paints over the transparency before
    // Flutter's first frame arrives.
    window_class.hbrBackground = nullptr;
    if (!::RegisterClassW(&window_class)) return false;
    registered = true;
  }

  const std::vector<Monitor> monitors = EnumerateMonitors();
  RECT bounds = {0, 0, 1280, 720};
  for (const Monitor& monitor : monitors) {
    if (monitor.primary) {
      bounds = monitor.bounds;
      monitor_id_ = monitor.id;
      break;
    }
  }

  // WS_POPUP: no frame, no caption, no system menu -- the overlay is a sheet of
  // glass, not a window anybody manages.
  //
  // WS_EX_TOOLWINDOW keeps it out of the taskbar and out of alt-tab, which
  // matters more than it sounds: an overlay that can be tabbed to is an overlay
  // that can steal focus from the game by accident.
  window_ = ::CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE |
          WS_EX_TRANSPARENT,
      kOverlayWindowClass, L"Hardline Overlay", WS_POPUP, bounds.left,
      bounds.top, bounds.right - bounds.left, bounds.bottom - bounds.top,
      nullptr, nullptr, ::GetModuleHandle(nullptr), this);
  if (!window_) return false;

  ApplyTransparency();
  SetExcludedFromCapture(excluded_from_capture_);

  RECT client = {};
  ::GetClientRect(window_, &client);
  controller_ = std::make_unique<flutter::FlutterViewController>(
      client.right - client.left, client.bottom - client.top, project_);
  if (!controller_->engine() || !controller_->view()) {
    controller_ = nullptr;
    ::DestroyWindow(window_);
    window_ = nullptr;
    return false;
  }

  // Deliberately no RegisterPlugins here -- see the header for why registering
  // flutter_webrtc a second time would break the app's own calls.

  // Parented and sized the way `Win32Window::SetChildContent` does it, with
  // one deliberate omission: no `SetFocus`. Taking the keyboard here would pull
  // the foreground away from whatever is running the moment the overlay
  // appears, which on a fullscreen game means minimising it.
  HWND content = controller_->view()->GetNativeWindow();
  ::SetParent(content, window_);
  ::MoveWindow(content, 0, 0, client.right - client.left,
               client.bottom - client.top, true);

  topmost_timer_ = ::SetTimer(window_, 1, kTopmostInterval, nullptr);
  return true;
}

flutter::BinaryMessenger* OverlayWindow::messenger() const {
  return controller_ ? controller_->engine()->messenger() : nullptr;
}

void OverlayWindow::Show() {
  if (!window_ || visible_) return;
  visible_ = true;
  // SW_SHOWNOACTIVATE, always: showing the overlay must never pull the
  // foreground away from the game, which on a fullscreen one would minimise it.
  ::ShowWindow(window_, SW_SHOWNOACTIVATE);
  ReassertTopmost();
}

void OverlayWindow::Hide() {
  if (!window_ || !visible_) return;
  visible_ = false;
  ::ShowWindow(window_, SW_HIDE);
}

void OverlayWindow::SetClickThrough(bool click_through) {
  if (!window_) return;
  click_through_ = click_through;

  LONG_PTR ex_style = ::GetWindowLongPtr(window_, GWL_EXSTYLE);
  if (click_through) {
    ex_style |= WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
  } else {
    // Both bits have to go. WS_EX_TRANSPARENT alone would keep the mouse out;
    // WS_EX_NOACTIVATE alone would let the mouse in but never give the window
    // the keyboard, so an editor could be clicked but not typed into.
    ex_style &= ~(WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
  }
  ::SetWindowLongPtr(window_, GWL_EXSTYLE, ex_style);

  if (!click_through && visible_) {
    // Taking the foreground costs the game its fullscreen exclusivity. That is
    // the right trade while somebody is dragging avatars around, and it is why
    // this is a mode rather than the default.
    ::SetForegroundWindow(window_);
  }
  ReassertTopmost();
}

void OverlayWindow::SetMonitor(const std::string& monitor_id) {
  if (!window_) return;

  const std::vector<Monitor> monitors = EnumerateMonitors();
  if (monitors.empty()) return;

  const Monitor* chosen = nullptr;
  for (const Monitor& monitor : monitors) {
    if (monitor.id == monitor_id) {
      chosen = &monitor;
      break;
    }
  }
  // A monitor named in a saved layout may have been unplugged since. Falling
  // back to the primary one is better than leaving the overlay somewhere the
  // user cannot see, wondering why it stopped working.
  if (!chosen) {
    for (const Monitor& monitor : monitors) {
      if (monitor.primary) chosen = &monitor;
    }
  }
  if (!chosen) chosen = &monitors.front();

  monitor_id_ = chosen->id;
  const RECT& bounds = chosen->bounds;
  ::SetWindowPos(window_, HWND_TOPMOST, bounds.left, bounds.top,
                 bounds.right - bounds.left, bounds.bottom - bounds.top,
                 SWP_NOACTIVATE);
}

void OverlayWindow::SetExcludedFromCapture(bool excluded) {
  excluded_from_capture_ = excluded;
  if (!window_) return;

  auto set_affinity = ResolveDisplayAffinity();
  if (!set_affinity) return;
  set_affinity(window_, excluded ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
}

std::vector<OverlayWindow::Monitor> OverlayWindow::EnumerateMonitors() {
  std::vector<Monitor> monitors;
  ::EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                        reinterpret_cast<LPARAM>(&monitors));
  return monitors;
}

void OverlayWindow::ApplyTransparency() {
  if (!window_) return;

  auto set_composition = ResolveComposition();
  if (set_composition) {
    AccentPolicy policy = {};
    policy.state = ACCENT_ENABLE_TRANSPARENTGRADIENT;
    policy.flags = 0;
    // Fully transparent black. Everything visible on the overlay comes from
    // what Flutter paints on top of it.
    policy.gradient_colour = 0x00000000;

    WindowCompositionAttributeData data = {};
    data.attribute = 19;  // WCA_ACCENT_POLICY
    data.data = &policy;
    data.size = sizeof(policy);

    if (set_composition(window_, &data)) return;
  }

  // Fallback, for a Windows build where the undocumented call is gone. Blur
  // behind an empty region is the documented way to tell DWM to honour a
  // layered window's own alpha; it is less reliable across compositor changes,
  // which is why it is second.
  DWM_BLURBEHIND blur = {};
  blur.dwFlags = DWM_BB_ENABLE | DWM_BB_BLURREGION;
  blur.fEnable = TRUE;
  blur.hRgnBlur = ::CreateRectRgn(0, 0, -1, -1);
  ::DwmEnableBlurBehindWindow(window_, &blur);
  if (blur.hRgnBlur) ::DeleteObject(blur.hRgnBlur);
}

void OverlayWindow::ReassertTopmost() {
  if (!window_ || !visible_) return;
  ::SetWindowPos(window_, HWND_TOPMOST, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

LRESULT CALLBACK OverlayWindow::WndProc(HWND window, UINT message,
                                        WPARAM wparam,
                                        LPARAM lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto* create = reinterpret_cast<CREATESTRUCT*>(lparam);
    ::SetWindowLongPtr(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(create->lpCreateParams));
  }

  auto* self = reinterpret_cast<OverlayWindow*>(
      ::GetWindowLongPtr(window, GWLP_USERDATA));
  if (self) return self->MessageHandler(window, message, wparam, lparam);

  return ::DefWindowProc(window, message, wparam, lparam);
}

LRESULT OverlayWindow::MessageHandler(HWND window, UINT message, WPARAM wparam,
                                      LPARAM lparam) noexcept {
  if (controller_) {
    std::optional<LRESULT> result =
        controller_->HandleTopLevelWindowProc(window, message, wparam, lparam);
    if (result) return *result;
  }

  switch (message) {
    case WM_TIMER:
      ReassertTopmost();
      return 0;

    case WM_SIZE: {
      if (controller_) {
        RECT client = {};
        ::GetClientRect(window, &client);
        ::MoveWindow(controller_->view()->GetNativeWindow(), 0, 0,
                     client.right - client.left, client.bottom - client.top,
                     true);
      }
      return 0;
    }

    // The overlay is never closed, only hidden. A stray close would leave the
    // app running with a dead engine and no way to get the HUD back.
    case WM_CLOSE:
      Hide();
      return 0;

    // Nothing here should ever take the foreground away from the game.
    case WM_MOUSEACTIVATE:
      return click_through_ ? MA_NOACTIVATE : MA_ACTIVATE;
  }

  return ::DefWindowProc(window, message, wparam, lparam);
}
