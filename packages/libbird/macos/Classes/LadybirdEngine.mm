//
//  LadybirdEngine.mm
//  Pods
//
//  Created by Eric Apostal on 2/25/26.
//

#import "LadybirdEngine.h"

#include <AK/Enumerate.h>
#include <AK/OwnPtr.h>
#include <AK/StringView.h>
#import <Application/Application.h>
#include <LibMain/Main.h>
#include <LibWebView/Application.h>
#include <LibWebView/BrowserProcess.h>

#import <Interface/LadybirdWebView.h>

static OwnPtr<Ladybird::Application> s_app;
static OwnPtr<WebView::BrowserProcess> s_browser_process;

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

+ (NSView *)createWebViewWithFrame:(NSRect)frame {
  // Instantiate the actual AppKit view from Ladybird
  LadybirdWebView *webView = [[LadybirdWebView alloc] initWithFrame:frame];
  return webView;
}

@end
