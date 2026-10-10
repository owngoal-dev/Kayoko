//
//  KayokoPostinstallUpdater.m
//  Kayoko
//

#import "KayokoPostinstallUpdater.h"
#import "KayokoCopyLogImporter.h"
#import "KayokoCopyVaultImporter.h"
#import "KayokoHistoryMigrator.h"
#import "KayokoHistoryStore.h"
#import "KayokoNotificationKeys.h"
#import "KayokoTagStore.h"

#import <CoreFoundation/CoreFoundation.h>
#import "KayokoPaths.h"
#import <unistd.h>

static NSString *const kKayokoCurrentDataDirectory = @"/var/mobile/Library/com.82flex.kayoko";
static NSString *const kKayokoCopyVaultDataDirectory = @"/var/mobile/Documents/CopyVault";
static NSString *const kKayokoCopyLogDataDirectory = @"/var/mobile/Library/CopyLog";
static NSString *const kKayokoPreferencesBundlePath = @"/Library/PreferenceBundles/KayokoPreferences.bundle";
static NSString *const kKayokoThumbnailCacheDirectoryPath = @"/var/mobile/Library/Caches/com.82flex.kayoko/thumbnails";
#if !TARGET_OS_SIMULATOR
static NSUInteger const kKayokoMobileUserID = 501;
static NSUInteger const kKayokoMobileGroupID = 501;
#endif
static useconds_t const kKayokoCoreMaintenanceGracePeriodMicroseconds = 500000;
static NSInteger const kKayokoUpdaterHistoryStoreBusyTimeoutMilliseconds = 10000;

@implementation KayokoPostinstallUpdater

#pragma mark - Postinstall

- (BOOL)runPostinstallWithError:(NSError **)error {
    [self notifyCoreToPrepareForMaintenance];

    NSError *defaultTagsError = nil;
    BOOL preparedDefaultTags = [self prepareDefaultTagsIfNeededWithError:&defaultTagsError];

    NSError *defaultTagsOwnershipError = nil;
    BOOL repairedDefaultTagsOwnership =
        preparedDefaultTags && [self repairDefaultTagsOwnershipWithError:&defaultTagsOwnershipError];

    KayokoHistoryStore *store = [self historyStore];
    NSError *lockError = nil;
    if (![store verifyExclusiveAccessWithError:&lockError]) {
        if (error) {
            *error = lockError;
        }
        return NO;
    }

    KayokoHistoryMigrator *migrator =
        [[KayokoHistoryMigrator alloc] initWithHistoryStore:store
                                           migrationSources:[KayokoHistoryMigrator defaultMigrationSources]];
    NSError *migrationError = nil;
    BOOL migrated = [migrator migrateIfNeededWithError:&migrationError];

    NSError *historySchemaError = nil;
    BOOL upgradedHistorySchema = migrated && [store upgradeHistorySchemaWithError:&historySchemaError];

    NSError *searchIndexError = nil;
    BOOL upgradedSearchIndex = upgradedHistorySchema && [store upgradeSearchIndexWithError:&searchIndexError];

    NSError *ownershipError = nil;
    BOOL repairedOwnership = upgradedSearchIndex && [self repairCurrentDataDirectoryOwnershipWithError:&ownershipError];
    if (!migrated) {
        if (error) {
            *error = migrationError;
        }
        return NO;
    }
    if (!upgradedHistorySchema) {
        if (error) {
            *error = historySchemaError;
        }
        return NO;
    }
    if (!upgradedSearchIndex) {
        if (error) {
            *error = searchIndexError;
        }
        return NO;
    }
    if (!preparedDefaultTags) {
        if (error) {
            *error = defaultTagsError;
        }
        return NO;
    }
    if (!repairedDefaultTagsOwnership) {
        if (error) {
            *error = defaultTagsOwnershipError;
        }
        return NO;
    }
    if (!repairedOwnership) {
        if (error) {
            *error = ownershipError;
        }
        return NO;
    }

    return YES;
}

#pragma mark - CopyVault Import

- (BOOL)importCopyVaultWithError:(NSError **)error {
    return [self importCopyVaultWithSkippedItemCount:nil error:error];
}

- (BOOL)importCopyVaultWithSkippedItemCount:(NSUInteger *)skippedItemCount error:(NSError **)error {
    [self notifyCoreToPrepareForMaintenance];

    KayokoHistoryStore *store = [self historyStore];
    if (![store verifyExclusiveAccessWithError:error]) {
        return NO;
    }
    if (![store prepareStoreWithError:error]) {
        [store closeDatabase];
        return NO;
    }
    if (![store upgradeSearchIndexWithError:error]) {
        [store closeDatabase];
        return NO;
    }

    KayokoTagStore *tagStore = [[KayokoTagStore alloc] initWithTagsPath:[KayokoTagStore defaultTagsPath]
                                                     localizationBundle:[self preferencesLocalizationBundle]];
    KayokoCopyVaultImporter *importer =
        [[KayokoCopyVaultImporter alloc] initWithSourceDirectoryPath:KayokoUserPath(kKayokoCopyVaultDataDirectory)
                                                        historyStore:store
                                                            tagStore:tagStore];
    BOOL imported = [importer runWithSkippedItemCount:skippedItemCount error:error];
    [store closeDatabase];
    if (!imported) {
        return NO;
    }

    return [self repairCurrentDataDirectoryOwnershipWithError:error];
}

#pragma mark - CopyLog Import

- (BOOL)importCopyLogWithSkippedItemCount:(NSUInteger *)skippedItemCount error:(NSError **)error {
    [self notifyCoreToPrepareForMaintenance];

    KayokoHistoryStore *store = [self historyStore];
    if (![store verifyExclusiveAccessWithError:error]) {
        return NO;
    }
    if (![store prepareStoreWithError:error]) {
        [store closeDatabase];
        return NO;
    }
    if (![store upgradeSearchIndexWithError:error]) {
        [store closeDatabase];
        return NO;
    }

    NSString *sourceDirectoryPath = KayokoRootPath(kKayokoCopyLogDataDirectory);
    KayokoCopyLogImporter *importer = [[KayokoCopyLogImporter alloc] initWithSourceDirectoryPath:sourceDirectoryPath
                                                                                    historyStore:store];
    BOOL imported = [importer runWithSkippedItemCount:skippedItemCount error:error];
    [store closeDatabase];
    if (!imported) {
        return NO;
    }
    return [self repairCurrentDataDirectoryOwnershipWithError:error];
}

#pragma mark - Thumbnail Cache

- (BOOL)resetThumbnailCacheWithError:(NSError **)error {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kKayokoNotificationKeyCoreResetThumbnailMemoryCache, nil,
                                         nil, YES);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:KayokoUserPath(kKayokoThumbnailCacheDirectoryPath)]) {
        return YES;
    }
    return [fileManager removeItemAtPath:KayokoUserPath(kKayokoThumbnailCacheDirectoryPath) error:error];
}

#pragma mark - Legacy Cleanup

- (NSArray<NSString *> *)safelyDeletableLegacyPathsWithError:(NSError **)error {
    KayokoHistoryStore *store = [self historyStore];
    if (![store prepareStoreWithError:error]) {
        return @[];
    }

    if (![store isMigrationCompletedWithError:error]) {
        return @[];
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *activeImagesPath = [[store imagesPath] stringByStandardizingPath];
    NSMutableArray<NSString *> *paths = [[NSMutableArray alloc] init];
    NSMutableSet<NSString *> *seenPaths = [[NSMutableSet alloc] init];

    for (KayokoHistoryMigrationSource *source in [KayokoHistoryMigrator defaultMigrationSources]) {
        [self addPathIfExists:[source historyPath] fileManager:fileManager paths:paths seenPaths:seenPaths];

        NSString *sourceImagesPath = [[source imagesPath] stringByStandardizingPath];
        if (![sourceImagesPath isEqualToString:activeImagesPath]) {
            [self addPathIfExists:[source imagesPath] fileManager:fileManager paths:paths seenPaths:seenPaths];
        }
    }

    return paths;
}

#pragma mark - Core Coordination

- (void)notifyCoreToPrepareForMaintenance {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)kKayokoNotificationKeyCorePrepareMaintenance, nil, nil,
                                         YES);
    usleep(kKayokoCoreMaintenanceGracePeriodMicroseconds);
}

#pragma mark - Store Paths

- (KayokoHistoryStore *)historyStore {
    return [[KayokoHistoryStore alloc] initWithDatabasePath:[KayokoHistoryStore defaultDatabasePath]
                                                 imagesPath:[self currentImagesPath]
                                                lockingMode:KayokoHistoryStoreLockingModeExclusiveWhileOpen
                                    busyTimeoutMilliseconds:kKayokoUpdaterHistoryStoreBusyTimeoutMilliseconds];
}

- (NSString *)currentImagesPath {
    return [KayokoRootPath(kKayokoCurrentDataDirectory) stringByAppendingPathComponent:@"images"];
}

#pragma mark - Default Tags

- (BOOL)prepareDefaultTagsIfNeededWithError:(NSError **)error {
    KayokoTagStore *tagStore = [[KayokoTagStore alloc] initWithTagsPath:[KayokoTagStore defaultTagsPath]
                                                     localizationBundle:[self preferencesLocalizationBundle]];
    return [tagStore ensureDefaultTagsFileExistsWithError:error];
}

- (NSBundle *)preferencesLocalizationBundle {
    NSString *bundlePath = KayokoRootPath(kKayokoPreferencesBundlePath);
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    return bundle ?: [NSBundle mainBundle];
}

#pragma mark - Ownership

- (BOOL)repairDefaultTagsOwnershipWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *dataDirectory = [[KayokoTagStore defaultTagsPath] stringByDeletingLastPathComponent];
    BOOL isDirectory = NO;
    if ([fileManager fileExistsAtPath:dataDirectory isDirectory:&isDirectory] && isDirectory) {
        if (![self repairOwnershipAtPath:dataDirectory isDirectory:YES fileManager:fileManager error:error]) {
            return NO;
        }
    }

    NSString *tagsPath = [KayokoTagStore defaultTagsPath];
    isDirectory = NO;
    if ([fileManager fileExistsAtPath:tagsPath isDirectory:&isDirectory]) {
        return [self repairOwnershipAtPath:tagsPath isDirectory:isDirectory fileManager:fileManager error:error];
    }

    return YES;
}

- (BOOL)repairCurrentDataDirectoryOwnershipWithError:(NSError **)error {
    NSString *dataDirectory = KayokoRootPath(kKayokoCurrentDataDirectory);
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:dataDirectory]) {
        return YES;
    }

    if (![self repairOwnershipAtPath:dataDirectory isDirectory:YES fileManager:fileManager error:error]) {
        return NO;
    }

    NSDirectoryEnumerator<NSString *> *enumerator = [fileManager enumeratorAtPath:dataDirectory];
    for (NSString *relativePath in enumerator) {
        NSString *path = [dataDirectory stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:path isDirectory:&isDirectory]) {
            continue;
        }
        if (![self repairOwnershipAtPath:path isDirectory:isDirectory fileManager:fileManager error:error]) {
            return NO;
        }
    }

    return YES;
}

- (BOOL)repairOwnershipAtPath:(NSString *)path
                  isDirectory:(BOOL)isDirectory
                  fileManager:(NSFileManager *)fileManager
                        error:(NSError **)error {
    NSDictionary<NSFileAttributeKey, id> *attributes = @{
#if !TARGET_OS_SIMULATOR
        NSFileOwnerAccountID : @(kKayokoMobileUserID),
        NSFileGroupOwnerAccountID : @(kKayokoMobileGroupID),
#endif
        NSFilePosixPermissions : @(isDirectory ? 0755 : 0644)
    };
    return [fileManager setAttributes:attributes ofItemAtPath:path error:error];
}

#pragma mark - Legacy Path Helpers

- (void)addPathIfExists:(NSString *)path
            fileManager:(NSFileManager *)fileManager
                  paths:(NSMutableArray<NSString *> *)paths
              seenPaths:(NSMutableSet<NSString *> *)seenPaths {
    if ([path length] == 0 || ![fileManager fileExistsAtPath:path]) {
        return;
    }

    NSString *standardizedPath = [path stringByStandardizingPath];
    if ([seenPaths containsObject:standardizedPath]) {
        return;
    }

    [seenPaths addObject:standardizedPath];
    [paths addObject:path];
}

@end
