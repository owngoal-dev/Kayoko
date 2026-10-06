//
//  KayokoDictationHooks.m
//  Kayoko
//

#define CHUseSubstrate

#import "KayokoHelperHookInstaller.h"
#import "KayokoHelperRuntime.h"

#import <CaptainHook/CaptainHook.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

CHDeclareClass(UIKeyboardDockItem);
CHDeclareClass(UIKeyboardDockItemButton);
CHDeclareClass(UISystemKeyboardDockController);
CHDeclareClass(UIKeyboardImpl);
CHDeclareClass(UIKeyboardLayoutStar);

@interface UIKeyboardDockItem : NSObject
- (id)initWithImageName:(id)arg1 identifier:(id)arg2;
- (id)initWithTitle:(NSString *)title image:(UIImage *)image identifier:(NSString *)identifier;
- (UIImage *)imageWithRenderConfig:(id)arg1;
- (void)setImageName:(NSString *)arg1;
- (void)setTitle:(NSString *)title image:(UIImage *)image;
@end

@interface UIKeyboardDockItemButton : UIButton
@property (retain, nonatomic) NSString *identifier;
@end

@interface UISystemKeyboardDockController : NSObject
@end

@interface UIKeyboardImpl : UIView
@end

@interface UIKBTree : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, strong) NSMutableDictionary<NSString *, id> *properties;
@end

@interface UIKeyboardLayoutStar : UIView
@end

static const void *kKayokoScaledDockImageAssociatedKey = &kKayokoScaledDockImageAssociatedKey;

CHOptimizedMethod2(self, id, UIKeyboardDockItem, initWithImageName, id, arg1, identifier, id, arg2) {
    if ([arg1 isEqualToString:@"mic"]) {
        if (@available(iOS 16, *)) {
            arg1 = @"list.clipboard";
        } else {
            arg1 = @"doc.on.clipboard";
        }
    }
    return CHSuper2(UIKeyboardDockItem, initWithImageName, arg1, identifier, arg2);
}

CHOptimizedMethod1(self, void, UIKeyboardDockItem, setImageName, NSString *, arg1) {
    if ([arg1 isEqualToString:@"mic"]) {
        if (@available(iOS 16, *)) {
            arg1 = @"list.clipboard";
        } else {
            arg1 = @"doc.on.clipboard";
        }
    }
    CHSuper1(UIKeyboardDockItem, setImageName, arg1);
}

CHOptimizedMethod3(self, id, UIKeyboardDockItem, initWithTitle, NSString *, title, image, UIImage *, image, identifier, NSString *, identifier) {
    if ([title isEqualToString:@"mic"]) {
        image = [UIImage systemImageNamed:@"list.clipboard"];
    }
    return CHSuper3(UIKeyboardDockItem, initWithTitle, title, image, image, identifier, identifier);
}

CHOptimizedMethod2(self, void, UIKeyboardDockItem, setTitle, NSString *, title, image, UIImage *, image) {
    if ([title isEqualToString:@"mic"]) {
        image = [UIImage systemImageNamed:@"list.clipboard"];
    }
    CHSuper2(UIKeyboardDockItem, setTitle, title, image, image);
}

CHOptimizedMethod1(self, UIImage *, UIKeyboardDockItem, imageWithRenderConfig, id, arg1) {
    UIImage *image = CHSuper1(UIKeyboardDockItem, imageWithRenderConfig, arg1);
    if (!image) {
        return image;
    }

    CGSize originalSize = image.size;
    if (ABS(originalSize.width - originalSize.height) <= 1.0) {
        return image;
    }

    UIImage *cachedImage = objc_getAssociatedObject(image, kKayokoScaledDockImageAssociatedKey);
    if (cachedImage) {
        return cachedImage;
    }

    CGFloat scaleFactor = 0.88;
    if (@available(iOS 16, *)) {
        scaleFactor = 0.92;
    }
    CGSize scaledSize = CGSizeMake(originalSize.width * scaleFactor, originalSize.height * scaleFactor);
    if (scaledSize.width <= 0.0 || scaledSize.height <= 0.0) {
        return image;
    }

    UIEdgeInsets alignmentInsets = image.alignmentRectInsets;
    CGRect imageBounds = CGRectMake(0.0, 0.0, originalSize.width, originalSize.height);
    CGRect alignmentRect = UIEdgeInsetsInsetRect(imageBounds, alignmentInsets);
    if (CGRectIsEmpty(alignmentRect) || CGRectIsNull(alignmentRect)) {
        alignmentRect = imageBounds;
    }
    CGPoint anchor = CGPointMake(CGRectGetMidX(alignmentRect), CGRectGetMidY(alignmentRect));
    CGPoint centeredOrigin = CGPointMake(anchor.x - scaledSize.width / 2.0, anchor.y - scaledSize.height / 2.0);

    UIGraphicsBeginImageContextWithOptions(originalSize, NO, image.scale);
    [image drawInRect:CGRectMake(centeredOrigin.x, centeredOrigin.y, scaledSize.width, scaledSize.height)];
    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (!scaledImage) {
        return image;
    }

    UIImage *result = [scaledImage imageWithRenderingMode:image.renderingMode];
    result = [result imageWithAlignmentRectInsets:alignmentInsets];
    if (image.hasBaseline) {
        result = [result imageWithBaselineOffsetFromBottom:image.baselineOffsetFromBottom];
    }
    if (image.flipsForRightToLeftLayoutDirection) {
        result = [result imageFlippedForRightToLeftLayoutDirection];
    }

    objc_setAssociatedObject(image, kKayokoScaledDockImageAssociatedKey, result, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return result;
}

CHOptimizedMethod1(self, CGRect, UIKeyboardDockItemButton, imageRectForContentRect, CGRect, arg1) {
    CGRect origRect = CHSuper1(UIKeyboardDockItemButton, imageRectForContentRect, arg1);
    if (@available(iOS 17.0.1, *)) {
        if ([self.identifier isEqualToString:@"dictation"]) {
            CGFloat width = origRect.size.width * 1.5;
            CGFloat height = origRect.size.height * 1.5;
            origRect.origin.x -= (width - origRect.size.width) / 2.0;
            origRect.origin.y -= (height - origRect.size.height) / 2.0;
            origRect.size.width = width;
            origRect.size.height = height;
        }
    } else if (@available(iOS 16, *)) {
        if (ABS(origRect.size.width - origRect.size.height) > 1.0) {
            CGSize newSize = CGSizeMake(origRect.size.width * 0.92, origRect.size.height * 0.92);
            CGPoint newOrigin = CGPointMake(origRect.origin.x + (origRect.size.width - newSize.width) / 2,
                                            origRect.origin.y + (origRect.size.height - newSize.height) / 2);
            return CGRectMake(newOrigin.x, newOrigin.y, newSize.width, newSize.height);
        }
    } else {
        if (ABS(origRect.size.width - origRect.size.height) > 1.0) {
            CGSize newSize = CGSizeMake(origRect.size.width * 0.86, origRect.size.height * 0.86);
            CGPoint newOrigin = CGPointMake(origRect.origin.x + (origRect.size.width - newSize.width) / 2,
                                            origRect.origin.y + (origRect.size.height - newSize.height) / 2);
            return CGRectMake(newOrigin.x, newOrigin.y, newSize.width, newSize.height);
        }
    }
    return origRect;
}

CHOptimizedMethod3(self, void, UISystemKeyboardDockController, dictationItemButtonWasPressed, id, arg1, withEvent, id,
                   arg2, isRunningButton, BOOL, arg3) {
    [[KayokoHelperRuntime sharedRuntime] activateKayokoAfterCapturingCurrentFocus];
}

CHOptimizedMethod2(self, void, UISystemKeyboardDockController, dictationItemButtonWasPressed, id, arg1, withEvent,
                   UIEvent *, event) {
    [[KayokoHelperRuntime sharedRuntime] activateKayoko];
}

CHOptimizedMethod0(self, BOOL, UIKeyboardImpl, shouldShowDictationKey) { return YES; }

CHOptimizedMethod1(self, UIKBTree *, UIKeyboardLayoutStar, keyHitTest, CGPoint, point) {
    UIKBTree *orig = CHSuper1(UIKeyboardLayoutStar, keyHitTest, point);

    if ([[orig name] isEqualToString:@"Dictation-Key"]) {
        [[orig properties] setValue:@(0) forKey:@"KBinteractionType"];
        [[KayokoHelperRuntime sharedRuntime] activateKayoko];
    }

    return orig;
}

@implementation KayokoHelperHookInstaller (Dictation)

+ (void)installDictationHooks {
    static dispatch_once_t sOnceToken;
    dispatch_once(&sOnceToken, ^{
      Class dockItemClass = CHLoadClass_(&UIKeyboardDockItem$, NSClassFromString(@"UIKeyboardDockItem"));
      CHLoadClass_(&UIKeyboardDockItemButton$, NSClassFromString(@"UIKeyboardDockItemButton"));
      CHLoadClass_(&UISystemKeyboardDockController$, NSClassFromString(@"UISystemKeyboardDockController"));
      CHLoadClass_(&UIKeyboardImpl$, NSClassFromString(@"UIKeyboardImpl"));
      CHLoadClass_(&UIKeyboardLayoutStar$, NSClassFromString(@"UIKeyboardLayoutStar"));

      if (@available(iOS 17.0.1, *)) {
          CHHook3(UIKeyboardDockItem, initWithTitle, image, identifier);
          CHHook2(UIKeyboardDockItem, setTitle, image);
      } else {
          CHHook2(UIKeyboardDockItem, initWithImageName, identifier);
          CHHook1(UIKeyboardDockItem, setImageName);
      }
      if (class_getInstanceMethod(dockItemClass, @selector(imageWithRenderConfig:))) {
          CHHook1(UIKeyboardDockItem, imageWithRenderConfig);
      } else {
          CHHook1(UIKeyboardDockItemButton, imageRectForContentRect);
      }
      CHHook3(UISystemKeyboardDockController, dictationItemButtonWasPressed, withEvent, isRunningButton);
      CHHook2(UISystemKeyboardDockController, dictationItemButtonWasPressed, withEvent);
      CHHook0(UIKeyboardImpl, shouldShowDictationKey);
      CHHook1(UIKeyboardLayoutStar, keyHitTest);
    });
}

@end
