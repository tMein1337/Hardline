// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "screencast_plugin.h"

#include <cstdlib>
#include <cstring>
#include <string>

#ifdef HARDLINE_SCREENCAST
#include <unistd.h>

#include <map>
#include <memory>

#include "pipewire_capture.h"
#include "portal_session.h"
#include "webrtc_bridge.h"
#endif

namespace {

constexpr char kMethodChannel[] = "hardline/screencast";
constexpr char kEventChannel[] = "hardline/screencast/events";

FlMethodChannel* g_methods = nullptr;
FlEventChannel* g_events = nullptr;

void Respond(FlMethodCall* call, FlMethodResponse* response) {
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("[screencast] could not respond: %s", error->message);
  }
  g_object_unref(response);
}

#ifdef HARDLINE_SCREENCAST

bool IsWaylandSession() {
  const char* type = getenv("XDG_SESSION_TYPE");
  return type != nullptr && strcmp(type, "wayland") == 0;
}

void RespondError(FlMethodCall* call, const char* code,
                  const std::string& message) {
  Respond(call, FL_METHOD_RESPONSE(fl_method_error_response_new(
                    code, message.c_str(), nullptr)));
}

using hardline_screencast::InjectedTrack;
using hardline_screencast::PipeWireCapture;
using hardline_screencast::PortalSession;

struct Share {
  // Destroyed in reverse order: the capture stops before the portal session
  // is closed.
  std::unique_ptr<PortalSession> portal;
  InjectedTrack track;
  std::unique_ptr<PipeWireCapture> capture;
};

// Every share, by session id, including ones still waiting for the user.
// Only touched on the platform thread.
std::map<std::string, std::unique_ptr<Share>>& Shares() {
  static auto* shares = new std::map<std::string, std::unique_ptr<Share>>();
  return *shares;
}

std::string NewSessionId() {
  static unsigned next = 1;
  return "portal:" + std::to_string(next++);
}

void SendEnded(const std::string& session_id) {
  if (g_events == nullptr) return;
  g_autoptr(FlValue) event = fl_value_new_map();
  fl_value_set_string_take(event, "event", fl_value_new_string("ended"));
  fl_value_set_string_take(event, "sessionId",
                           fl_value_new_string(session_id.c_str()));
  fl_event_channel_send(g_events, event, nullptr, nullptr);
}

// Ends a share from the platform thread, if it still exists. Dart is told
// only about a share it was given in the first place.
void EndShare(const std::string& session_id, bool notify) {
  auto it = Shares().find(session_id);
  if (it == Shares().end()) return;
  Shares().erase(it);
  if (notify) SendEnded(session_id);
}

// The capture reports from PipeWire's thread; the share is ended from the
// platform thread, where it lives.
void EndShareSoon(const std::string& session_id, bool notify = true) {
  struct Pending {
    std::string id;
    bool notify;
  };
  auto* pending = new Pending{session_id, notify};
  g_idle_add(
      [](gpointer data) -> gboolean {
        auto* pending = static_cast<Pending*>(data);
        EndShare(pending->id, pending->notify);
        delete pending;
        return G_SOURCE_REMOVE;
      },
      pending);
}

void HandleStart(FlMethodCall* call) {
  if (!IsWaylandSession()) {
    RespondError(call, "unavailable", "not a Wayland session");
    return;
  }
  const std::string session_id = NewSessionId();
  auto share = std::make_unique<Share>();
  share->portal = std::make_unique<PortalSession>(
      [session_id]() { EndShareSoon(session_id); });
  PortalSession* portal = share->portal.get();
  Shares()[session_id] = std::move(share);

  g_object_ref(call);
  portal->Start([call, session_id](PortalSession::Result result) {
    auto it = Shares().find(session_id);
    if (it == Shares().end()) {
      // Stopped while the picker was open. Nothing to answer with.
      if (result.fd >= 0) close(result.fd);
      Respond(call, FL_METHOD_RESPONSE(
                        fl_method_success_response_new(nullptr)));
      g_object_unref(call);
      return;
    }
    Share* share = it->second.get();

    if (result.status != PortalSession::Result::Status::kOk) {
      // Erased later: this runs inside the portal session's own callback.
      EndShareSoon(session_id, false);
      if (result.status == PortalSession::Result::Status::kCancelled) {
        Respond(call, FL_METHOD_RESPONSE(
                          fl_method_success_response_new(nullptr)));
      } else {
        RespondError(call, "portal", result.error);
      }
      g_object_unref(call);
      return;
    }

    std::string error;
    if (!hardline_screencast::CreateInjectedTrack(&share->track, &error)) {
      close(result.fd);
      EndShareSoon(session_id, false);
      RespondError(call, "webrtc", error);
      g_object_unref(call);
      return;
    }
    share->capture = std::make_unique<PipeWireCapture>(
        share->track.source, [session_id]() { EndShareSoon(session_id); });
    if (!share->capture->Start(result.fd, result.node_id, &error)) {
      EndShareSoon(session_id, false);
      RespondError(call, "pipewire", error);
      g_object_unref(call);
      return;
    }

    g_autoptr(FlValue) value = fl_value_new_map();
    fl_value_set_string_take(value, "sessionId",
                             fl_value_new_string(session_id.c_str()));
    fl_value_set_string_take(
        value, "streamId", fl_value_new_string(share->track.stream_id.c_str()));
    fl_value_set_string_take(
        value, "trackId", fl_value_new_string(share->track.track_id.c_str()));
    Respond(call, FL_METHOD_RESPONSE(fl_method_success_response_new(value)));
    g_object_unref(call);
  });
}

void HandleStop(FlMethodCall* call) {
  FlValue* args = fl_method_call_get_args(call);
  FlValue* id = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                    ? fl_value_lookup_string(args, "sessionId")
                    : nullptr;
  if (id != nullptr && fl_value_get_type(id) == FL_VALUE_TYPE_STRING) {
    // Stopped on request: no "ended" event, Dart already knows.
    Shares().erase(fl_value_get_string(id));
  }
  Respond(call, FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr)));
}

#endif  // HARDLINE_SCREENCAST

void HandleMethodCall(FlMethodChannel*, FlMethodCall* call, gpointer) {
  const gchar* method = fl_method_call_get_name(call);
  if (strcmp(method, "isAvailable") == 0) {
#ifdef HARDLINE_SCREENCAST
    const bool available = IsWaylandSession() && PortalSession::IsAvailable();
#else
    const bool available = false;
#endif
    g_autoptr(FlValue) value = fl_value_new_bool(available);
    Respond(call, FL_METHOD_RESPONSE(fl_method_success_response_new(value)));
    return;
  }
#ifdef HARDLINE_SCREENCAST
  if (strcmp(method, "start") == 0) {
    HandleStart(call);
    return;
  }
  if (strcmp(method, "stop") == 0) {
    HandleStop(call);
    return;
  }
#endif
  Respond(call, FL_METHOD_RESPONSE(fl_method_not_implemented_response_new()));
}

}  // namespace

void hardline_screencast_register(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry,
                                                  "HardlineScreencast");
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  g_methods =
      fl_method_channel_new(messenger, kMethodChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_methods, HandleMethodCall,
                                            nullptr, nullptr);
  // Dart listens before the first share and never stops; there is nothing to
  // set up or tear down per listener.
  g_events =
      fl_event_channel_new(messenger, kEventChannel, FL_METHOD_CODEC(codec));
}
