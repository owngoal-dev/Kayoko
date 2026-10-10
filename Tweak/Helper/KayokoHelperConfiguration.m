//
//  KayokoHelperConfiguration.m
//  Kayoko
//

#import "KayokoHelperConfiguration.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoPaths.h"

NS_ASSUME_NONNULL_BEGIN

@interface KayokoHelperConfiguration ()

@property(nonatomic, assign, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, assign, readwrite) NSUInteger activationMethod;
@property(nonatomic, assign, readwrite) KayokoGestureRecognizerMode gestureRecognizerMode;
@property(nonatomic, assign, readwrite, getter=isAutomaticallyPasteEnabled) BOOL automaticallyPasteEnabled;
@property(nonatomic, assign, readwrite, getter=isHapticFeedbackEnabled) BOOL hapticFeedbackEnabled;

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences;

@end

NS_ASSUME_NONNULL_END

@implementation KayokoHelperConfiguration

+ (instancetype)currentConfiguration {
    NSUserDefaults *preferences = [[NSUserDefaults alloc]
        initWithSuiteName:KayokoUserPath([NSString stringWithFormat:@"/var/mobile/Library/Preferences/%@.plist",
                                                                   kKayokoPreferencesIdentifier])];

    [preferences registerDefaults:@{
        kKayokoPreferenceKeyEnabled : @(kKayokoPreferenceKeyEnabledDefaultValue),
        kKayokoPreferenceKeyActivationMethod : @(kKayokoPreferenceKeyActivationMethodDefaultValue),
        kKayokoPreferenceKeyGestureRecognizerMode : @(kKayokoPreferenceKeyGestureRecognizerModeDefaultValue),
        kKayokoPreferenceKeyAutomaticallyPaste : @(kKayokoPreferenceKeyAutomaticallyPasteDefaultValue),
        kKayokoPreferenceKeyPlayHapticFeedback : @(kKayokoPreferenceKeyPlayHapticFeedbackDefaultValue)
    }];

    KayokoHelperConfiguration *configuration = [[self alloc] initWithPreferences:preferences];
    return configuration;
}

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences {
    self = [super init];
    if (self) {
        _enabled = [[preferences objectForKey:kKayokoPreferenceKeyEnabled] boolValue];
        _activationMethod = [[preferences objectForKey:kKayokoPreferenceKeyActivationMethod] unsignedIntegerValue];
        _gestureRecognizerMode =
            [[preferences objectForKey:kKayokoPreferenceKeyGestureRecognizerMode] unsignedIntegerValue];
        if (_gestureRecognizerMode != kKayokoGestureRecognizerModeClassic &&
            _gestureRecognizerMode != kKayokoGestureRecognizerModeSystem) {
            _gestureRecognizerMode = kKayokoPreferenceKeyGestureRecognizerModeDefaultValue;
        }
        _automaticallyPasteEnabled = [[preferences objectForKey:kKayokoPreferenceKeyAutomaticallyPaste] boolValue];
        _hapticFeedbackEnabled = [[preferences objectForKey:kKayokoPreferenceKeyPlayHapticFeedback] boolValue];
    }
    return self;
}

@end
