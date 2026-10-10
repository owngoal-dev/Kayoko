//
//  KayokoHelperLocalization.m
//  Kayoko
//

#import "KayokoHelperLocalization.h"

#import "KayokoPaths.h"

static NSBundle *kayokoHelperLocalizationBundle(void) {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      bundle = [NSBundle bundleWithPath:KayokoRootPath(@"/Library/PreferenceBundles/KayokoPreferences.bundle")];
    });
    return bundle;
}

NSString *KayokoHelperLocalizedString(NSString *key) {
    return [kayokoHelperLocalizationBundle() localizedStringForKey:key value:nil table:@"Tweak"];
}
