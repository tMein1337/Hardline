#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <memory>

#include "flutter_window.h"
#include "overlay_bridge.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Held for the life of the process so the installer can tell that Hardline
  // is running before it touches a single file.
  //
  // This is `AppMutex` in tool/hardline.iss. Without it, an upgrade relies
  // entirely on Restart Manager identifying the running window from the files
  // it is about to replace -- and when that fails the symptom is a locked DLL
  // and a half-finished install, which is a far worse outcome than being asked
  // to close the app first.
  //
  // Deliberately not used to enforce a single instance: two accounts in two
  // windows is a thing people do, and `GetLastError() == ERROR_ALREADY_EXISTS`
  // is ignored here for exactly that reason. The handle is never closed; the
  // kernel drops it when the process ends, which is precisely the lifetime the
  // installer is asking about.
  ::CreateMutexW(nullptr, FALSE, L"HardlineRunningMutex");

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // The three-column layout (rail + room list + chat) needs room to breathe;
  // a minimum size is enforced in Win32Window::MessageHandler.
  Win32Window::Size size(1400, 900);
  if (!window.Create(L"Hardline", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // The overlay's control channel, its watches, and the wire to its engine.
  // Constructed after the window because it needs the app engine's messenger,
  // and destroyed before `CoUninitialize` because it owns a second engine.
  //
  // The overlay window and engine themselves are not created here -- the bridge
  // brings them up on the first `show`, so somebody who never turns the overlay
  // on never pays for a second Flutter engine.
  std::unique_ptr<OverlayBridge> overlay_bridge;
  if (auto* messenger = window.messenger()) {
    overlay_bridge = std::make_unique<OverlayBridge>(messenger, project);
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  overlay_bridge = nullptr;

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
