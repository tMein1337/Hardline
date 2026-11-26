// SPDX-FileCopyrightText: 2026 Mein1337
// SPDX-License-Identifier: AGPL-3.0-or-later

#include "portal_session.h"

#include <gio/gunixfdlist.h>
#include <unistd.h>

#include <atomic>
#include <cstdio>
#include <utility>

namespace hardline_screencast {

namespace {

constexpr char kDestination[] = "org.freedesktop.portal.Desktop";
constexpr char kObjectPath[] = "/org/freedesktop/portal/desktop";
constexpr char kScreenCast[] = "org.freedesktop.portal.ScreenCast";
constexpr char kRequest[] = "org.freedesktop.portal.Request";
constexpr char kSession[] = "org.freedesktop.portal.Session";

// Bits of AvailableSourceTypes / SelectSources' "types".
constexpr uint32_t kMonitor = 1;
constexpr uint32_t kWindow = 2;
// Bits of AvailableCursorModes / SelectSources' "cursor_mode".
constexpr uint32_t kCursorHidden = 1;
constexpr uint32_t kCursorEmbedded = 2;

// Response codes of org.freedesktop.portal.Request.
constexpr uint32_t kResponseCancelled = 1;

// Reads one uint32 property of the ScreenCast interface, or 0.
uint32_t ReadProperty(GDBusConnection* connection, const char* name) {
  GError* error = nullptr;
  GVariant* reply = g_dbus_connection_call_sync(
      connection, kDestination, kObjectPath, "org.freedesktop.DBus.Properties",
      "Get", g_variant_new("(ss)", kScreenCast, name), G_VARIANT_TYPE("(v)"),
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  if (reply == nullptr) {
    g_clear_error(&error);
    return 0;
  }
  GVariant* value = nullptr;
  g_variant_get(reply, "(v)", &value);
  uint32_t result = 0;
  if (g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    result = g_variant_get_uint32(value);
  }
  g_variant_unref(value);
  g_variant_unref(reply);
  return result;
}

// What an async D-Bus call needs to find its way back, or to find out that
// the session it belonged to is gone.
struct CallContext {
  std::weak_ptr<int> alive;
  std::function<void(GObject*, GAsyncResult*)> done;
};

void OnCallDone(GObject* source, GAsyncResult* result, gpointer data) {
  auto* context = static_cast<CallContext*>(data);
  if (!context->alive.expired()) {
    context->done(source, result);
  } else {
    // Collect the reply anyway, so it is freed.
    GError* error = nullptr;
    GVariant* reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source),
                                                    result, &error);
    if (reply) g_variant_unref(reply);
    g_clear_error(&error);
  }
  delete context;
}

struct SignalContext {
  std::function<void(GVariant*)> handler;
};

void OnSignal(GDBusConnection*, const gchar*, const gchar*, const gchar*,
              const gchar*, GVariant* parameters, gpointer data) {
  // Copied first: the handler may unsubscribe, which frees the context.
  auto handler = static_cast<SignalContext*>(data)->handler;
  handler(parameters);
}

void FreeSignalContext(gpointer data) {
  delete static_cast<SignalContext*>(data);
}

}  // namespace

bool PortalSession::IsAvailable() {
  GDBusConnection* connection =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (connection == nullptr) return false;
  const bool available = ReadProperty(connection, "version") > 0;
  g_object_unref(connection);
  return available;
}

PortalSession::PortalSession(ClosedCallback on_closed)
    : on_closed_(std::move(on_closed)), cancellable_(g_cancellable_new()) {}

PortalSession::~PortalSession() {
  alive_.reset();
  g_cancellable_cancel(cancellable_);
  if (connection_ != nullptr) {
    if (request_subscription_ != 0) {
      g_dbus_connection_signal_unsubscribe(connection_, request_subscription_);
    }
    if (closed_subscription_ != 0) {
      g_dbus_connection_signal_unsubscribe(connection_, closed_subscription_);
    }
    if (!session_handle_.empty()) {
      g_dbus_connection_call(connection_, kDestination,
                             session_handle_.c_str(), kSession, "Close",
                             nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, -1,
                             nullptr, nullptr, nullptr);
    }
    g_object_unref(connection_);
  }
  g_object_unref(cancellable_);
}

std::string PortalSession::NewToken() {
  static std::atomic<unsigned> counter{0};
  return "hardline_" + std::to_string(g_random_int()) + "_" +
         std::to_string(counter++);
}

std::string PortalSession::RequestPath(const std::string& token) const {
  return std::string(kObjectPath) + "/request/" + sender_ + "/" + token;
}

void PortalSession::Start(StartedCallback done) {
  done_ = std::move(done);

  GError* error = nullptr;
  connection_ = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (connection_ == nullptr) {
    Fail(std::string("no D-Bus session bus: ") +
         (error ? error->message : "unknown"));
    g_clear_error(&error);
    return;
  }

  // ":1.42" becomes "1_42", the form the portal uses in Request paths.
  sender_ = g_dbus_connection_get_unique_name(connection_) + 1;
  for (char& c : sender_) {
    if (c == '.') c = '_';
  }

  source_types_ = ReadProperty(connection_, "AvailableSourceTypes");
  // Version 1 portals have no cursor modes, and the property reads as 0.
  cursor_modes_ = ReadProperty(connection_, "AvailableCursorModes");

  const std::string token = NewToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  g_variant_builder_add(&options, "{sv}", "session_handle_token",
                        g_variant_new_string(NewToken().c_str()));
  Request("CreateSession", g_variant_new("(a{sv})", &options), token,
          [this](uint32_t response, GVariant* results) {
            if (response != 0) {
              Fail("the portal refused to create a screencast session");
              return;
            }
            const gchar* handle = nullptr;
            if (!g_variant_lookup(results, "session_handle", "&s", &handle) &&
                !g_variant_lookup(results, "session_handle", "&o", &handle)) {
              Fail("the portal answered without a session");
              return;
            }
            session_handle_ = handle;

            auto* context = new SignalContext{[this](GVariant*) {
              fprintf(stderr, "[screencast] portal closed the session\n");
              session_handle_.clear();
              if (on_closed_) on_closed_();
            }};
            closed_subscription_ = g_dbus_connection_signal_subscribe(
                connection_, kDestination, kSession, "Closed",
                session_handle_.c_str(), nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
                OnSignal, context, FreeSignalContext);

            SelectSources();
          });
}

void PortalSession::SelectSources() {
  const std::string token = NewToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  uint32_t types = source_types_ & (kMonitor | kWindow);
  if (types == 0) types = kMonitor;
  g_variant_builder_add(&options, "{sv}", "types", g_variant_new_uint32(types));
  g_variant_builder_add(&options, "{sv}", "multiple",
                        g_variant_new_boolean(FALSE));
  // The pointer belongs in the picture: people point at things on a shared
  // screen. Where the portal cannot draw it in, leave it out rather than ask
  // for cursor metadata that nothing here would draw.
  if (cursor_modes_ & kCursorEmbedded) {
    g_variant_builder_add(&options, "{sv}", "cursor_mode",
                          g_variant_new_uint32(kCursorEmbedded));
  } else if (cursor_modes_ & kCursorHidden) {
    g_variant_builder_add(&options, "{sv}", "cursor_mode",
                          g_variant_new_uint32(kCursorHidden));
  }
  Request("SelectSources",
          g_variant_new("(oa{sv})", session_handle_.c_str(), &options), token,
          [this](uint32_t response, GVariant*) {
            if (response == kResponseCancelled) {
              Finish({Result::Status::kCancelled, -1, 0, {}});
              return;
            }
            if (response != 0) {
              Fail("the portal refused the source selection");
              return;
            }
            StartCast();
          });
}

void PortalSession::StartCast() {
  const std::string token = NewToken();
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  g_variant_builder_add(&options, "{sv}", "handle_token",
                        g_variant_new_string(token.c_str()));
  Request("Start",
          g_variant_new("(osa{sv})", session_handle_.c_str(), "", &options),
          token, [this](uint32_t response, GVariant* results) {
            if (response == kResponseCancelled) {
              Finish({Result::Status::kCancelled, -1, 0, {}});
              return;
            }
            if (response != 0) {
              Fail("the portal could not start the screencast");
              return;
            }
            GVariant* streams = g_variant_lookup_value(
                results, "streams", G_VARIANT_TYPE("a(ua{sv})"));
            if (streams == nullptr || g_variant_n_children(streams) < 1) {
              if (streams) g_variant_unref(streams);
              Fail("the portal started a screencast without a stream");
              return;
            }
            guint32 node_id = 0;
            GVariant* properties = nullptr;
            g_variant_get_child(streams, 0, "(u@a{sv})", &node_id,
                                &properties);
            g_variant_unref(properties);
            g_variant_unref(streams);
            OpenPipeWireRemote(node_id);
          });
}

void PortalSession::OpenPipeWireRemote(uint32_t node_id) {
  GVariantBuilder options;
  g_variant_builder_init(&options, G_VARIANT_TYPE_VARDICT);
  auto* context = new CallContext{
      alive_, [this, node_id](GObject* source, GAsyncResult* result) {
        GError* error = nullptr;
        GUnixFDList* fds = nullptr;
        GVariant* reply = g_dbus_connection_call_with_unix_fd_list_finish(
            G_DBUS_CONNECTION(source), &fds, result, &error);
        if (reply == nullptr) {
          Fail(std::string("OpenPipeWireRemote failed: ") +
               (error ? error->message : "unknown"));
          g_clear_error(&error);
          return;
        }
        gint32 index = -1;
        g_variant_get(reply, "(h)", &index);
        g_variant_unref(reply);
        const int fd = fds ? g_unix_fd_list_get(fds, index, &error) : -1;
        if (fds) g_object_unref(fds);
        if (fd < 0) {
          Fail("the portal gave no PipeWire remote");
          g_clear_error(&error);
          return;
        }
        Finish({Result::Status::kOk, fd, node_id, {}});
      }};
  g_dbus_connection_call_with_unix_fd_list(
      connection_, kDestination, kObjectPath, kScreenCast,
      "OpenPipeWireRemote",
      g_variant_new("(oa{sv})", session_handle_.c_str(), &options),
      G_VARIANT_TYPE("(h)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, cancellable_,
      [](GObject* source, GAsyncResult* result, gpointer data) {
        auto* context = static_cast<CallContext*>(data);
        if (!context->alive.expired()) {
          context->done(source, result);
        } else {
          GVariant* reply = g_dbus_connection_call_with_unix_fd_list_finish(
              G_DBUS_CONNECTION(source), nullptr, result, nullptr);
          if (reply) g_variant_unref(reply);
        }
        delete context;
      },
      context);
}

void PortalSession::Request(const char* method, GVariant* parameters,
                            const std::string& token,
                            ResponseHandler handler) {
  if (request_subscription_ != 0) {
    g_dbus_connection_signal_unsubscribe(connection_, request_subscription_);
    request_subscription_ = 0;
  }

  // Subscribed before the call, so that a portal answering very quickly
  // cannot answer into the void.
  const std::string path = RequestPath(token);
  auto* signal_context = new SignalContext{[this, handler](GVariant* params) {
    guint32 response = 2;
    GVariant* results = nullptr;
    g_variant_get(params, "(u@a{sv})", &response, &results);
    g_dbus_connection_signal_unsubscribe(connection_, request_subscription_);
    request_subscription_ = 0;
    handler(response, results);
    g_variant_unref(results);
  }};
  request_subscription_ = g_dbus_connection_signal_subscribe(
      connection_, kDestination, kRequest, "Response", path.c_str(), nullptr,
      G_DBUS_SIGNAL_FLAGS_NONE, OnSignal, signal_context, FreeSignalContext);

  const std::string name = method;
  auto* context = new CallContext{
      alive_, [this, name](GObject* source, GAsyncResult* result) {
        GError* error = nullptr;
        GVariant* reply = g_dbus_connection_call_finish(
            G_DBUS_CONNECTION(source), result, &error);
        if (reply == nullptr) {
          Fail(name + " failed: " + (error ? error->message : "unknown"));
          g_clear_error(&error);
          return;
        }
        g_variant_unref(reply);
      }};
  g_dbus_connection_call(connection_, kDestination, kObjectPath, kScreenCast,
                         method, parameters, G_VARIANT_TYPE("(o)"),
                         G_DBUS_CALL_FLAGS_NONE, -1, cancellable_, OnCallDone,
                         context);
}

void PortalSession::Finish(Result result) {
  if (!done_) {
    if (result.fd >= 0) close(result.fd);
    return;
  }
  auto done = std::move(done_);
  done_ = nullptr;
  done(std::move(result));
}

void PortalSession::Fail(const std::string& error) {
  fprintf(stderr, "[screencast] %s\n", error.c_str());
  Finish({Result::Status::kFailed, -1, 0, error});
}

}  // namespace hardline_screencast
