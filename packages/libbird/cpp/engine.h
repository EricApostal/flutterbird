#ifndef ENGINE_H
#define ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#if defined(_WIN32)
#define LADYBIRD_API __declspec(dllexport)
#else
#define LADYBIRD_API __attribute__((visibility("default"))) __attribute__((used))
#endif

#ifdef __cplusplus
extern "C"
{
#endif

    typedef void (*FrameCallback)(void *);
    typedef void (*ResizeCallback)();

    LADYBIRD_API void init_ladybird();

    LADYBIRD_API int create_web_view();
    LADYBIRD_API void destroy_web_view(int view_id);

    LADYBIRD_API void *get_latest_pixel_buffer(int view_id);

    LADYBIRD_API void set_frame_callback(int view_id, FrameCallback callback, void *context);

    LADYBIRD_API void set_resize_callback(int view_id, ResizeCallback callback);

    LADYBIRD_API void resize_window(int view_id, int width, int height);

    LADYBIRD_API void navigate_to(int view_id, const char *url);

    LADYBIRD_API void set_zoom(int view_id, double zoom);

    LADYBIRD_API int get_iosurface_width(int view_id);

    LADYBIRD_API int get_iosurface_height(int view_id);

    typedef void (*UrlChangeCallback)(const char *);
    typedef void (*TitleChangeCallback)(const char *);
    typedef void (*FaviconChangeCallback)(const uint8_t *, int, int);

    LADYBIRD_API void set_url_change_callback(int view_id, UrlChangeCallback callback);
    LADYBIRD_API void set_title_change_callback(int view_id, TitleChangeCallback callback);
    LADYBIRD_API void set_favicon_change_callback(int view_id, FaviconChangeCallback callback);

    LADYBIRD_API void tick_ladybird();

    LADYBIRD_API void reload_tab(int view_id);
    LADYBIRD_API void go_back(int view_id);
    LADYBIRD_API void go_forward(int view_id);
    LADYBIRD_API bool can_go_back(int view_id);
    LADYBIRD_API bool can_go_forward(int view_id);

    LADYBIRD_API void dispatch_mouse_event(int view_id, int type, int x, int y, int button, int buttons, int modifiers, int wheel_delta_x, int wheel_delta_y);

    LADYBIRD_API void dispatch_key_event(int view_id, int type, int keycode, int modifiers, uint32_t code_point, bool repeat);

    typedef char *(*AskUserForDownloadPathCallback)(const char *suggestion);
    typedef void (*DisplayDownloadConfirmationDialogCallback)(const char *suggestion, const char *path);
    typedef void (*DisplayErrorDialogCallback)(const char *message);

    LADYBIRD_API void set_ask_user_for_download_path_callback(AskUserForDownloadPathCallback callback);
    LADYBIRD_API void set_display_download_confirmation_dialog_callback(DisplayDownloadConfirmationDialogCallback callback);
    LADYBIRD_API void set_display_error_dialog_callback(DisplayErrorDialogCallback callback);

#ifdef __cplusplus
}
#endif

#endif // ENGINE_H