//
//  LadybirdEngine.m
//  Pods
//
//  Created by Eric Apostal on 2/25/26.
//


#import "LadybirdEngine.h"

#include <AK/Enumerate.h>
#include <LibMain/Main.h>
#include <LibWebView/Application.h>

// Assuming LadybirdWebView is the AppKit NSView subclass provided by ladybird_impl
#import <Interface/LadybirdWebView.h> 

@implementation LadybirdEngine

+ (void)initializeEngine {
    static bool initialized = false;
    if (initialized) return;

    AK::set_rich_debug_enabled(true);

    static char const* argv[] = { "Ladybird", nullptr };
    Main::Arguments arguments = { 1, (char**)argv };

    auto app = Ladybird::Application::create(arguments);
    if (app.is_error()) {
        NSLog(@"Failed to initialize Ladybird Engine");
        return;
    }

    initialized = true;
}

+ (NSView *)createWebViewWithFrame:(NSRect)frame {
    // Instantiate the actual AppKit view from Ladybird
    LadybirdWebView *webView = [[LadybirdWebView alloc] initWithFrame:frame];
    return webView;
}

@end