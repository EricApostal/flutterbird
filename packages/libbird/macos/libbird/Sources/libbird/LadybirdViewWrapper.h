#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LadybirdViewWrapper : NSObject

- (instancetype)init;
- (NSView *)getView;
- (void)loadURL:(NSString *)url;

@end

NS_ASSUME_NONNULL_END
