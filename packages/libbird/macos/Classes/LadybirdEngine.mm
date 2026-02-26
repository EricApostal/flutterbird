//
//  LadybirdEngine.mm
//  Pods
//
//  Created by Eric Apostal on 2/25/26.
//

#import "LadybirdEngine.h"

#include <AK/Enumerate.h>
#include <AK/OwnPtr.h>
#include <AK/String.h>
#include <AK/StringView.h>
#include <AK/Utf16String.h>
#import <Application/Application.h>
#include <LibGfx/Bitmap.h>
#include <LibMain/Main.h>
#include <LibURL/URL.h>
#include <LibWebView/Application.h>
#include <LibWebView/BrowserProcess.h>
#import <objc/runtime.h>

#import <Interface/LadybirdWebView.h>

static OwnPtr<Ladybird::Application> s_app;
static OwnPtr<WebView::BrowserProcess> s_browser_process;

@interface LadybirdEngineObserver : NSObject <LadybirdWebViewObserver>
@end

@implementation LadybirdEngineObserver

- (String const &)onCreateNewTab:(Optional<URL::URL> const &)url
                     activateTab:(Web::HTML::ActivateTab)activate_tab {
  static String empty;
  return empty;
}

- (String const &)onCreateChildTab:(Optional<URL::URL> const &)url
                       activateTab:(Web::HTML::ActivateTab)activate_tab
                         pageIndex:(u64)page_index {
  static String empty;
  return empty;
}

- (void)onLoadStart:(URL::URL const &)url isRedirect:(BOOL)is_redirect {
}
- (void)onLoadFinish:(URL::URL const &)url {
}
- (void)onURLChange:(URL::URL const &)url {
}
- (void)onTitleChange:(Utf16String const &)title {
}
- (void)onFaviconChange:(Gfx::Bitmap const &)bitmap {
}
- (void)onAudioPlayStateChange:(Web::HTML::AudioPlayState)play_state {
}
- (void)onFindInPageResult:(size_t)current_match_index
           totalMatchCount:(Optional<size_t> const &)total_match_count {
}

@end

@implementation LadybirdEngine

+ (void)initializeEngine {
  static bool initialized = false;
  if (initialized)
    return;

  AK::set_rich_debug_enabled(true);

  static char const *argv[] = {"Ladybird", nullptr};
  static AK::StringView string_views[] = {AK::StringView("Ladybird", 8)};
  Main::Arguments arguments = {1, (char **)argv, {string_views, 1}};

  auto app = Ladybird::Application::create(arguments);
  if (app.is_error()) {
    NSLog(@"Failed to initialize Ladybird Engine");
    return;
  }

  s_app = app.release_value();
  s_browser_process = make<WebView::BrowserProcess>();

  if (auto const &browser_options = WebView::Application::browser_options();
      !browser_options.headless_mode.has_value()) {
    if (browser_options.force_new_process == WebView::ForceNewProcess::No) {
      auto disposition = s_browser_process->connect(browser_options.raw_urls,
                                                    browser_options.new_window);

      if (!disposition.is_error() &&
          disposition.value() ==
              WebView::BrowserProcess::ProcessDisposition::ExitProcess) {
        NSLog(@"Opening in existing process");
        return;
      }
    }
  }

  initialized = true;
}

static char kObserverKey;

+ (NSView *)createWebViewWithFrame:(NSRect)frame {
  LadybirdEngineObserver *observer = [[LadybirdEngineObserver alloc] init];
  LadybirdWebView *webView = [[LadybirdWebView alloc] init:observer];
  [webView setFrame:frame];
  objc_setAssociatedObject(webView, &kObserverKey, observer,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return webView;
}

@end
