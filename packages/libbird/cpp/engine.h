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

LADYBIRD_API void configure_android_runtime(const char *resource_root,
                                            const char *user_dir,
                                            const char *native_library_dir,
                                            const char *certificates_path);

LADYBIRD_API void init_ladybird();

LADYBIRD_API int create_web_view();
LADYBIRD_API void destroy_web_view(int view_id);

LADYBIRD_API void *get_latest_pixel_buffer(int view_id);
LADYBIRD_API bool copy_latest_pixel_buffer(int view_id, uint8_t *out_buffer,
                                           int out_capacity, int *out_width,
                                           int *out_height);
LADYBIRD_API void *get_android_hardware_buffer(int view_id);
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

// Sets the page's preferred color scheme, mirroring the host's light/dark
// theme so `prefers-color-scheme` media queries resolve correctly.
// color_scheme: 0 = Auto, 1 = Dark, 2 = Light (matches
// Web::CSS::PreferredColorScheme).
LADYBIRD_API void set_preferred_color_scheme(int view_id, int color_scheme);

LADYBIRD_API void set_display_metadata(int view_id, bool has_display_id,
                                       uint64_t display_id,
                                       double refresh_rate,
                                       double maximum_frames_per_second);

LADYBIRD_API int get_iosurface_width(int view_id);

LADYBIRD_API int get_iosurface_height(int view_id);

typedef void (*UrlChangeCallback)(const char *);
typedef void (*TitleChangeCallback)(const char *);
typedef void (*FaviconChangeCallback)(const uint8_t *, int, int);
typedef void (*CrossSiteNavigationCallback)(int view_id);
typedef void (*LoadingStateChangeCallback)(bool is_loading);
typedef void (*CursorChangeCallback)(int cursor_type);
typedef void (*ContextMenuRequestCallback)(int view_id, char *menu_json);
typedef void (*NewWebViewCallback)(int new_view_id, bool activate_tab);
typedef void (*InputCaretRectChangeCallback)(int view_id, bool has_rect, int x,
                                             int y, int width, int height);

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
LADYBIRD_API void set_cursor_change_callback(int view_id,
                                             CursorChangeCallback callback);
LADYBIRD_API void set_context_menu_request_callback(
  int view_id, ContextMenuRequestCallback callback);
LADYBIRD_API void set_new_web_view_callback(int view_id,
                                            NewWebViewCallback callback);
LADYBIRD_API void
set_input_caret_rect_change_callback(int view_id,
                                     InputCaretRectChangeCallback callback);
LADYBIRD_API bool activate_context_menu_action(int view_id, int action_token);
LADYBIRD_API bool is_tab_loading(int view_id);

// Feeds committed/composed text from a platform input method (e.g. a Flutter
// soft keyboard IME) into the currently-focused editable element.
LADYBIRD_API void commit_text_from_input_method(int view_id, const char *text);
// Sets in-progress (preedit/marked) composition text, replacing any previous
// marked text. Used for predictive/composed input methods (e.g. Pinyin).
LADYBIRD_API void set_marked_text_from_input_method(int view_id,
                                                     const char *text);
// Finalizes (commits in place) any current marked text.
LADYBIRD_API void unmark_text_from_input_method(int view_id);

LADYBIRD_API void tick_ladybird();

LADYBIRD_API void reload_tab(int view_id);
LADYBIRD_API void go_back(int view_id);
LADYBIRD_API void go_forward(int view_id);
LADYBIRD_API bool can_go_back(int view_id);
LADYBIRD_API bool can_go_forward(int view_id);
LADYBIRD_API char *get_view_url(int view_id);

// Returns a JSON array string with bookmark items from
// LibWebView::BookmarkStore. Caller owns returned memory and must free it.
LADYBIRD_API char *get_bookmarks_json();

// Toggles bookmark status for the current URL in the target view.
LADYBIRD_API void toggle_bookmark_for_view(int view_id);

// Returns whether the current URL in the target view is bookmarked.
LADYBIRD_API bool is_current_view_bookmarked(int view_id);

// Returns a JSON array string of history autocomplete entries. Suggestions
// always come from the non-private history store, matching
// WebView::Autocomplete, regardless of whether the target view is private.
// Caller owns returned memory and must free it.
LADYBIRD_API char *history_autocomplete_json(int view_id, const char *query,
                                              int limit);

// Returns a JSON array string of the engine's built-in search engines, each
// with "name" and "queryUrl" fields. Caller owns returned memory and must
// free it.
LADYBIRD_API char *get_builtin_search_engines_json();

// Returns the name of the currently configured search engine, or nullptr if
// no explicit search engine has been configured (the embedder should treat
// this as "use the default"). Caller owns returned memory and must free it.
LADYBIRD_API char *get_search_engine_name();

// Sets the active search engine by name (must match a builtin or custom
// search engine name). Pass nullptr or an empty string to clear the
// selection and fall back to the default.
LADYBIRD_API void set_search_engine(const char *name);

// Returns a JSON array string describing all generic config variables
// exposed by the engine (name, title, description, default value, and
// optional array element type). Caller owns returned memory and must free
// it.
LADYBIRD_API char *get_config_variable_definitions_json();

// Returns the current JSON-encoded value of a config variable by name, or
// nullptr if the name is not recognized. Caller owns returned memory and
// must free it.
LADYBIRD_API char *get_config_variable_json(const char *name);

// Sets a config variable by name from a JSON-encoded value. Returns false if
// the name is not recognized (invalid values are silently ignored, matching
// engine behavior).
LADYBIRD_API bool set_config_variable_json(const char *name,
                                           const char *json_value);

// Returns a JSON object string snapshot of all engine settings (search
// engine, tab settings, zoom, languages, browsing behavior, etc), as defined
// by WebView::Settings::serialize_json(). Caller owns returned memory and
// must free it.
LADYBIRD_API char *get_settings_json();

LADYBIRD_API void copy_selection(int view_id);
LADYBIRD_API void paste_from_clipboard(int view_id);
LADYBIRD_API void select_all(int view_id);

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

// Fired whenever a download is created or its progress/status changes.
// Payload is a single JSON object: {id, url, fileName, destination, status,
// downloadedSize, totalSize, error}, matching the shape returned by
// get_downloads_json()'s array entries. Caller owns the string and must free
// it (mirrors every other *_json callback/getter in this header).
typedef void (*DownloadUpdateCallback)(const char *download_json);
// Fired when a download is pruned from the engine's tracked list.
typedef void (*DownloadRemovedCallback)(uint64_t id);

LADYBIRD_API void
set_download_update_callback(DownloadUpdateCallback callback);
LADYBIRD_API void
set_download_removed_callback(DownloadRemovedCallback callback);

// Returns a JSON array string snapshot of all known downloads. Caller owns
// returned memory and must free it.
LADYBIRD_API char *get_downloads_json();
LADYBIRD_API void cancel_download(uint64_t id);
LADYBIRD_API void open_download(uint64_t id);
LADYBIRD_API void show_download_in_folder(uint64_t id);
LADYBIRD_API void prune_inactive_downloads();

// Bridges the engine's clipboard access to the host Flutter layer (e.g.
// package:flutter/services.dart Clipboard), since the engine itself has no
// access to the real OS clipboard. GetClipboardTextCallback is invoked
// synchronously mid-paste, so the embedder must have the text ready
// up-front (e.g. by pre-fetching Clipboard.getData before triggering
// paste_from_clipboard). Caller owns the returned string and must free it.
typedef char *(*GetClipboardTextCallback)();
// Invoked with the plain-text selection whenever the engine wants to write
// to the system clipboard (e.g. after a "Copy" action). Fire-and-forget.
typedef void (*SetClipboardTextCallback)(const char *text);

LADYBIRD_API void
set_get_clipboard_text_callback(GetClipboardTextCallback callback);
LADYBIRD_API void
set_set_clipboard_text_callback(SetClipboardTextCallback callback);

#ifdef __cplusplus
}
#endif

#endif // ENGINE_H