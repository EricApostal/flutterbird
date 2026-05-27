#ifndef ENGINE_H
#define ENGINE_H

#include <stdint.h>

#ifndef __cplusplus
#if !defined(__bool_true_false_are_defined)
typedef _Bool bool;
#define true 1
#define false 0
#define __bool_true_false_are_defined 1
#endif
#endif

#if defined(_WIN32)
#define LADYBIRD_API __declspec(dllexport)
#else
#define LADYBIRD_API                                                           \
  __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*FrameCallback)(void *);
typedef void (*ResizeCallback)();

typedef struct {
  int fd;
  int width;
  int height;
  int pitch;
  uint32_t drm_format;
  uint64_t modifier;
  bool premultiplied;
  uint64_t generation;
} LadybirdLinuxDmaBufFrame;

LADYBIRD_API void init_ladybird();

LADYBIRD_API int create_web_view();
LADYBIRD_API void destroy_web_view(int view_id);

LADYBIRD_API void *get_latest_pixel_buffer(int view_id);
LADYBIRD_API bool copy_latest_pixel_buffer(int view_id, uint8_t *out_buffer,
                                           int out_capacity, int *out_width,
                                           int *out_height);
LADYBIRD_API uint64_t get_frame_generation(int view_id);
LADYBIRD_API bool acquire_latest_frame(int view_id, const uint8_t **out_pixels,
                                       int *out_width, int *out_height,
                                       int *out_pitch, uint64_t *out_generation,
                                       void **out_frame_handle);
LADYBIRD_API void release_latest_frame(void *frame_handle);
LADYBIRD_API bool
acquire_latest_linux_dmabuf_frame(int view_id,
                                  LadybirdLinuxDmaBufFrame *out_frame);

LADYBIRD_API void set_frame_callback(int view_id, FrameCallback callback,
                                     void *context);

LADYBIRD_API void set_resize_callback(int view_id, ResizeCallback callback);

LADYBIRD_API void resize_window(int view_id, int width, int height);

LADYBIRD_API void navigate_to(int view_id, const char *url);

LADYBIRD_API void set_zoom(int view_id, double zoom);

LADYBIRD_API int get_iosurface_width(int view_id);

LADYBIRD_API int get_iosurface_height(int view_id);

typedef void (*UrlChangeCallback)(const char *);
typedef void (*TitleChangeCallback)(const char *);
typedef void (*FaviconChangeCallback)(const uint8_t *, int, int);
typedef void (*CrossSiteNavigationCallback)(int view_id);
typedef void (*LoadingStateChangeCallback)(bool is_loading);

LADYBIRD_API void set_url_change_callback(int view_id,
                                          UrlChangeCallback callback);
LADYBIRD_API void set_title_change_callback(int view_id,
                                            TitleChangeCallback callback);
LADYBIRD_API void set_favicon_change_callback(int view_id,
                                              FaviconChangeCallback callback);
LADYBIRD_API void
set_cross_site_navigation_callback(int view_id,
                                   CrossSiteNavigationCallback callback);
LADYBIRD_API void
set_loading_state_change_callback(int view_id,
                                  LoadingStateChangeCallback callback);
LADYBIRD_API bool is_tab_loading(int view_id);

LADYBIRD_API void tick_ladybird();

LADYBIRD_API void reload_tab(int view_id);
LADYBIRD_API void go_back(int view_id);
LADYBIRD_API void go_forward(int view_id);
LADYBIRD_API bool can_go_back(int view_id);
LADYBIRD_API bool can_go_forward(int view_id);

// Returns a JSON array string with bookmark items from
// LibWebView::BookmarkStore. Caller owns returned memory and must free it.
LADYBIRD_API char *get_bookmarks_json();

// Toggles bookmark status for the current URL in the target view.
LADYBIRD_API void toggle_bookmark_for_view(int view_id);

// Returns whether the current URL in the target view is bookmarked.
LADYBIRD_API bool is_current_view_bookmarked(int view_id);

// Returns a JSON array string of history autocomplete entries.
// Caller owns returned memory and must free it.
LADYBIRD_API char *history_autocomplete_json(const char *query, int limit);

LADYBIRD_API void dispatch_mouse_event(int view_id, int type, int x, int y,
                                       int button, int buttons, int modifiers,
                                       double wheel_delta_x,
                                       double wheel_delta_y);

LADYBIRD_API void dispatch_key_event(int view_id, int type, int keycode,
                                     int modifiers, uint32_t code_point,
                                     bool repeat);

typedef char *(*AskUserForDownloadPathCallback)(const char *suggestion);
typedef void (*DisplayDownloadConfirmationDialogCallback)(
    const char *suggestion, const char *path);
typedef void (*DisplayErrorDialogCallback)(const char *message);

LADYBIRD_API void set_ask_user_for_download_path_callback(
    AskUserForDownloadPathCallback callback);
LADYBIRD_API void set_display_download_confirmation_dialog_callback(
    DisplayDownloadConfirmationDialogCallback callback);
LADYBIRD_API void
set_display_error_dialog_callback(DisplayErrorDialogCallback callback);

#ifdef __cplusplus
}
#endif

#endif // ENGINE_H