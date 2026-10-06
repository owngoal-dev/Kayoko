//
//  KayokoPredictionBarHooks.m
//  Kayoko
//

#define CHUseSubstrate

#import "KayokoHelperHookInstaller.h"
#import "KayokoHelperLocalization.h"
#import "KayokoHelperRuntime.h"
#import "KayokoNotificationKeys.h"

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>

@interface TIKeyboardCandidate : NSObject
@end

@interface TIAutocorrectionList : NSObject
+ (TIAutocorrectionList *)listWithAutocorrection:(TIKeyboardCandidate *)arg1
                                     predictions:(NSArray<TIKeyboardCandidate *> *)predictions
                                       emojiList:(NSArray<TIKeyboardCandidate *> *)emojiList;
@end

@interface UIKeyboardAutocorrectionController : NSObject
- (void)setTextSuggestionList:(TIAutocorrectionList *)textSuggestionList;
- (void)setAutocorrectionList:(TIAutocorrectionList *)textSuggestionList;
@end

@interface TUIPredictionView : UIView
@end

@interface TIKeyboardCandidateSingle : TIKeyboardCandidate
@property(nonatomic, copy) NSString *candidate;
@property(nonatomic, copy) NSString *input;
@end

@interface TIZephyrCandidate : TIKeyboardCandidateSingle
@property(nonatomic, copy) NSString *label;
@property(nonatomic, copy) NSString *fromBundleId;
@end

@interface UIPredictionViewController : UIViewController
@end

@class UIKBInputDelegateManager;

@interface UIKeyboardImpl : UIView
@property(nonatomic, strong, readonly) UIKeyboardAutocorrectionController *autocorrectionController;
@property(nonatomic, strong) UIKBInputDelegateManager *inputDelegateManager;
@property(nonatomic, strong, readonly) UIResponder<UITextInput> *inputDelegate;
+ (instancetype)activeInstance;
@end

@interface UIKBInputDelegateManager : NSObject
- (UITextRange *)selectedTextRange;
- (NSString *)textInRange:(UITextRange *)range;
@end

@interface UIKeyboardLayoutStar : UIView
@end

CHDeclareClass(UIKeyboardAutocorrectionController);
CHDeclareClass(UIPredictionViewController);
CHDeclareClass(UIKeyboardLayoutStar);

static BOOL kayokoShouldShowCustomSuggestions = NO;

static TIAutocorrectionList *kayokoCreateAutocorrectionList(void) {
    NSArray<NSString *> *labels = @[ @"History", @"Copy", @"Paste" ];
    NSMutableArray<TIZephyrCandidate *> *candidates = [[NSMutableArray alloc] init];
    for (NSString *label in labels) {
        TIZephyrCandidate *candidate = [[objc_getClass("TIZephyrCandidate") alloc] init];
        [candidate setLabel:KayokoHelperLocalizedString(label)];
        [candidate setCandidate:[NSString stringWithFormat:@"{kayoko-%@}", label]];
        [candidate setFromBundleId:@"com.82flex.kayoko"];
        [candidates addObject:candidate];
    }

    return [objc_getClass("TIAutocorrectionList") listWithAutocorrection:nil predictions:candidates emojiList:nil];
}

CHOptimizedMethod1(self, void, UIKeyboardAutocorrectionController, setTextSuggestionList, TIAutocorrectionList *,
                   textSuggestionList) {
    if (kayokoShouldShowCustomSuggestions) {
        CHSuper1(UIKeyboardAutocorrectionController, setTextSuggestionList, kayokoCreateAutocorrectionList());
    } else {
        CHSuper1(UIKeyboardAutocorrectionController, setTextSuggestionList, textSuggestionList);
    }
}

CHOptimizedMethod1(self, void, UIKeyboardAutocorrectionController, setAutocorrectionList, TIAutocorrectionList *,
                   autoCorrectionList) {
    if (kayokoShouldShowCustomSuggestions) {
        CHSuper1(UIKeyboardAutocorrectionController, setAutocorrectionList, kayokoCreateAutocorrectionList());
    } else {
        CHSuper1(UIKeyboardAutocorrectionController, setAutocorrectionList, autoCorrectionList);
    }
}

CHOptimizedMethod2(self, void, UIPredictionViewController, predictionView, TUIPredictionView *, predictionView,
                   didSelectCandidate, TIZephyrCandidate *, candidate) {
    if ([candidate respondsToSelector:@selector(fromBundleId)] &&
        [[candidate fromBundleId] isEqualToString:@"com.82flex.kayoko"]) {
        if ([[candidate candidate] isEqualToString:@"{kayoko-History}"]) {
            [[KayokoHelperRuntime sharedRuntime] activateKayoko];
        } else if ([[candidate candidate] isEqualToString:@"{kayoko-Copy}"]) {
            NSString *text = nil;
            if (@available(iOS 15.0, *)) {
                UIKBInputDelegateManager *delegateManager =
                    [[objc_getClass("UIKeyboardImpl") activeInstance] inputDelegateManager];
                UITextRange *range = [delegateManager selectedTextRange];
                text = [delegateManager textInRange:range];
            } else {
                id delegate = [[objc_getClass("UIKeyboardImpl") activeInstance] inputDelegate];
                UITextRange *range = [delegate selectedTextRange];
                text = [delegate textInRange:range];
            }

            if (text.length > 0) {
                [[UIPasteboard generalPasteboard] setString:text];
            }
        } else if ([[candidate candidate] isEqualToString:@"{kayoko-Paste}"]) {
            [[KayokoHelperRuntime sharedRuntime] pasteFromPredictionBar];
        }
    } else {
        CHSuper2(UIPredictionViewController, predictionView, predictionView, didSelectCandidate, candidate);
    }
}

CHOptimizedMethod2(self, BOOL, UIPredictionViewController, isVisibleForInputDelegate, id, delegate, inputViews, id,
                   inputViews) {
    return YES;
}

CHOptimizedMethod1(self, void, UIKeyboardLayoutStar, setKeyplaneName, NSString *, name) {
    CHSuper1(UIKeyboardLayoutStar, setKeyplaneName, name);

    kayokoShouldShowCustomSuggestions = [name isEqualToString:@"numbers-and-punctuation"] ||
                                        [name isEqualToString:@"numbers-and-punctuation-alternate"] ||
                                        [name isEqualToString:@"first-alternate"] ||
                                        [name isEqualToString:@"second-alternate"];

    if (@available(iOS 15.0, *)) {
        [[[objc_getClass("UIKeyboardImpl") activeInstance] autocorrectionController] setAutocorrectionList:nil];
    } else {
        [[[objc_getClass("UIKeyboardImpl") activeInstance] autocorrectionController] setTextSuggestionList:nil];
    }
}

@implementation KayokoHelperHookInstaller (PredictionBar)

+ (void)installPredictionBarHooks {
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
      CHLoadClass_(&UIKeyboardAutocorrectionController$, NSClassFromString(@"UIKeyboardAutocorrectionController"));
      if (@available(iOS 15.0, *)) {
          CHHook1(UIKeyboardAutocorrectionController, setAutocorrectionList);
      } else {
          CHHook1(UIKeyboardAutocorrectionController, setTextSuggestionList);
      }
      CHLoadClass_(&UIPredictionViewController$, NSClassFromString(@"UIPredictionViewController"));
      CHHook2(UIPredictionViewController, isVisibleForInputDelegate, inputViews);
      CHLoadClass_(&UIKeyboardLayoutStar$, NSClassFromString(@"UIKeyboardLayoutStar"));
      CHHook1(UIKeyboardLayoutStar, setKeyplaneName);
      CHHook2(UIPredictionViewController, predictionView, didSelectCandidate);
    });
}

@end
