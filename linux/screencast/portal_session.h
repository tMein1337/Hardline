// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#ifndef HARDLINE_SCREENCAST_PORTAL_SESSION_H_
#define HARDLINE_SCREENCAST_PORTAL_SESSION_H_

#include <gio/gio.h>

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

namespace hardline_screencast {

// One screencast session with the xdg-desktop-portal.
//
// On Wayland an application cannot read the screen itself. It asks the
// portal, the portal asks the user (in the compositor's or desktop's own
// dialog), and answers with a PipeWire stream of whatever was picked. This
// drives that exchange over D-Bus: CreateSession, SelectSources, Start, and
// OpenPipeWireRemote. All of it runs on the GLib main loop, which is the
// Flutter platform thread; no call here blocks it except the property reads
// in IsAvailable().
class PortalSession {
 public:
  struct Result {
    enum class Status { kOk, kCancelled, kFailed };
    Status status = Status::kFailed;
    int fd = -1;  // PipeWire remote, owned by the receiver
    uint32_t node_id = 0;
    std::string error;
  };
  using StartedCallback = std::function<void(Result)>;
  // The portal or the user ended the session (for example from the
  // desktop's own "stop sharing" control).
  using ClosedCallback = std::function<void()>;

  // Whether the portal offers ScreenCast at all.
  static bool IsAvailable();

  explicit PortalSession(ClosedCallback on_closed);
  // Closes the session with the portal, which ends the PipeWire stream.
  ~PortalSession();

  PortalSession(const PortalSession&) = delete;
  PortalSession& operator=(const PortalSession&) = delete;

  // Runs the whole exchange, including the user's choice. `done` is called
  // exactly once, unless this object is destroyed first.
  void Start(StartedCallback done);

 private:
  using ResponseHandler = std::function<void(uint32_t response, GVariant*)>;

  // Calls a portal method that answers through a Request object, and hands
  // the Request's Response signal to `handler`.
  void Request(const char* method, GVariant* parameters,
               const std::string& token, ResponseHandler handler);
  void SelectSources();
  void StartCast();
  void OpenPipeWireRemote(uint32_t node_id);
  void Finish(Result result);
  void Fail(const std::string& error);

  std::string NewToken();
  std::string RequestPath(const std::string& token) const;

  ClosedCallback on_closed_;
  StartedCallback done_;
  GDBusConnection* connection_ = nullptr;
  GCancellable* cancellable_ = nullptr;
  std::string sender_;
  std::string session_handle_;
  guint request_subscription_ = 0;
  guint closed_subscription_ = 0;
  uint32_t source_types_ = 1;
  uint32_t cursor_modes_ = 0;
  // Lets async callbacks tell whether this object still exists.
  std::shared_ptr<int> alive_ = std::make_shared<int>(0);
};

}  // namespace hardline_screencast

#endif  // HARDLINE_SCREENCAST_PORTAL_SESSION_H_
