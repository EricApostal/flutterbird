#include "engine.h"
#include "LibWebView/Application.h"
#include <cstdio>
#include <cerrno>
#include <memory>
#include <mutex>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Platform-specific backend header.  All __APPLE__ ifdefs live here and
// in the on_ready_to_paint lambda — nowhere else in this file.
#ifdef __APPLE__
#include "platform/macos_view_backend.h"
#include <IOSurface/IOSurface.h>
#else
#include "platform/linux_view_backend.h"
#endif

#ifdef __ANDROID__
#include <android/hardware_buffer.h>
#endif

#ifdef __APPLE__
// For opening downloaded files with their default handler / revealing them in
// Finder (see open_download / show_download_in_folder).
#include <crt_externs.h>
#include <spawn.h>
#endif

#include <AK/Base64.h>
#include <AK/BitCast.h>
#include <AK/Error.h>
#include <AK/HashMap.h>
#include <AK/JsonArray.h>
#include <AK/JsonObject.h>
#include <AK/LexicalPath.h>
#include <AK/OwnPtr.h>
#include <AK/StringView.h>
#include <AK/Time.h>
#include <LibCore/Environment.h>
#include <LibCore/EventLoop.h>
#include <LibCore/Promise.h>
#include <LibCore/ResourceImplementation.h>
#include <LibCore/ResourceImplementationFile.h>
#include <LibCore/System.h>
#include <LibCore/ThreadEventQueue.h>
#include <LibGfx/Bitmap.h>
#include <LibGfx/SharedImageBuffer.h>
#include <LibGfx/SystemTheme.h>
#include <LibMain/Main.h>
#include <LibURL/Parser.h>
#include <LibURL/URL.h>
#include <LibWebCommon/CSS/PreferredColorScheme.h>
#include <LibWebCommon/HTML/ActivateTab.h>
#include <LibWebCommon/HTML/VisibilityState.h>
#include <LibWebCommon/HTML/WebViewHints.h>
#include <LibWebCommon/Page/InputEvent.h>
#include <LibWebCommon/Page/ViewportIsFullscreen.h>
#include <LibWebCommon/PixelUnits.h>
#include <LibWebCommon/WebView/Utilities.h>
#include <LibDatabase/Database.h>
#include <LibGfx/ImageFormats/PNGWriter.h>
#include <LibWebCommon/Clipboard/SystemClipboard.h>
#include <LibWebView/Application.h>
#include <LibWebView/BrowsingSession.h>
#include <LibWebView/ContextMenuRequest.h>
#include <LibWebView/FaviconStore.h>
#include <LibWebView/FileDownloader.h>
#include <LibWebView/HistoryDebug.h>
#include <LibWebView/HistoryStore.h>
#include <LibWebView/Options.h>
#include <LibWebView/SearchEngine.h>
#include <LibWebView/Settings.h>
#include <LibWebView/URL.h>
#include <LibWebView/ViewImplementation.h>
#include <LibWebView/WebContentPage.h>
#ifndef __APPLE__
#include <unistd.h>
#endif

namespace WebView {
// The resource root the engine resolves `res/` out of; declared in
// LibWebCommon/WebView/Utilities.h.
}

int g_next_view_id = 1;
int g_active_view_id = -1;
// False until init_ladybird() has a fully initialized WebView::Application;
// every entry point that touches the engine checks it, so a failed or absent
// initialization degrades to no-ops instead of a null-application crash.
static bool g_engine_ready = false;

// Upstream 2026-11 moved the history and favicon stores out of LibWebView and
// into the browser's UI, which now owns them and records visits, titles and
// favicons itself. The engine is that UI for FlutterBird, so it owns the same
// stores here; the autocomplete ABI and the bookmark store (in bird_core, which
// reads these stores through the favicon lookup below) use them.
static AK::OwnPtr<WebView::FaviconStore> g_favicon_store;
static AK::OwnPtr<WebView::HistoryStore> g_history_store;

static void create_engine_stores() {
  auto const &paths = WebView::Application::profile().paths();

  if (WebView::Application::browser_options().disable_sql_database !=
      WebView::DisableSQLDatabase::No) {
    g_favicon_store = WebView::FaviconStore::create();
    g_history_store = WebView::HistoryStore::create_disabled();
    return;
  }

  // The History database is shared by the favicon and history stores, so
  // preflight both before applying either migration: a database written by a
  // newer build must be left untouched, as the Qt frontend does.
  auto created = [&]() -> ErrorOr<bool> {
    auto database = TRY(Database::Database::create(paths.data, "History"sv));
    auto favicons_outcome = TRY(WebView::FaviconStore::migrate_schema(
        database, Database::MigrationMode::CheckOnly));
    auto history_outcome = TRY(WebView::HistoryStore::migrate_schema(
        database, Database::MigrationMode::CheckOnly));
    if (favicons_outcome != Database::MigrationOutcome::Success ||
        history_outcome != Database::MigrationOutcome::Success)
      return false;
    if (TRY(WebView::FaviconStore::migrate_schema(database)) !=
        Database::MigrationOutcome::Success)
      return false;
    if (TRY(WebView::HistoryStore::migrate_schema(database)) !=
        Database::MigrationOutcome::Success)
      return false;

    g_favicon_store = TRY(WebView::FaviconStore::create(database));
    g_history_store = TRY(WebView::HistoryStore::create(database));
    return true;
  }();

  if (created.is_error() || !created.value()) {
    if (created.is_error())
      std::fprintf(stderr,
                   "[Ladybird] Unable to open the History database: %d\n",
                   created.error().code());
    g_favicon_store = WebView::FaviconStore::create();
    g_history_store = WebView::HistoryStore::create(*g_favicon_store);
  }
}

AskUserForDownloadPathCallback g_ask_user_for_download_path_callback = nullptr;
DisplayDownloadConfirmationDialogCallback
    g_display_download_confirmation_dialog_callback = nullptr;
DisplayErrorDialogCallback g_display_error_dialog_callback = nullptr;
GetClipboardTextCallback g_get_clipboard_text_callback = nullptr;
SetClipboardTextCallback g_set_clipboard_text_callback = nullptr;
DownloadUpdateCallback g_download_update_callback = nullptr;
DownloadRemovedCallback g_download_removed_callback = nullptr;

#ifdef __ANDROID__
struct AndroidRuntimeConfig {
  ByteString resource_root;
  ByteString user_dir;
  ByteString native_library_dir;
  ByteString certificates_path;

  bool is_valid() const {
    return !resource_root.is_empty() && !user_dir.is_empty();
  }
};

static std::mutex g_android_runtime_mutex;
static AndroidRuntimeConfig g_android_runtime_config;

static AndroidRuntimeConfig snapshot_android_runtime_config() {
  std::lock_guard lock(g_android_runtime_mutex);
  return g_android_runtime_config;
}

extern "C" void configure_android_runtime(const char *resource_root,
                                          const char *user_dir,
                                          const char *native_library_dir,
                                          const char *certificates_path) {
  std::lock_guard lock(g_android_runtime_mutex);
  g_android_runtime_config.resource_root =
      resource_root ? ByteString(resource_root) : ByteString{};
  g_android_runtime_config.user_dir =
      user_dir ? ByteString(user_dir) : ByteString{};
  g_android_runtime_config.native_library_dir =
      native_library_dir ? ByteString(native_library_dir) : ByteString{};
  g_android_runtime_config.certificates_path =
      certificates_path ? ByteString(certificates_path) : ByteString{};
}

static void apply_android_runtime_config(AndroidRuntimeConfig const &config) {
  auto const config_dir = ByteString::formatted("{}/config", config.user_dir);
  auto const data_dir = ByteString::formatted("{}/userdata", config.user_dir);
  auto const runtime_dir = ByteString::formatted("{}/runtime", config.user_dir);
  auto const cache_dir = ByteString::formatted("{}/cache", config.user_dir);

  MUST(Core::Environment::set("LADYBIRD_RESOURCE_ROOT"sv, config.resource_root,
                              Core::Environment::Overwrite::Yes));
  MUST(Core::Environment::set("HOME"sv, config.user_dir,
                              Core::Environment::Overwrite::Yes));
  MUST(Core::Environment::set("XDG_CONFIG_HOME"sv, config_dir,
                              Core::Environment::Overwrite::Yes));
  MUST(Core::Environment::set("XDG_DATA_HOME"sv, data_dir,
                              Core::Environment::Overwrite::Yes));
  MUST(Core::Environment::set("XDG_RUNTIME_DIR"sv, runtime_dir,
                              Core::Environment::Overwrite::Yes));
  MUST(Core::Environment::set("TMPDIR"sv, cache_dir,
                              Core::Environment::Overwrite::Yes));

  if (!config.certificates_path.is_empty()) {
    MUST(Core::Environment::set("SSL_CERT_FILE"sv, config.certificates_path,
                                Core::Environment::Overwrite::Yes));
  }

  if (!config.native_library_dir.is_empty()) {
    if (auto existing_library_path =
            Core::Environment::get("LD_LIBRARY_PATH"sv);
        existing_library_path.has_value()) {
      MUST(Core::Environment::set(
          "LD_LIBRARY_PATH"sv,
          ByteString::formatted("{}:{}", config.native_library_dir,
                                *existing_library_path),
          Core::Environment::Overwrite::Yes));
    } else {
      MUST(Core::Environment::set("LD_LIBRARY_PATH"sv,
                                  config.native_library_dir,
                                  Core::Environment::Overwrite::Yes));
    }
  }

  WebView::s_ladybird_resource_root = config.resource_root;
  Core::ResourceImplementation::install(make<Core::ResourceImplementationFile>(
      MUST(String::from_byte_string(config.resource_root))));
}
#else
extern "C" void configure_android_runtime(const char *, const char *,
                                          const char *, const char *) {}
#endif

// ---------------------------------------------------------------------------
// Platform backend factory
// ---------------------------------------------------------------------------

static std::unique_ptr<ViewBackend> create_view_backend() {
#ifdef __APPLE__
  return std::make_unique<MacOSViewBackend>();
#else
  return std::make_unique<LinuxViewBackend>();
#endif
}

#ifdef __ANDROID__
// An AHardwareBuffer the plugin owns and refills with each presented frame,
// replaced whenever the frame size changes.
class AndroidFrameBuffer {
public:
  AndroidFrameBuffer(AHardwareBuffer *buffer, Gfx::IntSize size)
      : m_buffer(buffer), m_size(size) {}
  ~AndroidFrameBuffer() {
    if (m_buffer)
      AHardwareBuffer_release(m_buffer);
  }
  AK_MAKE_NONCOPYABLE(AndroidFrameBuffer);
  AK_MAKE_NONMOVABLE(AndroidFrameBuffer);
  AK_ALLOC_WITH_KMALLOC;

public:
  AHardwareBuffer *buffer() const { return m_buffer; }
  Gfx::IntSize size() const { return m_size; }

private:
  AHardwareBuffer *m_buffer{nullptr};
  Gfx::IntSize m_size;
};
#endif

// ---------------------------------------------------------------------------
// FlutterViewImpl
// ---------------------------------------------------------------------------

class FlutterViewImpl final : public WebView::ViewImplementation {
  AK_ALLOC_WITH_KMALLOC;

public:
  static constexpr double kDefaultRefreshRate = 60.0;

  enum class MacFrameSource {
    Unknown,
    IOSurface,
    BitmapFallback,
  };

  static ErrorOr<NonnullOwnPtr<FlutterViewImpl>> create(int view_id) {
    return adopt_nonnull_own_or_enomem(new (std::nothrow)
                                           FlutterViewImpl(view_id));
  }

  int m_view_id;
  double m_zoom{1.0};

  // The hash the engine's stores know the current page's favicon by. Guarded by
  // m_info_mutex because the C ABI reads it from Flutter's thread.
  Optional<String> m_favicon_hash;

  // The link the page is making to the selected text, for the context menu's
  // "Copy Link to Highlight".
  Optional<URL::URL> m_link_to_highlight;

  Optional<String> favicon_hash() {
    std::lock_guard lock(m_info_mutex);
    return m_favicon_hash;
  }

  // Viewport dimensions — updated by resize() so viewport_size() always
  // returns the currently-requested render size, not the last painted size.
  int m_viewport_width{800};
  int m_viewport_height{600};

  // Platform rendering backend (LinuxViewBackend / MacOSViewBackend).
  std::unique_ptr<ViewBackend> m_backend;
  uint64_t m_debug_paint_event_count{0};
  Optional<u64> m_display_id;
  double m_display_refresh_rate{kDefaultRefreshRate};

#ifdef __APPLE__
  MacFrameSource m_last_mac_frame_source{MacFrameSource::Unknown};
#endif

  // Mutex for the non-frame callbacks (URL, title, favicon, loading state).
  std::mutex m_info_mutex;

  UrlChangeCallback m_url_change_callback = nullptr;
  TitleChangeCallback m_title_change_callback = nullptr;
  FaviconChangeCallback m_favicon_change_callback = nullptr;
  CrossSiteNavigationCallback m_cross_site_navigation_callback = nullptr;
  LoadingStateChangeCallback m_loading_state_change_callback = nullptr;
  CursorChangeCallback m_cursor_change_callback = nullptr;
  ContextMenuRequestCallback m_context_menu_request_callback = nullptr;
  NewWebViewCallback m_new_web_view_callback = nullptr;
  InputCaretRectChangeCallback m_input_caret_rect_change_callback = nullptr;
  FullscreenChangeCallback m_fullscreen_change_callback = nullptr;
  NavigationHistoryChangeCallback m_navigation_history_change_callback =
      nullptr;

  std::mutex m_context_menu_mutex;

  // What one context menu item does; the token Flutter hands back names it.
  struct ContextMenuAction {
    bool enabled { true };
    Function<void()> activate;
  };

  HashMap<int, ContextMenuAction> m_context_menu_actions;
  int m_next_context_menu_action_token{1};

  static int to_cursor_type_for_flutter(Gfx::Cursor const &cursor) {
    return cursor.visit(
        [](Gfx::StandardCursor standard) { return static_cast<int>(standard); },
        [](Gfx::ImageCursor const &) {
          // Flutter cannot consume custom pixel cursors via this API, so use
          // a standard fallback.
          return static_cast<int>(Gfx::StandardCursor::Arrow);
        });
  }

  // Called with m_context_menu_mutex held.
  int register_context_menu_action(ContextMenuAction action) {
    int token = m_next_context_menu_action_token++;
    m_context_menu_actions.set(token, move(action));
    return token;
  }

  // Android hands the current frame to the platform as an AHardwareBuffer, which
  // the Java side wraps in a Bitmap and blits into the Flutter texture's Surface.
  //
  // Normally that is the very buffer the compositor rendered into, exported from
  // its Vulkan image (USE_VULKAN_AHB_IMAGES, the Android counterpart of the Linux
  // dma-buf path): zero copies per frame. Only when the engine has no hardware
  // buffer for the frame does the plugin fall back to owning one and copying the
  // presented bitmap into it (refresh_android_hardware_buffer).
  void *front_ahb() {
#ifdef __ANDROID__
    // The presented frame lives in the backing stores now; present its own
    // hardware buffer when the compositor exported one.
    if (auto frame = backing_stores().displayed_frame();
        frame.has_value() && frame->shared_image_buffer) {
      if (auto *engine_buffer = frame->shared_image_buffer->native_buffer())
        return engine_buffer;
    }
    if (!m_android_frame_buffer)
      return nullptr;
    return m_android_frame_buffer->buffer();
#else
    return nullptr;
#endif
  }

#ifdef __ANDROID__
  void refresh_android_hardware_buffer() {
    auto frame = backing_stores().displayed_frame();
    if (!frame.has_value() || !frame->shared_image_buffer)
      return;

    auto const &bitmap = frame->shared_image_buffer->bitmap();
    auto const bitmap_size = frame->size;

    // AHardwareBuffer only offers R8G8B8A8; an engine BGRA bitmap has to be
    // swizzled on the way in. Anything else has no representable layout.
    auto const bitmap_format = bitmap->format();
    bool needs_swizzle = false;
    if (bitmap_format == Gfx::BitmapFormat::RGBA8888) {
      needs_swizzle = false;
    } else if (bitmap_format == Gfx::BitmapFormat::BGRA8888) {
      needs_swizzle = true;
    } else {
      if (!m_logged_unsupported_ahb_format) {
        m_logged_unsupported_ahb_format = true;
        std::fprintf(stderr,
                     "[Ladybird][Android] Unsupported frame format %s; "
                     "hardware-buffer frame export disabled\n",
                     Gfx::bitmap_format_name(bitmap_format)
                         .to_byte_string()
                         .characters());
      }
      return;
    }

    if (!m_android_frame_buffer ||
        m_android_frame_buffer->size() != bitmap_size) {
      m_android_frame_buffer = nullptr;

      AHardwareBuffer_Desc description {};
      description.width = static_cast<uint32_t>(bitmap_size.width());
      description.height = static_cast<uint32_t>(bitmap_size.height());
      description.layers = 1;
      description.format = AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM;
      description.usage = AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN |
                          AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE;

      AHardwareBuffer *buffer = nullptr;
      if (AHardwareBuffer_allocate(&description, &buffer) != 0 || !buffer) {
        if (!m_logged_unsupported_ahb_format) {
          m_logged_unsupported_ahb_format = true;
          std::fprintf(stderr,
                       "[Ladybird][Android] AHardwareBuffer_allocate failed "
                       "for %dx%d\n",
                       bitmap_size.width(), bitmap_size.height());
        }
        return;
      }
      m_android_frame_buffer =
          adopt_own_if_nonnull(new (std::nothrow)
                                   AndroidFrameBuffer(buffer, bitmap_size));
      if (!m_android_frame_buffer) {
        AHardwareBuffer_release(buffer);
        return;
      }
    }

    auto *buffer = m_android_frame_buffer->buffer();
    void *pixels = nullptr;
    int32_t row_stride = 0;
    if (AHardwareBuffer_lock(buffer, AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN, -1,
                             nullptr, &pixels) != 0 ||
        !pixels)
      return;

    AHardwareBuffer_Desc locked_description {};
    AHardwareBuffer_describe(buffer, &locked_description);
    row_stride = static_cast<int32_t>(locked_description.stride) * 4;

    auto const *source = bitmap->scanline_u8(0);
    auto const source_stride = bitmap->pitch();
    auto const width = static_cast<size_t>(bitmap_size.width());
    auto const height = static_cast<size_t>(bitmap_size.height());

    for (size_t y = 0; y < height; ++y) {
      auto *destination_row =
          static_cast<uint8_t *>(pixels) + (y * static_cast<size_t>(row_stride));
      auto const *source_row = source + (y * static_cast<size_t>(source_stride));
      if (!needs_swizzle) {
        memcpy(destination_row, source_row, width * 4);
        continue;
      }
      for (size_t x = 0; x < width; ++x) {
        auto const *source_pixel = source_row + (x * 4);
        auto *destination_pixel = destination_row + (x * 4);
        destination_pixel[0] = source_pixel[2];
        destination_pixel[1] = source_pixel[1];
        destination_pixel[2] = source_pixel[0];
        destination_pixel[3] = source_pixel[3];
      }
    }

    AHardwareBuffer_unlock(buffer, nullptr);
  }

#endif

  // Upstream moved the action and menu classes, and the building of context
  // menus, into the browser's UI: a view now only says what the menu is about.
  // FlutterBird is a UI of its own, so the engine builds the menu here and
  // hands Flutter the same JSON it always has: every action item carries a
  // token the engine maps back to the work the item does.
  // Called with m_context_menu_mutex held.
  void add_action(JsonArray &items, StringView text, Function<void()> activate,
                  bool enabled = true) {
    JsonObject item;
    item.set("kind"sv, "action"sv);
    item.set("token"sv, register_context_menu_action({ enabled, move(activate) }));
    item.set("text"sv, text);
    item.set("enabled"sv, enabled);
    item.set("checkable"sv, false);
    items.must_append(move(item));
  }

  // Called with m_context_menu_mutex held.
  void add_checkable_action(JsonArray &items, StringView text, bool checked,
                            Function<void()> activate, bool enabled = true) {
    JsonObject item;
    item.set("kind"sv, "action"sv);
    item.set("token"sv, register_context_menu_action({ enabled, move(activate) }));
    item.set("text"sv, text);
    item.set("enabled"sv, enabled);
    item.set("checkable"sv, true);
    item.set("checked"sv, checked);
    items.must_append(move(item));
  }

  static void add_separator(JsonArray &items) {
    JsonObject item;
    item.set("kind"sv, "separator"sv);
    items.must_append(move(item));
  }

  static void copy_text_to_clipboard(ByteString const &text) {
    if (!text.is_empty())
      WebView::Application::the().set_clipboard_text(
          MUST(String::from_byte_string(text)));
  }

  void add_copy_url_action(JsonArray &items, StringView text,
                           URL::URL const &url) {
    add_action(items, text, [url] {
      copy_text_to_clipboard(WebView::url_text_to_copy(url));
    });
  }

  void add_open_in_new_tab_action(
      JsonArray &items, StringView text, URL::URL const &url,
      Optional<Web::HTML::PreparedNavigationDescriptor> const &navigation) {
    add_action(items, text, [this, url, navigation] {
      if (navigation.has_value())
        open_navigation_in_new_tab(*navigation, Web::HTML::ActivateTab::No);
      else
        open_url_in_new_tab(url, Web::HTML::ActivateTab::No);
    });
  }

  void add_open_url_actions(
      JsonArray &items, URL::URL const &url,
      Optional<Web::HTML::PreparedNavigationDescriptor> const &navigation) {
    add_open_in_new_tab_action(items, "Open Link in New Tab"sv, url,
                               navigation);

    if (is_private() != WebView::IsPrivate::No)
      return;

    add_action(items, "Open Link in New Window"sv, [this, url, navigation] {
      if (navigation.has_value())
        open_navigation_in_new_window(*navigation, WebView::IsPrivate::No);
      else
        open_url_in_new_window(url, WebView::IsPrivate::No);
    });

    if (!WebView::Application::the().supports_private_browsing_windows())
      return;

    add_action(
        items, "Open Link in Private Window"sv, [this, url, navigation] {
          if (!navigation.has_value()) {
            open_url_in_new_window(url, WebView::IsPrivate::Yes);
            return;
          }
          auto private_navigation = *navigation;
          private_navigation.referrer_policy =
              Web::ReferrerPolicy::ReferrerPolicy::NoReferrer;
          open_navigation_in_new_window(move(private_navigation),
                                        WebView::IsPrivate::Yes);
        });
  }

  void add_link_actions(
      JsonArray &items,
      Web::HTML::PreparedNavigationDescriptor const &navigation) {
    auto url = navigation.url;

    StringView copy_url_text = "Copy Link"sv;
    switch (WebView::url_type(url)) {
    case WebView::URLType::Email:
      copy_url_text = "Copy Email Address"sv;
      break;
    case WebView::URLType::Telephone:
      copy_url_text = "Copy Phone Number"sv;
      break;
    case WebView::URLType::Other:
      break;
    }

    add_open_url_actions(items, url, navigation);
    add_separator(items);
    add_copy_url_action(items, copy_url_text, url);
    add_action(items, "Download Linked File"sv,
               [this, url] { download_url(url, PromptForPath::No); });
    add_action(items, "Save Link As…"sv,
               [this, url] { download_url(url, PromptForPath::Yes); });
  }

  // Text can be edited only in a field, and copied only where there is some.
  void add_text_edit_actions(JsonArray &items, bool is_editable,
                             bool has_selected_text) {
    if (is_editable) {
      add_action(items, "Cut"sv, [this] {
        cut_selected_text()->when_resolved(
            [](ByteString text) { copy_text_to_clipboard(text); });
      });
    }
    if (is_editable || has_selected_text) {
      add_action(items, "Copy"sv, [this] {
        selected_text()->when_resolved(
            [](ByteString text) { copy_text_to_clipboard(text); });
      });
    }
    if (is_editable) {
      add_action(items, "Paste"sv, [this] {
        paste_from_clipboard(Web::Clipboard::PasteMode::AllMimeTypes);
      });
      add_action(items, "Paste and Match Style"sv, [this] {
        paste_from_clipboard(Web::Clipboard::PasteMode::PlainTextOnly);
      });
      add_action(items, "Select All"sv, [this] { select_all(); });
    }
  }

  void add_look_up_action(JsonArray &items,
                          WebView::ContextMenuRequest const &request) {
    if (!request.dictionary_lookup.has_value())
      return;

    add_action(items, "Look Up"sv,
               [this, lookup = *request.dictionary_lookup,
                position = request.dictionary_lookup_position] {
                 if (on_request_dictionary_lookup)
                   on_request_dictionary_lookup(lookup, position);
               });
  }

  void add_search_action(JsonArray &items,
                         Optional<String> const &selected_text) {
    auto const &search_engine =
        WebView::Application::settings().search_engine_settings().engine;
    if (!search_engine.has_value() || !selected_text.has_value())
      return;

    auto url = URL::Parser::basic_parse(
        search_engine->format_search_query_for_navigation(*selected_text));
    if (!url.has_value())
      return;

    add_action(items,
               search_engine->format_search_query_for_display(*selected_text),
               [this, url = url.release_value()] {
                 open_url_in_new_tab(url, Web::HTML::ActivateTab::Yes);
               });
  }

  void add_spelling_actions(JsonArray &items,
                            WebView::ContextMenuRequest const &request) {
    if (!request.misspelled_word.has_value())
      return;

    for (auto const &guess : request.spelling_guesses) {
      add_action(items, MUST(guess.utf16_view().to_utf8()),
                 [this, guess] {
                   replace_context_menu_misspelling(guess);
                 });
    }
    if (request.spelling_guesses.is_empty())
      add_action(items, "No Guesses Found"sv, [] {}, false);

    add_separator(items);
    add_action(items, "Ignore Spelling"sv, [this, word = *request.misspelled_word] {
      ignore_misspelling(word);
    });
    add_action(items, "Learn Spelling"sv, [this, word = *request.misspelled_word] {
      learn_misspelling(word);
    });
  }

  void add_copy_link_to_highlight_action(
      JsonArray &items, WebView::ContextMenuRequest const &request) {
    if (!request.makes_link_to_highlight)
      return;

    add_action(items, "Copy Link to Highlight"sv, [this] {
      if (m_link_to_highlight.has_value())
        copy_text_to_clipboard(WebView::url_text_to_copy(*m_link_to_highlight));
    }, m_link_to_highlight.has_value());
  }

  // The element is the one under the cursor when the context menu opened, so a
  // page that changes while the menu is open still inspects the right element.
  void add_inspect_element_action(JsonArray &items,
                                  WebView::ContextMenuRequest const &request) {
    if (!request.can_inspect_element)
      return;
    add_separator(items);
    add_action(items, "Inspect Element"sv,
               [this] { inspect_context_menu_element(); });
  }

  JsonArray create_page_context_menu(WebView::ContextMenuRequest const &request) {
    // The page's own items are left out where the menu is about the text.
    auto is_about_page = !request.is_editable && !request.selected_text.has_value();

    JsonArray items;
    add_spelling_actions(items, request);
    add_separator(items);
    add_look_up_action(items, request);
    if (is_about_page) {
      add_action(items, "Back"sv, [this] { traverse_the_history_by_delta(-1); },
                 can_navigate_back());
      add_action(items, "Forward"sv,
                 [this] { traverse_the_history_by_delta(1); },
                 can_navigate_forward());
      add_action(items, "Reload"sv, [this] { reload(); });
    }
    add_separator(items);
    add_text_edit_actions(items, request.is_editable,
                          request.selected_text.has_value());
    add_separator(items);
    add_search_action(items, request.selected_text);
    add_copy_link_to_highlight_action(items, request);
    add_separator(items);
    if (is_about_page)
      add_action(items, "View Page Source"sv, [this] { get_source(); },
                 can_view_source());
    add_action(items, "Report Website Issue…"sv,
               [this] { report_website_issue(); },
               can_report_website_issue());
    add_separator(items);
    if (is_about_page) {
      add_action(items, "Take Screenshot..."sv, [this] {
        if (on_request_screenshot)
          on_request_screenshot();
      });
    }
    add_inspect_element_action(items, request);
    return items;
  }

  JsonArray create_selected_text_link_context_menu(
      WebView::ContextMenuRequest const &request, URL::URL const &url) {
    JsonArray items;
    add_look_up_action(items, request);
    add_open_url_actions(items, url, {});
    add_separator(items);
    add_text_edit_actions(items, request.is_editable, true);
    add_separator(items);
    add_search_action(items, request.selected_text);
    add_copy_link_to_highlight_action(items, request);
    add_inspect_element_action(items, request);
    return items;
  }

  JsonArray create_link_context_menu(WebView::ContextMenuRequest const &request) {
    JsonArray items;
    add_link_actions(items, *request.link_navigation);
    add_copy_link_to_highlight_action(items, request);
    add_inspect_element_action(items, request);
    return items;
  }

  JsonArray create_image_context_menu(WebView::ContextMenuRequest const &request) {
    auto const &navigation = *request.navigation;
    auto url = navigation.url;

    JsonArray items;
    if (request.link_navigation.has_value()) {
      add_link_actions(items, *request.link_navigation);
      add_separator(items);
    }
    add_open_in_new_tab_action(items, "Open Image in New Tab"sv, url, navigation);
    add_action(items, "Open Image"sv, [this, navigation] { load(navigation); });
    add_separator(items);
    add_action(
        items, "Copy Image"sv,
        [bitmap = request.image_bitmap] {
          if (!bitmap.has_value() || !bitmap->is_valid())
            return;
          auto encoded = Gfx::PNGWriter::encode(*bitmap->bitmap());
          if (encoded.is_error())
            return;
          WebView::Application::the().insert_clipboard_item(
              { { { MUST(String::from_utf8("image/png"sv)),
                    ByteString { encoded.value().bytes() } } } });
        },
        request.image_bitmap.has_value());
    add_copy_url_action(items, "Copy Image Address"sv, url);
    add_action(items, "Save Image As…"sv,
               [this, url, image_mime_type = request.image_mime_type] {
                 download_url(url, PromptForPath::Yes, image_mime_type);
               });
    add_inspect_element_action(items, request);
    return items;
  }

  JsonArray create_media_context_menu(WebView::ContextMenuRequest const &request) {
    auto const &media = *request.media;

    auto send = [this](WebView::ContextMenuMediaAction action) {
      return [this, action] { do_context_menu_media_action(action); };
    };

    JsonArray items;
    if (media.is_playing)
      add_action(items, "Pause"sv, send(WebView::ContextMenuMediaAction::TogglePlay));
    else
      add_action(items, "Play"sv, send(WebView::ContextMenuMediaAction::TogglePlay));
    if (media.is_muted)
      add_action(items, "Unmute"sv, send(WebView::ContextMenuMediaAction::ToggleMute));
    else
      add_action(items, "Mute"sv, send(WebView::ContextMenuMediaAction::ToggleMute));
    if (media.has_user_agent_controls)
      add_action(items, "Hide Controls"sv, send(WebView::ContextMenuMediaAction::ToggleControls));
    else
      add_action(items, "Show Controls"sv, send(WebView::ContextMenuMediaAction::ToggleControls));
    add_checkable_action(items, "Loop"sv, media.is_looping,
                         send(WebView::ContextMenuMediaAction::ToggleLoop));
    add_separator(items);
    if (media.is_picture_in_picture)
      add_action(items, "Exit Picture in Picture"sv,
                 send(WebView::ContextMenuMediaAction::TogglePictureInPicture));
    else if (media.can_enter_picture_in_picture)
      add_action(items, "Picture in Picture"sv,
                 send(WebView::ContextMenuMediaAction::TogglePictureInPicture));
    if (media.is_video && media.is_fullscreen)
      add_action(items, "Exit Full Screen"sv,
                 send(WebView::ContextMenuMediaAction::ToggleFullscreen));
    else if (media.is_video)
      add_action(items, "Full Screen"sv,
                 send(WebView::ContextMenuMediaAction::ToggleFullscreen));
    add_separator(items);
    if (media.media_url.has_value()) {
      auto url = *media.media_url;
      add_open_in_new_tab_action(
          items, media.is_video ? "Open Video in New Tab"sv
                                : "Open Audio in New Tab"sv,
          url, request.navigation);
      if (request.navigation.has_value())
        add_action(items, media.is_video ? "Open Video"sv : "Open Audio"sv,
                   [this, navigation = *request.navigation] { load(navigation); });
      add_copy_url_action(
          items, media.is_video ? "Copy Video Address"sv : "Copy Audio Address"sv,
          url);
    }
    add_inspect_element_action(items, request);
    return items;
  }

  JsonArray create_context_menu(WebView::ContextMenuRequest const &request) {
    switch (request.kind) {
    case WebView::ContextMenuKind::Page:
      if (request.selected_text.has_value()) {
        if (auto url = WebView::url_from_text(*request.selected_text);
            url.has_value())
          return create_selected_text_link_context_menu(request, *url);
      }
      return create_page_context_menu(request);
    case WebView::ContextMenuKind::Link:
      if (request.link_navigation.has_value())
        return create_link_context_menu(request);
      break;
    case WebView::ContextMenuKind::Image:
      if (request.navigation.has_value())
        return create_image_context_menu(request);
      break;
    case WebView::ContextMenuKind::Media:
      if (request.media.has_value())
        return create_media_context_menu(request);
      break;
    }
    return create_page_context_menu(request);
  }

  static StringView context_menu_type(WebView::ContextMenuRequest const &request) {
    switch (request.kind) {
    case WebView::ContextMenuKind::Page:
      if (request.selected_text.has_value() &&
          WebView::url_from_text(*request.selected_text).has_value())
        return "link"sv;
      return "page"sv;
    case WebView::ContextMenuKind::Link:
      return "link"sv;
    case WebView::ContextMenuKind::Image:
      return "image"sv;
    case WebView::ContextMenuKind::Media:
      return "media"sv;
    }
    return "page"sv;
  }

  // The view says what the user asked a menu for; the engine, as the UI, makes
  // the menu for it and hands Flutter its JSON.
  virtual void did_request_context_menu(WebView::ContextMenuRequest request) override {
    ContextMenuRequestCallback callback = nullptr;
    char *payload = nullptr;

    {
      std::lock_guard lock(m_context_menu_mutex);
      m_context_menu_actions.clear();

      JsonObject menu;
      menu.set("type"sv, context_menu_type(request));
      menu.set("x"sv, request.widget_position.x());
      menu.set("y"sv, request.widget_position.y());
      menu.set("items"sv, JsonValue(create_context_menu(request)));

      auto serialized = JsonValue(move(menu)).serialized();
      auto bytes = serialized.to_byte_string();
      payload = strdup(bytes.characters());
      callback = m_context_menu_request_callback;
    }

    if (!payload)
      return;

    if (callback)
      callback(m_view_id, payload);
    else
      free(payload);
  }

  String create_child_web_view_handle(WebView::CanonicalTraversable &traversable,
                                      int &new_view_id);

  void set_context_menu_request_callback(ContextMenuRequestCallback callback) {
    std::lock_guard lock(m_context_menu_mutex);
    m_context_menu_request_callback = callback;
    if (!callback)
      m_context_menu_actions.clear();
  }

  bool activate_context_menu_action(int action_token) {
    ContextMenuAction action;

    {
      std::lock_guard lock(m_context_menu_mutex);
      auto it = m_context_menu_actions.find(action_token);
      if (it == m_context_menu_actions.end())
        return false;
      action = move(it->value);
      m_context_menu_actions.clear();
    }

    if (!action.enabled || !action.activate)
      return false;

    // The actions a context menu carries are application-wide (Copy, Paste,
    // View Source, ...), and their callbacks ask the application for the active
    // view. This embedder only ever set that when a view was created, so it
    // would stay on the first tab forever and every such action would act on
    // the wrong page. A context menu is the plugin's proof of which view the
    // user is acting on, so mark that one active before the action runs.
    g_active_view_id = m_view_id;

    action.activate();
    return true;
  }

  // Pushes the engine's viewport/window geometry for the currently-requested
  // render size. Ladybird 2026-10 moved viewport pushes behind
  // ViewImplementation::handle_resize()/set_window_size(); the device pixel
  // ratio still comes from Flutter, which is what libbird's set_zoom() sets.
  void push_viewport() {
    set_window_size(Gfx::IntSize{m_viewport_width, m_viewport_height});
    handle_resize();
  }

  void sync_device_pixel_ratio() { m_device_pixel_ratio = m_zoom; }

  void set_display_metadata(Optional<u64> display_id, double refresh_rate,
                            double maximum_frames_per_second) {
    auto const sanitized_refresh_rate =
        refresh_rate > 0.0 ? refresh_rate : kDefaultRefreshRate;
    auto const sanitized_maximum_frames_per_second =
        maximum_frames_per_second > 0.0 ? maximum_frames_per_second
                                        : sanitized_refresh_rate;

    m_display_id = display_id;
    m_display_refresh_rate = sanitized_refresh_rate;
    m_maximum_frames_per_second = sanitized_maximum_frames_per_second;

    if (has_traversable())
      ViewImplementation::set_display_metadata(m_display_id,
                                               m_maximum_frames_per_second);
  }

  // The engine asks for the system theme when a page starts hosting the tab.
  // FlutterBird has no native theme plumbing, so serve Ladybird's default
  // theme out of res/themes/Default.ini.
  virtual Core::AnonymousBuffer system_theme() override {
    if (!m_system_theme_buffer.is_valid()) {
      auto theme_path = LexicalPath::join(WebView::s_ladybird_resource_root,
                                          "themes"sv, "Default.ini"sv);
      if (auto theme = Gfx::load_system_theme(theme_path.string());
          !theme.is_error())
        m_system_theme_buffer = theme.release_value();
    }
    return m_system_theme_buffer;
  }

  // Starts a tab: creates a page for it on the engine side, then attaches the
  // signals. Mirrors what the Qt frontend's Tab does with initialize_tab(),
  // which is how Ladybird 2026-10 set up views (replacing the old
  // initialize_client()).
  void start_tab() {
    // With no traversable to adopt, initialize_tab() asks the application for a
    // page of its own, which launches WebContent for it (or reuses a spare one).
    initialize_tab(Web::HTML::VisibilityState::Visible);
    attach_signals();
  }

  void attach_signals() {
    push_viewport();
    set_system_visibility_state(Web::HTML::VisibilityState::Visible);

    // -----------------------------------------------------------------------
    // on_ready_to_paint — modelled after Qt's WebContentView pattern.
    //
    // Linux path consumes bitmap/dmabuf. macOS first tries IOSurface for the
    // zero-copy external-texture path, then falls back to bitmap conversion.
    // -----------------------------------------------------------------------
    on_ready_to_paint = [this]() {
      // Upstream moved the presented frame into PageBackingStores: the frame to
      // show is the one in the front backing store, or the kept backup until
      // that has one.
      auto frame = backing_stores().displayed_frame();
      if (!frame.has_value() || !frame->shared_image_buffer)
        return;

      ++m_debug_paint_event_count;

      auto *shared_image_buffer = frame->shared_image_buffer;

      // A hardware buffer the compositor rendered into is presented as-is; the
      // plugin reads it through get_android_hardware_buffer.
      if (front_ahb() != nullptr) {
        m_backend->on_hardware_frame_ready(frame->size.width(),
                                           frame->size.height());
        return;
      }

#ifndef __APPLE__
#ifdef USE_VULKAN_DMABUF_IMAGES
      auto *linux_backend = static_cast<LinuxViewBackend *>(m_backend.get());
      if (auto const *dmabuf = shared_image_buffer->linux_dmabuf_handle()) {
        linux_backend->set_linux_dmabuf_frame(
            dmabuf->file.fd(), dmabuf->size.width(), dmabuf->size.height(),
            static_cast<int>(dmabuf->pitch), dmabuf->drm_format,
            dmabuf->modifier,
            dmabuf->alpha_type == Gfx::AlphaType::Premultiplied);
      } else {
        linux_backend->clear_linux_dmabuf_frame();
      }
#endif
#else
      auto *mac_backend = static_cast<MacOSViewBackend *>(m_backend.get());
      auto *surface = static_cast<IOSurfaceRef>(
          shared_image_buffer->iosurface_handle().core_foundation_pointer());
      if (surface) {
        auto surface_width = static_cast<int>(IOSurfaceGetWidth(surface));
        auto surface_height = static_cast<int>(IOSurfaceGetHeight(surface));
        if (surface_width <= 0 || surface_height <= 0) {
          surface_width = frame->size.width();
          surface_height = frame->size.height();
        }

        if (mac_backend->on_iosurface_ready(surface, surface_width,
                                            surface_height)) {
          if (m_last_mac_frame_source != MacFrameSource::IOSurface) {
            std::fprintf(
                stderr,
                "[Ladybird][macOS] View %d rendering source: IOSurface\n",
                m_view_id);
            m_last_mac_frame_source = MacFrameSource::IOSurface;
          }
          return;
        }
      }
#endif

      auto bitmap =
          AK::RefPtr<Gfx::Bitmap const>(shared_image_buffer->bitmap());
      m_backend->on_bitmap_ready(bitmap);
#ifdef __ANDROID__
      // A frame the compositor exported as an AHardwareBuffer never needs the
      // copied one; only fall back to it for frames that have none.
      if (front_ahb() != nullptr)
        m_android_frame_buffer = nullptr;
      else
        refresh_android_hardware_buffer();
#endif

#ifdef __APPLE__
      if (m_last_mac_frame_source != MacFrameSource::BitmapFallback) {
        std::fprintf(
            stderr,
            "[Ladybird][macOS] View %d rendering source: Bitmap fallback\n",
            m_view_id);
        m_last_mac_frame_source = MacFrameSource::BitmapFallback;
      }
#endif
    };

    on_web_content_process_change_for_cross_site_navigation = [this]() {
      std::fprintf(stderr,
                   "WebContent process changed for cross site navigation.\n");
      // The engine re-pushes the viewport to the new page itself when it moves
      // the display page, so only FlutterBird's own bookkeeping happens here.
      std::lock_guard lock(m_info_mutex);
      if (m_cross_site_navigation_callback)
        m_cross_site_navigation_callback(m_view_id);
    };

    on_web_content_crashed = [this](WebContentCrashReason reason) {
      std::fprintf(stderr, "WebContent process crashed (reason %d).\n",
                   static_cast<int>(reason));
      notify_loading_state(false);
    };

    // The engine funnels every load start/finish into this one signal, so it is
    // the only loading state FlutterBird has to follow.
    on_loading_state_change = [this](bool is_loading) {
      notify_loading_state(is_loading);
    };

    on_url_change = [this](URL::URL const &url) {
      std::lock_guard lock(m_info_mutex);
      if (m_url_change_callback) {
        auto url_string = url.to_string().to_byte_string();
        m_url_change_callback(strdup(url_string.characters()));
      }
    };

    on_title_change = [this](Utf16String const &title) {
      std::lock_guard lock(m_info_mutex);
      if (m_title_change_callback) {
        auto title_string = title.to_utf8().to_byte_string();
        m_title_change_callback(strdup(title_string.characters()));
      }
    };

    on_navigation_history_change = [this]() {
      NavigationHistoryChangeCallback callback = nullptr;
      char *payload = nullptr;

      {
        std::lock_guard lock(m_info_mutex);
        callback = m_navigation_history_change_callback;
        if (callback) {
          auto json = WebView::history_json_entries(
                          traversable().session_history())
                          .serialized()
                          .to_byte_string();
          payload = strdup(json.characters());
        }
      }

      if (callback && payload)
        callback(m_view_id, payload);
    };

    on_favicon_change = [this](Optional<Gfx::Bitmap const &> favicon) {
      // The view no longer hashes favicons itself, so the engine does it here:
      // the history store is keyed by that hash, and the embedder asks for it to
      // attach a favicon to a bookmark.
      Optional<String> favicon_hash;
      if (favicon.has_value() && g_favicon_store) {
        if (auto favicon_png = Gfx::PNGWriter::encode(*favicon);
            !favicon_png.is_error())
          favicon_hash =
              g_favicon_store->add_favicon(favicon_png.release_value());
      }

      {
        std::lock_guard lock(m_info_mutex);
        m_favicon_hash = favicon_hash;
      }

      if (favicon_hash.has_value() && g_history_store)
        g_history_store->update_favicon(url(), *favicon_hash);

      if (!favicon.has_value())
        return;

      std::lock_guard lock(m_info_mutex);
      if (m_favicon_change_callback) {
        auto const &bitmap = *favicon;
        size_t length = bitmap.width() * bitmap.height() * 4;
        uint8_t *buffer = (uint8_t *)malloc(length);
        memcpy(buffer, reinterpret_cast<const uint8_t *>(bitmap.begin()),
               length);
        m_favicon_change_callback(buffer, bitmap.width(), bitmap.height());
      }
    };

    on_cursor_change = [this](Gfx::Cursor const &cursor) {
      std::lock_guard lock(m_info_mutex);
      if (m_cursor_change_callback)
        m_cursor_change_callback(to_cursor_type_for_flutter(cursor));
    };

    on_input_method_state_change = [this]() {
      std::lock_guard lock(m_info_mutex);
      if (!m_input_caret_rect_change_callback)
        return;
      auto const &rect = input_method_state().caret_rect;
      if (rect.has_value()) {
        m_input_caret_rect_change_callback(m_view_id, true, rect->x().value(),
                                           rect->y().value(),
                                           rect->width().value(),
                                           rect->height().value());
      } else {
        m_input_caret_rect_change_callback(m_view_id, false, 0, 0, 0, 0);
      }
    };

    // A page opened a tab or a popup window: create a Flutter view bound to the
    // traversable the engine already prepared for it, and hand back its handle
    // so the engine can name the new tab.
    on_new_web_view = [this](Web::HTML::ActivateTab activate_tab,
                             Web::HTML::WebViewHints,
                             WebView::CanonicalTraversable &traversable)
        -> String {
      int new_view_id = -1;
      auto handle = create_child_web_view_handle(traversable, new_view_id);
      if (handle.is_empty())
        return {};

      NewWebViewCallback callback = nullptr;
      {
        std::lock_guard lock(m_info_mutex);
        callback = m_new_web_view_callback;
      }

      if (callback)
        callback(new_view_id, activate_tab == Web::HTML::ActivateTab::Yes);

      return handle;
    };

    // The page requested fullscreen (element.requestFullscreen() or a
    // <video>'s native fullscreen control). We deliberately do NOT call
    // set_is_fullscreen() here: that would confirm the transition to the
    // engine before Flutter has actually performed it, racing against the
    // viewport updates Flutter's own window-resize handling sends as a side
    // effect of that transition — whichever arrives at WebContent last wins,
    // and losing that race is what silently and permanently got fullscreen
    // stuck. Instead we just notify Flutter; it calls confirm_fullscreen_state()
    // once its own transition has actually settled (mirrors how Ladybird's
    // Qt frontend only calls set_is_fullscreen() from its
    // QEvent::WindowStateChange handler, not eagerly).
    on_fullscreen_window = [this]() {
      std::fprintf(stderr,
                   "[Fullscreen] on_fullscreen_window view=%d "
                   "viewport_size=%dx%d\n",
                   m_view_id, m_viewport_width, m_viewport_height);

      FullscreenChangeCallback callback = nullptr;
      {
        std::lock_guard lock(m_info_mutex);
        callback = m_fullscreen_change_callback;
      }
      if (callback)
        callback(m_view_id, true);
    };

    // The page (or the user, via Escape) exited fullscreen. See above for
    // why set_is_fullscreen() isn't called eagerly here either.
    on_exit_fullscreen_window = [this]() {
      std::fprintf(stderr,
                   "[Fullscreen] on_exit_fullscreen_window view=%d\n",
                   m_view_id);

      FullscreenChangeCallback callback = nullptr;
      {
        std::lock_guard lock(m_info_mutex);
        callback = m_fullscreen_change_callback;
      }
      if (callback)
        callback(m_view_id, false);
    };
  }

  void notify_loading_state(bool is_loading) {
    LoadingStateChangeCallback callback = nullptr;
    {
      std::lock_guard lock(m_info_mutex);
      callback = m_loading_state_change_callback;
    }
    if (callback)
      callback(is_loading);
  }

  void resize(int width, int height) {
    m_viewport_width = width;
    m_viewport_height = height;
    sync_device_pixel_ratio();
    push_viewport();
  }

  void update_zoom_scale() {
    sync_device_pixel_ratio();
    push_viewport();
  }

  // Maps FlutterBird's own ABI event type onto the engine's. Returns nullopt
  // for a value the ABI does not define.
  static Optional<Web::MouseEvent::Type> to_engine_mouse_event_type(int type) {
    switch (type) {
    case LADYBIRD_MOUSE_DOWN:
      return Web::MouseEvent::Type::MouseDown;
    case LADYBIRD_MOUSE_UP:
      return Web::MouseEvent::Type::MouseUp;
    case LADYBIRD_MOUSE_MOVE:
      return Web::MouseEvent::Type::MouseMove;
    case LADYBIRD_MOUSE_LEAVE:
      return Web::MouseEvent::Type::MouseLeave;
    case LADYBIRD_MOUSE_WHEEL:
      return Web::MouseEvent::Type::MouseWheel;
    }
    return {};
  }

  static Web::WheelDeltaPrecision
  to_engine_wheel_delta_precision(int precision) {
    return precision == LADYBIRD_WHEEL_PRECISE
               ? Web::WheelDeltaPrecision::Precise
               : Web::WheelDeltaPrecision::Discrete;
  }

  static Web::ScrollGesturePhase
  to_engine_scroll_gesture_phase(int phase) {
    switch (phase) {
    case LADYBIRD_SCROLL_PHASE_ONGOING:
      return Web::ScrollGesturePhase::Ongoing;
    case LADYBIRD_SCROLL_PHASE_MOMENTUM:
      return Web::ScrollGesturePhase::Momentum;
    case LADYBIRD_SCROLL_PHASE_ENDED:
      return Web::ScrollGesturePhase::Ended;
    }
    return Web::ScrollGesturePhase::None;
  }

  void dispatch_mouse_event(int abi_type, int x, int y, int button, int buttons,
                            int modifiers, double wheel_delta_x,
                            double wheel_delta_y, int abi_precision,
                            int abi_phase) {
    auto type = to_engine_mouse_event_type(abi_type);
    if (!type.has_value()) {
      std::fprintf(stderr,
                   "dispatch_mouse_event: unknown event type %d\n", abi_type);
      return;
    }

    Web::DevicePixelPoint position = {x, y};
    Web::DevicePixelPoint screen_position = {x, y};

    // Flutter says which of its input produced the deltas and where they sit in
    // their gesture (see window.dart: a touchpad's pan steps against a mouse
    // wheel's notches, and the framework's own momentum steps), so the engine
    // gets the same picture Ladybird's Qt frontend gives it: precise phased
    // steps for a trackpad, discrete phase-less ones for a wheel.
    auto wheel_delta_precision = to_engine_wheel_delta_precision(abi_precision);
    auto scroll_gesture_phase = to_engine_scroll_gesture_phase(abi_phase);
    auto wheel_tick_120ths_x =
        Web::wheel_tick_120ths_from_pixel_delta(wheel_delta_x,
                                                wheel_delta_precision);
    auto wheel_tick_120ths_y =
        Web::wheel_tick_120ths_from_pixel_delta(wheel_delta_y,
                                                wheel_delta_precision);

    enqueue_input_event(
        Web::MouseEvent{*type,
                        position,
                        screen_position,
                        static_cast<Web::UIEvents::MouseButton>(button),
                        static_cast<Web::UIEvents::MouseButton>(buttons),
                        static_cast<Web::UIEvents::KeyModifier>(modifiers),
                        wheel_delta_x,
                        wheel_delta_y,
                        wheel_tick_120ths_x,
                        wheel_tick_120ths_y,
                        wheel_delta_precision,
                        scroll_gesture_phase,
                        *type == Web::MouseEvent::Type::MouseDown ||
                                *type == Web::MouseEvent::Type::MouseUp
                            ? 1
                            : 0,
                        nullptr});
  }

  void dispatch_key_event(Web::KeyEvent::Type type, int keycode, int modifiers,
                          uint32_t code_point, bool repeat) {
    enqueue_input_event(
        Web::KeyEvent{type, static_cast<Web::UIEvents::KeyCode>(keycode),
                      static_cast<Web::UIEvents::KeyModifier>(modifiers),
                      code_point, repeat,
                      type == Web::KeyEvent::Type::KeyDown &&
                          code_point != 0});
  }

  virtual ~FlutterViewImpl() = default;

private:
  explicit FlutterViewImpl(int view_id)
      : WebView::ViewImplementation(WebView::IsPrivate::No), m_view_id(view_id) {
    m_backend = create_view_backend();
  }

  virtual Web::DevicePixelSize viewport_size() const override {
    return {m_viewport_width, m_viewport_height};
  }
  virtual Gfx::IntPoint
  to_content_position(Gfx::IntPoint widget_position) const override {
    return widget_position;
  }
  virtual Gfx::IntPoint
  to_widget_position(Gfx::IntPoint content_position) const override {
    return content_position;
  }

  // With the history store owned by the UI, a view is what records its visits,
  // titles and favicons, as the Qt frontend's RemoteView does.
  virtual void did_visit_page(URL::URL const &url,
                              Optional<String> const &title,
                              WebView::HistoryVisitTransition transition) override {
    if (is_private() != WebView::IsPrivate::No || !g_history_store)
      return;

    g_history_store->record_visit(url, title, UnixDateTime::now(), transition);
    if (auto hash = favicon_hash(); hash.has_value())
      g_history_store->update_favicon(url, *hash);
  }

  virtual void did_change_visited_page_title(URL::URL const &url,
                                             String const &title) override {
    if (is_private() == WebView::IsPrivate::No && g_history_store)
      g_history_store->update_title(url, title);
  }

  virtual void did_make_link_to_highlight(Optional<URL::URL> url) override {
    m_link_to_highlight = move(url);
  }

  Core::AnonymousBuffer m_system_theme_buffer;

#ifdef __ANDROID__
  OwnPtr<AndroidFrameBuffer> m_android_frame_buffer;
  bool m_logged_unsupported_ahb_format{false};
#endif
};

#include <map>
// View registry — owns all FlutterViewImpl instances.
static std::map<int, AK::OwnPtr<FlutterViewImpl>> g_web_views;

// Adopts an already-prepared traversable (a tab or popup the page opened) into
// a fresh Flutter view and returns its window handle.
String FlutterViewImpl::create_child_web_view_handle(
    WebView::CanonicalTraversable &traversable, int &new_view_id) {
  new_view_id = -1;

  auto created_view = FlutterViewImpl::create(g_next_view_id++).release_value();
  created_view->initialize_tab(Web::HTML::VisibilityState::Visible, traversable);
  created_view->attach_signals();

  new_view_id = created_view->m_view_id;
  auto handle = created_view->handle();
  g_web_views[new_view_id] = std::move(created_view);
  return handle;
}

// Creates a view with a tab of its own -- no traversable to adopt -- for a tab
// the engine opens by itself rather than one the embedder or a page asked for.
// View Source is the one such case: the engine answers a source request by
// handing the embedder a brand-new tab holding the highlighted source.
// Mirrors what create_web_view() does for an embedder-requested tab.
static int create_blank_web_view() {
  auto created_view = FlutterViewImpl::create(g_next_view_id++).release_value();
  created_view->start_tab();

  int const new_view_id = created_view->m_view_id;
  g_web_views[new_view_id] = std::move(created_view);
  if (g_active_view_id == -1)
    g_active_view_id = new_view_id;
  return new_view_id;
}

// Looks up the new-web-view callback the Flutter side registers per view. Such
// a callback is what turns an engine-created view into a tab widget, and every
// view carries the same Dart handler, so the active view answers for the tab the
// engine is about to open. Views whose Dart controller has been disposed have no
// handler left, so any view that still has one is a better answer than none.
static NewWebViewCallback new_web_view_callback_from_views() {
  if (auto it = g_web_views.find(g_active_view_id); it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    if (it->second->m_new_web_view_callback)
      return it->second->m_new_web_view_callback;
  }

  for (auto const &[view_id, view] : g_web_views) {
    std::lock_guard lock(view->m_info_mutex);
    if (view->m_new_web_view_callback)
      return view->m_new_web_view_callback;
  }
  return nullptr;
}

static StringView
download_status_to_string(WebView::FileDownloader::DownloadStatus status) {
  switch (status) {
  case WebView::FileDownloader::DownloadStatus::InProgress:
    return "in-progress"sv;
  case WebView::FileDownloader::DownloadStatus::Paused:
    return "paused"sv;
  case WebView::FileDownloader::DownloadStatus::Completed:
    return "completed"sv;
  case WebView::FileDownloader::DownloadStatus::Canceled:
    return "canceled"sv;
  case WebView::FileDownloader::DownloadStatus::Failed:
    return "failed"sv;
  }
  VERIFY_NOT_REACHED();
}

static JsonObject
serialize_download(WebView::FileDownloader::Download const &download) {
  JsonObject serialized;
  serialized.set("id"sv, download.id);
  serialized.set("url"sv, download.url.serialize());
  serialized.set("fileName"sv, String::from_utf8_with_replacement_character(
                                   download.destination.basename(),
                                   String::WithBOMHandling::No));
  serialized.set("destination"sv, String::from_utf8_with_replacement_character(
                                      download.destination.string().view(),
                                      String::WithBOMHandling::No));
  serialized.set("status"sv, download_status_to_string(download.status));
  serialized.set("downloadedSize"sv, download.downloaded_size);
  serialized.set("totalSize"sv, download.total_size.has_value()
                                    ? JsonValue{*download.total_size}
                                    : JsonValue{});
  serialized.set("error"sv, download.error.value_or(String{}));
  return serialized;
}

// Bridges WebView::FileDownloader's observer pattern to Flutter. Constructed
// once from init_ladybird(); the FileDownloaderObserver base ctor/dtor
// self-register with FileDownloader, so no manual add_observer call is
// needed here.
class FlutterFileDownloaderObserver final
    : public WebView::FileDownloaderObserver {
  AK_ALLOC_WITH_KMALLOC;

public:
  virtual void
  download_added(WebView::FileDownloader::Download const &download) override {
    notify(download);
  }
  virtual void
  download_updated(WebView::FileDownloader::Download const &download) override {
    notify(download);
  }
  virtual void download_removed(u64 id, WebView::IsPrivate) override {
    if (g_download_removed_callback)
      g_download_removed_callback(id);
  }

private:
  void notify(WebView::FileDownloader::Download const &download) {
    if (!g_download_update_callback)
      return;
    auto json = serialize_download(download).serialized().to_byte_string();
    g_download_update_callback(strdup(json.characters()));
  }
};

static AK::OwnPtr<FlutterFileDownloaderObserver> g_download_observer;

#ifdef __APPLE__
// Hands a path to /usr/bin/open: plain for "Open" (the default handler for the
// file type), "-R" to reveal it in Finder. Returning false means the spawn
// itself failed, leaving the caller to fall back to upstream's behavior.
static bool open_path_with_host(ByteString const &path, bool reveal_in_folder) {
  if (path.is_empty())
    return false;

  char const *argv[4];
  int argc = 0;
  argv[argc++] = "/usr/bin/open";
  if (reveal_in_folder)
    argv[argc++] = "-R";
  argv[argc++] = path.characters();
  argv[argc] = nullptr;

  // Close-on-exec for every other descriptor, so the helper cannot inherit the
  // engine's IPC sockets and leave a peer waiting on one until it exits.
  posix_spawnattr_t attributes;
  if (posix_spawnattr_init(&attributes) != 0)
    return false;
  posix_spawnattr_setflags(&attributes, POSIX_SPAWN_CLOEXEC_DEFAULT);

  pid_t pid = 0;
  int const result = posix_spawn(&pid, argv[0], nullptr, &attributes,
                                 const_cast<char **>(argv), *_NSGetEnviron());
  posix_spawnattr_destroy(&attributes);
  return result == 0;
}
#else
// Only macOS has a host handler / file manager wired up here; everywhere else
// the caller falls back to upstream's implementation.
static bool open_path_with_host(ByteString const &, bool) { return false; }
#endif

class FlutterApplication : public WebView::Application {
  WEB_VIEW_APPLICATION(FlutterApplication)
  AK_ALLOC_WITH_KMALLOC;

public:
  FlutterApplication(Optional<ByteString> ladybird_binary_path = {})
      : WebView::Application(std::move(ladybird_binary_path)) {}

  virtual ~FlutterApplication() override = default;

  virtual void create_platform_arguments(Core::ArgsParser &) override {}
  virtual void create_platform_options(
      [[maybe_unused]] WebView::BrowserOptions &browser_options,
      [[maybe_unused]] WebView::RequestServerOptions &request_server_options,
      WebView::WebContentOptions &web_content_options) override {
#if defined(__linux__)
    browser_options.disable_sandbox = WebView::DisableSandbox::Yes;
#endif
#ifdef __ANDROID__
    auto const config = snapshot_android_runtime_config();
    if (!config.certificates_path.is_empty())
      request_server_options.certificates.append(config.certificates_path);
#endif
    // WebContent renders into a shared image buffer; the embedder composites
    // it itself, so there is no GPU path to force CPU painting away from.
    web_content_options.force_cpu_painting = WebView::ForceCPUPainting::No;
  }

  virtual Core::EventLoop &create_platform_event_loop() override {
    return WebView::Application::create_platform_event_loop();
  }

  // FlutterBird is the browser: it owns its profile and its process, and a
  // second instance must start a second engine rather than hand its URLs to the
  // first one and exit, which would leave a window with no engine behind it.
  virtual bool should_coordinate_browser_process() const override {
    return false;
  }

  // macOS hands pages the bounce they expect at a scroller's edge, the way
  // Ladybird's Qt frontend does there (Application::platform_scrolls_elastically
  // in UI/Qt/Application.cpp).
  virtual bool platform_scrolls_elastically() const override {
#if defined(__APPLE__)
    return true;
#endif
    return false;
  }

  virtual Optional<WebView::ViewImplementation &>
  active_web_view() const override {
    if (g_active_view_id != -1) {
      auto it = g_web_views.find(g_active_view_id);
      if (it != g_web_views.end())
        return *it->second;
    }
    if (!g_web_views.empty()) {
      return *g_web_views.begin()->second;
    }
    return {};
  }

  virtual Optional<WebView::ViewImplementation &>
  open_blank_new_tab(Web::HTML::ActivateTab activate_tab,
                     WebView::ViewImplementation const * = nullptr) const override {
    int const new_view_id = create_blank_web_view();
    auto it = g_web_views.find(new_view_id);
    if (it == g_web_views.end())
      return {};

    if (auto callback = new_web_view_callback_from_views())
      callback(new_view_id, activate_tab == Web::HTML::ActivateTab::Yes);

    return *it->second;
  }

  // Ladybird 2026-11 moved download-path prompting behind a promise so a
  // frontend can show an async dialog. FlutterBird's callback is synchronous,
  // so settle the promise before returning it.
  virtual NonnullRefPtr<Core::Promise<ByteString>>
  ask_user_for_download_path(ByteString const &file) const override {
    if (!g_ask_user_for_download_path_callback)
      return Core::Promise<ByteString>::rejected(Error::from_errno(ECANCELED));

    char *result = g_ask_user_for_download_path_callback(file.characters());
    if (!result)
      return Core::Promise<ByteString>::rejected(Error::from_errno(ECANCELED));

    ByteString path(result);
    free(result);
    return Core::Promise<ByteString>::resolved(move(path));
  }

  virtual void display_download_confirmation_dialog(
      StringView path, LexicalPath const &lexical_path) const override {
    if (g_display_download_confirmation_dialog_callback) {
      auto path_string = path.to_byte_string();
      g_display_download_confirmation_dialog_callback(
          path_string.characters(), lexical_path.string().characters());
    }
  }
  virtual void display_error_dialog(StringView message) const override {
    if (g_display_error_dialog_callback) {
      auto message_string = message.to_byte_string();
      g_display_error_dialog_callback(message_string.characters());
    }
  }

  virtual Utf16String
  clipboard_text(ClipboardType type = ClipboardType::Text) const override {
    if (g_get_clipboard_text_callback) {
      if (char *result = g_get_clipboard_text_callback()) {
        auto text = Utf16String::from_utf8(StringView(result, strlen(result)));
        free(result);
        return text;
      }
      return {};
    }
    return WebView::Application::clipboard_text(type);
  }

  virtual void set_clipboard_text(
      String text, ClipboardType type = ClipboardType::Text) override {
    if (g_set_clipboard_text_callback &&
        type == ClipboardType::Text) {
      g_set_clipboard_text_callback(text.to_byte_string().characters());
      return;
    }
    WebView::Application::set_clipboard_text(move(text), type);
  }

  // Every copy the engine performs -- a selection copy, a context menu action,
  // navigator.clipboard.write -- ends up in Application::insert_clipboard_entry,
  // which funnels into insert_clipboard_item(); reads (paste) go through
  // clipboard_item(). Those item-level hooks are what carry text to and from
  // the real OS clipboard, so the embedder's callbacks have to be wired there
  // and not only in the text-level overrides above (which only serve the
  // selection clipboard).
  virtual Web::Clipboard::SystemClipboardItem clipboard_item() const override {
    if (g_get_clipboard_text_callback) {
      if (char *result = g_get_clipboard_text_callback()) {
        auto text = ByteString(result);
        free(result);
        return Web::Clipboard::SystemClipboardItem{{
            {
                .name = MUST(String::from_utf8("text/plain"sv)),
                .data = move(text),
            },
        }};
      }
    }
    return WebView::Application::clipboard_item();
  }

  virtual void
  insert_clipboard_item(Web::Clipboard::SystemClipboardItem item) override {
    for (auto const &representation :
         item.system_clipboard_representations) {
      if (representation.name != "text/plain"sv)
        continue;

      if (auto const *data = representation.data.get_pointer<ByteString>()) {
        if (g_set_clipboard_text_callback)
          g_set_clipboard_text_callback(data->characters());
        return;
      }
    }
    WebView::Application::insert_clipboard_item(move(item));
  }
};

static AK::OwnPtr<FlutterApplication> s_app;

struct LatestFrameHandle {
  AK::RefPtr<Gfx::Bitmap const> bitmap;
  int width{0};
  int height{0};
  int pitch{0};
  uint64_t generation{0};
};

void init_ladybird() {
  static bool initialized = false;
  if (initialized)
    return;

  initialized = true;

  AK::set_rich_debug_enabled(true);

  Optional<ByteString> lib_path;

#ifdef __APPLE__
  // Do nothing on macos, it should default properly
#elif defined(__ANDROID__)
  auto const android_config = snapshot_android_runtime_config();
  if (!android_config.is_valid()) {
    std::fprintf(
        stderr,
        "[Ladybird][Android] Runtime not configured before init_ladybird()\n");
    return;
  }

  apply_android_runtime_config(android_config);
  if (!android_config.native_library_dir.is_empty())
    lib_path = android_config.native_library_dir;
#else
  auto current_executable_path = Core::System::current_executable_path();
  if (!current_executable_path.is_error()) {
    auto path = current_executable_path.value();
    auto app_dir = LexicalPath::dirname(path);
    lib_path = LexicalPath::join(app_dir, "lib"sv).string();

    // Use share/Lagom in the bundle as resource root
    auto resource_root =
        LexicalPath::join(app_dir, "share"sv, "Lagom"sv).string();
    Web::s_ladybird_resource_root = resource_root;
    Core::ResourceImplementation::install(
        make<Core::ResourceImplementationFile>(
            MUST(String::from_byte_string(resource_root))));
  } else {
    fprintf(stderr, "[Ladybird] Failed to get executable path: %d\n",
            current_executable_path.error().code());
  }
#endif

  static char program_name[] = "ladybird";
  static char *argv[] = {program_name, nullptr};
  static AK::StringView string_views[] = {AK::StringView("ladybird", 8)};
  Main::Arguments arguments = {1, argv, {string_views, 1}};

  auto app = FlutterApplication::create(arguments, lib_path);
  if (app.is_error()) {
    std::fprintf(stderr,
                 "Failed to construct Ladybird Engine Application: %d\n",
                 app.error().code());
    return;
  }
  s_app = app.release_value();
  create_engine_stores();
  g_download_observer = make<FlutterFileDownloaderObserver>();
  g_engine_ready = true;
}

// ---------------------------------------------------------------------------
// Event-loop tick — inspired by GTK's EventLoopImplementationGtk::pump():
//
//   result  = ThreadEventQueue::current().process();   // pre-drain
//   g_main_context_iteration(ctx, FALSE);              // platform poll
//   result += ThreadEventQueue::current().process();   // post-drain
//
// The pre-drain step flushes any events already posted to the queue (e.g.
// IPC messages received between the previous tick and this one).  The pump
// call exercises EventLoopImplementationUnix::wait_for_events() which does
// a non-blocking poll(2) over all registered notifiers (WebContent /
// RequestServer IPC sockets, timers, etc.).  The post-drain picks up
// anything that was enqueued during that poll.
// ---------------------------------------------------------------------------
extern "C" void tick_ladybird() {
  // Pre-drain: flush events queued since last tick.
  Core::ThreadEventQueue::current().process();

  // Non-blocking IO poll + timer dispatch.
  if (Core::EventLoop::is_running())
    Core::EventLoop::current().pump(Core::EventLoop::WaitMode::PollForEvents);

  // Post-drain: flush whatever the poll triggered.
  Core::ThreadEventQueue::current().process();
}

int create_web_view() {
  if (!g_engine_ready) {
    std::fprintf(stderr,
                 "create_web_view: Ladybird engine is not initialized\n");
    return -1;
  }

  int id = g_next_view_id++;
  auto view = FlutterViewImpl::create(id).release_value();
  view->start_tab();
  g_web_views[id] = std::move(view);
  if (g_active_view_id == -1)
    g_active_view_id = id;
  return id;
}

void destroy_web_view(int view_id) {
  if (g_active_view_id == view_id)
    g_active_view_id = -1;
  g_web_views.erase(view_id);
}

void *get_latest_pixel_buffer(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end()) {
    std::printf("get_latest_pixel_buffer: view %d not found\n", view_id);
    return nullptr;
  }
  return it->second->m_backend->pixel_data();
}

bool copy_latest_pixel_buffer(int view_id, uint8_t *out_buffer,
                              int out_capacity, int *out_width,
                              int *out_height) {
  if (!out_buffer || !out_width || !out_height || out_capacity <= 0)
    return false;

  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;

  int width = 0;
  int height = 0;
  bool copied = it->second->m_backend->copy_pixels_into(
      out_buffer, static_cast<size_t>(out_capacity), width, height);
  if (!copied)
    return false;

  *out_width = width;
  *out_height = height;
  return true;
}

uint64_t get_frame_generation(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return 0;
  return it->second->m_backend->frame_generation();
}

bool acquire_latest_frame(int view_id, const uint8_t **out_pixels,
                          int *out_width, int *out_height, int *out_pitch,
                          uint64_t *out_generation, void **out_frame_handle) {
  if (!out_pixels || !out_width || !out_height || !out_pitch ||
      !out_generation || !out_frame_handle)
    return false;

  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;

  FrameSnapshot snapshot;
  if (!it->second->m_backend->snapshot_frame(snapshot) || !snapshot.bitmap)
    return false;

  auto *frame = new (std::nothrow) LatestFrameHandle;
  if (!frame)
    return false;

  frame->bitmap = snapshot.bitmap;
  frame->width = snapshot.width;
  frame->height = snapshot.height;
  frame->pitch = snapshot.pitch;
  frame->generation = snapshot.generation;

  auto const *pixels = frame->bitmap->scanline_u8(0);
  if (!pixels) {
    delete frame;
    return false;
  }

  *out_pixels = pixels;
  *out_width = frame->width;
  *out_height = frame->height;
  *out_pitch = frame->pitch;
  *out_generation = frame->generation;
  *out_frame_handle = frame;
  return true;
}

void *get_android_hardware_buffer(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return nullptr;
  auto &view = *it->second;

  return view.front_ahb();
}

void release_latest_frame(void *frame_handle) {
  if (!frame_handle)
    return;
  auto *frame = static_cast<LatestFrameHandle *>(frame_handle);
  delete frame;
}

bool acquire_latest_linux_dmabuf_frame(int view_id,
                                       LadybirdLinuxDmaBufFrame *out_frame) {
  if (!out_frame)
    return false;

  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;

  LinuxDmaBufFrameSnapshot snapshot;
  if (!it->second->m_backend->snapshot_linux_dmabuf_frame(snapshot))
    return false;

  out_frame->fd = snapshot.fd;
  out_frame->width = snapshot.width;
  out_frame->height = snapshot.height;
  out_frame->pitch = snapshot.pitch;
  out_frame->drm_format = snapshot.drm_format;
  out_frame->modifier = snapshot.modifier;
  out_frame->premultiplied = snapshot.premultiplied;
  out_frame->generation = snapshot.generation;
  return true;
}

void set_frame_callback(int view_id, FrameCallback callback, void *context) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_backend->callback_mutex);
    it->second->m_backend->frame_callback = callback;
    it->second->m_backend->frame_callback_context = context;
  }
}

void set_resize_callback(int view_id, ResizeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_backend->callback_mutex);
    it->second->m_backend->resize_callback = callback;
  }
}

void resize_window(int view_id, int width, int height) {
  if (width <= 0 || height <= 0)
    return;
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end())
    it->second->resize(width, height);
}

void navigate_to(int view_id, const char *url) {
  if (!url)
    return;
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    auto parsed = URL::Parser::basic_parse(AK::StringView(url, strlen(url)));
    if (parsed.has_value())
      it->second->load(parsed.value());
  }
}

void set_zoom(int view_id, double zoom) {
  if (zoom <= 0.0)
    return;
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->m_zoom = zoom;
    it->second->update_zoom_scale();
  }
}

void set_preferred_color_scheme(int view_id, int color_scheme) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;
  it->second->set_preferred_color_scheme(
      static_cast<Web::CSS::PreferredColorScheme>(color_scheme));
}

void set_display_metadata(int view_id, bool has_display_id, uint64_t display_id,
                          double refresh_rate,
                          double maximum_frames_per_second) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  Optional<u64> optional_display_id;
  if (has_display_id)
    optional_display_id = display_id;

  it->second->set_display_metadata(optional_display_id, refresh_rate,
                                   maximum_frames_per_second);
}

int get_iosurface_width(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return 0;
  return it->second->m_backend->width();
}

int get_iosurface_height(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return 0;
  return it->second->m_backend->height();
}

void set_url_change_callback(int view_id, UrlChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    ByteString current_url;
    bool has_valid_initial_url = false;
    {
      std::lock_guard lock(it->second->m_info_mutex);
      it->second->m_url_change_callback = callback;
      auto const &url = it->second->displayed_url();
      has_valid_initial_url = !url.scheme().is_empty();
      if (has_valid_initial_url)
        current_url = url.to_string().to_byte_string();
    }

    if (callback && has_valid_initial_url)
      callback(strdup(current_url.characters()));
  }
}

void set_title_change_callback(int view_id, TitleChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    ByteString current_title;
    {
      std::lock_guard lock(it->second->m_info_mutex);
      it->second->m_title_change_callback = callback;
      current_title = it->second->title().to_utf8().to_byte_string();
    }

    if (callback)
      callback(strdup(current_title.characters()));
  }
}

void set_navigation_history_change_callback(
    int view_id, NavigationHistoryChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  ByteString current_json;
  {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_navigation_history_change_callback = callback;
    if (callback && it->second->has_traversable()) {
      current_json = WebView::history_json_entries(
                         it->second->traversable().session_history())
                         .serialized()
                         .to_byte_string();
    }
  }

  if (callback && !current_json.is_empty())
    callback(view_id, strdup(current_json.characters()));
}

void set_favicon_change_callback(int view_id, FaviconChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_favicon_change_callback = callback;
  }
}

void set_cross_site_navigation_callback(int view_id,
                                        CrossSiteNavigationCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_cross_site_navigation_callback = callback;
  }
}

void reload_tab(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->reload();
  }
}

void go_back(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->traverse_the_history_by_delta(-1);
  }
}

void go_forward(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->traverse_the_history_by_delta(1);
  }
}

void request_exit_fullscreen(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end())
    it->second->exit_fullscreen();
}

// Confirms to the engine that Flutter has *settled* into (or out of)
// fullscreen, so the DOM Fullscreen API's pending enter/exit operation can
// proceed. Called by the embedder itself, after its own platform transition
// (OS window fullscreen, immersive mode, etc) has actually completed — not
// eagerly from the on_fullscreen_window/on_exit_fullscreen_window
// notifications, to avoid racing Flutter's own in-flight viewport updates.
void confirm_fullscreen_state(int view_id, bool is_fullscreen) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;
  it->second->set_is_fullscreen(is_fullscreen ? Web::ViewportIsFullscreen::Yes
                                              : Web::ViewportIsFullscreen::No);
}

bool can_go_back(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->can_navigate_back();
}

bool can_go_forward(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->can_navigate_forward();
}

char *get_view_url(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return nullptr;

  auto const &url = it->second->displayed_url();
  if (url.scheme().is_empty())
    return nullptr;

  auto bytes = url.to_string().to_byte_string();
  return strdup(bytes.characters());
}

// The profile's config directory, which is where the embedder keeps its own
// per-profile files next to the engine's (bookmarks, for bird_core).
char *get_profile_config_directory() {
  if (!s_app)
    return nullptr;

  auto const &config = WebView::Application::profile().paths().config;
  if (config.is_empty())
    return nullptr;

  return strdup(config.characters());
}

// The favicon hash the engine's store knows the viewed page's favicon by, for
// an embedder that keeps bookmarks of its own.
char *get_view_favicon_hash(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return nullptr;

  auto hash = it->second->favicon_hash();
  if (!hash.has_value())
    return nullptr;

  auto bytes = hash->to_byte_string();
  return strdup(bytes.characters());
}

// The PNG of a favicon the engine has stored, base64-encoded, so an embedder's
// bookmark store can show it without keeping favicon bytes of its own.
char *get_favicon_png_base64(const char *favicon_hash) {
  if (!s_app || !g_favicon_store || !favicon_hash)
    return nullptr;

  auto hash = StringView(favicon_hash, strlen(favicon_hash));
  if (hash.is_empty())
    return nullptr;

  auto favicon_png = g_favicon_store->favicon_png(hash);
  if (!favicon_png.has_value())
    return nullptr;

  auto encoded = encode_base64(favicon_png->bytes());
  if (encoded.is_error())
    return nullptr;

  auto bytes = encoded.release_value().to_byte_string();
  return strdup(bytes.characters());
}

char *history_autocomplete_json(int view_id, const char *query, int limit) {
  if (!s_app)
    return nullptr;

  if (g_web_views.find(view_id) == g_web_views.end())
    return nullptr;

  if (!g_history_store)
    return nullptr;

  StringView query_string;
  if (query && strlen(query) > 0)
    query_string = StringView(query, strlen(query));

  size_t safe_limit = limit > 0 ? static_cast<size_t>(limit) : 8;

  // A private view's own history store is disabled, but autocomplete still
  // draws suggestions from ordinary (non-private) history regardless of the
  // view's privacy — hence the engine's ordinary history store.
  auto entries = g_history_store->autocomplete_entries(query_string, safe_limit);

  JsonArray suggestions;
  suggestions.ensure_capacity(entries.size());

  for (auto const &entry : entries) {
    JsonObject item;
    item.set("url"sv, entry.url);
    if (entry.title.has_value())
      item.set("title"sv, *entry.title);
    if (entry.favicon_png.has_value()) {
      if (auto encoded = encode_base64(entry.favicon_png->bytes());
          !encoded.is_error())
        item.set("favicon"sv, encoded.release_value());
    }
    suggestions.must_append(move(item));
  }

  auto json = JsonValue(move(suggestions)).serialized();
  auto bytes = json.to_byte_string();
  return strdup(bytes.characters());
}

// Settings exposes no accessor for its custom engines, and they can be added
// either through this ABI or through the engine's own about:settings page, so
// read them back out of the serialized settings -- the same JSON the engine
// persists them in.
static void append_custom_search_engines(JsonArray &engines) {
  auto settings = WebView::Application::settings().serialize_json();
  auto search_engine = settings.as_object().get_object("searchEngine"sv);
  if (!search_engine.has_value())
    return;

  auto custom_engines = search_engine->get_array("custom"sv);
  if (!custom_engines.has_value())
    return;

  custom_engines->for_each([&](JsonValue const &engine) {
    if (!engine.is_object())
      return;
    auto name = engine.as_object().get_string("name"sv);
    auto url = engine.as_object().get_string("url"sv);
    if (!name.has_value() || !url.has_value())
      return;

    JsonObject item;
    item.set("name"sv, *name);
    item.set("queryUrl"sv, *url);
    engines.must_append(move(item));
  });
}

char *get_search_engines_json() {
  JsonArray engines;
  for (auto const &engine : WebView::builtin_search_engines()) {
    JsonObject item;
    item.set("name"sv, engine.name);
    item.set("queryUrl"sv, engine.query_url);
    engines.must_append(move(item));
  }

  if (s_app)
    append_custom_search_engines(engines);

  auto json = JsonValue(move(engines)).serialized();
  auto bytes = json.to_byte_string();
  return strdup(bytes.characters());
}

char *get_search_engine_name() {
  if (!s_app)
    return nullptr;

  auto const &search_engine_settings =
      WebView::Application::settings().search_engine_settings();
  if (!search_engine_settings.engine.has_value())
    return nullptr;

  auto bytes = search_engine_settings.engine->name.to_byte_string();
  return strdup(bytes.characters());
}

bool add_custom_search_engine(const char *name, const char *query_url) {
  if (!s_app || !name || strlen(name) == 0 || !query_url ||
      strlen(query_url) == 0)
    return false;

  auto &settings = WebView::Application::settings();

  // Names identify engines everywhere else in this API and in the engine, so a
  // second engine under an existing name would be unreachable.
  if (settings.find_search_engine_by_name(StringView(name, strlen(name)))
          .has_value())
    return false;

  // Without the placeholder every query would be dropped on the floor.
  if (strstr(query_url, "%s") == nullptr)
    return false;

  // Let the engine validate the URL, so an engine added here is no more
  // lenient than one added on its own settings page.
  JsonObject engine;
  engine.set("name"sv, StringView(name, strlen(name)));
  engine.set("url"sv, StringView(query_url, strlen(query_url)));
  auto parsed = WebView::Settings::parse_custom_search_engine(
      JsonValue(move(engine)));
  if (!parsed.has_value())
    return false;

  settings.add_custom_search_engine(parsed.release_value());
  return true;
}

bool set_search_engine(const char *name) {
  if (!s_app)
    return false;

  auto &settings = WebView::Application::settings();
  auto current = settings.search_engine_settings();
  if (name && strlen(name) > 0) {
    auto engine =
        settings.find_search_engine_by_name(StringView(name, strlen(name)));
    if (!engine.has_value())
      return false;
    current.engine = move(engine);
  } else {
    current.engine = {};
  }
  settings.set_search_engine_settings(move(current));
  return true;
}

static char const *json_value_type_name(JsonValue::Type type) {
  switch (type) {
  case JsonValue::Type::Null:
    return "null";
  case JsonValue::Type::Bool:
    return "bool";
  case JsonValue::Type::Number:
    return "number";
  case JsonValue::Type::String:
    return "string";
  case JsonValue::Type::Array:
    return "array";
  case JsonValue::Type::Object:
    return "object";
  }
  return "unknown";
}

char *get_config_variable_definitions_json() {
  JsonArray definitions;
  for (auto const &variable : WebView::config_variable_definitions()) {
    JsonObject item;
    item.set("name"sv, variable.name);
    item.set("title"sv, variable.title);
    item.set("description"sv, variable.description);
    item.set("defaultValue"sv, variable.default_value);
    if (variable.array_element_type.has_value()) {
      auto const *type_name =
          json_value_type_name(*variable.array_element_type);
      item.set("arrayElementType"sv, StringView(type_name, strlen(type_name)));
    }
    definitions.must_append(move(item));
  }

  auto json = JsonValue(move(definitions)).serialized();
  auto bytes = json.to_byte_string();
  return strdup(bytes.characters());
}

char *get_config_variable_json(const char *name) {
  if (!s_app || !name)
    return nullptr;

  auto id =
      WebView::config_variable_id_from_name(StringView(name, strlen(name)));
  if (!id.has_value())
    return nullptr;

  auto const &value = WebView::Application::settings().config_variable(*id);
  auto bytes = value.serialized().to_byte_string();
  return strdup(bytes.characters());
}

bool set_config_variable_json(const char *name, const char *json_value) {
  if (!s_app || !name || !json_value)
    return false;

  auto id =
      WebView::config_variable_id_from_name(StringView(name, strlen(name)));
  if (!id.has_value())
    return false;

  auto parsed =
      JsonValue::from_string(StringView(json_value, strlen(json_value)));
  if (parsed.is_error())
    return false;

  WebView::Application::settings().set_config_variable(*id,
                                                       parsed.release_value());
  return true;
}

char *get_settings_json() {
  if (!s_app)
    return nullptr;

  auto json = WebView::Application::settings().serialize_json().serialized();
  auto bytes = json.to_byte_string();
  return strdup(bytes.characters());
}

void copy_selection(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  it->second->selected_text()->when_resolved([view_id](ByteString const &text) {
    if (text.is_empty())
      return;
    auto it = g_web_views.find(view_id);
    if (it == g_web_views.end())
      return;
    WebView::Application::the().insert_clipboard_entry(
        Web::Clipboard::SystemClipboardRepresentation {
            MUST(String::from_utf8("text/plain"sv)), text });
  });
}

void paste_from_clipboard(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  it->second->paste_from_clipboard(Web::Clipboard::PasteMode::AllMimeTypes);
}

void select_all(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  it->second->select_all();
}

void view_source(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;

  it->second->get_source();
}

void set_loading_state_change_callback(int view_id,
                                       LoadingStateChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    bool is_loading = false;
    {
      std::lock_guard lock(it->second->m_info_mutex);
      it->second->m_loading_state_change_callback = callback;
      is_loading = it->second->is_loading();
    }
    if (callback)
      callback(is_loading);
  }
}

void set_cursor_change_callback(int view_id, CursorChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_cursor_change_callback = callback;
  }
}

void set_context_menu_request_callback(int view_id,
                                       ContextMenuRequestCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end())
    it->second->set_context_menu_request_callback(callback);
}

void set_new_web_view_callback(int view_id, NewWebViewCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_new_web_view_callback = callback;
  }
}

void set_fullscreen_change_callback(int view_id,
                                    FullscreenChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_fullscreen_change_callback = callback;
  }
}

void set_input_caret_rect_change_callback(
    int view_id, InputCaretRectChangeCallback callback) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    std::lock_guard lock(it->second->m_info_mutex);
    it->second->m_input_caret_rect_change_callback = callback;
  }
}

void commit_text_from_input_method(int view_id, const char *text) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end() || !text)
    return;
  it->second->commit_text_from_input_method(
      Utf16String::from_utf8(StringView{text, strlen(text)}));
}

void set_marked_text_from_input_method(int view_id, const char *text) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end() || !text)
    return;
  it->second->set_marked_text_from_input_method(
      Utf16String::from_utf8(StringView{text, strlen(text)}));
}

void unmark_text_from_input_method(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return;
  it->second->unmark_text_from_input_method();
}

bool activate_context_menu_action(int view_id, int action_token) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->activate_context_menu_action(action_token);
}

bool is_tab_loading(int view_id) {
  auto it = g_web_views.find(view_id);
  if (it == g_web_views.end())
    return false;
  return it->second->is_loading();
}

extern "C" {

void dispatch_mouse_event(int view_id, int type, int x, int y, int button,
                          int buttons, int modifiers, double wheel_delta_x,
                          double wheel_delta_y, int wheel_delta_precision,
                          int scroll_gesture_phase) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->dispatch_mouse_event(type, x, y, button, buttons, modifiers,
                                     wheel_delta_x, wheel_delta_y,
                                     wheel_delta_precision,
                                     scroll_gesture_phase);
  }
}

void set_view_focused(int view_id, bool focused) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end())
    it->second->set_has_system_focus(focused);
}

void dispatch_key_event(int view_id, int type, int keycode, int modifiers,
                        uint32_t code_point, bool repeat) {
  auto it = g_web_views.find(view_id);
  if (it != g_web_views.end()) {
    it->second->dispatch_key_event(static_cast<Web::KeyEvent::Type>(type),
                                   keycode, modifiers, code_point, repeat);
  }
}
}

void set_ask_user_for_download_path_callback(
    AskUserForDownloadPathCallback callback) {
  g_ask_user_for_download_path_callback = callback;
}

void set_display_download_confirmation_dialog_callback(
    DisplayDownloadConfirmationDialogCallback callback) {
  g_display_download_confirmation_dialog_callback = callback;
}

void set_display_error_dialog_callback(DisplayErrorDialogCallback callback) {
  g_display_error_dialog_callback = callback;
}

void set_get_clipboard_text_callback(GetClipboardTextCallback callback) {
  g_get_clipboard_text_callback = callback;
}

void set_set_clipboard_text_callback(SetClipboardTextCallback callback) {
  g_set_clipboard_text_callback = callback;
}

void set_download_update_callback(DownloadUpdateCallback callback) {
  g_download_update_callback = callback;
}

void set_download_removed_callback(DownloadRemovedCallback callback) {
  g_download_removed_callback = callback;
}

char *get_downloads_json() {
  if (!s_app)
    return strdup("[]");

  JsonArray array;
  for (auto const &download :
       WebView::Application::the().file_downloader().downloads())
    array.must_append(serialize_download(download));

  auto bytes = array.serialized().to_byte_string();
  return strdup(bytes.characters());
}

void cancel_download(uint64_t id) {
  if (!s_app)
    return;
  WebView::Application::the().file_downloader().cancel_download(id);
}

// Hands the file to the OS: the default handler for "Open", Finder for "Show
// in folder". Upstream moved this out of Application and into each frontend, so
// the engine asks the host itself.
void open_download(uint64_t id) {
  if (!s_app)
    return;
  if (auto download =
          WebView::Application::the().file_downloader().download(id);
      download.has_value())
    open_path_with_host(download->destination.string(), false);
}

void show_download_in_folder(uint64_t id) {
  if (!s_app)
    return;
  if (auto download =
          WebView::Application::the().file_downloader().download(id);
      download.has_value())
    open_path_with_host(download->destination.string(), true);
}

void prune_inactive_downloads() {
  if (!s_app)
    return;
  (void)WebView::Application::the()
      .file_downloader()
      .prune_inactive_downloads(WebView::IsPrivate::No);
}