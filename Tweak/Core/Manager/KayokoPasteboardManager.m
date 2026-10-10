//
//  KayokoPasteboardManager.m
//  Kayoko
//
//  Created by Alexandra Aurora Göttlicher
//

#import "KayokoPasteboardManager.h"
#import "KayokoHistoryChangeNotifier.h"
#import "KayokoHistoryRepository.h"
#import "KayokoKeyboardHostResolver.h"
#import "KayokoKeyboardShortcutSender.h"
#import "KayokoNotificationKeys.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPreferenceKeys.h"
#import "KayokoRichTextRepresentation.h"
#import "KayokoSearchCriteria.h"
#import "KayokoThumbnailCache.h"

#import <HBLog.h>
#import <ImageIO/ImageIO.h>
#import <math.h>
#import "KayokoPaths.h"

static NSTimeInterval const kKayokoPasteboardWriteConfirmationTimeout = 0.25;
static NSTimeInterval const kKayokoSimulatedAutomaticPasteDelay = 0.2;
static NSString *const kKayokoRemoteClipboardPasteboardType = @"com.apple.is-remote-clipboard";
static NSString *const kKayokoPasteboardManagerErrorDomain = @"com.82flex.kayoko.pasteboard-manager";

@interface SBApplication : NSObject
@property(nonatomic, copy, readonly) NSString *bundleIdentifier;
@end

@interface UIApplication (Private)
- (SBApplication *_Nullable)_accessibilityFrontMostApplication;
@end

NS_ASSUME_NONNULL_BEGIN

@interface KayokoPasteboardPendingWrite : NSObject

#pragma mark - State

@property(nonatomic, assign, readonly, getter=isActive) BOOL active;
@property(nonatomic, assign, readonly) BOOL shouldAutoPaste;
@property(nonatomic, assign, readonly) KayokoAutomaticPasteMode automaticPasteMode;
@property(nonatomic, assign, readonly) NSUInteger token;
@property(nonatomic, assign, readonly) NSUInteger previousChangeCount;

#pragma mark - Expiration

@property(nonatomic, copy, nullable) dispatch_block_t expirationBlock;

#pragma mark - Lifecycle

- (NSUInteger)beginAfterChangeCount:(NSUInteger)previousChangeCount
                    shouldAutoPaste:(BOOL)shouldAutoPaste
                 automaticPasteMode:(KayokoAutomaticPasteMode)automaticPasteMode;

#pragma mark - Expiration

- (void)scheduleExpirationOnQueue:(dispatch_queue_t)queue
                       afterDelay:(NSTimeInterval)delay
                          handler:(dispatch_block_t)handler;

#pragma mark - Matching

- (BOOL)matchesToken:(NSUInteger)token;
- (BOOL)hasAdvancedToChangeCount:(NSUInteger)changeCount;

#pragma mark - Cancellation

- (void)cancelExpirationBlock;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoPasteboardPendingWrite

- (NSUInteger)beginAfterChangeCount:(NSUInteger)previousChangeCount
                    shouldAutoPaste:(BOOL)shouldAutoPaste
                 automaticPasteMode:(KayokoAutomaticPasteMode)automaticPasteMode {
    [self cancelExpirationBlock];
    _token++;
    _active = YES;
    _shouldAutoPaste = shouldAutoPaste;
    _automaticPasteMode = automaticPasteMode;
    _previousChangeCount = previousChangeCount;
    return _token;
}

- (void)scheduleExpirationOnQueue:(dispatch_queue_t)queue
                       afterDelay:(NSTimeInterval)delay
                          handler:(dispatch_block_t)handler {
    [self cancelExpirationBlock];
    dispatch_block_t expirationBlock = dispatch_block_create(0, handler);
    self.expirationBlock = expirationBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), queue, expirationBlock);
}

- (BOOL)matchesToken:(NSUInteger)token {
    return _active && token == _token;
}

- (BOOL)hasAdvancedToChangeCount:(NSUInteger)changeCount {
    return _active && changeCount != _previousChangeCount;
}

- (void)cancel {
    [self cancelExpirationBlock];
    _token++;
    _active = NO;
    _shouldAutoPaste = NO;
    _automaticPasteMode = kKayokoAutomaticPasteModeClassic;
    _previousChangeCount = 0;
}

- (void)cancelExpirationBlock {
    dispatch_block_t expirationBlock = self.expirationBlock;
    if (expirationBlock) {
        dispatch_block_cancel(expirationBlock);
        self.expirationBlock = nil;
    }
}

@end

@implementation KayokoPasteboardManager {
    UIPasteboard *_pasteboard;
    NSUInteger _lastChangeCount;
    NSFileManager *_fileManager;

    dispatch_queue_t _pasteboardQueue;
    KayokoThumbnailCache *_thumbnailCache;

    BOOL _isWritingPasteboardItem;
    KayokoPasteboardPendingWrite *_pendingPasteboardWrite;

    KayokoHistoryRepository *_historyRepository;
    KayokoHistoryChangeNotifier *_historyChangeNotifier;
    BOOL _maintenanceMode;
}

#pragma mark - Lifecycle

+ (instancetype)sharedInstance {
    static KayokoPasteboardManager *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sharedInstance = [[KayokoPasteboardManager alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Paths and Resources

+ (NSString *)historyPath {
    static NSString *kayokoHistoryPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      kayokoHistoryPath = KayokoRootPath(@"/var/mobile/Library/com.82flex.kayoko/history.json");
    });
    return kayokoHistoryPath;
}

+ (NSString *)historyImagesPath {
    static NSString *kayokoHistoryImagesPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      kayokoHistoryImagesPath = KayokoRootPath(@"/var/mobile/Library/com.82flex.kayoko/images/");
    });
    return kayokoHistoryImagesPath;
}

+ (NSString *)historyRichTextPath {
    static NSString *kayokoHistoryRichTextPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      kayokoHistoryRichTextPath =
          [[[self historyDatabasePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"rich-text"];
    });
    return kayokoHistoryRichTextPath;
}

+ (NSBundle *)localizationBundle {
    static NSBundle *kayokoLocalizationBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      kayokoLocalizationBundle =
          [NSBundle bundleWithPath:KayokoRootPath(@"/Library/PreferenceBundles/KayokoPreferences.bundle")];
    });
    return kayokoLocalizationBundle;
}

+ (NSString *)historyDatabasePath {
    return [KayokoHistoryRepository defaultDatabasePath];
}

+ (NSUInteger)normalizedMaximumHistoryAmountForValue:(NSUInteger)value {
    if (value == 0) {
        return kKayokoPreferenceKeyMaximumHistoryAmountDefaultValue;
    }

    NSArray<NSNumber *> *stepValues = @[ @50, @100, @200, @300, @500, @1000, @2000, @3000, @4000, @5000 ];
    for (NSNumber *stepValue in stepValues) {
        NSUInteger candidate = [stepValue unsignedIntegerValue];
        if (value <= candidate) {
            return candidate;
        }
    }

    return [[stepValues lastObject] unsignedIntegerValue];
}

#pragma mark - Setup

- (instancetype)init {
    self = [super init];
    if (self) {
        _fileManager = [NSFileManager defaultManager];
        if (@available(iOS 16, *)) {
            _pasteboardQueue = dispatch_queue_create("com.82flex.kayoko.queue.pasteboard",
                                                     DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        }
        _thumbnailCache = [[KayokoThumbnailCache alloc] init];
        _automaticPromotionMode = kKayokoPreferenceKeyAutomaticPromotionModeDefaultValue;
        _applicationBlacklist = [NSSet set];
        _pendingPasteboardWrite = [[KayokoPasteboardPendingWrite alloc] init];
        __weak typeof(self) weakSelf = self;
        _historyRepository =
            [[KayokoHistoryRepository alloc] initWithDatabasePath:[KayokoPasteboardManager historyDatabasePath]
                                                       imagesPath:[KayokoPasteboardManager historyImagesPath]
                                                    limitProvider:^NSUInteger(NSString *historyKey) {
                                                      return [weakSelf limitForHistoryKey:historyKey];
                                                    }];
        _historyChangeNotifier = [[KayokoHistoryChangeNotifier alloc] init];
#if !TARGET_OS_SIMULATOR
        if (@available(iOS 15, *)) {
            [self prepareGeneralPasteboard];
        } else
#endif
        {
            // Simulator pasteboard initialization can deadlock while the dylib constructor holds dyld's lock.
            dispatch_async(dispatch_get_main_queue(), ^{
              [self prepareGeneralPasteboard];
            });
        }
    }
    return self;
}

- (void)prepareGeneralPasteboard {
    _pasteboard = [UIPasteboard generalPasteboard];
    _lastChangeCount = [_pasteboard changeCount];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(generalPasteboardDidChange:)
                                                 name:UIPasteboardChangedNotification
                                               object:_pasteboard];
}

- (void)warmUpHistoryAccess {
    if (_maintenanceMode) {
        return;
    }
    [_historyRepository prepareStore];
}

- (void)enterMaintenanceModeUntilProcessExit {
    _maintenanceMode = YES;
    [_historyRepository closeStore];
}

- (void)checkpointHistoryDatabase {
    if (_maintenanceMode) {
        return;
    }
    [_historyRepository checkpointWriteAheadLog];
}

- (void)resetThumbnailMemoryCache {
    [_thumbnailCache removeAllMemoryCachedThumbnails];
}

#pragma mark - Image Storage Helpers

- (NSString *)randomStringWithLength:(NSUInteger)length {
    NSString *characters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    NSMutableString *string = [NSMutableString stringWithCapacity:length];

    for (NSUInteger i = 0; i < length; i++) {
        [string appendFormat:@"%c", [characters characterAtIndex:arc4random_uniform((uint32_t)[characters length])]];
    }

    return string;
}

- (BOOL)imageHasAlpha:(UIImage *)image {
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo([image CGImage]);
    return (alpha == kCGImageAlphaFirst || alpha == kCGImageAlphaLast || alpha == kCGImageAlphaPremultipliedFirst ||
            alpha == kCGImageAlphaPremultipliedLast);
}

- (UIImage *)imageByApplyingOrientation:(UIImage *)image {
    if ([image imageOrientation] == UIImageOrientationUp) {
        return image;
    }

    UIGraphicsBeginImageContext([image size]);
    [image drawInRect:CGRectMake(0, 0, [image size].width, [image size].height)];
    UIImage *rotatedImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return rotatedImage;
}

- (CGSize)pixelSizeForEncodedImageData:(NSData *)imageData {
    if ([imageData length] == 0) {
        return CGSizeZero;
    }

    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!imageSource) {
        return CGSizeZero;
    }
    NSDictionary<NSString *, id> *properties =
        CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL));
    CFRelease(imageSource);

    CGFloat width = [properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat height = [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    if (!isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) {
        return CGSizeZero;
    }
    NSUInteger orientation = [properties[(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue];
    return orientation >= 5 && orientation <= 8 ? CGSizeMake(height, width) : CGSizeMake(width, height);
}

#pragma mark - Pasteboard Representation Helpers

- (UIImage *)imageFromPasteboardItemDictionary:(NSDictionary<NSString *, id> *)dictionary {
    for (id value in [dictionary allValues]) {
        if ([value isKindOfClass:[UIImage class]]) {
            return value;
        }
    }

    NSArray<NSString *> *imageTypeIdentifiers = @[
        @"public.png",
        @"public.jpeg",
        @"public.jpeg-2000",
        @"public.tiff",
        @"public.image",
        @"com.apple.uikit.image",
    ];
    for (NSString *typeIdentifier in imageTypeIdentifiers) {
        id value = dictionary[typeIdentifier];
        if (![value isKindOfClass:[NSData class]]) {
            continue;
        }
        UIImage *image = [UIImage imageWithData:value];
        if (image) {
            return image;
        }
    }

    for (NSString *typeIdentifier in dictionary) {
        if ([imageTypeIdentifiers containsObject:typeIdentifier]) {
            continue;
        }
        id value = dictionary[typeIdentifier];
        if (![value isKindOfClass:[NSData class]]) {
            continue;
        }
        UIImage *image = [UIImage imageWithData:value];
        if (image) {
            return image;
        }
    }
    return nil;
}

- (NSString *)plainTextFromPasteboardItemDictionary:(NSDictionary<NSString *, id> *)dictionary {
    NSArray<NSString *> *textTypeIdentifiers = @[
        @"public.utf8-plain-text",
        @"public.plain-text",
        @"public.text",
        @"public.url",
        @"public.file-url",
    ];
    for (NSString *typeIdentifier in textTypeIdentifiers) {
        id value = dictionary[typeIdentifier];
        NSString *text = nil;
        if ([value isKindOfClass:[NSString class]]) {
            text = value;
        } else if ([value isKindOfClass:[NSURL class]]) {
            text = [value absoluteString];
        } else if ([value isKindOfClass:[NSAttributedString class]]) {
            text = [value string];
        } else if ([value isKindOfClass:[NSData class]]) {
            text = [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
        }
        if ([text length] > 0) {
            return text;
        }
    }
    return nil;
}

- (BOOL)storeRichTextRepresentation:(KayokoRichTextRepresentation *)representation {
    NSString *directoryPath = [KayokoPasteboardManager historyRichTextPath];
    NSError *directoryError = nil;
    if (![_fileManager createDirectoryAtPath:directoryPath
                 withIntermediateDirectories:YES
                                  attributes:nil
                                       error:&directoryError] &&
        ![_fileManager fileExistsAtPath:directoryPath]) {
        HBLogDebug(@"Kayoko: Failed to create rich text directory: %@", directoryError);
        return NO;
    }

    NSString *filePath = [directoryPath stringByAppendingPathComponent:[representation stableFileName]];
    if ([_fileManager fileExistsAtPath:filePath]) {
        NSData *existingData = [_fileManager contentsAtPath:filePath];
        if ([existingData isEqualToData:[representation data]]) {
            return YES;
        }
        HBLogDebug(@"Kayoko: Rich text file conflicts with existing content: %@", filePath);
        return NO;
    }

    NSError *writeError = nil;
    if (![[representation data] writeToFile:filePath options:NSDataWritingAtomic error:&writeError]) {
        HBLogDebug(@"Kayoko: Failed to save rich text representation: %@", writeError);
        return NO;
    }
    return YES;
}

#pragma mark - Pasteboard Observation

- (void)pullPasteboardChanges {
    [self pullPasteboardChangesWithCompletion:nil];
}

- (void)pullPasteboardChangesWithCompletion:(void (^)(BOOL didSaveAnyItem))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    void (^complete)(BOOL) = ^(BOOL didSaveAnyItem) {
      if (!completion) {
          return;
      }

      dispatch_async(dispatch_get_main_queue(), ^{
        completion(didSaveAnyItem);
      });
    };

    NSString *sourceBundleIdentifier = [self sourceApplicationBundleIdentifierForCurrentPasteboardChangeOnMain];

    if (@available(iOS 16, *)) {
        dispatch_async(_pasteboardQueue, ^{
          complete([self _reallyPullPasteboardChangesWithSourceBundleIdentifier:sourceBundleIdentifier]);
        });
        return;
    }

    NSArray<KayokoPasteboardItem *> *items =
        [self pasteboardItemsForCurrentChangeWithSourceBundleIdentifier:sourceBundleIdentifier];
    [self savePasteboardItems:items
             toHistoryWithKey:kKayokoHistoryKeyHistory
                   completion:^(BOOL didSaveAnyItem) {
                     complete(didSaveAnyItem);
                   }];
}

- (BOOL)pasteboardContainsType:(NSString *)pasteboardType {
    return [_pasteboard containsPasteboardTypes:@[ pasteboardType ]];
}

- (void)generalPasteboardDidChange:(NSNotification *)notification {
    (void)notification;
    if ([_pendingPasteboardWrite isActive]) {
        HBLogDebug(@"Kayoko: pending pasteboard write observed changed notification token=%lu changeCount=%lu",
                   (unsigned long)[_pendingPasteboardWrite token], (unsigned long)[_pasteboard changeCount]);
    }
    if (@available(iOS 16, *)) {
        dispatch_async(_pasteboardQueue, ^{
          [self resolvePendingPasteboardWriteForToken:[_pendingPasteboardWrite token] didExpire:NO];
        });
        return;
    }

    [self resolvePendingPasteboardWriteForToken:[_pendingPasteboardWrite token] didExpire:NO];
}

- (BOOL)shouldIgnoreCurrentPasteboardChangeFromSourceBundleIdentifier:(NSString *)sourceBundleIdentifier {
    if ([self ignoreRemoteReplication] && [self pasteboardContainsType:kKayokoRemoteClipboardPasteboardType]) {
        return YES;
    }

    if ([[self applicationBlacklist] containsObject:sourceBundleIdentifier]) {
        HBLogDebug(@"Kayoko: ignored pasteboard change from blacklisted source app bundleIdentifier=%@",
                   sourceBundleIdentifier);
        return YES;
    }

    return [self pasteboardContainsType:@"com.apple.icns"];
}

- (NSString *)sourceApplicationBundleIdentifierForCurrentPasteboardChangeOnMain {
    if ([self pasteboardContainsType:kKayokoRemoteClipboardPasteboardType]) {
        HBLogDebug(@"Kayoko: pasteboard source app using Continuity for remote clipboard change "
                   @"pasteboardType=%@ finalBundleIdentifier=%@",
                   kKayokoRemoteClipboardPasteboardType, kKayokoContinuityBundleIdentifier);
        return kKayokoContinuityBundleIdentifier;
    }

    KayokoKeyboardHostContext *hostContext =
        [[KayokoKeyboardHostResolver sharedResolver] keyboardHostContextForSourceAttribution];
    if ([[hostContext bundleIdentifier] length] > 0) {
        HBLogDebug(@"Kayoko: pasteboard source app using %@ keyboard host bundleIdentifier=%@ scene=%@ "
                   @"kind=%@ cached=%@ kayokoOwned=%@",
                   hostContext.isCached ? @"cached external" : @"current", [hostContext bundleIdentifier],
                   [hostContext identifier], [KayokoKeyboardHostResolver stringForHostKind:[hostContext kind]],
                   hostContext.isCached ? @"YES" : @"NO", hostContext.isKayokoOwned ? @"YES" : @"NO");
        return [hostContext bundleIdentifier];
    }

    SBApplication *frontMostApplication = [[UIApplication sharedApplication] _accessibilityFrontMostApplication];
    NSString *frontMostBundleIdentifier = [frontMostApplication bundleIdentifier];
    NSString *fallbackBundleIdentifier =
        [frontMostBundleIdentifier length] > 0 ? frontMostBundleIdentifier : @"com.apple.springboard";
    HBLogDebug(@"Kayoko: pasteboard source app falling back to frontmost application "
               @"hostScene=%@ hostKind=%@ hostCached=%@ hostBundleIdentifier=%@ frontMostBundleIdentifier=%@ "
               @"finalBundleIdentifier=%@",
               [hostContext identifier] ?: @"nil", [KayokoKeyboardHostResolver stringForHostKind:[hostContext kind]],
               hostContext.isCached ? @"YES" : @"NO", [hostContext bundleIdentifier] ?: @"nil",
               frontMostBundleIdentifier ?: @"nil", fallbackBundleIdentifier);
    return fallbackBundleIdentifier;
}

- (NSArray<KayokoPasteboardItem *> *)pasteboardItemsForCurrentChangeWithSourceBundleIdentifier:
    (NSString *)sourceBundleIdentifier {
    NSUInteger currentChangeCount = [_pasteboard changeCount];
    if (currentChangeCount == _lastChangeCount) {
        return @[];
    }

    _lastChangeCount = currentChangeCount;

    if ([self shouldIgnoreCurrentPasteboardChangeFromSourceBundleIdentifier:sourceBundleIdentifier]) {
        return @[];
    }

    NSMutableArray<KayokoPasteboardItem *> *items = [[NSMutableArray alloc] init];
    for (id pasteboardValue in [_pasteboard items]) {
        @autoreleasepool {
            if (![pasteboardValue isKindOfClass:[NSDictionary class]]) {
                continue;
            }
            NSDictionary<NSString *, id> *pasteboardItem = pasteboardValue;
            UIImage *image = [self imageFromPasteboardItemDictionary:pasteboardItem];
            if (image) {
                if (![self saveImages]) {
                    continue;
                }

                NSString *imageName = [self randomStringWithLength:32];
                NSData *imageData = nil;
                if ([self imageHasAlpha:image]) {
                    imageName = [imageName stringByAppendingString:@".png"];
                    imageData = UIImagePNGRepresentation([self imageByApplyingOrientation:image]);
                } else {
                    imageName = [imageName stringByAppendingString:@".jpg"];
                    imageData = UIImageJPEGRepresentation(image, 1);
                }
                if ([imageData length] == 0) {
                    continue;
                }

                NSString *filePath =
                    [[KayokoPasteboardManager historyImagesPath] stringByAppendingPathComponent:imageName];
                NSError *writeError = nil;
                if (![imageData writeToFile:filePath options:NSDataWritingAtomic error:&writeError]) {
                    HBLogDebug(@"Kayoko: Failed to save captured pasteboard image: %@", writeError);
                    continue;
                }

                KayokoPasteboardItem *item =
                    [[KayokoPasteboardItem alloc] initWithBundleIdentifier:sourceBundleIdentifier
                                                                andContent:imageName
                                                            withImageNamed:imageName];
                CGSize pixelSize = [self pixelSizeForEncodedImageData:imageData];
                [item setImagePixelWidth:(NSUInteger)llround(pixelSize.width)];
                [item setImagePixelHeight:(NSUInteger)llround(pixelSize.height)];
                [item setImageByteCount:(unsigned long long)[imageData length]];
                [items addObject:item];
                continue;
            }

            if (![self saveText]) {
                continue;
            }

            NSString *plainText = [self plainTextFromPasteboardItemDictionary:pasteboardItem];
            KayokoRichTextRepresentation *richTextRepresentation =
                [KayokoRichTextRepresentation preferredRepresentationFromDictionary:pasteboardItem];
            if ([plainText length] == 0) {
                plainText = [richTextRepresentation plainText];
            }
            if ([plainText length] == 0) {
                continue;
            }

            KayokoPasteboardItem *item = [[KayokoPasteboardItem alloc] initWithBundleIdentifier:sourceBundleIdentifier
                                                                                     andContent:plainText
                                                                                 withImageNamed:nil];
            if (richTextRepresentation) {
                NSError *prepareError = nil;
                if (![_historyRepository ensureStorePreparedWithError:&prepareError]) {
                    HBLogDebug(@"Kayoko: Failed to prepare history store before saving rich text: %@", prepareError);
                    continue;
                }
                if ([self storeRichTextRepresentation:richTextRepresentation]) {
                    [item setRichTextUTI:[richTextRepresentation typeIdentifier]];
                    [item setRichTextName:[richTextRepresentation stableFileName]];
                }
            }
            [items addObject:item];
        }
    }

    return items;
}

- (BOOL)_reallyPullPasteboardChangesWithSourceBundleIdentifier:(NSString *)sourceBundleIdentifier {
    if ([_pendingPasteboardWrite isActive]) {
        HBLogDebug(@"Kayoko: ignored pasteboard pull while local write is pending token=%lu changeCount=%lu",
                   (unsigned long)[_pendingPasteboardWrite token], (unsigned long)[_pasteboard changeCount]);
        [self resolvePendingPasteboardWriteForToken:[_pendingPasteboardWrite token] didExpire:NO];
        return NO;
    }

    NSArray<KayokoPasteboardItem *> *items =
        [self pasteboardItemsForCurrentChangeWithSourceBundleIdentifier:sourceBundleIdentifier];
    return [self savePasteboardItemsSynchronously:items toHistoryWithKey:kKayokoHistoryKeyHistory];
}

#pragma mark - History Access

- (BOOL)savePasteboardItemsSynchronously:(NSArray<KayokoPasteboardItem *> *)items
                        toHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return NO;
    }

    BOOL didSaveAnyItem = NO;
    for (KayokoPasteboardItem *item in items) {
        if ([self addPasteboardItem:item toHistoryWithKey:historyKey]) {
            didSaveAnyItem = YES;
        }
    }
    return didSaveAnyItem;
}

- (void)savePasteboardItems:(NSArray<KayokoPasteboardItem *> *)items
           toHistoryWithKey:(NSString *)historyKey
                 completion:(void (^)(BOOL didSaveAnyItem))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *dictionaries =
        [[NSMutableArray alloc] initWithCapacity:[items count]];
    for (KayokoPasteboardItem *item in items) {
        if ([[item content] isEqualToString:@""]) {
            continue;
        }
        [dictionaries addObject:[item dictionaryRepresentation]];
    }

    if ([dictionaries count] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSUInteger limit = [self limitForHistoryKey:historyKey];
    __weak typeof(self) weakSelf = self;
    [_historyRepository
        addItemDictionaries:dictionaries
               toHistoryKey:historyKey
                 completion:^(NSArray<NSDictionary<NSString *, id> *> *savedDictionaries) {
                   __strong typeof(weakSelf) strongSelf = weakSelf;
                   if (!strongSelf) {
                       return;
                   }
                   for (NSDictionary<NSString *, id> *dictionary in savedDictionaries) {
                       [strongSelf
                           postHistoryChangedNotificationForHistoryKey:historyKey
                                                            changeType:
                                                                kKayokoPasteboardManagerHistoryChangeTypeUpsertTop
                                                        itemDictionary:dictionary
                                                                 limit:limit];
                   }
                   if (completion) {
                       completion([savedDictionaries count] > 0);
                   }
                 }];
}

#pragma mark - History Mutations

- (BOOL)addPasteboardItem:(KayokoPasteboardItem *)item toHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return NO;
    }

    if ([[item content] isEqualToString:@""]) {
        return NO;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    NSUInteger limit = [self limitForHistoryKey:historyKey];
    NSError *error = nil;
    BOOL success = [_historyRepository addItemDictionary:dictionary toHistoryKey:historyKey error:&error];
    if (!success) {
        HBLogDebug(@"Kayoko: Failed to add history item: %@", error);
        return NO;
    }

    NSDictionary<NSString *, id> *savedDictionary = [_historyRepository latestItemForHistoryKey:historyKey error:nil];
    if (![savedDictionary[kKayokoItemKeyContent] isEqualToString:dictionary[kKayokoItemKeyContent]]) {
        savedDictionary = dictionary;
    }
    [self postHistoryChangedNotificationForHistoryKey:historyKey
                                           changeType:kKayokoPasteboardManagerHistoryChangeTypeUpsertTop
                                       itemDictionary:savedDictionary
                                                limit:limit];
    return YES;
}

- (void)removePasteboardItem:(KayokoPasteboardItem *)item
          fromHistoryWithKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage {
    if (_maintenanceMode) {
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    NSError *error = nil;
    BOOL success = [_historyRepository removeItemDictionary:dictionary
                                             fromHistoryKey:historyKey
                                          shouldRemoveImage:shouldRemoveImage
                                                      error:&error];
    if (!success) {
        HBLogDebug(@"Kayoko: Failed to remove history item: %@", error);
        return;
    }

    [self postHistoryChangedNotificationForHistoryKey:historyKey
                                           changeType:kKayokoPasteboardManagerHistoryChangeTypeRemove
                                       itemDictionary:dictionary
                                                limit:[self limitForHistoryKey:historyKey]];
}

- (void)removePasteboardItem:(KayokoPasteboardItem *)item
          fromHistoryWithKey:(NSString *)historyKey
           shouldRemoveImage:(BOOL)shouldRemoveImage
                  completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository removeItemDictionary:dictionary
                              fromHistoryKey:historyKey
                           shouldRemoveImage:shouldRemoveImage
                                  completion:completion];
}

- (void)movePasteboardItem:(KayokoPasteboardItem *)item
        fromHistoryWithKey:(NSString *)sourceHistoryKey
          toHistoryWithKey:(NSString *)destinationHistoryKey
                completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository moveItemDictionary:dictionary
                            fromHistoryKey:sourceHistoryKey
                              toHistoryKey:destinationHistoryKey
                                completion:completion];
}

- (void)setTagUUID:(NSString *)tagUUID
    forPasteboardItem:(KayokoPasteboardItem *)item
     inHistoryWithKey:(NSString *)historyKey
           completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if (!item || [historyKey length] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository setTagUUID:tagUUID forItemDictionary:dictionary inHistoryKey:historyKey completion:completion];
}

- (void)setNote:(NSString *)note
    forPasteboardItem:(KayokoPasteboardItem *)item
     inHistoryWithKey:(NSString *)historyKey
           completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if (!item || [historyKey length] == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    [_historyRepository setNote:note forItemDictionary:dictionary inHistoryKey:historyKey completion:completion];
}

- (void)removeAllPasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                                shouldRemoveImages:(BOOL)shouldRemoveImages
                           postsChangeNotification:(BOOL)postsChangeNotification
                                        completion:(void (^)(BOOL success))completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    [_historyRepository
        removeItemsFromHistoryKey:historyKey
               shouldRemoveImages:shouldRemoveImages
                       completion:^(BOOL success) {
                         if (success && postsChangeNotification) {
                             [self postHistoryChangedNotificationForHistoryKey:historyKey
                                                                    changeType:
                                                                        kKayokoPasteboardManagerHistoryChangeTypeClear
                                                                itemDictionary:nil
                                                                         limit:[self limitForHistoryKey:historyKey]];
                         }
                         if (completion) {
                             completion(success);
                         }
                       }];
}

- (void)removeAllPasteboardItemsFromHistoryWithKey:(NSString *)historyKey
                                shouldRemoveImages:(BOOL)shouldRemoveImages
                                        completion:(void (^)(BOOL success))completion {
    [self removeAllPasteboardItemsFromHistoryWithKey:historyKey
                                  shouldRemoveImages:shouldRemoveImages
                             postsChangeNotification:YES
                                          completion:completion];
}

#pragma mark - Promotion Policy

- (void)setAutomaticPromotionMode:(NSUInteger)automaticPromotionMode {
    if (automaticPromotionMode != kKayokoAutomaticPromotionModeOff &&
        automaticPromotionMode != kKayokoAutomaticPromotionModeHistoryOnly &&
        automaticPromotionMode != kKayokoAutomaticPromotionModeAlways) {
        automaticPromotionMode = kKayokoPreferenceKeyAutomaticPromotionModeDefaultValue;
    }
    _automaticPromotionMode = automaticPromotionMode;
}

- (BOOL)shouldPromoteSourceHistoryItemFromHistoryKey:(NSString *)historyKey {
    switch ((KayokoAutomaticPromotionMode)[self automaticPromotionMode]) {
    case kKayokoAutomaticPromotionModeOff:
        return NO;
    case kKayokoAutomaticPromotionModeHistoryOnly:
        return [historyKey isEqualToString:kKayokoHistoryKeyHistory];
    case kKayokoAutomaticPromotionModeAlways:
        return [historyKey isEqualToString:kKayokoHistoryKeyHistory] ||
               [historyKey isEqualToString:kKayokoHistoryKeyFavorites];
    }
    return NO;
}

#pragma mark - Pasteboard Writes

- (void)writePasteboardItem:(KayokoPasteboardItem *)pasteboardItem
          sourceHistoryItem:(KayokoPasteboardItem *)sourceHistoryItem
         fromHistoryWithKey:(NSString *)historyKey
       allowsAutomaticPaste:(BOOL)allowsAutomaticPaste {
    BOOL performsAutomaticPaste = [self automaticallyPaste] && allowsAutomaticPaste;
    KayokoAutomaticPasteMode automaticPasteMode =
        performsAutomaticPaste ? [self resolvedAutomaticPasteMode] : kKayokoAutomaticPasteModeClassic;
    if (@available(iOS 16, *)) {
        dispatch_async(_pasteboardQueue, ^{
          [self _reallyWritePasteboardItem:pasteboardItem
                         sourceHistoryItem:sourceHistoryItem
                        fromHistoryWithKey:historyKey
                           shouldAutoPaste:performsAutomaticPaste
                        automaticPasteMode:automaticPasteMode];
        });
        return;
    }

    [self _reallyWritePasteboardItem:pasteboardItem
                   sourceHistoryItem:sourceHistoryItem
                  fromHistoryWithKey:historyKey
                     shouldAutoPaste:performsAutomaticPaste
                  automaticPasteMode:automaticPasteMode];
}

- (BOOL)copyPasteboardItemToPasteboard:(KayokoPasteboardItem *)item {
    if (@available(iOS 16, *)) {
        __block BOOL didUpdatePasteboard = NO;
        dispatch_sync(_pasteboardQueue, ^{
          didUpdatePasteboard = [self _reallyCopyPasteboardItemToPasteboard:item];
        });
        return didUpdatePasteboard;
    }

    return [self _reallyCopyPasteboardItemToPasteboard:item];
}

- (BOOL)_reallyCopyPasteboardItemToPasteboard:(KayokoPasteboardItem *)item {
    [self cancelPendingPasteboardWrite];
    NSUInteger previousChangeCount = [_pasteboard changeCount];
    HBLogDebug(@"Kayoko: copy write started previousChangeCount=%lu contentLength=%lu hasImage=%@",
               (unsigned long)previousChangeCount, (unsigned long)[[item content] length],
               ([[item imageName] length] > 0) ? @"YES" : @"NO");
    BOOL didUpdatePasteboard = [self setPasteboardContentFromItem:item];
    if (didUpdatePasteboard) {
        NSUInteger token = [self beginPendingPasteboardWriteAfterChangeCount:previousChangeCount
                                                             shouldAutoPaste:NO
                                                          automaticPasteMode:kKayokoAutomaticPasteModeClassic];
        [self resolvePendingPasteboardWriteForToken:token didExpire:NO];
    } else {
        HBLogDebug(@"Kayoko: copy write did not update pasteboard previousChangeCount=%lu",
                   (unsigned long)previousChangeCount);
    }
    return didUpdatePasteboard;
}

- (void)_reallyWritePasteboardItem:(KayokoPasteboardItem *)pasteboardItem
                 sourceHistoryItem:(KayokoPasteboardItem *)sourceHistoryItem
                fromHistoryWithKey:(NSString *)historyKey
                   shouldAutoPaste:(BOOL)shouldAutoPaste
                automaticPasteMode:(KayokoAutomaticPasteMode)automaticPasteMode {
    if (_isWritingPasteboardItem) {
        HBLogDebug(@"Kayoko: pasteboard item write ignored because another write is in progress");
        return;
    }

    _isWritingPasteboardItem = YES;

    [self cancelPendingPasteboardWrite];
    NSUInteger previousChangeCount = [_pasteboard changeCount];
    HBLogDebug(@"Kayoko: pasteboard item write started previousChangeCount=%lu contentLength=%lu hasImage=%@ "
               @"shouldAutoPaste=%@ automaticallyPaste=%@ automaticPasteMode=%lu automaticPromotionMode=%lu "
               @"historyKey=%@",
               (unsigned long)previousChangeCount, (unsigned long)[[pasteboardItem content] length],
               ([[pasteboardItem imageName] length] > 0) ? @"YES" : @"NO", shouldAutoPaste ? @"YES" : @"NO",
               [self automaticallyPaste] ? @"YES" : @"NO", (unsigned long)[self automaticPasteMode],
               (unsigned long)[self automaticPromotionMode], historyKey);
    BOOL didUpdatePasteboard = [self setPasteboardContentFromItem:pasteboardItem];
    if (didUpdatePasteboard) {
        if ([self shouldPromoteSourceHistoryItemFromHistoryKey:historyKey]) {
            [self movePasteboardItemToTop:sourceHistoryItem inHistoryWithKey:historyKey];
        }

        NSUInteger token = [self beginPendingPasteboardWriteAfterChangeCount:previousChangeCount
                                                             shouldAutoPaste:shouldAutoPaste
                                                          automaticPasteMode:automaticPasteMode];
        [self resolvePendingPasteboardWriteForToken:token didExpire:NO];
    } else {
        HBLogDebug(@"Kayoko: pasteboard item write did not update pasteboard previousChangeCount=%lu",
                   (unsigned long)previousChangeCount);
    }

    _isWritingPasteboardItem = NO;
}

- (NSUInteger)beginPendingPasteboardWriteAfterChangeCount:(NSUInteger)previousChangeCount
                                          shouldAutoPaste:(BOOL)shouldAutoPaste
                                       automaticPasteMode:(KayokoAutomaticPasteMode)automaticPasteMode {
    NSUInteger token = [_pendingPasteboardWrite beginAfterChangeCount:previousChangeCount
                                                      shouldAutoPaste:shouldAutoPaste
                                                   automaticPasteMode:automaticPasteMode];
    HBLogDebug(@"Kayoko: pending pasteboard write began token=%lu previousChangeCount=%lu shouldAutoPaste=%@ "
               @"automaticPasteMode=%lu",
               (unsigned long)token, (unsigned long)previousChangeCount, shouldAutoPaste ? @"YES" : @"NO",
               (unsigned long)automaticPasteMode);
    dispatch_queue_t timeoutQueue = dispatch_get_main_queue();
    if (@available(iOS 16, *)) {
        timeoutQueue = _pasteboardQueue;
    }
    __weak typeof(self) weakSelf = self;
    [_pendingPasteboardWrite scheduleExpirationOnQueue:timeoutQueue
                                            afterDelay:kKayokoPasteboardWriteConfirmationTimeout
                                               handler:^{
                                                 __strong typeof(weakSelf) strongSelf = weakSelf;
                                                 [strongSelf resolvePendingPasteboardWriteForToken:token didExpire:YES];
                                               }];

    return token;
}

- (BOOL)resolvePendingPasteboardWriteForToken:(NSUInteger)token didExpire:(BOOL)didExpire {
    if (![_pendingPasteboardWrite matchesToken:token]) {
        if (didExpire) {
            HBLogDebug(@"Kayoko: ignored stale pending pasteboard write timeout token=%lu activeToken=%lu active=%@",
                       (unsigned long)token, (unsigned long)[_pendingPasteboardWrite token],
                       ([_pendingPasteboardWrite isActive] ? @"YES" : @"NO"));
        }
        return NO;
    }

    NSUInteger currentChangeCount = [_pasteboard changeCount];
    if (![_pendingPasteboardWrite hasAdvancedToChangeCount:currentChangeCount]) {
        if (didExpire) {
            HBLogDebug(
                @"Kayoko: pending pasteboard write timed out token=%lu previousChangeCount=%lu currentChangeCount=%lu",
                (unsigned long)token, (unsigned long)[_pendingPasteboardWrite previousChangeCount],
                (unsigned long)currentChangeCount);
            [self cancelPendingPasteboardWrite];
        }
        return NO;
    }

    BOOL shouldAutoPaste = [_pendingPasteboardWrite shouldAutoPaste];
    KayokoAutomaticPasteMode automaticPasteMode = [_pendingPasteboardWrite automaticPasteMode];
    _lastChangeCount = currentChangeCount;
    [self cancelPendingPasteboardWrite];

    HBLogDebug(@"Kayoko: pending pasteboard write confirmed token=%lu currentChangeCount=%lu shouldAutoPaste=%@ "
               @"automaticPasteMode=%lu",
               (unsigned long)token, (unsigned long)currentChangeCount, shouldAutoPaste ? @"YES" : @"NO",
               (unsigned long)automaticPasteMode);
    if (shouldAutoPaste) {
        [self performAutomaticPasteForToken:token automaticPasteMode:automaticPasteMode];
    }

    return YES;
}

- (void)performAutomaticPasteForToken:(NSUInteger)token
                   automaticPasteMode:(KayokoAutomaticPasteMode)automaticPasteMode {
    if (automaticPasteMode == kKayokoAutomaticPasteModeSimulated) {
        HBLogDebug(@"Kayoko: scheduling simulated Cmd+V automatic paste token=%lu delay=%.2f", (unsigned long)token,
                   kKayokoSimulatedAutomaticPasteDelay);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kKayokoSimulatedAutomaticPasteDelay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         CFNotificationCenterPostNotification(
                             CFNotificationCenterGetDarwinNotifyCenter(),
                             (__bridge CFStringRef)kKayokoNotificationKeyPasteWillStart, nil, nil, YES);
                         CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                              (__bridge CFStringRef)kKayokoNotificationKeyPasteFeedback,
                                                              nil, nil, YES);
                         [[KayokoKeyboardShortcutSender sharedSender] sendCommandV];
                       });
        return;
    }

    HBLogDebug(@"Kayoko: posting helper paste notification token=%lu", (unsigned long)token);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kKayokoNotificationKeyHelperPaste, nil, nil, NO);
}

- (KayokoAutomaticPasteMode)resolvedAutomaticPasteMode {
    KayokoAutomaticPasteMode automaticPasteMode = (KayokoAutomaticPasteMode)[self automaticPasteMode];
    if (automaticPasteMode != kKayokoAutomaticPasteModeAutomatic) {
        return automaticPasteMode;
    }

    BOOL usesClassic = [self effectiveKeyboardHostUsesClassicAutomaticPaste];
    HBLogDebug(@"Kayoko: automatic paste auto mode resolved to %@", usesClassic ? @"classic" : @"simulated");
    return usesClassic ? kKayokoAutomaticPasteModeClassic : kKayokoAutomaticPasteModeSimulated;
}

- (BOOL)effectiveKeyboardHostUsesClassicAutomaticPaste {
    KayokoKeyboardHostContext *hostContext =
        [[KayokoKeyboardHostResolver sharedResolver] effectiveExternalKeyboardHostContext];
    if (!hostContext) {
        HBLogDebug(@"Kayoko: automatic paste auto mode has no external keyboard host context; using simulated");
        return NO;
    }

    BOOL springBoardHost =
        hostContext.kind == KayokoKeyboardHostKindSpringBoard || hostContext.kind == KayokoKeyboardHostKindSpotlight;
    BOOL usesClassic = springBoardHost || [hostContext isHelperInjected];
    HBLogDebug(@"Kayoko: automatic paste auto mode using %@ keyboard host scene=%@ kind=%@ cached=%@ "
               @"helperMarkerAvailable=%@ helperFlag=%lld injected=%@",
               hostContext.isCached ? @"cached external" : @"current", hostContext.identifier,
               [KayokoKeyboardHostResolver stringForHostKind:hostContext.kind], hostContext.isCached ? @"YES" : @"NO",
               hostContext.helperMarkerAvailable ? @"YES" : @"NO", hostContext.helperInjectedFlag,
               hostContext.isHelperInjected ? @"YES" : @"NO");
    return usesClassic;
}

- (void)cancelPendingPasteboardWrite {
    [_pendingPasteboardWrite cancel];
}

- (BOOL)setPasteboardContentFromItem:(KayokoPasteboardItem *)item {
    if (!item) {
        return NO;
    }

    if ([[item imageName] length] > 0) {
        NSString *filePath =
            [NSString stringWithFormat:@"%@/%@", [KayokoPasteboardManager historyImagesPath], [item imageName]];
        UIImage *image = [UIImage imageWithContentsOfFile:filePath];
        if (!image) {
            return NO;
        }

        [_pasteboard setImage:image];
        return YES;
    }

    if ([[item content] length] == 0) {
        return NO;
    }

    NSString *richTextUTI = [item richTextUTI];
    NSString *richTextName = [item richTextName];
    if ([richTextUTI length] > 0 && [richTextName length] > 0 &&
        [[richTextName lastPathComponent] isEqualToString:richTextName]) {
        NSString *filePath =
            [[KayokoPasteboardManager historyRichTextPath] stringByAppendingPathComponent:richTextName];
        NSData *richTextData = [_fileManager contentsAtPath:filePath];
        KayokoRichTextRepresentation *representation = [KayokoRichTextRepresentation
            preferredRepresentationFromDictionary:@{richTextUTI : richTextData ?: [NSData data]}];
        if ([[representation typeIdentifier] isEqualToString:richTextUTI] &&
            [[representation stableFileName] isEqualToString:richTextName]) {
            id richTextValue = [representation data];
            if ([richTextUTI isEqualToString:@"public.html"]) {
                richTextValue = [[NSString alloc] initWithData:[representation data] encoding:NSUTF8StringEncoding];
            }
            if (richTextValue) {
                [_pasteboard setItems:@[ @{
                                 @"public.utf8-plain-text" : [item content],
                                 richTextUTI : richTextValue,
                             } ]];
                return YES;
            }
        }
    }

    [_pasteboard setString:[item content]];
    return YES;
}

- (void)movePasteboardItemToTop:(KayokoPasteboardItem *)item inHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return;
    }

    if (!item || [[item content] length] == 0 || [[historyKey description] length] == 0) {
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    NSUInteger limit = [self limitForHistoryKey:historyKey];
    NSError *error = nil;
    BOOL success = [_historyRepository moveItemDictionaryToTop:dictionary inHistoryKey:historyKey error:&error];
    if (!success) {
        HBLogDebug(@"Kayoko: Failed to promote history item: %@", error);
        return;
    }

    [self postHistoryChangedNotificationForHistoryKey:historyKey
                                           changeType:kKayokoPasteboardManagerHistoryChangeTypeUpsertTop
                                       itemDictionary:dictionary
                                                limit:limit];
}

#pragma mark - History Reads

- (NSError *)maintenanceModeError {
    NSString *description = [[KayokoPasteboardManager localizationBundle]
        localizedStringForKey:
            @"Kayoko history is unavailable while package maintenance is in progress. Try again after "
            @"installation finishes."
                        value:nil
                        table:@"Tweak"];
    return [NSError errorWithDomain:kKayokoPasteboardManagerErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey : description}];
}

- (NSMutableArray<NSDictionary<NSString *, id> *> *)getItemsFromHistoryWithKey:(NSString *)historyKey {
    if (_maintenanceMode) {
        return [[NSMutableArray alloc] init];
    }

    NSError *error = nil;
    NSMutableArray<NSDictionary<NSString *, id> *> *history = [_historyRepository itemsForHistoryKey:historyKey
                                                                                               error:&error];
    if (error) {
        HBLogDebug(@"Kayoko: Failed to load history items: %@", error);
    }
    return history ?: [[NSMutableArray alloc] init];
}

- (void)getItemsFromHistoryWithKey:(NSString *)historyKey completion:(KayokoPasteboardItemsCompletion)completion {
    [self getItemsFromHistoryWithKey:historyKey searchCriteria:nil completion:completion];
}

- (void)getItemsFromHistoryWithKey:(NSString *)historyKey
                    searchCriteria:(KayokoSearchCriteria *)searchCriteria
                        completion:(KayokoPasteboardItemsCompletion)completion {
    if (_maintenanceMode) {
        if (completion) {
            completion([[NSMutableArray alloc] init], [self maintenanceModeError]);
        }
        return;
    }

    [_historyRepository itemsForHistoryKey:historyKey searchCriteria:searchCriteria completion:completion];
}

- (void)availableSearchAppBundleIdentifiersWithCompletion:(KayokoPasteboardAppBundleIdentifiersCompletion)completion {
    if (_maintenanceMode) {
        if (completion) {
            completion(@[], [self maintenanceModeError]);
        }
        return;
    }

    [_historyRepository availableSearchAppBundleIdentifiersWithCompletion:completion];
}

- (KayokoPasteboardItem *)getLatestHistoryItem {
    if (_maintenanceMode) {
        return nil;
    }

    NSError *error = nil;
    NSDictionary<NSString *, id> *dictionary = [_historyRepository latestItemForHistoryKey:kKayokoHistoryKeyHistory
                                                                                     error:&error];
    if (error) {
        HBLogDebug(@"Kayoko: Failed to load latest history item: %@", error);
    }
    return [KayokoPasteboardItem itemFromDictionary:dictionary];
}

- (UIImage *)getImageForItem:(KayokoPasteboardItem *)item {
    NSData *imageData =
        [_fileManager contentsAtPath:[NSString stringWithFormat:@"%@/%@", [KayokoPasteboardManager historyImagesPath],
                                                                [item imageName]]];
    return [UIImage imageWithData:imageData];
}

- (void)getThumbnailForItem:(KayokoPasteboardItem *)item
                 targetSize:(CGSize)targetSize
                 completion:(void (^)(UIImage *_Nullable image))completion {
    NSString *imageName = [[item imageName] copy];
    NSString *imagePath = [[KayokoPasteboardManager historyImagesPath] stringByAppendingPathComponent:imageName ?: @""];
    [_thumbnailCache thumbnailForImageName:imageName ?: @""
                                 imagePath:imagePath
                                targetSize:targetSize
                                     scale:[[UIScreen mainScreen] scale]
                                completion:completion];
}

#pragma mark - Notifications

- (void)postHistoryChangedNotification {
    [_historyChangeNotifier postReloadNotificationWithObject:self];
}

- (void)postHistoryChangedNotificationForHistoryKey:(NSString *)historyKey
                                         changeType:(NSString *)changeType
                                     itemDictionary:(NSDictionary<NSString *, id> *)itemDictionary
                                              limit:(NSUInteger)limit {
    [_historyChangeNotifier postChangeNotificationForHistoryKey:historyKey
                                                     changeType:changeType
                                                 itemDictionary:itemDictionary
                                                          limit:limit
                                                         object:self];
}

#pragma mark - Limits

- (NSUInteger)limitForHistoryKey:(NSString *)historyKey {
    if ([historyKey isEqualToString:kKayokoHistoryKeyFavorites]) {
        return NSUIntegerMax;
    }

    return [self maximumHistoryAmount];
}

@end
