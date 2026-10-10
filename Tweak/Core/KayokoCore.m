//
//  KayokoCore.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoCore.h"
#import "KayokoCoreRuntime.h"
#import "KayokoNotificationKeys.h"
#import "KayokoSpringBoardHooks.h"

#import <CoreFoundation/CoreFoundation.h>
#import <TargetConditionals.h>

typedef NS_ENUM(NSUInteger, KayokoCoreProcessKind) {
    KayokoCoreProcessKindUnsupported = 0,
    KayokoCoreProcessKindSpringBoard,
    KayokoCoreProcessKindDruidOrPasted,
};

@interface KayokoCoreProcessContext : NSObject

@property(nonatomic, assign, readonly) KayokoCoreProcessKind kind;

+ (instancetype)currentContext;

- (instancetype)initWithKind:(KayokoCoreProcessKind)kind;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

@end

@interface KayokoCoreBootstrap : NSObject

+ (void)installForSpringBoard;
+ (void)installForDruidOrPasted;

@end

@implementation KayokoCoreProcessContext

#pragma mark - Lifecycle

+ (instancetype)currentContext {
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        return [[self alloc] initWithKind:KayokoCoreProcessKindSpringBoard];
    }

    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    NSString *processName = [[NSProcessInfo processInfo] processName];
    NSString *executablePath = [args firstObject];
#if TARGET_OS_SIMULATOR
    NSString *simulatorRoot = NSProcessInfo.processInfo.environment[@"SIMULATOR_ROOT"];
    if (simulatorRoot.length > 0 && [executablePath hasPrefix:[simulatorRoot stringByAppendingString:@"/"]]) {
        executablePath = [executablePath substringFromIndex:simulatorRoot.length];
    }
#endif
    BOOL isSystemExecutable =
        [executablePath hasPrefix:@"/System/Library/"] || [executablePath hasPrefix:@"/usr/libexec/"];
    BOOL isPasteTipProcess = [processName isEqualToString:@"druid"] || [processName isEqualToString:@"pasted"];
    if (isSystemExecutable && isPasteTipProcess) {
        return [[self alloc] initWithKind:KayokoCoreProcessKindDruidOrPasted];
    }

    return [[self alloc] initWithKind:KayokoCoreProcessKindUnsupported];
}

- (instancetype)initWithKind:(KayokoCoreProcessKind)kind {
    self = [super init];
    if (self) {
        _kind = kind;
    }
    return self;
}

@end

#pragma mark - Darwin Callbacks

static void kayokoCorePasteboardChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] capturePasteboardChange];
}

static void kayokoCoreShowCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] show];
}

static void kayokoCoreHideCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] hideForExternalRequest];
}

static void kayokoCoreReloadCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                     const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] reloadHistory];
}

static void kayokoCoreCheckpointHistoryCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] checkpointHistoryDatabase];
}

static void kayokoCorePrepareMaintenanceCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                 const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] prepareForPackageMaintenance];
}

static void kayokoCoreResetThumbnailMemoryCacheCallback(CFNotificationCenterRef center, void *observer,
                                                        CFStringRef name, const void *object,
                                                        CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] resetThumbnailMemoryCache];
}

static void kayokoCoreClearFavoritesCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                             const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] clearFavorites];
}

static void kayokoCoreClearHistoryCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                           const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] clearHistory];
}

static void kayokoCorePreferencesReloadCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] loadPreferences];
}

static void kayokoCoreHeightPreferenceReloadCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                                     const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] loadHeightPreference];
}

static void kayokoCoreHelperPasteCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                          const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] playPasteFeedback];
}

static void kayokoCorePasteFeedbackCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                            const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] playPasteFeedback];
}

static void kayokoCorePasteWillStartCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                             const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] markPasteWillStart];
}

static void kayokoCorePasteTipPreferencesReloadCallback(CFNotificationCenterRef center, void *observer,
                                                        CFStringRef name, const void *object,
                                                        CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[KayokoCoreRuntime sharedRuntime] refreshPasteTipPreferences];
}

@implementation KayokoCoreBootstrap

#pragma mark - Observers

+ (void)addDarwinObserverForName:(CFStringRef)name callback:(CFNotificationCallback)callback {
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(), NULL, callback, name, NULL,
        (CFNotificationSuspensionBehavior)CFNotificationSuspensionBehaviorDeliverImmediately);
}

#pragma mark - Installation

+ (void)installForSpringBoard {
    KayokoCoreRuntime *runtime = [KayokoCoreRuntime sharedRuntime];
    [runtime loadPreferences];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCoreCheckpointHistory
                          callback:kayokoCoreCheckpointHistoryCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCorePrepareMaintenance
                          callback:kayokoCorePrepareMaintenanceCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCoreResetThumbnailMemoryCache
                          callback:kayokoCoreResetThumbnailMemoryCacheCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCoreClearFavorites
                          callback:kayokoCoreClearFavoritesCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCoreClearHistory
                          callback:kayokoCoreClearHistoryCallback];
    if (![runtime isEnabled]) {
        return;
    }

    [KayokoPasteTipHookInstaller installHooks];
    [KayokoSpringBoardHookInstaller installHooks];
    [runtime startLockStateObserver];

    [self addDarwinObserverForName:CFSTR("com.apple.pasteboard.notify.changed")
                          callback:kayokoCorePasteboardChangedCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCoreShow
                          callback:kayokoCoreShowCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoLegacyNotificationKeyCoreShow
                          callback:kayokoCoreShowCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCoreHide
                          callback:kayokoCoreHideCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoLegacyNotificationKeyCoreHide
                          callback:kayokoCoreHideCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyCoreReload
                          callback:kayokoCoreReloadCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyPreferencesReload
                          callback:kayokoCorePreferencesReloadCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyPreferencesHeightReload
                          callback:kayokoCoreHeightPreferenceReloadCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyHelperPaste
                          callback:kayokoCoreHelperPasteCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyPasteFeedback
                          callback:kayokoCorePasteFeedbackCallback];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyPasteWillStart
                          callback:kayokoCorePasteWillStartCallback];
}

+ (void)installForDruidOrPasted {
    BOOL shouldInstallPasteTipHooks = [[KayokoCoreRuntime sharedRuntime] refreshPasteTipPreferences];
    if (!shouldInstallPasteTipHooks) {
        return;
    }

    [KayokoPasteTipHookInstaller installHooks];
    [self addDarwinObserverForName:(__bridge CFStringRef)kKayokoNotificationKeyPreferencesReload
                          callback:kayokoCorePasteTipPreferencesReloadCallback];
}

@end

#pragma mark - Entrypoint

__attribute((constructor)) static void initialize() {
    switch ([KayokoCoreProcessContext currentContext].kind) {
    case KayokoCoreProcessKindSpringBoard:
        [KayokoCoreBootstrap installForSpringBoard];
        return;
    case KayokoCoreProcessKindDruidOrPasted:
        [KayokoCoreBootstrap installForDruidOrPasted];
        return;
    case KayokoCoreProcessKindUnsupported:
        return;
    }
}
