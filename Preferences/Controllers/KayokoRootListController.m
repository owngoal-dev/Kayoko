//
//  KayokoRootListController.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoRootListController.h"
#import "KayokoNotificationKeys.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoPurchaseAuthorization.h"
#import "KayokoRespringControllerSupport.h"
#import "KayokoStatusOverlayView.h"

#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import "KayokoPaths.h"

@interface NSConcreteNotification : NSNotification
@end

@interface PSListController (Private)
- (void)_returnKeyPressed:(NSConcreteNotification *)notification;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@end

@interface NSTask : NSObject
- (void)setLaunchPath:(NSString *)launchPath;
- (void)setArguments:(NSArray<NSString *> *)arguments;
- (void)setStandardOutput:(id)standardOutput;
- (void)setStandardError:(id)standardError;
- (void)launch;
- (void)waitUntilExit;
@end

NS_ASSUME_NONNULL_BEGIN

@interface KayokoRootListController () <UISearchResultsUpdating>
- (void)presentExternalImportRestartReminderIfNeeded;
@end

NS_ASSUME_NONNULL_END

static NSString *const kKayokoSileoStoreBundleIdentifier = @"org.coolstar.SileoStore";
static NSString *const kKayokoSileoBundleIdentifier = @"org.coolstar.Sileo";
static NSString *const kKayokoZebraBundleIdentifier = @"com.getzbra.zebra2";
static NSString *const kKayokoLegacyZebraBundleIdentifier = @"xyz.willy.Zebra";

@implementation KayokoRootListController {
    ActivationMethod _lastActivationMethod;
    BOOL _hasActivationMethodSnapshot;
    UISearchController *_testInputSearchController;
    KayokoStatusOverlayView *_authorizationOverlayView;
    BOOL _authorizationCheckInProgress;
    NSUInteger _authorizationCheckGeneration;
    BOOL _externalImportRestartReminderPending;
    BOOL _externalImportRestartReminderSucceeded;
    NSString *_externalImportRestartReminderSource;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];

    [self configureTestInputSearchController];

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *title = [bundle localizedStringForKey:@"Respring" value:nil table:@"Root"];
    UIBarButtonItem *respringButton = [[UIBarButtonItem alloc] initWithTitle:title
                                                                       style:UIBarButtonItemStyleDone
                                                                      target:self
                                                                      action:@selector(respringPrompt)];

    [[self navigationItem] setLargeTitleDisplayMode:UINavigationItemLargeTitleDisplayModeNever];
    [[self navigationItem] setRightBarButtonItem:respringButton];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(externalImportRequiresRestart:)
                                                 name:kKayokoNotificationKeyExternalImportRequiresRestart
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Test Input Search

- (void)configureTestInputSearchController {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    _testInputSearchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _testInputSearchController.searchResultsUpdater = self;
    _testInputSearchController.obscuresBackgroundDuringPresentation = NO;
    _testInputSearchController.hidesNavigationBarDuringPresentation = NO;
    _testInputSearchController.searchBar.placeholder = [bundle localizedStringForKey:@"Wishing on a star…"
                                                                               value:nil
                                                                               table:@"Root"];

    self.definesPresentationContext = YES;
    self.navigationItem.searchController = _testInputSearchController;
    self.navigationItem.hidesSearchBarWhenScrolling = YES;
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    (void)searchController;
}

#pragma mark - Specifiers

- (NSArray<PSSpecifier *> *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        [self configureConditionalFootersInSpecifiers:_specifiers];
        [self configureTagManagementSpecifierInSpecifiers:_specifiers];
    }

    return _specifiers;
}

- (void)configureTagManagementSpecifierInSpecifiers:(NSArray<PSSpecifier *> *)specifiers {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *localizedTitle = [bundle localizedStringForKey:@"Custom Tags…" value:nil table:@"Tags"];
    for (PSSpecifier *specifier in specifiers) {
        NSString *detail = [specifier propertyForKey:@"detail"];
        if (![detail isEqualToString:@"KayokoTagManagementViewController"]) {
            continue;
        }

        [specifier setProperty:localizedTitle forKey:@"label"];
        break;
    }
}

- (void)configureConditionalFootersInSpecifiers:(NSArray<PSSpecifier *> *)specifiers {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    for (PSSpecifier *specifier in specifiers) {
        NSString *preferenceKey = [specifier propertyForKey:@"hideFooterTextAfterPreferenceKey"];
        NSString *condensedFooterText = [specifier propertyForKey:@"condensedFooterText"];
        if (![preferenceKey isKindOfClass:[NSString class]] || [preferenceKey length] == 0 ||
            ![condensedFooterText isKindOfClass:[NSString class]] || [condensedFooterText length] == 0) {
            continue;
        }

        NSString *defaultsIdentifier = [specifier propertyForKey:@"hideFooterTextAfterPreferenceDefaults"];
        NSUserDefaults *userDefaults = [defaultsIdentifier length] > 0
                                           ? [[NSUserDefaults alloc] initWithSuiteName:defaultsIdentifier]
                                           : [NSUserDefaults standardUserDefaults];
        if ([userDefaults boolForKey:preferenceKey]) {
            NSString *localizedFooterText = [bundle localizedStringForKey:condensedFooterText value:nil table:@"Root"];
            [specifier setProperty:localizedFooterText forKey:@"footerText"];
        }
    }
}

#pragma mark - Preference State

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    id<UIViewControllerTransitionCoordinator> transitionCoordinator = [self transitionCoordinator];
    if (![transitionCoordinator isInteractive]) {
        [[self navigationController] setToolbarHidden:YES animated:animated];
    }
    [self beginAuthorizationCheckIfNeededRestartingExistingOverlay:NO];

    ActivationMethod currentActivationMethod = [self currentActivationMethod];
    if (!_hasActivationMethodSnapshot) {
        _lastActivationMethod = currentActivationMethod;
        _hasActivationMethodSnapshot = YES;
        return;
    }

    if (currentActivationMethod != _lastActivationMethod) {
        _lastActivationMethod = currentActivationMethod;
        [self promptToRespring];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[self navigationController] setToolbarHidden:YES animated:animated];
    [self presentExternalImportRestartReminderIfNeeded];
}

- (void)externalImportRequiresRestart:(NSNotification *)notification {
    _externalImportRestartReminderPending = YES;
    _externalImportRestartReminderSucceeded =
        [notification.userInfo[kKayokoNotificationUserInfoKeyExternalImportSucceeded] boolValue];
    NSString *source = notification.userInfo[kKayokoNotificationUserInfoKeyExternalImportSource];
    _externalImportRestartReminderSource = [source isKindOfClass:[NSString class]] ? [source copy] : nil;
}

- (void)presentExternalImportRestartReminderIfNeeded {
    if (!_externalImportRestartReminderPending || self.presentedViewController) {
        return;
    }
    _externalImportRestartReminderPending = NO;

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *message = nil;
    if (_externalImportRestartReminderSucceeded && [_externalImportRestartReminderSource length] > 0) {
        NSString *format = [bundle localizedStringForKey:@"%@ data was imported successfully. Restart SpringBoard "
                                                          "now to finish the import and continue using Kayoko."
                                                   value:nil
                                                   table:@"Root"];
        message = [NSString stringWithFormat:format, _externalImportRestartReminderSource];
    } else if (_externalImportRestartReminderSucceeded) {
        message = [bundle localizedStringForKey:@"The data was imported successfully. Restart SpringBoard now to "
                                                 "finish the import and continue using Kayoko."
                                          value:nil
                                          table:@"Root"];
    } else {
        message = [bundle localizedStringForKey:@"Kayoko entered maintenance mode before the import failed. Restart "
                                                 "SpringBoard now to continue using Kayoko."
                                          value:nil
                                          table:@"Root"];
    }
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Restart Required" value:nil table:@"Root"]
                         message:message
                  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *restartAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Respring Now"
                                                                                          value:nil
                                                                                          table:@"Root"]
                                                            style:UIAlertActionStyleDestructive
                                                          handler:^(UIAlertAction *action) {
                                                            (void)action;
                                                            [self respring];
                                                          }];
    [alert addAction:restartAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (ActivationMethod)currentActivationMethod {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];
    ActivationMethod activationMethod = [userDefaults integerForKey:kKayokoPreferenceKeyActivationMethod];
    return activationMethod == 0 ? kKayokoPreferenceKeyActivationMethodDefaultValue : activationMethod;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];

    // Prompt to respring for options that require one to apply changes.
    if ([[specifier propertyForKey:@"key"] isEqualToString:kKayokoPreferenceKeyEnabled] ||
        [[specifier propertyForKey:@"key"] isEqualToString:kKayokoPreferenceKeyActivationMethod] ||
        [[specifier propertyForKey:@"key"] isEqualToString:kKayokoPreferenceKeyAutomaticallyPaste]) {
        if ([[specifier propertyForKey:@"key"] isEqualToString:kKayokoPreferenceKeyActivationMethod]) {
            _lastActivationMethod = [self currentActivationMethod];
            _hasActivationMethodSnapshot = YES;
        }
        [self promptToRespring];
    }
}

#pragma mark - Actions

- (void)_returnKeyPressed:(NSConcreteNotification *)notification {
    [[self view] endEditing:YES];
    [super _returnKeyPressed:notification];
}

- (void)respringPrompt {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];

    UIAlertController *respringAlert = [UIAlertController
        alertControllerWithTitle:[bundle localizedStringForKey:@"Kayoko" value:nil table:@"Root"]
                         message:[bundle localizedStringForKey:@"Respringing will restart SpringBoard and close all "
                                                               @"apps. Unsaved work may be lost."
                                                         value:nil
                                                         table:@"Root"]
                  preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *respringAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Respring Now"
                                                                                           value:nil
                                                                                           table:@"Root"]
                                                             style:UIAlertActionStyleDestructive
                                                           handler:^(UIAlertAction *action) {
                                                             [self respring];
                                                           }];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[bundle localizedStringForKey:@"Cancel"
                                                                                         value:nil
                                                                                         table:@"Root"]
                                                           style:UIAlertActionStyleCancel
                                                         handler:nil];

    [respringAlert addAction:respringAction];
    [respringAlert addAction:cancelAction];

    [self presentViewController:respringAlert animated:YES completion:nil];
}

- (void)showKayoko {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyCoreShow, nil, nil, YES);
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    (void)notification;
    if ([self isViewLoaded] && self.view.window) {
        [self beginAuthorizationCheckIfNeededRestartingExistingOverlay:YES];
    }
}

#pragma mark - Authorization Overlay

- (void)beginAuthorizationCheckIfNeededRestartingExistingOverlay:(BOOL)restartExistingOverlay {
    if (_authorizationCheckInProgress) {
        return;
    }

    NSError *flagError = nil;
    if ([KayokoPurchaseAuthorization hasAuthorizationPassFlagWithError:&flagError]) {
        [self dismissAuthorizationOverlayAnimated:NO];
        return;
    }

    if (_authorizationOverlayView && !restartExistingOverlay) {
        return;
    }

    _authorizationCheckInProgress = YES;
    NSUInteger generation = ++_authorizationCheckGeneration;
    [self showAuthorizationOverlayChecking];

    NSString *updaterPath = [self kayokoUpdaterPath];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      [self runCredentialSyncTaskAtPath:updaterPath];
      [self checkMirroredPurchaseForGeneration:generation];
    });
}

- (void)showAuthorizationOverlayChecking {
    KayokoStatusOverlayView *overlayView = [self authorizationOverlayView];
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    [overlayView setLoadingTitle:[bundle localizedStringForKey:@"Check Product Authorization" value:nil table:@"Root"]
                        subtitle:nil];
    [overlayView animateAppearance];
}

- (KayokoStatusOverlayView *)authorizationOverlayView {
    if (!_authorizationOverlayView) {
        _authorizationOverlayView = [[KayokoStatusOverlayView alloc] initWithFrame:CGRectZero];
        _authorizationOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
        __weak typeof(self) weakSelf = self;
        _authorizationOverlayView.tapHandler = ^{
          [weakSelf retryAuthorizationCheck];
        };
    }

    if (!_authorizationOverlayView.superview) {
        _authorizationOverlayView.alpha = 0.0;
        [self.view addSubview:_authorizationOverlayView];
        [NSLayoutConstraint activateConstraints:@[
            [_authorizationOverlayView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
            [_authorizationOverlayView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [_authorizationOverlayView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [_authorizationOverlayView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
        ]];
    }
    return _authorizationOverlayView;
}

- (void)retryAuthorizationCheck {
    [self beginAuthorizationCheckIfNeededRestartingExistingOverlay:YES];
}

- (void)checkMirroredPurchaseForGeneration:(NSUInteger)generation {
    [KayokoPurchaseAuthorization checkMirroredPurchaseWithCompletion:^(KayokoPurchaseAuthorizationResult *result) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self->_authorizationCheckGeneration) {
            return;
        }
        [self handleAuthorizationResult:result];
      });
    }];
}

- (void)handleAuthorizationResult:(KayokoPurchaseAuthorizationResult *)result {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    _authorizationCheckInProgress = NO;
    BOOL useZebraInstructions = [self shouldUseZebraAuthorizationInstructions];

    switch (result.state) {
    case KayokoPurchaseAuthorizationStatePurchased: {
        NSError *error = nil;
        [KayokoPurchaseAuthorization setAuthorizationPassFlagWithError:&error];
        [self dismissAuthorizationOverlayAnimated:YES];
        break;
    }
    case KayokoPurchaseAuthorizationStateMissingCredential: {
        NSString *subtitleKey = useZebraInstructions
                                    ? @"Please check the following: open Zebra → select the Sources tab → tap Havoc → "
                                      @"make sure it is signed in"
                                    : @"Please check the following: open Sileo → tap the avatar in the top-right "
                                      @"corner → make sure the Havoc payment provider is signed in";
        [[self authorizationOverlayView]
            setFailureTitle:[bundle localizedStringForKey:@"Read Account Failed" value:nil table:@"Root"]
                   subtitle:[bundle localizedStringForKey:subtitleKey value:nil table:@"Root"]
              actionEnabled:NO];
        break;
    }
    case KayokoPurchaseAuthorizationStateNetworkFailed: {
        NSString *subtitle = [result.error localizedDescription]
                                 ?: [bundle localizedStringForKey:@"The network request failed."
                                                            value:nil
                                                            table:@"Root"];
        [[self authorizationOverlayView] setFailureTitle:[bundle localizedStringForKey:@"Network Request Failed"
                                                                                 value:nil
                                                                                 table:@"Root"]
                                                subtitle:subtitle
                                           actionEnabled:YES];
        break;
    }
    case KayokoPurchaseAuthorizationStateInvalidResponse: {
        NSString *statusMessage =
            result.statusMessage ?: [bundle localizedStringForKey:@"Invalid Response" value:nil table:@"Root"];
        NSString *format = [bundle localizedStringForKey:@"Server returned an invalid response. Tap the screen to "
                                                         @"retry: %@"
                                                   value:nil
                                                   table:@"Root"];
        [[self authorizationOverlayView] setFailureTitle:[bundle localizedStringForKey:@"Network Request Failed"
                                                                                 value:nil
                                                                                 table:@"Root"]
                                                subtitle:[NSString stringWithFormat:format, statusMessage]
                                           actionEnabled:YES];
        break;
    }
    case KayokoPurchaseAuthorizationStateNotPurchased: {
        NSString *subtitleKey = useZebraInstructions
                                    ? @"Please check the following: open Zebra → select the Sources tab → tap Havoc → "
                                      @"tap My Account in the top-right corner → make sure Kayoko is in your purchases"
                                    : @"Please check the following: open Sileo → tap the avatar in the top-right "
                                      @"corner → tap Havoc → make sure Kayoko is in your purchases";
        [[self authorizationOverlayView]
            setFailureTitle:[bundle localizedStringForKey:@"Authorization Not Found" value:nil table:@"Root"]
                   subtitle:[bundle localizedStringForKey:subtitleKey value:nil table:@"Root"]
              actionEnabled:NO];
        break;
    }
    }
}

- (BOOL)shouldUseZebraAuthorizationInstructions {
    BOOL hasSileo = [self isApplicationInstalledWithBundleIdentifiers:@[
        kKayokoSileoStoreBundleIdentifier, kKayokoSileoBundleIdentifier
    ]];
    if (hasSileo) {
        return NO;
    }

    return [self isApplicationInstalledWithBundleIdentifiers:@[
        kKayokoZebraBundleIdentifier, kKayokoLegacyZebraBundleIdentifier
    ]];
}

- (BOOL)isApplicationInstalledWithBundleIdentifiers:(NSArray<NSString *> *)bundleIdentifiers {
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    if (![proxyClass respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        return NO;
    }
    typedef LSApplicationProxy *(*KayokoApplicationProxyForIdentifierIMP)(Class, SEL, NSString *);
    KayokoApplicationProxyForIdentifierIMP proxyForIdentifier = (KayokoApplicationProxyForIdentifierIMP)
        [proxyClass methodForSelector:@selector(applicationProxyForIdentifier:)];
    if (!proxyForIdentifier) {
        return NO;
    }

    for (NSString *bundleIdentifier in bundleIdentifiers) {
        if ([bundleIdentifier length] == 0) {
            continue;
        }

        LSApplicationProxy *proxy =
            proxyForIdentifier(proxyClass, @selector(applicationProxyForIdentifier:), bundleIdentifier);
        if (proxy) {
            return YES;
        }
    }
    return NO;
}

- (void)dismissAuthorizationOverlayAnimated:(BOOL)animated {
    KayokoStatusOverlayView *overlayView = _authorizationOverlayView;
    if (!overlayView) {
        return;
    }

    void (^completion)(void) = ^{
      [overlayView removeFromSuperview];
      if (self->_authorizationOverlayView == overlayView) {
          self->_authorizationOverlayView = nil;
      }
    };

    if (animated) {
        [overlayView animateDisappearanceWithCompletion:completion];
    } else {
        completion();
    }
}

#pragma mark - Credential Sync

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

- (void)runCredentialSyncTaskAtPath:(NSString *)updaterPath {
    if ([updaterPath length] == 0) {
        return;
    }

    @try {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:updaterPath];
        [task setArguments:@[ @"sync-credential" ]];
        [task setStandardOutput:[NSPipe pipe]];
        [task setStandardError:[NSPipe pipe]];
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        (void)exception;
    }
}

#pragma mark - Cell Helpers

- (UISlider *_Nullable)findSliderInView:(UIView *)view {
    if ([view isKindOfClass:[UISlider class]]) {
        return (UISlider *)view;
    }
    for (UIView *subview in view.subviews) {
        UISlider *slider = [self findSliderInView:subview];
        if (slider) {
            return slider;
        }
    }
    return nil;
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
    if ([key isEqualToString:@"PSSliderCell"]) {
        UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
        NSNumber *isContinuousValue = [specifier propertyForKey:@"isContinuous"];
        BOOL isContinuous = [isContinuousValue boolValue];
        UISlider *slider = [self findSliderInView:cell];
        if (slider) {
            slider.continuous = isContinuous;
        }
        return cell;
    }
    if ([key isEqualToString:@"PSLinkListCell"]) {
        NSString *detail = [specifier propertyForKey:@"detail"];
        if ([detail isEqualToString:@"KayokoListItemsController"]) {
            UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
            NSBundle *bundle = [NSBundle bundleForClass:[self class]];

            // Get the current activation methods
            ActivationMethod currentOptions = [self currentActivationMethod];

            // Get valid values and titles
            NSArray<NSNumber *> *validValues = [specifier propertyForKey:@"validValues"];
            NSArray<NSString *> *validTitles = [specifier propertyForKey:@"validTitles"];

            // Find selected options
            NSMutableArray<NSString *> *selectedTitles = [NSMutableArray array];
            for (NSUInteger i = 0; i < validValues.count; i++) {
                NSNumber *value = validValues[i];
                if (currentOptions & [value integerValue]) {
                    [selectedTitles addObject:[bundle localizedStringForKey:validTitles[i] value:nil table:@"Root"]];
                }
            }

            // Format the detail text based on the number of selected options
            NSString *detailText;
            if (selectedTitles.count == 1) {
                // Only one option - display its name
                detailText = selectedTitles[0];
            } else if (selectedTitles.count == 2) {
                // Two options - display "Option A and Option B"
                NSString *format = [bundle localizedStringForKey:@"%@ and %@" value:nil table:@"Root"];
                detailText = [NSString stringWithFormat:format, selectedTitles[0], selectedTitles[1]];
            } else if (selectedTitles.count > 2) {
                // Three or more options - display "Option A and X others"
                NSString *format = [bundle localizedStringForKey:@"%@ and %d others" value:nil table:@"Root"];
                detailText = [NSString stringWithFormat:format, selectedTitles[0], (int)selectedTitles.count - 1];
            } else {
                // No options (shouldn't happen)
                detailText = @"";
            }

            cell.detailTextLabel.text = detailText;
            return cell;
        }
    }
    if ([key isEqualToString:@"PSLinkCell"]) {
        NSString *detail = [specifier propertyForKey:@"detail"];
        if ([detail isEqualToString:@"KayokoTagManagementViewController"]) {
            UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
            NSBundle *bundle = [NSBundle bundleForClass:[self class]];
            cell.textLabel.text = [bundle localizedStringForKey:@"Custom Tags…" value:nil table:@"Tags"];
            return cell;
        }
    }
    return [super tableView:tableView cellForRowAtIndexPath:indexPath];
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return 20.0; // Height for the first section header
    }
    return [super tableView:tableView heightForHeaderInSection:section];
}

@end
