//
//  KayokoAdvancedOptionsListController.m
//  Kayoko
//

#import "KayokoAdvancedOptionsListController.h"
#import "KayokoNotificationKeys.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoPurchaseAuthorization.h"
#import "KayokoRespringControllerSupport.h"
#import "KayokoStatusOverlayView.h"
#import "KayokoTagStore.h"

#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "KayokoPaths.h"

static NSString *const kKayokoDataDirectoryPath = @"/var/mobile/Library/com.82flex.kayoko";
static NSString *const kKayokoCopyLogDataDirectoryPath = @"/var/mobile/Library/CopyLog";
static NSString *const kKayokoCopyVaultDataDirectoryPath = @"/var/mobile/Documents/CopyVault";

@interface NSTask : NSObject
- (void)setLaunchPath:(NSString *)launchPath;
- (void)setArguments:(NSArray<NSString *> *)arguments;
- (void)setStandardOutput:(id)standardOutput;
- (void)setStandardError:(id)standardError;
- (void)launch;
- (void)waitUntilExit;
- (int)terminationStatus;
@end

@interface KayokoAdvancedOptionsListController ()
- (NSString *)localizedExternalImportFailureDetail:(NSString *)detail;
@end

@implementation KayokoAdvancedOptionsListController {
    KayokoStatusOverlayView *_externalImportOverlayView;
    BOOL _externalImportInProgress;
    BOOL _externalImportOverlayHiddenForNavigation;
}

#pragma mark - Lifecycle

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    BOOL isLeavingNavigationStack =
        [self isMovingFromParentViewController] || [[self navigationController] isBeingDismissed];
    if (!isLeavingNavigationStack || _externalImportInProgress || !_externalImportOverlayView ||
        _externalImportOverlayView.alpha <= 0.0) {
        return;
    }

    // Keep the overlay attached so a cancelled interactive pop can fade it back in.
    _externalImportOverlayHiddenForNavigation = YES;
    [_externalImportOverlayView animateDisappearanceWithCompletion:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (!_externalImportOverlayHiddenForNavigation) {
        return;
    }
    _externalImportOverlayHiddenForNavigation = NO;
    if (!_externalImportInProgress && _externalImportOverlayView.superview) {
        [_externalImportOverlayView animateAppearance];
    }
}

#pragma mark - Specifiers

- (NSArray<PSSpecifier *> *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"AdvancedOptions" target:self];
    }

    return _specifiers;
}

#pragma mark - Preference Writing

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    if ([[specifier propertyForKey:@"key"] isEqualToString:kKayokoPreferenceKeyGestureRecognizerMode]) {
        [self promptToRespring];
    }
}

#pragma mark - Prompts

- (void)resetPrompt {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *resetAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Kayoko" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:@"Are you sure you want to reset your "
                                                               @"preferences?"
                                                         value:nil
                                                         table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Reset"
                                                                                        value:nil
                                                                                        table:@"AdvancedOptions"]
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(UIAlertAction *action) {
                                                          [self resetPreferences];
                                                        }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [resetAlert addAction:resetAction];
    [resetAlert addAction:cancelAction];

    [self presentViewController:resetAlert animated:YES completion:nil];
}

- (void)clearFavoritesPrompt {
    [self presentClearConfirmationWithMessageKey:
              @"Are you sure you want to clear all favorite items? This action cannot be undone."
                                  actionTitleKey:@"Clear Favorites"
                                notificationName:kKayokoNotificationKeyCoreClearFavorites];
}

- (void)clearHistoryPrompt {
    [self presentClearConfirmationWithMessageKey:
              @"Are you sure you want to clear all history items? This action cannot be undone."
                                  actionTitleKey:@"Clear History"
                                notificationName:kKayokoNotificationKeyCoreClearHistory];
}

- (void)deactivateAuthorizationPrompt {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *deactivateAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Kayoko" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:
                                             @"Are you sure you want to deactivate Kayoko on this device? "
                                             @"This removes Kayoko’s mirrored Havoc credentials and "
                                             @"local authorization state."
                                                         value:nil
                                                         table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *deactivateAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Deactivate"
                                                                                             value:nil
                                                                                             table:@"AdvancedOptions"]
                                                               style:UIAlertActionStyleDestructive
                                                             handler:^(UIAlertAction *action) {
                                                               (void)action;
                                                               [self deactivateAuthorization];
                                                             }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [deactivateAlert addAction:deactivateAction];
    [deactivateAlert addAction:cancelAction];

    [self presentViewController:deactivateAlert animated:YES completion:nil];
}

- (void)restoreTagsPrompt {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *restoreAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Kayoko" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:@"Are you sure you want to restore the default tags? "
                                                               @"Existing tags will be replaced. This action cannot be "
                                                               @"undone."
                                                         value:nil
                                                         table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *restoreAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Restore Tags"
                                                                                          value:nil
                                                                                          table:@"AdvancedOptions"]
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction *action) {
                                                            (void)action;
                                                            [self restoreTags];
                                                          }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [restoreAlert addAction:restoreAction];
    [restoreAlert addAction:cancelAction];

    [self presentViewController:restoreAlert animated:YES completion:nil];
}

- (void)resetThumbnailCachePrompt {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Kayoko" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:
                                             @"Are you sure you want to reset the thumbnail cache? Thumbnails will "
                                             @"be regenerated as needed."
                                                         value:nil
                                                         table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *resetAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Reset Thumbnail Cache"
                                                                                        value:nil
                                                                                        table:@"AdvancedOptions"]
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                                                          (void)action;
                                                          [self resetThumbnailCache];
                                                        }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:resetAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)importCopyLogPrompt {
    [self presentExternalImportPromptForSourceName:kKayokoExternalImportSourceCopyLog
                                 dataDirectoryPath:KayokoRootPath(kKayokoCopyLogDataDirectoryPath)
                                          titleKey:@"Import from CopyLog"
                                        messageKey:@"Kayoko will merge CopyLog snippets and favorite items with your "
                                                    "current data. Existing Kayoko items will be kept. SpringBoard "
                                                    "must restart when the import finishes."
                                   loadingTitleKey:@"Importing from CopyLog…"
                                           command:@"import-copylog"];
}

- (void)importCopyVaultPrompt {
    [self presentExternalImportPromptForSourceName:kKayokoExternalImportSourceCopyVault
                                 dataDirectoryPath:KayokoUserPath(kKayokoCopyVaultDataDirectoryPath)
                                          titleKey:@"Import from CopyVault"
                                        messageKey:@"Kayoko will merge CopyVault history and archived items with your "
                                                    "current data. Existing Kayoko items will be kept. SpringBoard "
                                                    "must restart when the import finishes."
                                   loadingTitleKey:@"Importing from CopyVault…"
                                           command:@"import-copyvault"];
}

- (void)presentExternalImportPromptForSourceName:(NSString *)sourceName
                               dataDirectoryPath:(NSString *)dataDirectoryPath
                                        titleKey:(NSString *)titleKey
                                      messageKey:(NSString *)messageKey
                                 loadingTitleKey:(NSString *)loadingTitleKey
                                         command:(NSString *)command {
    if (_externalImportInProgress) {
        return;
    }

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    BOOL directoryExists = [fileManager fileExistsAtPath:dataDirectoryPath isDirectory:&isDirectory];
    if (!directoryExists || !isDirectory || ![fileManager isReadableFileAtPath:dataDirectoryPath]) {
        NSString *unavailableFormat = [bundle localizedStringForKey:@"The %@ data directory could not be found or read."
                                                              value:nil
                                                              table:@"AdvancedOptions"];
        UIAlertController *unavailableAlert =
            [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"Data Unavailable"
                                                                                value:nil
                                                                                table:@"AdvancedOptions"]
                                                message:[NSString stringWithFormat:unavailableFormat, sourceName]
                                         preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *action = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK"
                                                                                       value:nil
                                                                                       table:@"AdvancedOptions"]
                                                         style:UIAlertActionStyleDefault
                                                       handler:nil];
        [unavailableAlert addAction:action];
        [self presentViewController:unavailableAlert animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:titleKey value:nil table:@"AdvancedOptions"]
                         message:[bundle localizedStringForKey:messageKey value:nil table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *importAction = [UIAlertAction
        actionWithTitle:[bundle localizedStringForKey:@"Import" value:nil table:@"AdvancedOptions"]
                  style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *action) {
                  (void)action;
                  [self importExternalDataSource:sourceName command:command loadingTitleKey:loadingTitleKey];
                }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    [alert addAction:importAction];
    [alert addAction:cancelAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)presentClearConfirmationWithMessageKey:(NSString *)messageKey
                                actionTitleKey:(NSString *)actionTitleKey
                              notificationName:(NSString *)notificationName {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *clearAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Kayoko" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:messageKey value:nil table:@"AdvancedOptions"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *clearAction =
        [UIAlertAction actionWithTitle:[bundle localizedStringForKey:actionTitleKey value:nil table:@"AdvancedOptions"]
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
                                 CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                                      (CFStringRef)notificationName, nil, nil, YES);
                               }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [clearAlert addAction:clearAction];
    [clearAlert addAction:cancelAction];

    [self presentViewController:clearAlert animated:YES completion:nil];
}

#pragma mark - Data Directory

- (void)checkDataDirectory {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyCoreCheckpointHistory, nil, nil, YES);

    NSURL *filzaURL = [self filzaURLForDataDirectoryPath:[self dataDirectoryPath]];
    if (!filzaURL) {
        [self presentDataDirectoryPathAlert];
        return;
    }

    [[UIApplication sharedApplication] openURL:filzaURL
                                       options:@{}
                             completionHandler:^(BOOL success) {
                               if (!success) {
                                   dispatch_async(dispatch_get_main_queue(), ^{
                                     [self presentDataDirectoryPathAlert];
                                   });
                               }
                             }];
}

- (NSString *)dataDirectoryPath {
    return KayokoRootPath(kKayokoDataDirectoryPath);
}

- (NSURL *)filzaURLForDataDirectoryPath:(NSString *)dataDirectoryPath {
    NSString *encodedPath = [dataDirectoryPath
        stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    NSString *pathComponent = encodedPath ?: dataDirectoryPath;
    NSString *URLString = [@"filza://view" stringByAppendingString:pathComponent];
    return [NSURL URLWithString:URLString];
}

- (void)presentDataDirectoryPathAlert {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *dataDirectoryPath = [self dataDirectoryPath];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"Unable to Open Filza"
                                                                            value:nil
                                                                            table:@"AdvancedOptions"]
                                            message:dataDirectoryPath
                                     preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"AdvancedOptions"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Copy Path"
                                                                                       value:nil
                                                                                       table:@"AdvancedOptions"]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
                                                         [UIPasteboard generalPasteboard].string = dataDirectoryPath;
                                                       }];

    [alert addAction:cancelAction];
    [alert addAction:copyAction];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Authorization

- (void)deactivateAuthorization {
    NSError *error = nil;
    if (![KayokoPurchaseAuthorization clearAuthorizationStateWithError:&error]) {
        [self presentDeactivateAuthorizationError:error];
        return;
    }

    [self.navigationController popToRootViewControllerAnimated:YES];
}

- (void)presentDeactivateAuthorizationError:(NSError *)error {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *message = [error localizedDescription]
                            ?: [bundle localizedStringForKey:@"Unable to Deactivate"
                                                       value:nil
                                                       table:@"AdvancedOptions"];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"Unable to Deactivate"
                                                                            value:nil
                                                                            table:@"AdvancedOptions"]
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK"
                                                                                   value:nil
                                                                                   table:@"AdvancedOptions"]
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil];
    [alert addAction:action];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Maintenance Actions

- (void)importExternalDataSource:(NSString *)sourceName
                         command:(NSString *)command
                 loadingTitleKey:(NSString *)loadingTitleKey {
    if (_externalImportInProgress) {
        return;
    }
    _externalImportInProgress = YES;
    self.navigationController.view.userInteractionEnabled = NO;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    KayokoStatusOverlayView *overlayView = [self externalImportOverlayView];
    overlayView.tapHandler = nil;
    [overlayView setLoadingTitle:[bundle localizedStringForKey:loadingTitleKey value:nil table:@"AdvancedOptions"]
                        subtitle:nil];
    [overlayView animateAppearance];

    NSString *updaterPath = [self kayokoUpdaterPath];
    if ([updaterPath length] == 0) {
        _externalImportInProgress = NO;
        [self showExternalImportFailureReason:[bundle localizedStringForKey:@"The import could not be completed."
                                                                      value:nil
                                                                      table:@"AdvancedOptions"]
                                       source:sourceName
                             requiresRespring:NO];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      @autoreleasepool {
          BOOL launched = NO;
          int terminationStatus = -1;
          __block NSData *standardOutputData = nil;
          __block NSData *standardErrorData = nil;
          NSString *exceptionReason = nil;
          @try {
              NSPipe *standardOutputPipe = [NSPipe pipe];
              NSPipe *standardErrorPipe = [NSPipe pipe];
              NSTask *task = [[NSTask alloc] init];
              [task setLaunchPath:updaterPath];
              [task setArguments:@[ command ]];
              [task setStandardOutput:standardOutputPipe];
              [task setStandardError:standardErrorPipe];
              [task launch];
              launched = YES;

              dispatch_group_t outputGroup = dispatch_group_create();
              dispatch_group_async(outputGroup, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                standardOutputData = [[standardOutputPipe fileHandleForReading] readDataToEndOfFile];
              });
              dispatch_group_async(outputGroup, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                standardErrorData = [[standardErrorPipe fileHandleForReading] readDataToEndOfFile];
              });
              [task waitUntilExit];
              terminationStatus = [task terminationStatus];
              dispatch_group_wait(outputGroup, DISPATCH_TIME_FOREVER);
          } @catch (NSException *exception) {
              exceptionReason = [exception reason];
          }

          dispatch_async(dispatch_get_main_queue(), ^{
            self->_externalImportInProgress = NO;
            if (launched && terminationStatus == 0) {
                [self
                    showExternalImportSuccessForSource:sourceName
                                      skippedItemCount:[self
                                                           skippedItemCountFromStandardOutputData:standardOutputData]];
                return;
            }

            NSString *standardError = nil;
            if ([standardErrorData length] > 0) {
                standardError = [[NSString alloc] initWithData:standardErrorData encoding:NSUTF8StringEncoding];
                standardError =
                    [standardError stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            NSBundle *mainBundle = [NSBundle bundleForClass:[self class]];
            NSString *reason = [standardError length] > 0 ? standardError
                               : [exceptionReason length] > 0
                                   ? exceptionReason
                                   : [mainBundle localizedStringForKey:@"The import could not be completed."
                                                                 value:nil
                                                                 table:@"AdvancedOptions"];
            [self showExternalImportFailureReason:[self localizedExternalImportFailureReason:reason]
                                           source:sourceName
                                 requiresRespring:launched];
          });
      }
    });
}

- (NSUInteger)skippedItemCountFromStandardOutputData:(NSData *)standardOutputData {
    if ([standardOutputData length] == 0) {
        return 0;
    }

    NSError *error = nil;
    id object = [NSJSONSerialization JSONObjectWithData:standardOutputData options:0 error:&error];
    NSNumber *skippedValue = [object isKindOfClass:[NSDictionary class]] ? object[@"skipped"] : nil;
    if (![skippedValue isKindOfClass:[NSNumber class]] || [skippedValue longLongValue] < 0) {
        NSLog(@"Kayoko: Unable to read external import summary: %@", error ?: object);
        return 0;
    }
    return [skippedValue unsignedIntegerValue];
}

- (KayokoStatusOverlayView *)externalImportOverlayView {
    if (!_externalImportOverlayView) {
        _externalImportOverlayView = [[KayokoStatusOverlayView alloc] initWithFrame:CGRectZero];
        _externalImportOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    }
    if (!_externalImportOverlayView.superview) {
        _externalImportOverlayView.alpha = 0.0;
        [self.view addSubview:_externalImportOverlayView];
        [NSLayoutConstraint activateConstraints:@[
            [_externalImportOverlayView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [_externalImportOverlayView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [_externalImportOverlayView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [_externalImportOverlayView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
    }
    return _externalImportOverlayView;
}

- (NSString *)localizedExternalImportFailureReason:(NSString *)reason {
    if ([reason length] == 0) {
        return reason;
    }

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *localizedReason = [bundle localizedStringForKey:reason value:reason table:@"Tweak"];
    if (![localizedReason isEqualToString:reason]) {
        return localizedReason;
    }

    NSArray<NSString *> *formatKeys = @[
        @"CopyLog data is invalid: %@", @"Unable to read CopyLog data: %@",
        @"CopyVault contains unsupported content: %@", @"CopyVault data is invalid: %@",
        @"Unable to read CopyVault data: %@"
    ];
    for (NSString *formatKey in formatKeys) {
        NSRange placeholderRange = [formatKey rangeOfString:@"%@"];
        NSString *prefix = [formatKey substringToIndex:placeholderRange.location];
        if (![reason hasPrefix:prefix]) {
            continue;
        }

        NSString *detail = [reason substringFromIndex:[prefix length]];
        NSString *localizedFormat = [bundle localizedStringForKey:formatKey value:formatKey table:@"Tweak"];
        return [NSString stringWithFormat:localizedFormat, [self localizedExternalImportFailureDetail:detail]];
    }
    return [self localizedExternalImportFailureDetail:reason];
}

- (NSString *)localizedExternalImportFailureDetail:(NSString *)detail {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *localizedDetail = [bundle localizedStringForKey:detail value:detail table:@"Tweak"];
    if (![localizedDetail isEqualToString:detail]) {
        return localizedDetail;
    }

    NSArray<NSString *> *formatKeys = @[
        @"%@ contains an invalid item", @"%@ contains an invalid payload", @"%@ has no contents", @"%@ has no items",
        @"%@ is not an array", @"%@ is not readable", @"conflicting image %@", @"conflicting rich text %@",
        @"image %@ already contains different data", @"invalid %@ timestamp", @"invalid item path %@",
        @"invalid timestamp %@", @"Imported file %@ already contains different data."
    ];
    for (NSString *formatKey in formatKeys) {
        NSRange placeholderRange = [formatKey rangeOfString:@"%@"];
        NSString *prefix = [formatKey substringToIndex:placeholderRange.location];
        NSString *suffix = [formatKey substringFromIndex:NSMaxRange(placeholderRange)];
        if (![detail hasPrefix:prefix] || ![detail hasSuffix:suffix] ||
            [detail length] < [prefix length] + [suffix length]) {
            continue;
        }

        NSRange valueRange = NSMakeRange([prefix length], [detail length] - [prefix length] - [suffix length]);
        NSString *value = [detail substringWithRange:valueRange];
        NSString *localizedFormat = [bundle localizedStringForKey:formatKey value:formatKey table:@"Tweak"];
        return [NSString stringWithFormat:localizedFormat, value];
    }
    return detail;
}

- (void)showExternalImportSuccessForSource:(NSString *)sourceName skippedItemCount:(NSUInteger)skippedItemCount {
    self.navigationController.view.userInteractionEnabled = YES;
    [[NSNotificationCenter defaultCenter]
        postNotificationName:kKayokoNotificationKeyExternalImportRequiresRestart
                      object:nil
                    userInfo:@{
                        kKayokoNotificationUserInfoKeyExternalImportSucceeded : @YES,
                        kKayokoNotificationUserInfoKeyExternalImportSource : sourceName
                    }];
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *restartMessage = [bundle localizedStringForKey:@"Tap the screen to restart SpringBoard and finish "
                                                              "importing."
                                                       value:nil
                                                       table:@"AdvancedOptions"];
    NSString *subtitle = restartMessage;
    if (skippedItemCount > 0) {
        NSString *summaryKey = skippedItemCount == 1 ? @"%lu unsupported item was not imported."
                                                     : @"%lu unsupported items were not imported.";
        NSString *summaryFormat = [bundle localizedStringForKey:summaryKey value:nil table:@"AdvancedOptions"];
        NSString *summary = [NSString stringWithFormat:summaryFormat, (unsigned long)skippedItemCount];
        subtitle = [NSString stringWithFormat:@"%@\n\n%@", summary, restartMessage];
    }
    KayokoStatusOverlayView *overlayView = [self externalImportOverlayView];
    [overlayView setSuccessTitle:[bundle localizedStringForKey:@"Import Complete" value:nil table:@"AdvancedOptions"]
                        subtitle:subtitle
                   actionEnabled:YES];
    __weak typeof(self) weakSelf = self;
    overlayView.tapHandler = ^{
      [weakSelf dismissExternalImportOverlayWithCompletion:^{
        [weakSelf respring];
      }];
    };
}

- (void)showExternalImportFailureReason:(NSString *)reason
                                 source:(NSString *)sourceName
                       requiresRespring:(BOOL)requiresRespring {
    self.navigationController.view.userInteractionEnabled = YES;
    if (requiresRespring) {
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kKayokoNotificationKeyExternalImportRequiresRestart
                          object:nil
                        userInfo:@{
                            kKayokoNotificationUserInfoKeyExternalImportSucceeded : @NO,
                            kKayokoNotificationUserInfoKeyExternalImportSource : sourceName
                        }];
    }
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *actionMessage =
        [bundle localizedStringForKey:(requiresRespring ? @"Tap the screen to restart SpringBoard and restore Kayoko."
                                                        : @"Tap the screen to close.")
                                value:nil
                                table:@"AdvancedOptions"];
    NSString *subtitle = [NSString stringWithFormat:@"%@\n\n%@", reason, actionMessage];
    KayokoStatusOverlayView *overlayView = [self externalImportOverlayView];
    [overlayView setFailureTitle:[bundle localizedStringForKey:@"Unable to Import" value:nil table:@"AdvancedOptions"]
                        subtitle:subtitle
                   actionEnabled:YES];
    __weak typeof(self) weakSelf = self;
    overlayView.tapHandler = ^{
      if (requiresRespring) {
          [weakSelf dismissExternalImportOverlayWithCompletion:^{
            [weakSelf respring];
          }];
      } else {
          [weakSelf dismissExternalImportOverlay];
      }
    };
}

- (void)dismissExternalImportOverlay {
    [self dismissExternalImportOverlayWithCompletion:nil];
}

- (void)dismissExternalImportOverlayWithCompletion:(void (^)(void))completion {
    KayokoStatusOverlayView *overlayView = _externalImportOverlayView;
    if (!overlayView) {
        if (completion) {
            completion();
        }
        return;
    }
    [overlayView animateDisappearanceWithCompletion:^{
      [overlayView removeFromSuperview];
      if (self->_externalImportOverlayView == overlayView) {
          self->_externalImportOverlayView = nil;
      }
      if (completion) {
          completion();
      }
    }];
}

- (void)resetThumbnailCache {
    NSString *updaterPath = [self kayokoUpdaterPath];
    if ([updaterPath length] == 0) {
        NSLog(@"Kayoko: Unable to reset thumbnail cache because kayoko_updater is unavailable");
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      @try {
          NSTask *task = [[NSTask alloc] init];
          [task setLaunchPath:updaterPath];
          [task setArguments:@[ @"reset-thumbnail-cache" ]];
          [task setStandardOutput:[NSPipe pipe]];
          [task setStandardError:[NSPipe pipe]];
          [task launch];
          [task waitUntilExit];
      } @catch (NSException *exception) {
          NSLog(@"Kayoko: Unable to launch thumbnail cache reset: %@", exception);
      }
    });
}

- (NSString *)kayokoUpdaterPath {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray<NSString *> *candidatePaths = @[
        KayokoRootPath(@"/usr/local/libexec/kayoko_updater"), @"/var/jb/usr/local/libexec/kayoko_updater",
        @"/usr/local/libexec/kayoko_updater"
    ];
    for (NSString *path in candidatePaths) {
        if ([fileManager isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (void)resetPreferences {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    for (NSString *key in [userDefaults dictionaryRepresentation]) {
        [userDefaults removeObjectForKey:key];
    }

    [self reloadSpecifiers];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyPreferencesReload, nil, nil, YES);
}

- (void)restoreTags {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    KayokoTagStore *tagStore = [[KayokoTagStore alloc] initWithTagsPath:[KayokoTagStore defaultTagsPath]
                                                     localizationBundle:bundle];

    NSError *error = nil;
    if (![tagStore restoreDefaultTagsWithError:&error]) {
        [self presentRestoreTagsError:error];
    }
}

- (void)presentRestoreTagsError:(NSError *)error {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *message = [error localizedDescription]
                            ?: [bundle localizedStringForKey:@"Unable to Restore Tags"
                                                       value:nil
                                                       table:@"AdvancedOptions"];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:[bundle localizedStringForKey:@"Unable to Restore Tags"
                                                                            value:nil
                                                                            table:@"AdvancedOptions"]
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *action = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"OK"
                                                                                   value:nil
                                                                                   table:@"AdvancedOptions"]
                                                     style:UIAlertActionStyleDefault
                                                   handler:nil];
    [alert addAction:action];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSString *key = [specifier propertyForKey:@"cell"];
    if ([key isEqualToString:@"PSButtonCell"]) {
        UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
        NSNumber *isDestructiveValue = [specifier propertyForKey:@"isDestructive"];
        BOOL isDestructive = [isDestructiveValue boolValue];
        cell.textLabel.textColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
        cell.textLabel.highlightedTextColor = isDestructive ? [UIColor systemRedColor] : [UIColor systemBlueColor];
        return cell;
    }

    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

@end
