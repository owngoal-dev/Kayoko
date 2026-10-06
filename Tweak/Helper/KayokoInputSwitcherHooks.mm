//
//  KayokoInputSwitcherHooks.mm
//  Kayoko
//

#define CHUseSubstrate

#import "KayokoHelperHookInstaller.h"
#import "KayokoHelperLocalization.h"
#import "KayokoHelperRuntime.h"

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const kKayokoInputSwitcherItemIdentifier = @"com.82flex.kayoko.globe";

CHDeclareClass(UIInputSwitcherView);

@interface UIInputSwitcherView : UIView
@property(nonatomic, readonly) BOOL isForDictation;
@end

@interface UIInputSwitcherItem : NSObject
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, copy) NSString *localizedTitle;
@property(nonatomic, copy) NSString *localizedSubtitle;
@property(nonatomic, strong) UIFont *titleFont;
@property(nonatomic, strong) UIFont *subtitleFont;
@property(assign, nonatomic) BOOL usesDeviceLanguage;
@property(nonatomic, strong) UISwitch *switchControl;
@property(nonatomic, copy) id switchIsOnBlock;
@property(nonatomic, copy) id switchToggleBlock;
- (instancetype)initWithIdentifier:(NSString *)identifier;
@end

CHOptimizedMethod0(self, void, UIInputSwitcherView, _reloadInputSwitcherItems) {
    CHSuper0(UIInputSwitcherView, _reloadInputSwitcherItems);
    BOOL isForDictation;
    if ([self respondsToSelector:@selector(isForDictation)]) {
        isForDictation = self.isForDictation;
    } else if (class_getInstanceVariable(object_getClass(self), "m_isForDictation")) {
        isForDictation = MSHookIvar<BOOL>(self, "m_isForDictation");
    } else {
        return;
    }
    if (isForDictation) {
        return;
    }
    NSArray *items = MSHookIvar<NSArray *>(self, "m_inputSwitcherItems");
    NSMutableArray *newItems = [NSMutableArray arrayWithArray:items];
    UIInputSwitcherItem *item =
        [[NSClassFromString(@"UIInputSwitcherItem") alloc] initWithIdentifier:kKayokoInputSwitcherItemIdentifier];
    [item setLocalizedTitle:KayokoHelperLocalizedString(@"Kayoko")];
    if (item) {
        [newItems insertObject:item atIndex:newItems.count - 1];
    }
    MSHookIvar<NSArray *>(self, "m_inputSwitcherItems") = newItems;
}

CHOptimizedMethod1(self, void, UIInputSwitcherView, didSelectItemAtIndex, unsigned long long, index) {
    NSArray *items = MSHookIvar<NSArray *>(self, "m_inputSwitcherItems");
    UIInputSwitcherItem *item = items[index];
    if ([item.identifier isEqualToString:kKayokoInputSwitcherItemIdentifier]) {
        [[KayokoHelperRuntime sharedRuntime] activateKayokoAfterCapturingCurrentFocus];
    }
    CHSuper1(UIInputSwitcherView, didSelectItemAtIndex, index);
}

@implementation KayokoHelperHookInstaller (InputSwitcher)

+ (void)installInputSwitcherHooks {
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
      CHLoadClass_(&UIInputSwitcherView$, NSClassFromString(@"UIInputSwitcherView"));

      CHHook0(UIInputSwitcherView, _reloadInputSwitcherItems);
      CHHook1(UIInputSwitcherView, didSelectItemAtIndex);
    });
}

@end
