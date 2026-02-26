//
//  LadybirdEngine.h
//  Pods
//
//  Created by Eric Apostal on 2/25/26.
//


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LadybirdEngine : NSObject

+ (void)initializeEngine;
+ (NSView *)createWebViewWithFrame:(NSRect)frame;

@end

NS_ASSUME_NONNULL_END