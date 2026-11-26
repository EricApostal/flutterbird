// Hosts the already built engine (libengine.dylib) for the end-to-end tests, on
// the one thread its event loop needs, and is driven over pipes by run.dart.
//
// A message either way is a line, "<name> <a> <b> <c> <length>\n", followed by
// <length> bytes of payload. The engine logs to stdout, so that is pointed at
// stderr and the protocol keeps the original stdout to itself.
//
// This builds nothing of the engine or the app: run.dart compiles this one file
// with clang and puts it beside copies of the app's helper programs, which is
// where the engine looks for them.

#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <unistd.h>

static int protocol_out = -1;
static pthread_mutex_t out_lock = PTHREAD_MUTEX_INITIALIZER;

static void write_all(const char *data, size_t length) {
  while (length > 0) {
    ssize_t written = write(protocol_out, data, length);
    if (written <= 0)
      exit(3);
    data += written;
    length -= (size_t)written;
  }
}

static void emit(const char *name, unsigned long long a, long long b,
                 long long c, const char *payload) {
  size_t length = payload ? strlen(payload) : 0;
  char header[160];
  int n = snprintf(header, sizeof header, "%s %llu %lld %lld %zu\n", name, a, b,
                   c, length);
  pthread_mutex_lock(&out_lock);
  write_all(header, (size_t)n);
  if (length)
    write_all(payload, length);
  pthread_mutex_unlock(&out_lock);
}

// Every string the engine hands to these is ours to free.
static void on_created(uint64_t context, int view, char *uuid, char *url,
                       bool top) {
  size_t length = strlen(uuid) + strlen(url) + 2;
  char *joined = malloc(length);
  snprintf(joined, length, "%s\n%s", uuid, url);
  emit("created", context, view, top, joined);
  free(joined);
  free(uuid);
  free(url);
}

static void on_destroyed(uint64_t context) {
  emit("destroyed", context, 0, 0, NULL);
}

static void on_message(uint64_t context, char *payload) {
  emit("message", context, 0, 0, payload);
  free(payload);
}

static void on_intercept(uint64_t request, int view, char *details) {
  emit("intercept", request, view, 0, details);
  free(details);
}

// The engine's per-view callbacks say nothing of which view they are about, so
// each view gets functions of its own.
#define VIEWS(X)                                                               \
  X(1) X(2) X(3) X(4) X(5) X(6) X(7) X(8) X(9) X(10) X(11) X(12) X(13) X(14)   \
  X(15) X(16) X(17) X(18) X(19) X(20) X(21) X(22) X(23) X(24) X(25) X(26)      \
  X(27) X(28) X(29) X(30) X(31) X(32) X(33) X(34) X(35) X(36) X(37) X(38)      \
  X(39) X(40) X(41) X(42) X(43) X(44) X(45) X(46) X(47) X(48) X(49) X(50)      \
  X(51) X(52) X(53) X(54) X(55) X(56) X(57) X(58) X(59) X(60) X(61) X(62)      \
  X(63) X(64)

#define VIEW_CALLBACKS(n)                                                      \
  static void on_url_##n(char *url) {                                          \
    emit("url", n, 0, 0, url);                                                 \
    free(url);                                                                 \
  }                                                                            \
  static void on_loading_##n(bool loading) {                                   \
    emit("loading", n, loading, 0, NULL);                                      \
  }
VIEWS(VIEW_CALLBACKS)

#define URL_ENTRY(n) on_url_##n,
#define LOADING_ENTRY(n) on_loading_##n,
static void (*const url_callbacks[])(char *) = {VIEWS(URL_ENTRY)};
static void (*const loading_callbacks[])(bool) = {VIEWS(LOADING_ENTRY)};

#define LOAD(name, type)                                                       \
  __typeof__(type) name = (__typeof__(type))dlsym(engine, #name);              \
  if (!name) {                                                                 \
    fprintf(stderr, "engine_host: the engine has no %s\n", #name);             \
    return 2;                                                                  \
  }

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: engine_host <libengine.dylib>\n");
    return 2;
  }
  protocol_out = dup(STDOUT_FILENO);
  dup2(STDERR_FILENO, STDOUT_FILENO);

  void *engine = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
  if (!engine) {
    fprintf(stderr, "engine_host: %s\n", dlerror());
    return 2;
  }

  LOAD(init_ladybird, void (*)(void));
  LOAD(tick_ladybird, void (*)(void));
  LOAD(create_web_view, int (*)(void));
  LOAD(destroy_web_view, void (*)(int));
  LOAD(resize_window, void (*)(int, int, int));
  LOAD(navigate_to, void (*)(int, const char *));
  LOAD(set_extension_callbacks,
       void (*)(void (*)(uint64_t, int, char *, char *, bool),
                void (*)(uint64_t), void (*)(uint64_t, char *)));
  LOAD(set_extension_intercept_callback,
       void (*)(void (*)(uint64_t, int, char *)));
  LOAD(respond_extension_intercept, bool (*)(uint64_t, const char *));
  LOAD(set_extension_state, void (*)(const char *));
  LOAD(send_extension_message, bool (*)(uint64_t, const char *));

  LOAD(set_url_change_callback, void (*)(int, void (*)(char *)));
  LOAD(set_loading_state_change_callback, void (*)(int, void (*)(bool)));

  // Absent from engines built before it was added, which the screen size check
  // then reports.
  void (*set_screen_size)(int, int, int) =
      (void (*)(int, int, int))dlsym(engine, "set_screen_size");

  init_ladybird();
  set_extension_callbacks(on_created, on_destroyed, on_message);
  emit("ready", 0, 0, 0, NULL);

  size_t capacity = 1 << 20, used = 0;
  char *buffer = malloc(capacity);

  for (;;) {
    tick_ladybird();

    fd_set readable;
    FD_ZERO(&readable);
    FD_SET(STDIN_FILENO, &readable);
    struct timeval wait = {0, 1000};
    if (select(STDIN_FILENO + 1, &readable, NULL, NULL, &wait) <= 0)
      continue;

    if (capacity - used < (1 << 16)) {
      capacity *= 2;
      buffer = realloc(buffer, capacity);
    }
    ssize_t got = read(STDIN_FILENO, buffer + used, capacity - used);
    if (got <= 0)
      return 0;
    used += (size_t)got;

    for (;;) {
      char *newline = memchr(buffer, '\n', used);
      if (!newline)
        break;
      char name[32];
      unsigned long long a;
      long long b, c;
      size_t length;
      if (sscanf(buffer, "%31s %llu %lld %lld %zu", name, &a, &b, &c,
                 &length) != 5)
        return 3;
      size_t header = (size_t)(newline - buffer) + 1;
      if (used < header + length)
        break;

      char *payload = malloc(length + 1);
      memcpy(payload, buffer + header, length);
      payload[length] = 0;
      memmove(buffer, buffer + header + length, used - header - length);
      used -= header + length;

      if (!strcmp(name, "create")) {
        int view = create_web_view();
        if (view >= 0)
          resize_window(view, 1280, 800);
        // As the app does, which knows the screen its window is on.
        if (view >= 0 && set_screen_size)
          set_screen_size(view, 2560, 1440);
        if (view >= 1 && view <= 64) {
          set_url_change_callback(view, url_callbacks[view - 1]);
          set_loading_state_change_callback(view, loading_callbacks[view - 1]);
        }
        emit("view", a, view, 0, NULL);
      } else if (!strcmp(name, "destroy")) {
        destroy_web_view((int)a);
      } else if (!strcmp(name, "navigate")) {
        navigate_to((int)a, payload);
      } else if (!strcmp(name, "state")) {
        set_extension_state(payload);
      } else if (!strcmp(name, "send")) {
        send_extension_message(a, payload);
      } else if (!strcmp(name, "intercepting")) {
        set_extension_intercept_callback(on_intercept);
      } else if (!strcmp(name, "verdict")) {
        respond_extension_intercept(a, payload);
      } else if (!strcmp(name, "quit")) {
        return 0;
      }
      free(payload);
    }
  }
}
