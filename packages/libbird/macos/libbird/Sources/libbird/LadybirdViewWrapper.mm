#import "LadybirdViewWrapper.h"
#import <Interface/LadybirdWebView.h>
#import <LibURL/URL.h>
#import <AK/String.h>

@interface LadybirdViewWrapper () <LadybirdWebViewObserver>
@property (nonatomic, strong) LadybirdWebView *webView;
@end

@implementation LadybirdViewWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        _webView = [[LadybirdWebView alloc] init:self];
    }
    return self;
}

- (NSView *)getView {
    return self.webView;
}

- (void)loadURL:(NSString *)url {
    auto akUrl = URL::create_with_url_or_path(StringView { [url UTF8String], [url lengthOfBytesUsingEncoding:NSUTF8StringEncoding] }).value();
    [self.webView loadURL:akUrl];
}

#pragma mark - LadybirdWebViewObserver

- (String const&)onCreateNewTab:(Optional<URL::URL> const&)url
                    activateTab:(Web::HTML::ActivateTab)activate_tab {
    static String emptyString = String {};
    return emptyString;
}

- (String const&)onCreateChildTab:(Optional<URL::URL> const&)url
                      activateTab:(Web::HTML::ActivateTab)activate_tab
                        pageIndex:(u64)page_index {
    static String emptyString = String {};
    return emptyString;
}

- (void)onLoadStart:(URL::URL const&)url isRedirect:(BOOL)is_redirect {
}

- (void)onLoadFinish:(URL::URL const&)url {
}

- (void)onURLChange:(URL::URL const&)url {
}

- (void)onTitleChange:(Utf16String const&)title {
}

- (void)onFaviconChange:(Gfx::Bitmap const&)bitmap {
}

- (void)onAudioPlayStateChange:(Web::HTML::AudioPlayState)play_state {
}

- (void)onFindInPageResult:(size_t)current_match_index
           totalMatchCount:(Optional<size_t> const&)total_match_count {
}

@end
