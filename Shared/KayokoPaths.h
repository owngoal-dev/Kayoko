#pragma once

#import <Foundation/Foundation.h>
#import <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR
#import <roothide.h>
#endif

// Use the shared device directory even when injected into a sandboxed simulator app.
NS_INLINE NSString *KayokoUserPath(NSString *path) {
#if TARGET_OS_SIMULATOR
    NSString *mobilePrefix = @"/var/mobile/";
    if ([path hasPrefix:mobilePrefix]) {
        NSString *root = NSProcessInfo.processInfo.environment[@"SIMULATOR_SHARED_RESOURCES_DIRECTORY"];
        return [(root ?: NSHomeDirectory())
            stringByAppendingPathComponent:[path substringFromIndex:mobilePrefix.length]];
    }
#endif
    return path;
}

NS_INLINE NSString *KayokoRootPath(NSString *path) {
#if TARGET_OS_SIMULATOR
    NSString *bundlePrefix = @"/Library/PreferenceBundles/";
    if ([path hasPrefix:bundlePrefix]) {
        return [@"/opt/simject/PreferenceBundles"
            stringByAppendingPathComponent:[path substringFromIndex:bundlePrefix.length]];
    }
    if ([path isEqualToString:@"/usr/local/libexec/kayoko_updater"]) {
        return @"/opt/simject/kayoko_updater";
    }
    return KayokoUserPath(path);
#else
    return jbroot(path);
#endif
}
