//
//  KayokoCoreRuntime.m
//  Kayoko
//

#import "KayokoCoreRuntime.h"
#import "KayokoKeyboardHostResolver.h"
#import "KayokoMainViewController.h"
#import "KayokoNotificationKeys.h"
#import "KayokoPanelPresentationMode.h"
#import "KayokoPasteboardManager.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoPurchaseAuthorization.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreFoundation/CoreFoundation.h>
#import <HBLog.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import "KayokoPaths.h"

static NSTimeInterval const kKayokoMinimumFeedbackInterval = 0.6;
static NSTimeInterval const kKayokoPasteSuppressionExpirationDelay = 1.0;

@interface UIApplication (KayokoPrivate)
- (UIInterfaceOrientation)_frontMostAppOrientation;
@end

@interface UIApplicationSceneSettings : NSObject
- (UIUserInterfaceStyle)userInterfaceStyle;
@end

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

@protocol KayokoSBLockScreenManagerClass <NSObject>
+ (SBLockScreenManager *)sharedInstance;
@end

@protocol KayokoKeyboardAppearanceProviding <NSObject>
- (UIKeyboardAppearance)keyboardAppearance;
@end

@interface TITextInputTraits : NSObject <KayokoKeyboardAppearanceProviding>
- (UIKeyboardAppearance)keyboardAppearance;
@end

@interface UIKeyboardImpl : NSObject
+ (instancetype)activeInstance;
- (TITextInputTraits *)textInputTraits;
- (NSObject<KayokoKeyboardAppearanceProviding> *)inputDelegate;
- (NSObject<KayokoKeyboardAppearanceProviding> *)delegate;
@end

@protocol KayokoUIKeyboardImplClass <NSObject>
+ (UIKeyboardImpl *)activeInstance;
@end

@interface KayokoCompactLandscapeOverlayWindow : UIWindow
@end

NS_ASSUME_NONNULL_BEGIN

@interface KayokoPasteSuppressionState : NSObject
@property(nonatomic, assign, readonly, getter=isActive) BOOL active;
- (void)beginWithExpirationDelay:(NSTimeInterval)expirationDelay;
- (BOOL)consumeIfActive;
@end

@interface KayokoPasteSuppressionState ()

#pragma mark - State

@property(nonatomic, assign, readwrite, getter=isActive) BOOL active;
@property(nonatomic, assign) NSUInteger token;

#pragma mark - Expiration

@property(nonatomic, copy, nullable) dispatch_block_t expirationBlock;

#pragma mark - Lifecycle

- (void)clear;

#pragma mark - Expiration

- (void)cancelExpiration;
- (void)expireForToken:(NSUInteger)token;

@end

NS_ASSUME_NONNULL_END

@implementation KayokoCompactLandscapeOverlayWindow

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *rootView = [[self rootViewController] view];
    if (!rootView || [rootView isHidden]) {
        return nil;
    }

    return [super hitTest:point withEvent:event];
}

@end

@implementation KayokoPasteSuppressionState

- (void)beginWithExpirationDelay:(NSTimeInterval)expirationDelay {
    self.token++;
    self.active = YES;

    [self cancelExpiration];

    NSUInteger token = self.token;
    __weak typeof(self) weakSelf = self;
    dispatch_block_t expirationBlock = dispatch_block_create(0, ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || strongSelf.token != token) {
          return;
      }

      [strongSelf expireForToken:token];
    });
    self.expirationBlock = expirationBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(expirationDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), expirationBlock);
}

- (BOOL)consumeIfActive {
    if (!self.active) {
        return NO;
    }

    [self clear];
    return YES;
}

- (void)clear {
    [self cancelExpiration];
    self.active = NO;
}

- (void)cancelExpiration {
    dispatch_block_t expirationBlock = self.expirationBlock;
    if (expirationBlock) {
        dispatch_block_cancel(expirationBlock);
        self.expirationBlock = nil;
    }
}

- (void)expireForToken:(NSUInteger)token {
    if (self.token != token) {
        return;
    }

    self.expirationBlock = nil;
    self.active = NO;
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface KayokoCoreRuntime () <KayokoMainViewControllerDelegate>

#pragma mark - Runtime Configuration

@property(nonatomic, assign, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, assign, readwrite) NSUInteger activationMethod;
@property(nonatomic, assign, readwrite) KayokoGestureRecognizerMode gestureRecognizerMode;
@property(nonatomic, assign, readwrite) BOOL pasteTipsDisabled;

#pragma mark - View State

@property(nonatomic, strong, nullable) KayokoMainViewController *mainViewController;
@property(nonatomic, weak, nullable) UIWindow *statusBarWindow;
@property(nonatomic, strong, nullable) UIControl *portraitOutsideDismissOverlayView;
@property(nonatomic, strong, nullable) UIWindow *compactLandscapeOverlayWindow;
@property(nonatomic, assign) KayokoPanelPresentationMode activePresentationMode;
@property(nonatomic, assign) BOOL pendingHeightPreferenceApply;
@property(nonatomic, assign) BOOL didRequestInitialHistoryPreload;
@property(nonatomic, assign, getter=hasAuthorizationPassInMemory) BOOL authorizationPassInMemory;

#pragma mark - Preferences

@property(nonatomic, strong, nullable) NSUserDefaults *preferences;
@property(nonatomic, assign) NSUInteger maximumHistoryAmount;
@property(nonatomic, assign) BOOL saveText;
@property(nonatomic, assign) BOOL saveImages;
@property(nonatomic, assign) BOOL swipeToSelectWords;
@property(nonatomic, assign) BOOL automaticallyPaste;
@property(nonatomic, assign) KayokoAutomaticPasteMode automaticPasteMode;
@property(nonatomic, assign) KayokoAutomaticPromotionMode automaticPromotionMode;
@property(nonatomic, assign) KayokoInitialViewMode initialViewMode;
@property(nonatomic, assign) BOOL alwaysScrollToTop;
@property(nonatomic, assign) KayokoClearButtonMode clearButtonMode;
@property(nonatomic, assign) BOOL dismissOnOutsideTouch;
@property(nonatomic, assign) BOOL playSoundEffects;
@property(nonatomic, assign) BOOL playHapticFeedback;
@property(nonatomic, assign) NSUInteger previewLineCount;
@property(nonatomic, assign) KayokoItemDetailsMode itemDetailsMode;
@property(nonatomic, assign) CGFloat heightInPoints;

#pragma mark - Feedback

@property(nonatomic, strong, nullable) AVAudioPlayer *clipboardFeedbackSoundPlayer;
@property(nonatomic, strong, nullable) AVAudioPlayer *pasteFeedbackSoundPlayer;
@property(nonatomic, assign) NSTimeInterval lastPasteFeedbackOccurred;
@property(nonatomic, assign) NSTimeInterval lastCopyFeedbackOccurred;

#pragma mark - Pasteboard Capture

@property(nonatomic, strong) KayokoPasteSuppressionState *pasteSuppressionState;

#pragma mark - Device State

@property(nonatomic, assign) int lockStateToken;
@property(nonatomic, assign, getter=isPackageMaintenanceMode) BOOL packageMaintenanceMode;

#pragma mark - Panel Host

- (BOOL)preparePanelHostForPresentationMode:(KayokoPanelPresentationMode)presentationMode;
- (CGRect)fullscreenPanelFrameInWindow:(nullable UIWindow *)window;

@end

NS_ASSUME_NONNULL_END

@implementation KayokoCoreRuntime

+ (instancetype)sharedRuntime {
    static KayokoCoreRuntime *runtime = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      runtime = [[self alloc] initPrivate];
    });
    return runtime;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _previewLineCount = 1;
        _itemDetailsMode = kKayokoPreferenceKeyItemDetailsModeDefaultValue;
        _heightInPoints = 420;
        _activePresentationMode = KayokoPanelPresentationModePortraitDrawer;
        _pasteSuppressionState = [[KayokoPasteSuppressionState alloc] init];
    }
    return self;
}

- (BOOL)panelVisible {
    return self.mainViewController && ![self.mainViewController isHidden];
}

- (BOOL)fullscreenSearchActive {
    if (!self.panelVisible) {
        return NO;
    }

    return [self activePresentationMode] == KayokoPanelPresentationModeCompactLandscapeFullscreen ||
           [self.mainViewController isFullscreenSearchActive];
}

- (BOOL)systemMultitaskingGestureSuppressed {
    return self.panelVisible && [self.mainViewController shouldSuppressSystemMultitaskingGesture];
}

#pragma mark - Panel

- (CGRect)portraitPanelFrameInWindow:(nullable UIWindow *)window {
    CGRect bounds = window ? [window bounds] : [[UIScreen mainScreen] bounds];
    CGFloat height = MIN(self.heightInPoints, CGRectGetHeight(bounds));
    return CGRectMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - height, CGRectGetWidth(bounds), height);
}

- (CGRect)fullscreenPanelFrameInWindow:(UIWindow *)window {
    return window ? [window bounds] : [[UIScreen mainScreen] bounds];
}

- (UIControl *)ensurePortraitOutsideDismissOverlayInWindow:(UIWindow *)window {
    if (self.portraitOutsideDismissOverlayView && [self.portraitOutsideDismissOverlayView superview] == window) {
        return self.portraitOutsideDismissOverlayView;
    }

    [self.portraitOutsideDismissOverlayView removeFromSuperview];
    UIControl *outsideDismissOverlayView = [[UIControl alloc] initWithFrame:[window bounds]];
    [outsideDismissOverlayView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [outsideDismissOverlayView setBackgroundColor:[UIColor colorWithWhite:0 alpha:0.18]];
    [outsideDismissOverlayView setAlpha:0];
    [outsideDismissOverlayView setHidden:YES];
    [outsideDismissOverlayView setUserInteractionEnabled:NO];
    [window addSubview:outsideDismissOverlayView];
    self.portraitOutsideDismissOverlayView = outsideDismissOverlayView;
    return outsideDismissOverlayView;
}

- (void)createMainViewControllerIfNeeded {
    if (self.mainViewController) {
        return;
    }

    CGRect initialFrame = [self portraitPanelFrameInWindow:self.statusBarWindow];
    self.mainViewController = [[KayokoMainViewController alloc] initWithFrame:initialFrame];
    [self.mainViewController setDelegate:self];
    [self applyPreferencesToView];
    if (self.didRequestInitialHistoryPreload) {
        [self.mainViewController preloadHistoryIfNeeded];
    }
}

- (void)installPanelInStatusBarWindow:(UIWindow *)window {
    if (!window) {
        return;
    }

    self.statusBarWindow = window;
    [self createMainViewControllerIfNeeded];

    if (![self.mainViewController isHidden]) {
        return;
    }

    [self preparePanelHostForPresentationMode:KayokoPanelPresentationModePortraitDrawer];
}

- (CGFloat)overlayWindowLevel {
    if (self.statusBarWindow) {
        return [self.statusBarWindow windowLevel];
    }

    return UIWindowLevelStatusBar;
}

- (UIInterfaceOrientation)frontmostAppInterfaceOrientation {
    UIApplication *application = [UIApplication sharedApplication];
    if (![application respondsToSelector:@selector(_frontMostAppOrientation)]) {
        return UIInterfaceOrientationUnknown;
    }

    return [application _frontMostAppOrientation];
}

- (UIInterfaceOrientationMask)compactLandscapeSupportedInterfaceOrientations {
    switch ([self frontmostAppInterfaceOrientation]) {
    case UIInterfaceOrientationLandscapeLeft:
        return UIInterfaceOrientationMaskLandscapeLeft;
    case UIInterfaceOrientationLandscapeRight:
        return UIInterfaceOrientationMaskLandscapeRight;
    default:
        return UIInterfaceOrientationMaskLandscape;
    }
}

- (nullable UIWindow *)compactLandscapeOverlayWindowCreatingIfNeeded {
    UIWindowScene *windowScene = [self.statusBarWindow windowScene];
    if (!windowScene) {
        return nil;
    }

    if (self.compactLandscapeOverlayWindow && [self.compactLandscapeOverlayWindow windowScene] != windowScene) {
        [self.compactLandscapeOverlayWindow setHidden:YES];
        [self.compactLandscapeOverlayWindow setRootViewController:nil];
        self.compactLandscapeOverlayWindow = nil;
    }

    if (!self.compactLandscapeOverlayWindow) {
        UIWindow *window = [[KayokoCompactLandscapeOverlayWindow alloc] initWithWindowScene:windowScene];
        [window setBackgroundColor:[UIColor clearColor]];
        [window setOpaque:NO];
        [window setClipsToBounds:YES];
        [window setHidden:YES];
        self.compactLandscapeOverlayWindow = window;
    }

    [self.compactLandscapeOverlayWindow setWindowLevel:[self overlayWindowLevel]];
    return self.compactLandscapeOverlayWindow;
}

- (void)applyCompactLandscapeOverlayFrame:(UIWindow *)window {
    CGRect bounds = [[UIScreen mainScreen] bounds];
    [window setFrame:bounds];
    [[window rootViewController].view setFrame:[window bounds]];
    [[window rootViewController].view setNeedsLayout];
}

- (void)tearDownCompactLandscapeOverlayHost {
    [self.compactLandscapeOverlayWindow setHidden:YES];
    if ([self.compactLandscapeOverlayWindow rootViewController] == self.mainViewController) {
        [self.compactLandscapeOverlayWindow setRootViewController:nil];
    }
    [self.mainViewController setKayokoSupportedInterfaceOrientations:UIInterfaceOrientationMaskAll];
}

- (void)handleMainPanelDidHide {
    if ([self activePresentationMode] != KayokoPanelPresentationModeCompactLandscapeFullscreen &&
        [self.compactLandscapeOverlayWindow rootViewController] != self.mainViewController) {
        return;
    }

    [self tearDownCompactLandscapeOverlayHost];
}

- (void)mainViewControllerDidRequestFocusRestore:(KayokoMainViewController *)viewController {
    if (viewController != self.mainViewController) {
        return;
    }

    [self requestHelperFocusRestore];
}

- (void)mainViewControllerDidHide:(KayokoMainViewController *)viewController {
    if (viewController != self.mainViewController) {
        return;
    }

    [self handleMainPanelDidHide];
}

- (BOOL)prepareCompactLandscapeHost {
    UIWindow *window = [self compactLandscapeOverlayWindowCreatingIfNeeded];
    if (!window) {
        return NO;
    }

    [self.mainViewController setOutsideDismissOverlayView:nil];
    [self.mainViewController
        setKayokoSupportedInterfaceOrientations:[self compactLandscapeSupportedInterfaceOrientations]];
    [self.mainViewController setPresentationMode:KayokoPanelPresentationModeCompactLandscapeFullscreen];
    [self applyCompactLandscapeOverlayFrame:window];
    if ([window rootViewController] != self.mainViewController) {
        [[self.mainViewController view] removeFromSuperview];
        [window setRootViewController:self.mainViewController];
    }
    [window setHidden:NO];
    [self applyCompactLandscapeOverlayFrame:window];

    UIView *panelView = [self.mainViewController view];
    [panelView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight];
    [panelView setFrame:[self fullscreenPanelFrameInWindow:window]];
    [panelView setNeedsLayout];
    self.activePresentationMode = KayokoPanelPresentationModeCompactLandscapeFullscreen;
    return YES;
}

- (BOOL)preparePortraitHost {
    UIWindow *window = self.statusBarWindow;
    if (!window) {
        return NO;
    }

    UIControl *outsideDismissOverlayView = [self ensurePortraitOutsideDismissOverlayInWindow:window];
    [self.mainViewController setOutsideDismissOverlayView:outsideDismissOverlayView];
    [self.mainViewController setKayokoSupportedInterfaceOrientations:UIInterfaceOrientationMaskAll];
    [self.mainViewController setPresentationMode:KayokoPanelPresentationModePortraitDrawer];

    if ([self.compactLandscapeOverlayWindow rootViewController] == self.mainViewController) {
        [self.compactLandscapeOverlayWindow setRootViewController:nil];
    }
    [self.compactLandscapeOverlayWindow setHidden:YES];

    UIView *panelView = [self.mainViewController view];
    if ([panelView superview] != window) {
        [panelView removeFromSuperview];
        [window addSubview:panelView];
    }
    [window bringSubviewToFront:outsideDismissOverlayView];
    [window bringSubviewToFront:panelView];
    [panelView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin];
    [panelView setFrame:[self portraitPanelFrameInWindow:window]];
    [panelView setNeedsLayout];
    self.activePresentationMode = KayokoPanelPresentationModePortraitDrawer;
    return YES;
}

- (BOOL)preparePanelHostForPresentationMode:(KayokoPanelPresentationMode)presentationMode {
    if (!self.mainViewController) {
        return NO;
    }

    if (!CGAffineTransformIsIdentity([[self.mainViewController view] transform])) {
        [[self.mainViewController view] setTransform:CGAffineTransformIdentity];
    }

    if (presentationMode == KayokoPanelPresentationModeCompactLandscapeFullscreen) {
        return [self prepareCompactLandscapeHost];
    }

    return [self preparePortraitHost];
}

- (void)preloadInitialHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    self.didRequestInitialHistoryPreload = YES;

    KayokoPasteboardManager *pasteboardManager = [KayokoPasteboardManager sharedInstance];
    [pasteboardManager warmUpHistoryAccess];

    if (self.mainViewController) {
        [self.mainViewController preloadHistoryIfNeeded];
    }
}

- (void)applyHeightPreferenceToViewApplyingWhenHidden:(BOOL)applyWhenHidden {
    if (!self.mainViewController) {
        return;
    }

    if (!applyWhenHidden && [self.mainViewController isHidden]) {
        return;
    }

    if ([self activePresentationMode] == KayokoPanelPresentationModeCompactLandscapeFullscreen) {
        UIWindow *window = self.compactLandscapeOverlayWindow;
        UIView *panelView = [self.mainViewController view];
        CGRect newFrame = [self fullscreenPanelFrameInWindow:window];
        if (!CGRectEqualToRect([panelView frame], newFrame)) {
            if (!CGAffineTransformIsIdentity([panelView transform])) {
                [panelView setTransform:CGAffineTransformIdentity];
            }
            [panelView setFrame:newFrame];
            [panelView setNeedsLayout];
        }
        return;
    }

    UIView *panelView = [self.mainViewController view];
    UIView *containerView = [panelView superview];
    CGRect bounds = containerView ? [containerView bounds] : [[UIScreen mainScreen] bounds];
    CGFloat height = MIN(self.heightInPoints, CGRectGetHeight(bounds));
    CGRect newFrame = CGRectMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - height, CGRectGetWidth(bounds), height);
    if (!CGRectEqualToRect([panelView frame], newFrame)) {
        if (!CGAffineTransformIsIdentity([panelView transform])) {
            [panelView setTransform:CGAffineTransformIdentity];
        }
        [panelView setFrame:newFrame];
        [panelView setNeedsLayout];
    }
}

- (void)applyPreferencesToView {
    if (!self.mainViewController) {
        return;
    }

    if ([self.mainViewController automaticallyPaste] != self.automaticallyPaste) {
        [self.mainViewController setAutomaticallyPaste:self.automaticallyPaste];
    }
    if ([self.mainViewController dismissOnOutsideTouch] != self.dismissOnOutsideTouch) {
        [self.mainViewController setDismissOnOutsideTouch:self.dismissOnOutsideTouch];
    }
    if ([self.mainViewController swipeToSelectWords] != self.swipeToSelectWords) {
        [self.mainViewController setSwipeToSelectWords:self.swipeToSelectWords];
    }
    if ([self.mainViewController previewLineCount] != self.previewLineCount) {
        [self.mainViewController setPreviewLineCount:self.previewLineCount];
    }
    if ([self.mainViewController itemDetailsMode] != self.itemDetailsMode) {
        [self.mainViewController setItemDetailsMode:self.itemDetailsMode];
    }
    if ([self.mainViewController initialViewMode] != self.initialViewMode) {
        [self.mainViewController setInitialViewMode:self.initialViewMode];
    }
    if ([self.mainViewController alwaysScrollToTop] != self.alwaysScrollToTop) {
        [self.mainViewController setAlwaysScrollToTop:self.alwaysScrollToTop];
    }
    if ([self.mainViewController clearButtonMode] != self.clearButtonMode) {
        [self.mainViewController setClearButtonMode:self.clearButtonMode];
    }
    if ([self.mainViewController shouldPlayFeedback] != self.playHapticFeedback) {
        [self.mainViewController setShouldPlayFeedback:self.playHapticFeedback];
    }

    [self applyHeightPreferenceToViewApplyingWhenHidden:YES];
}

- (void)requestHelperFocusRestore {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyHelperRestoreFocus, nil, nil, YES);
}

#pragma mark - Preferences

- (void)readPasteTipPreferencesFromPreferences:(NSUserDefaults *)preferences {
    self.enabled = [[preferences objectForKey:kKayokoPreferenceKeyEnabled] boolValue];
    self.pasteTipsDisabled = [[preferences objectForKey:kKayokoPreferenceKeyDisablePasteTips] boolValue];
}

- (BOOL)refreshPasteTipPreferences {
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [preferences registerDefaults:@{
        kKayokoPreferenceKeyEnabled : @(kKayokoPreferenceKeyEnabledDefaultValue),
        kKayokoPreferenceKeyDisablePasteTips : @(kKayokoPreferenceKeyDisablePasteTipsDefaultValue),
    }];

    [self readPasteTipPreferencesFromPreferences:preferences];
    return self.enabled;
}

- (void)loadPreferences {
    self.preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [self.preferences registerDefaults:@{
        kKayokoPreferenceKeyEnabled : @(kKayokoPreferenceKeyEnabledDefaultValue),
        kKayokoPreferenceKeyActivationMethod : @(kKayokoPreferenceKeyActivationMethodDefaultValue),
        kKayokoPreferenceKeyGestureRecognizerMode : @(kKayokoPreferenceKeyGestureRecognizerModeDefaultValue),
        kKayokoPreferenceKeyMaximumHistoryAmount : @(kKayokoPreferenceKeyMaximumHistoryAmountDefaultValue),
        kKayokoPreferenceKeySaveText : @(kKayokoPreferenceKeySaveTextDefaultValue),
        kKayokoPreferenceKeySaveImages : @(kKayokoPreferenceKeySaveImagesDefaultValue),
        kKayokoPreferenceKeySwipeToSelectWords : @(kKayokoPreferenceKeySwipeToSelectWordsDefaultValue),
        kKayokoPreferenceKeyAutomaticallyPaste : @(kKayokoPreferenceKeyAutomaticallyPasteDefaultValue),
        kKayokoPreferenceKeyAutomaticPasteMode : @(kKayokoPreferenceKeyAutomaticPasteModeDefaultValue),
        kKayokoPreferenceKeyAutomaticPromotionMode : @(kKayokoPreferenceKeyAutomaticPromotionModeDefaultValue),
        kKayokoPreferenceKeyInitialViewMode : @(kKayokoPreferenceKeyInitialViewModeDefaultValue),
        kKayokoPreferenceKeyAlwaysScrollToTop : @(kKayokoPreferenceKeyAlwaysScrollToTopDefaultValue),
        kKayokoPreferenceKeyClearButtonMode : @(kKayokoPreferenceKeyClearButtonModeDefaultValue),
        kKayokoPreferenceKeyDismissOnOutsideTouch : @(kKayokoPreferenceKeyDismissOnOutsideTouchDefaultValue),
        kKayokoPreferenceKeyDisablePasteTips : @(kKayokoPreferenceKeyDisablePasteTipsDefaultValue),
        kKayokoPreferenceKeyIgnoreRemoteReplication : @(kKayokoPreferenceKeyIgnoreRemoteReplicationDefaultValue),
        kKayokoPreferenceKeyApplicationBlacklist : @[],
        kKayokoPreferenceKeyPlaySoundEffects : @(kKayokoPreferenceKeyPlaySoundEffectsDefaultValue),
        kKayokoPreferenceKeyPlayHapticFeedback : @(kKayokoPreferenceKeyPlayHapticFeedbackDefaultValue),
        kKayokoPreferenceKeyPreviewLineCount : @(kKayokoPreferenceKeyPreviewLineCountDefaultValue),
        kKayokoPreferenceKeyItemDetailsMode : @(kKayokoPreferenceKeyItemDetailsModeDefaultValue),
        kKayokoPreferenceKeyHeightInPoints : @(kKayokoPreferenceKeyHeightInPointsDefaultValue),
    }];

    [self readPasteTipPreferencesFromPreferences:self.preferences];
    self.activationMethod = [[self.preferences objectForKey:kKayokoPreferenceKeyActivationMethod] unsignedIntegerValue];
    self.gestureRecognizerMode =
        [[self.preferences objectForKey:kKayokoPreferenceKeyGestureRecognizerMode] unsignedIntegerValue];
    if (self.gestureRecognizerMode != kKayokoGestureRecognizerModeClassic &&
        self.gestureRecognizerMode != kKayokoGestureRecognizerModeSystem) {
        self.gestureRecognizerMode = kKayokoPreferenceKeyGestureRecognizerModeDefaultValue;
    }
    self.maximumHistoryAmount = [KayokoPasteboardManager
        normalizedMaximumHistoryAmountForValue:[[self.preferences objectForKey:kKayokoPreferenceKeyMaximumHistoryAmount]
                                                   unsignedIntegerValue]];
    self.saveText = [[self.preferences objectForKey:kKayokoPreferenceKeySaveText] boolValue];
    self.saveImages = [[self.preferences objectForKey:kKayokoPreferenceKeySaveImages] boolValue];
    self.swipeToSelectWords = [[self.preferences objectForKey:kKayokoPreferenceKeySwipeToSelectWords] boolValue];
    self.automaticallyPaste = [[self.preferences objectForKey:kKayokoPreferenceKeyAutomaticallyPaste] boolValue];
    self.automaticPasteMode =
        [[self.preferences objectForKey:kKayokoPreferenceKeyAutomaticPasteMode] unsignedIntegerValue];
    if (self.automaticPasteMode != kKayokoAutomaticPasteModeClassic &&
        self.automaticPasteMode != kKayokoAutomaticPasteModeSimulated &&
        self.automaticPasteMode != kKayokoAutomaticPasteModeAutomatic) {
        self.automaticPasteMode = kKayokoPreferenceKeyAutomaticPasteModeDefaultValue;
    }
    self.automaticPromotionMode =
        [[self.preferences objectForKey:kKayokoPreferenceKeyAutomaticPromotionMode] unsignedIntegerValue];
    if (self.automaticPromotionMode != kKayokoAutomaticPromotionModeOff &&
        self.automaticPromotionMode != kKayokoAutomaticPromotionModeHistoryOnly &&
        self.automaticPromotionMode != kKayokoAutomaticPromotionModeAlways) {
        self.automaticPromotionMode = kKayokoPreferenceKeyAutomaticPromotionModeDefaultValue;
    }
    self.initialViewMode = [[self.preferences objectForKey:kKayokoPreferenceKeyInitialViewMode] unsignedIntegerValue];
    if (self.initialViewMode != kKayokoInitialViewModeHistory &&
        self.initialViewMode != kKayokoInitialViewModeFavorites &&
        self.initialViewMode != kKayokoInitialViewModePreviousSelection) {
        self.initialViewMode = kKayokoPreferenceKeyInitialViewModeDefaultValue;
    }
    self.alwaysScrollToTop = [[self.preferences objectForKey:kKayokoPreferenceKeyAlwaysScrollToTop] boolValue];
    self.clearButtonMode = [[self.preferences objectForKey:kKayokoPreferenceKeyClearButtonMode] unsignedIntegerValue];
    if (self.clearButtonMode != kKayokoClearButtonModeOff &&
        self.clearButtonMode != kKayokoClearButtonModeHistoryOnly &&
        self.clearButtonMode != kKayokoClearButtonModeAlways) {
        self.clearButtonMode = kKayokoPreferenceKeyClearButtonModeDefaultValue;
    }
    self.dismissOnOutsideTouch = [[self.preferences objectForKey:kKayokoPreferenceKeyDismissOnOutsideTouch] boolValue];
    BOOL ignoreRemoteReplication =
        [[self.preferences objectForKey:kKayokoPreferenceKeyIgnoreRemoteReplication] boolValue];
    NSSet<NSString *> *applicationBlacklist =
        [NSSet setWithArray:[self.preferences arrayForKey:kKayokoPreferenceKeyApplicationBlacklist] ?: @[]];
    self.playSoundEffects = [[self.preferences objectForKey:kKayokoPreferenceKeyPlaySoundEffects] boolValue];
    self.playHapticFeedback = [[self.preferences objectForKey:kKayokoPreferenceKeyPlayHapticFeedback] boolValue];
    self.previewLineCount = [[self.preferences objectForKey:kKayokoPreferenceKeyPreviewLineCount] unsignedIntegerValue];
    self.itemDetailsMode = [[self.preferences objectForKey:kKayokoPreferenceKeyItemDetailsMode] unsignedIntegerValue];
    if (self.itemDetailsMode != kKayokoItemDetailsModeOff && self.itemDetailsMode != kKayokoItemDetailsModeImagesOnly &&
        self.itemDetailsMode != kKayokoItemDetailsModeAll) {
        self.itemDetailsMode = kKayokoPreferenceKeyItemDetailsModeDefaultValue;
    }
    self.heightInPoints = [[self.preferences objectForKey:kKayokoPreferenceKeyHeightInPoints] doubleValue];

    KayokoPasteboardManager *pasteboardManager = [KayokoPasteboardManager sharedInstance];
    if ([pasteboardManager maximumHistoryAmount] != self.maximumHistoryAmount) {
        [pasteboardManager setMaximumHistoryAmount:self.maximumHistoryAmount];
    }
    if ([pasteboardManager saveText] != self.saveText) {
        [pasteboardManager setSaveText:self.saveText];
    }
    if ([pasteboardManager saveImages] != self.saveImages) {
        [pasteboardManager setSaveImages:self.saveImages];
    }
    if ([pasteboardManager automaticallyPaste] != self.automaticallyPaste) {
        [pasteboardManager setAutomaticallyPaste:self.automaticallyPaste];
    }
    if ([pasteboardManager automaticPasteMode] != self.automaticPasteMode) {
        [pasteboardManager setAutomaticPasteMode:self.automaticPasteMode];
    }
    if ([pasteboardManager automaticPromotionMode] != self.automaticPromotionMode) {
        [pasteboardManager setAutomaticPromotionMode:self.automaticPromotionMode];
    }
    if ([pasteboardManager ignoreRemoteReplication] != ignoreRemoteReplication) {
        [pasteboardManager setIgnoreRemoteReplication:ignoreRemoteReplication];
    }
    if (![[pasteboardManager applicationBlacklist] isEqualToSet:applicationBlacklist]) {
        [pasteboardManager setApplicationBlacklist:applicationBlacklist];
    }

    [self applyPreferencesToView];
}

- (void)loadHeightPreference {
    NSUserDefaults *heightPreferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    [heightPreferences registerDefaults:@{
        kKayokoPreferenceKeyHeightInPoints : @(kKayokoPreferenceKeyHeightInPointsDefaultValue),
    }];
    self.heightInPoints = [[heightPreferences objectForKey:kKayokoPreferenceKeyHeightInPoints] doubleValue];
    if (self.pendingHeightPreferenceApply) {
        return;
    }

    self.pendingHeightPreferenceApply = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
      self.pendingHeightPreferenceApply = NO;
      [self applyHeightPreferenceToViewApplyingWhenHidden:NO];
    });
}

#pragma mark - Device State

- (BOOL)readUILocked:(BOOL *)locked {
    Class<KayokoSBLockScreenManagerClass> managerClass =
        (Class<KayokoSBLockScreenManagerClass>)NSClassFromString(@"SBLockScreenManager");
    if (![managerClass respondsToSelector:@selector(sharedInstance)]) {
        return NO;
    }

    SBLockScreenManager *manager = [managerClass sharedInstance];
    if (![manager respondsToSelector:@selector(isUILocked)]) {
        return NO;
    }

    if (locked) {
        *locked = [manager isUILocked];
    }
    return YES;
}

- (UIUserInterfaceStyle)userInterfaceStyleFromSceneSettings:(UIApplicationSceneSettings *)settings {
    if (![settings respondsToSelector:@selector(userInterfaceStyle)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    NSInteger style = (NSInteger)[settings userInterfaceStyle];
    if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
        return (UIUserInterfaceStyle)style;
    }
    return UIUserInterfaceStyleUnspecified;
}

- (UIUserInterfaceStyle)userInterfaceStyleFromKeyboardAppearance:(NSInteger)keyboardAppearance {
    switch ((UIKeyboardAppearance)keyboardAppearance) {
    case UIKeyboardAppearanceDark:
        return UIUserInterfaceStyleDark;
    case UIKeyboardAppearanceLight:
        return UIUserInterfaceStyleLight;
    default:
        return UIUserInterfaceStyleUnspecified;
    }
}

- (UIUserInterfaceStyle)userInterfaceStyleFromKeyboardAppearanceProvider:
    (NSObject<KayokoKeyboardAppearanceProviding> *)provider {
    if (![provider respondsToSelector:@selector(keyboardAppearance)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    return [self userInterfaceStyleFromKeyboardAppearance:[provider keyboardAppearance]];
}

- (UIUserInterfaceStyle)currentSpringBoardKeyboardUserInterfaceStyle {
    Class<KayokoUIKeyboardImplClass> keyboardImplClass =
        (Class<KayokoUIKeyboardImplClass>)NSClassFromString(@"UIKeyboardImpl");
    if (![keyboardImplClass respondsToSelector:@selector(activeInstance)]) {
        return UIUserInterfaceStyleUnspecified;
    }

    UIKeyboardImpl *keyboardImpl = [keyboardImplClass activeInstance];
    if ([keyboardImpl respondsToSelector:@selector(textInputTraits)]) {
        UIUserInterfaceStyle style =
            [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl textInputTraits]];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    if ([keyboardImpl respondsToSelector:@selector(inputDelegate)]) {
        UIUserInterfaceStyle style =
            [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl inputDelegate]];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    return [keyboardImpl respondsToSelector:@selector(delegate)]
               ? [self userInterfaceStyleFromKeyboardAppearanceProvider:[keyboardImpl delegate]]
               : UIUserInterfaceStyleUnspecified;
}

- (UIUserInterfaceStyle)currentKeyboardHostUserInterfaceStyle {
    KayokoKeyboardHostResolver *resolver = [KayokoKeyboardHostResolver sharedResolver];
    FBScene *hostScene = [resolver currentKeyboardHostScene];
    if ([resolver sceneIsHostedBySpringBoard:hostScene]) {
        UIUserInterfaceStyle style = [self currentSpringBoardKeyboardUserInterfaceStyle];
        if (style == UIUserInterfaceStyleLight || style == UIUserInterfaceStyleDark) {
            return style;
        }
    }

    if ([resolver sceneIsSpotlightScene:hostScene]) {
        return UIUserInterfaceStyleDark;
    }

    return [self userInterfaceStyleFromSceneSettings:[resolver settingsForScene:hostScene]];
}

- (void)applyKeyboardHostUserInterfaceStyle:(UIUserInterfaceStyle)style {
    if (!self.mainViewController || (style != UIUserInterfaceStyleLight && style != UIUserInterfaceStyleDark)) {
        return;
    }

    [self.mainViewController applyUserInterfaceStyle:style];
}

- (void)applyCurrentKeyboardHostUserInterfaceStyle {
    [self applyKeyboardHostUserInterfaceStyle:[self currentKeyboardHostUserInterfaceStyle]];
}

- (BOOL)sceneIsCurrentKeyboardHostScene:(FBScene *)scene {
    return [[KayokoKeyboardHostResolver sharedResolver] sceneIsCurrentKeyboardHostScene:scene];
}

- (void)handleScene:(FBScene *)scene didUpdateSettings:(UIApplicationSceneSettings *)settings {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self handleScene:scene didUpdateSettings:settings];
        });
        return;
    }

    if (![self panelVisible] || ![self sceneIsCurrentKeyboardHostScene:scene]) {
        return;
    }

    KayokoKeyboardHostResolver *resolver = [KayokoKeyboardHostResolver sharedResolver];
    UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
    if ([resolver sceneIsHostedBySpringBoard:scene]) {
        style = [self currentSpringBoardKeyboardUserInterfaceStyle];
    }
    if (style != UIUserInterfaceStyleLight && style != UIUserInterfaceStyleDark) {
        style = [resolver sceneIsSpotlightScene:scene] ? UIUserInterfaceStyleDark
                                                       : [self userInterfaceStyleFromSceneSettings:settings];
    }
    [self applyKeyboardHostUserInterfaceStyle:style];
}

- (BOOL)frontmostAppIsLandscape {
    return UIInterfaceOrientationIsLandscape([self frontmostAppInterfaceOrientation]);
}

- (BOOL)deviceUsesCompactLandscapePresentation {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone && [self frontmostAppIsLandscape];
}

- (KayokoPanelPresentationMode)currentPresentationMode {
    return [self deviceUsesCompactLandscapePresentation] ? KayokoPanelPresentationModeCompactLandscapeFullscreen
                                                         : KayokoPanelPresentationModePortraitDrawer;
}

- (BOOL)authorizationPassedForPanelShow {
    if ([self hasAuthorizationPassInMemory]) {
        return YES;
    }

    NSError *authorizationError = nil;
    BOOL authorizationPassed = [KayokoPurchaseAuthorization hasAuthorizationPassFlagWithError:&authorizationError];
    if (authorizationError) {
        HBLogDebug(@"Kayoko: Authorization pass flag check failed: %@", authorizationError);
    }
    if (authorizationPassed) {
        [self setAuthorizationPassInMemory:YES];
    }
    return authorizationPassed;
}

- (void)startLockStateObserver {
    if (self.lockStateToken != 0) {
        return;
    }

    int status = notify_register_dispatch("com.apple.springboard.lockstate", &_lockStateToken,
                                          dispatch_get_main_queue(), ^(int token) {
                                            (void)token;
                                            [self handleLockStateNotification];
                                          });
    if (status != NOTIFY_STATUS_OK) {
        HBLogDebug(@"Kayoko: Unable to observe SpringBoard lock state: %d", status);
        self.lockStateToken = 0;
    }
}

- (void)handleLockStateNotification {
    BOOL locked = NO;
    if (![self readUILocked:&locked] || !locked) {
        return;
    }

    [self hideImmediately];
}

#pragma mark - Feedback

- (AVAudioPlayer *)audioPlayerForSound:(NSString *)soundName {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient
                                     withOptions:AVAudioSessionCategoryOptionMixWithOthers
                                           error:&error];
    if (error) {
        HBLogDebug(@"Kayoko: Failed to configure audio session: %@", error);
    }

    NSString *relativeSoundPath =
        [NSString stringWithFormat:@"/Library/PreferenceBundles/KayokoPreferences.bundle/%@.aiff", soundName];
    NSString *soundPath = KayokoRootPath(relativeSoundPath);
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:soundPath]
                                                                   error:&error];
    if (error) {
        HBLogDebug(@"Kayoko: Failed to load %@ sound: %@", soundName, error);
        return nil;
    }

    [player prepareToPlay];
    return player;
}

- (nullable AVAudioPlayer *)playFeedbackSoundWithPlayer:(nullable AVAudioPlayer *)player
                                              soundName:(NSString *)soundName {
    if (!player) {
        player = [self audioPlayerForSound:soundName];
    }

    [player setCurrentTime:0];
    [player play];
    return player;
}

- (void)playSuccessHapticFeedbackIfNeeded {
    if (self.playHapticFeedback) {
        AudioServicesPlaySystemSound(1519);
    }
}

- (void)playFailureHapticFeedbackIfNeeded {
    if (self.playHapticFeedback) {
        AudioServicesPlaySystemSound(1521);
    }
}

- (void)playPasteFeedback {
    NSTimeInterval now = CACurrentMediaTime();
    if (fabs(now - self.lastPasteFeedbackOccurred) < kKayokoMinimumFeedbackInterval) {
        return;
    }
    self.lastPasteFeedbackOccurred = now;
    if (self.playSoundEffects) {
        self.pasteFeedbackSoundPlayer = [self playFeedbackSoundWithPlayer:self.pasteFeedbackSoundPlayer
                                                                soundName:@"Paste"];
    }
    [self playSuccessHapticFeedbackIfNeeded];
}

#pragma mark - Pasteboard

- (void)markPasteWillStart {
    [self.pasteSuppressionState beginWithExpirationDelay:kKayokoPasteSuppressionExpirationDelay];
}

- (void)capturePasteboardChange {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self capturePasteboardChangeNow];
    });
}

- (void)capturePasteboardChangeNow {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] pullPasteboardChangesWithCompletion:^(BOOL didSaveAnyItem) {
      if ([self.pasteSuppressionState consumeIfActive]) {
          return;
      }
      if (!didSaveAnyItem) {
          return;
      }

      NSTimeInterval now = CACurrentMediaTime();
      if (fabs(now - self.lastCopyFeedbackOccurred) < kKayokoMinimumFeedbackInterval) {
          return;
      }
      self.lastCopyFeedbackOccurred = now;
      if (self.playSoundEffects) {
          self.clipboardFeedbackSoundPlayer = [self playFeedbackSoundWithPlayer:self.clipboardFeedbackSoundPlayer
                                                                      soundName:@"Copy"];
      }
      [self playSuccessHapticFeedbackIfNeeded];
    }];
}

#pragma mark - Visibility

- (void)show {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (!self.mainViewController || ![self.mainViewController isHidden]) {
        return;
    }

    BOOL locked = NO;
    if ([self readUILocked:&locked] && locked) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }

    KayokoPanelPresentationMode presentationMode = [self currentPresentationMode];
    if (![self preparePanelHostForPresentationMode:presentationMode]) {
        [self playFailureHapticFeedbackIfNeeded];
        return;
    }

    [self.mainViewController setAuthorizationPassed:[self authorizationPassedForPanelShow]];

    [self applyHeightPreferenceToViewApplyingWhenHidden:YES];
    [self.mainViewController applyUserInterfaceStyle:UIUserInterfaceStyleUnspecified];
    [self applyCurrentKeyboardHostUserInterfaceStyle];

    [self.mainViewController show];

    if (self.activationMethod & kActivationMethodDictationKey) {
        [self playSuccessHapticFeedbackIfNeeded];
    }
}

- (void)hideWithAnimationStyle:(KayokoPanelHideAnimationStyle)animationStyle {
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideWithAnimationStyle:animationStyle completion:nil];
    }
}

- (void)hideForExternalRequest {
    if (!self.mainViewController || [self.mainViewController isHidden]) {
        return;
    }

    [self.mainViewController hideForExternalRequestWithAnimationStyle:KayokoPanelHideAnimationStyleDefault
                                                           completion:nil];
}

- (void)hide {
    [self hideWithAnimationStyle:KayokoPanelHideAnimationStyleDefault];
}

- (void)hideWithStandardDismissAnimation {
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideWithStandardDismissAnimation];
    }
}

- (void)hideForRotation {
    [self hideWithAnimationStyle:KayokoPanelHideAnimationStyleFade];
}

- (void)hideImmediately {
    if (self.mainViewController && ![self.mainViewController isHidden]) {
        [self.mainViewController hideImmediately];
    }
}

- (void)reloadHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (self.mainViewController) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.mainViewController handleHistoryChanged];
        });
    }
}

- (void)handleApplicationMetadataChanged {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    if (self.mainViewController) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self.mainViewController handleApplicationMetadataChanged];
        });
    }
}

- (void)checkpointHistoryDatabase {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] checkpointHistoryDatabase];
}

- (void)prepareForPackageMaintenance {
    [self setPackageMaintenanceMode:YES];
    [[KayokoPasteboardManager sharedInstance] enterMaintenanceModeUntilProcessExit];
    [self hideImmediately];
}

- (void)resetThumbnailMemoryCache {
    [[KayokoPasteboardManager sharedInstance] resetThumbnailMemoryCache];
}

- (void)clearFavorites {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] removeAllPasteboardItemsFromHistoryWithKey:kKayokoHistoryKeyFavorites
                                                                      shouldRemoveImages:YES
                                                                              completion:nil];
}

- (void)clearHistory {
    if ([self isPackageMaintenanceMode]) {
        return;
    }

    [[KayokoPasteboardManager sharedInstance] removeAllPasteboardItemsFromHistoryWithKey:kKayokoHistoryKeyHistory
                                                                      shouldRemoveImages:YES
                                                                              completion:nil];
}

@end
