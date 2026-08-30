// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "overlay_bridge.h"

#include <flutter/standard_method_codec.h>
#include <psapi.h>

#include <cwctype>
#include <string>
#include <vector>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

constexpr char kControlChannel[] = "hardline/overlay";
constexpr char kEventChannel[] = "hardline/overlay_events";
constexpr char kOverlayChannel[] = "hardline/overlay_state";

constexpr wchar_t kMessageWindowClass[] = L"HARDLINE_OVERLAY_BRIDGE";

// The one bridge. A WinEvent hook and a window procedure are both C callbacks
// with no user pointer worth the name, and there is exactly one bridge per
// process, so a file-scope pointer is honest about the situation rather than
// pretending to a generality that does not exist.
OverlayBridge* g_bridge = nullptr;

const EncodableValue* Lookup(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(std::string(key)));
  return it == map.end() ? nullptr : &it->second;
}

std::string StringArg(const EncodableMap& map, const char* key) {
  const EncodableValue* value = Lookup(map, key);
  if (!value || !std::holds_alternative<std::string>(*value)) return {};
  return std::get<std::string>(*value);
}

bool BoolArg(const EncodableMap& map, const char* key, bool fallback) {
  const EncodableValue* value = Lookup(map, key);
  if (!value || !std::holds_alternative<bool>(*value)) return fallback;
  return std::get<bool>(*value);
}

int IntArg(const EncodableMap& map, const char* key, int fallback) {
  const EncodableValue* value = Lookup(map, key);
  if (!value) return fallback;
  if (std::holds_alternative<int32_t>(*value)) {
    return std::get<int32_t>(*value);
  }
  if (std::holds_alternative<int64_t>(*value)) {
    return static_cast<int>(std::get<int64_t>(*value));
  }
  return fallback;
}

const EncodableMap* AsMap(const EncodableValue* value) {
  if (!value || !std::holds_alternative<EncodableMap>(*value)) return nullptr;
  return &std::get<EncodableMap>(*value);
}

std::string Narrow(const wchar_t* wide, size_t length) {
  if (!wide || length == 0) return std::string();
  int size = ::WideCharToMultiByte(CP_UTF8, 0, wide, static_cast<int>(length),
                                   nullptr, 0, nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string out(static_cast<size_t>(size), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, wide, static_cast<int>(length), out.data(),
                        size, nullptr, nullptr);
  return out;
}

// The foreground window's executable, lowercased, without its directory.
//
// `QueryFullProcessImageNameW` with PROCESS_QUERY_LIMITED_INFORMATION rather
// than reading the module list: limited information is the least this can ask
// for and the only variant that succeeds against an elevated process, which
// several launchers are.
std::string ExecutableOf(HWND window) {
  DWORD pid = 0;
  ::GetWindowThreadProcessId(window, &pid);
  if (pid == 0) return {};

  HANDLE process =
      ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return {};

  wchar_t path[MAX_PATH] = {};
  DWORD length = MAX_PATH;
  const BOOL ok = ::QueryFullProcessImageNameW(process, 0, path, &length);
  ::CloseHandle(process);
  if (!ok || length == 0) return {};

  const wchar_t* name = path;
  for (DWORD i = 0; i < length; i++) {
    if (path[i] == L'\\' || path[i] == L'/') name = path + i + 1;
  }

  std::wstring lowered(name);
  for (wchar_t& c : lowered) c = static_cast<wchar_t>(::towlower(c));
  return Narrow(lowered.c_str(), lowered.size());
}

std::string TitleOf(HWND window) {
  const int length = ::GetWindowTextLengthW(window);
  if (length <= 0) return {};
  std::wstring buffer(static_cast<size_t>(length) + 1, L'\0');
  const int copied =
      ::GetWindowTextW(window, buffer.data(), static_cast<int>(buffer.size()));
  if (copied <= 0) return {};
  return Narrow(buffer.c_str(), static_cast<size_t>(copied));
}

}  // namespace

OverlayBridge::OverlayBridge(flutter::BinaryMessenger* app_messenger,
                             const flutter::DartProject& project)
    : app_messenger_(app_messenger), project_(project) {
  g_bridge = this;

  control_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      app_messenger_, kControlChannel,
      &flutter::StandardMethodCodec::GetInstance());
  control_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleCall(call, std::move(result));
      });

  events_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      app_messenger_, kEventChannel,
      &flutter::StandardMethodCodec::GetInstance());

  CreateMessageWindow();

  // WINEVENT_OUTOFCONTEXT: the callback is delivered while this thread pumps
  // messages, so it lands on the platform thread with the engines, and nothing
  // is injected into the watched process.
  foreground_hook_ = ::SetWinEventHook(
      EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, nullptr,
      &OverlayBridge::ForegroundHook, 0, 0,
      WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);
}

OverlayBridge::~OverlayBridge() {
  if (foreground_hook_) ::UnhookWinEvent(foreground_hook_);
  if (message_window_) {
    // Any hotkey still registered dies with the window it was registered on.
    ::DestroyWindow(message_window_);
  }
  overlay_ = nullptr;
  g_bridge = nullptr;
}

bool OverlayBridge::CreateMessageWindow() {
  static bool registered = false;
  if (!registered) {
    WNDCLASSW window_class = {};
    window_class.lpszClassName = kMessageWindowClass;
    window_class.lpfnWndProc = &OverlayBridge::MessageWindowProc;
    window_class.hInstance = ::GetModuleHandle(nullptr);
    if (!::RegisterClassW(&window_class)) return false;
    registered = true;
  }

  message_window_ = ::CreateWindowExW(
      0, kMessageWindowClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr,
      ::GetModuleHandle(nullptr), nullptr);
  return message_window_ != nullptr;
}

bool OverlayBridge::EnsureOverlay() {
  if (overlay_ && overlay_->ok()) return true;

  auto overlay = std::make_unique<OverlayWindow>(project_);
  if (!overlay->Create()) return false;
  overlay_ = std::move(overlay);

  // The key Dart asked for before there was a window to ask about.
  //
  // `setChromaKey` arrives before the first `show` -- deliberately, so the
  // window's very first frame is keyed correctly -- but at that point there is
  // no window and the request had nowhere to go. It used to be dropped, so the
  // first overlay of a session was created keying the compiled-in default
  // while Dart painted the palette's colour. On any theme where those differ
  // that is nothing keyed at all: an opaque sheet, on the first call after
  // launch and no other.
  overlay_->SetChromaKey(pending_chroma_key_);

  to_overlay_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      overlay_->messenger(), kOverlayChannel,
      &flutter::StandardMethodCodec::GetInstance());

  // The overlay talks back on the same channel: drag results out of edit mode,
  // and anything clicked on the HUD. Forwarded verbatim, because the two halves
  // of that conversation are both Dart and the shape of it is none of this
  // file's business.
  to_overlay_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "event" && call.arguments() &&
            std::holds_alternative<std::string>(*call.arguments())) {
          Emit("overlayEvent", *call.arguments());
        }
        result->Success();
      });

  return true;
}

void OverlayBridge::PushState(const std::string& payload) {
  if (!to_overlay_) return;
  to_overlay_->InvokeMethod("state",
                            std::make_unique<EncodableValue>(payload));
}

void OverlayBridge::Emit(const std::string& method,
                         EncodableValue arguments) {
  if (!events_) return;
  events_->InvokeMethod(method,
                        std::make_unique<EncodableValue>(std::move(arguments)));
}

void OverlayBridge::HandleCall(const MethodCall& call,
                               std::unique_ptr<MethodResult> result) {
  const std::string& method = call.method_name();
  const EncodableMap* args = AsMap(call.arguments());
  const EncodableMap empty;
  const EncodableMap& map = args ? *args : empty;

  if (method == "isSupported") {
    result->Success(EncodableValue(true));
    return;
  }

  if (method == "listMonitors") {
    EncodableList monitors;
    for (const OverlayWindow::Monitor& monitor :
         OverlayWindow::EnumerateMonitors()) {
      monitors.push_back(EncodableValue(EncodableMap{
          {EncodableValue("id"), EncodableValue(monitor.id)},
          {EncodableValue("label"), EncodableValue(monitor.label)},
          {EncodableValue("primary"), EncodableValue(monitor.primary)},
          {EncodableValue("width"),
           EncodableValue(static_cast<int32_t>(monitor.bounds.right -
                                               monitor.bounds.left))},
          {EncodableValue("height"),
           EncodableValue(static_cast<int32_t>(monitor.bounds.bottom -
                                               monitor.bounds.top))},
      }));
    }
    result->Success(EncodableValue(monitors));
    return;
  }

  if (method == "show") {
    if (!EnsureOverlay()) {
      result->Error("overlay_unavailable",
                    "The overlay window or its engine could not be created.");
      return;
    }
    const std::string monitor = StringArg(map, "monitor");
    if (!monitor.empty()) overlay_->SetMonitor(monitor);
    overlay_->SetExcludedFromCapture(BoolArg(map, "excludeFromCapture", true));
    overlay_->SetClickThrough(BoolArg(map, "clickThrough", true));
    overlay_->Show();
    // Whatever the app knew before the window existed never reached it.
    PushState(StringArg(map, "state"));
    result->Success();
    return;
  }

  if (method == "hide") {
    if (overlay_) overlay_->Hide();
    result->Success();
    return;
  }

  if (method == "setClickThrough") {
    if (overlay_) overlay_->SetClickThrough(BoolArg(map, "value", true));
    result->Success();
    return;
  }

  if (method == "setChromaKey") {
    // ARGB from Dart; the alpha is ignored and COLORREF is 0x00BBGGRR.
    const int argb = IntArg(map, "value", 0);
    // Remembered whether or not there is a window yet. `EnsureOverlay` applies
    // it on creation, which is the only way the first frame of the first
    // overlay of a session can be keyed on the right colour.
    pending_chroma_key_ =
        RGB((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF);
    if (overlay_) overlay_->SetChromaKey(pending_chroma_key_);
    result->Success();
    return;
  }

  if (method == "setOpacity") {
    if (overlay_) overlay_->SetOpacity(IntArg(map, "value", 255));
    result->Success();
    return;
  }

  if (method == "setMonitor") {
    if (overlay_) overlay_->SetMonitor(StringArg(map, "id"));
    result->Success();
    return;
  }

  if (method == "setCaptureExclusion") {
    if (overlay_) overlay_->SetExcludedFromCapture(BoolArg(map, "value", true));
    result->Success();
    return;
  }

  if (method == "pushState") {
    PushState(StringArg(map, "state"));
    result->Success();
    return;
  }

  if (method == "registerHotkey") {
    if (!message_window_) {
      result->Error("no_message_window", "The hotkey sink does not exist.");
      return;
    }
    const int id = IntArg(map, "id", 0);
    // Re-registering the same id is how a rebind works, and Windows refuses a
    // duplicate rather than replacing it.
    ::UnregisterHotKey(message_window_, id);
    const int mods = IntArg(map, "modifiers", 0);
    const int key = IntArg(map, "key", 0);
    if (key == 0) {
      result->Success(EncodableValue(false));
      return;
    }
    // MOD_NOREPEAT: a held-down chord must fire once, not sixty times a second.
    const BOOL ok = ::RegisterHotKey(
        message_window_, id, static_cast<UINT>(mods) | MOD_NOREPEAT,
        static_cast<UINT>(key));
    result->Success(EncodableValue(ok != FALSE));
    return;
  }

  if (method == "unregisterHotkey") {
    if (message_window_) ::UnregisterHotKey(message_window_, IntArg(map, "id", 0));
    result->Success();
    return;
  }

  if (method == "foregroundApp") {
    HWND foreground = ::GetForegroundWindow();
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("executable"), EncodableValue(ExecutableOf(foreground))},
        {EncodableValue("title"), EncodableValue(TitleOf(foreground))},
    }));
    return;
  }

  result->NotImplemented();
}

void OverlayBridge::ReportForeground(HWND foreground) {
  const std::string executable = ExecutableOf(foreground);
  if (executable.empty()) return;

  // Alt-tabbing between two windows of the same application is not a change of
  // layout, and re-pushing one would restart every fade on the HUD.
  if (executable == last_executable_) return;
  last_executable_ = executable;

  Emit("foregroundApp", EncodableValue(EncodableMap{
                            {EncodableValue("executable"),
                             EncodableValue(executable)},
                            {EncodableValue("title"),
                             EncodableValue(TitleOf(foreground))},
                        }));
}

void CALLBACK OverlayBridge::ForegroundHook(HWINEVENTHOOK, DWORD event,
                                            HWND window, LONG object_id, LONG,
                                            DWORD, DWORD) {
  // OBJID_WINDOW only: the same event fires for controls inside a window, and
  // those are not applications changing.
  if (!g_bridge || event != EVENT_SYSTEM_FOREGROUND ||
      object_id != OBJID_WINDOW || !window) {
    return;
  }
  g_bridge->ReportForeground(window);
}

LRESULT CALLBACK OverlayBridge::MessageWindowProc(HWND window, UINT message,
                                                  WPARAM wparam,
                                                  LPARAM lparam) noexcept {
  if (message == WM_HOTKEY && g_bridge) {
    g_bridge->Emit("hotkey",
                   EncodableValue(static_cast<int32_t>(wparam)));
    return 0;
  }
  return ::DefWindowProc(window, message, wparam, lparam);
}
