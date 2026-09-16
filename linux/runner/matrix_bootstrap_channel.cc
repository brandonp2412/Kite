#include "matrix_bootstrap_channel.h"

#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstring>

namespace {

constexpr char kChannelName[] = "nz.presley.kite/matrix_bootstrap";
constexpr char kErrorCode[] = "matrix_bootstrap_error";

FlMethodResponse* error_response(const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(kErrorCode, message, nullptr));
}

bool ensure_private_directory(const char* path) {
  if (g_mkdir_with_parents(path, 0700) != 0) {
    return false;
  }
  return chmod(path, 0700) == 0;
}

gchar* matrix_data_root() {
  return g_build_filename(g_get_user_data_dir(), "nz.presley.kite", "matrix",
                          nullptr);
}

bool read_secret(const char* path, gchar** value) {
  gsize length = 0;
  if (!g_file_get_contents(path, value, &length, nullptr)) {
    return false;
  }
  if (length == 0 || *value == nullptr || (*value)[0] == '\0') {
    g_clear_pointer(value, g_free);
    return false;
  }
  return true;
}

bool fill_random_bytes(guint8* bytes, gsize length) {
  int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return false;
  }

  gsize offset = 0;
  while (offset < length) {
    ssize_t count = read(fd, bytes + offset, length - offset);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      close(fd);
      return false;
    }
    offset += static_cast<gsize>(count);
  }
  return close(fd) == 0;
}

bool write_all(int fd, const gchar* value, gsize length) {
  gsize offset = 0;
  while (offset < length) {
    ssize_t count = write(fd, value + offset, length - offset);
    if (count < 0 && errno == EINTR) {
      continue;
    }
    if (count <= 0) {
      return false;
    }
    offset += static_cast<gsize>(count);
  }
  return fsync(fd) == 0;
}

gchar* resolve_store_secret(const char* key_id) {
  g_autofree gchar* root = matrix_data_root();
  if (!ensure_private_directory(root)) {
    return nullptr;
  }

  g_autofree gchar* secret_dir = g_build_filename(root, "secrets", nullptr);
  if (!ensure_private_directory(secret_dir)) {
    return nullptr;
  }

  g_autofree gchar* key_hash =
      g_compute_checksum_for_string(G_CHECKSUM_SHA256, key_id, -1);
  g_autofree gchar* path =
      g_build_filename(secret_dir, key_hash, nullptr);

  gchar* existing = nullptr;
  if (read_secret(path, &existing)) {
    return existing;
  }

  guint8 random_bytes[32];
  if (!fill_random_bytes(random_bytes, sizeof(random_bytes))) {
    return nullptr;
  }
  g_autofree gchar* encoded =
      g_base64_encode(random_bytes, sizeof(random_bytes));
  std::memset(random_bytes, 0, sizeof(random_bytes));

  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
  if (fd < 0) {
    if (errno == EEXIST && read_secret(path, &existing)) {
      return existing;
    }
    return nullptr;
  }

  const gsize length = std::strlen(encoded);
  const bool wrote = write_all(fd, encoded, length);
  const bool closed = close(fd) == 0;
  if (!wrote || !closed) {
    unlink(path);
    return nullptr;
  }
  chmod(path, 0600);
  return g_strdup(encoded);
}

void handle_method_call(FlMethodChannel*, FlMethodCall* method_call, gpointer) {
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);

  if (std::strcmp(method, "dataRoot") == 0) {
    g_autofree gchar* root = matrix_data_root();
    if (!ensure_private_directory(root)) {
      response = error_response("Matrix data root is unavailable.");
    } else {
      g_autoptr(FlValue) result = fl_value_new_string(root);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
  } else if (std::strcmp(method, "resolveStoreSecret") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      response = error_response("Matrix store key id is missing.");
    } else {
      FlValue* key = fl_value_lookup_string(args, "keyId");
      if (key == nullptr || fl_value_get_type(key) != FL_VALUE_TYPE_STRING) {
        response = error_response("Matrix store key id is invalid.");
      } else {
        const gchar* key_id = fl_value_get_string(key);
        if (key_id == nullptr || key_id[0] == '\0') {
          response = error_response("Matrix store key id is invalid.");
        } else {
          g_autofree gchar* secret = resolve_store_secret(key_id);
          if (secret == nullptr) {
            response = error_response("Matrix store secret is unavailable.");
          } else {
            g_autoptr(FlValue) result = fl_value_new_string(secret);
            response =
                FL_METHOD_RESPONSE(fl_method_success_response_new(result));
          }
        }
      }
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

}  // namespace

void matrix_bootstrap_channel_register(FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, handle_method_call, nullptr,
                                            nullptr);
}
