//
//  KayokoHistoryMigrator.m
//  Kayoko
//

#import "KayokoHistoryMigrator.h"
#import "KayokoHistoryStore.h"
#import "KayokoPasteboardItem.h"

#import "KayokoPaths.h"

static NSString *const kKayokoMigratorHistoryKey = @"history";
static NSString *const kKayokoMigratorFavoritesKey = @"favorites";
static NSString *const kKayokoHistoryMigratorErrorDomain = @"com.82flex.kayoko.history-migrator";

static NSString *KayokoHistoryMigratorLocalizedString(NSString *key) {
    static NSBundle *localizationBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      localizationBundle = [NSBundle bundleWithPath:KayokoRootPath(@"/Library/PreferenceBundles/KayokoPreferences.bundle")];
    });
    return [localizationBundle localizedStringForKey:key value:key table:@"Tweak"] ?: key;
}

NS_ASSUME_NONNULL_BEGIN

@implementation KayokoHistoryMigrationSource

#pragma mark - Construction

+ (instancetype)sourceWithIdentifier:(NSString *)identifier
                         historyPath:(NSString *)historyPath
                          imagesPath:(NSString *)imagesPath {
    return [[self alloc] initWithIdentifier:identifier historyPath:historyPath imagesPath:imagesPath];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
                       historyPath:(NSString *)historyPath
                        imagesPath:(NSString *)imagesPath {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _historyPath = [historyPath copy];
        _imagesPath = [imagesPath copy];
    }
    return self;
}

@end

@interface KayokoHistoryMigrator ()

#pragma mark - Store

@property(nonatomic, strong) KayokoHistoryStore *historyStore;

#pragma mark - Sources

@property(nonatomic, copy) NSArray<KayokoHistoryMigrationSource *> *migrationSources;

#pragma mark - Image Copying

@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *copiedImageNamesBySourcePath;
@end

NS_ASSUME_NONNULL_END

@implementation KayokoHistoryMigrator

#pragma mark - Sources

+ (NSArray<KayokoHistoryMigrationSource *> *)defaultMigrationSources {
    return @[
        [KayokoHistoryMigrationSource
            sourceWithIdentifier:@"codes.aurora.kayoko"
                     historyPath:KayokoRootPath(@"/var/mobile/Library/codes.aurora.kayoko/history.json")
                      imagesPath:KayokoRootPath(@"/var/mobile/Library/codes.aurora.kayoko/images/")],
        [KayokoHistoryMigrationSource sourceWithIdentifier:@"com.82flex.kayoko"
                                               historyPath:KayokoRootPath(@"/var/mobile/Library/com.82flex.kayoko/history.json")
                                                imagesPath:KayokoRootPath(@"/var/mobile/Library/com.82flex.kayoko/images/")]
    ];
}

#pragma mark - Lifecycle

- (instancetype)initWithHistoryStore:(KayokoHistoryStore *)historyStore
                    migrationSources:(NSArray<KayokoHistoryMigrationSource *> *)migrationSources {
    self = [super init];
    if (self) {
        _historyStore = historyStore;
        _migrationSources = [migrationSources copy];
        _copiedImageNamesBySourcePath = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (instancetype)initWithHistoryStore:(KayokoHistoryStore *)historyStore
                   legacyHistoryPath:(NSString *)legacyHistoryPath {
    KayokoHistoryMigrationSource *source =
        [KayokoHistoryMigrationSource sourceWithIdentifier:@"legacy"
                                               historyPath:legacyHistoryPath
                                                imagesPath:[legacyHistoryPath.stringByDeletingLastPathComponent
                                                               stringByAppendingPathComponent:@"images"]];
    return [self initWithHistoryStore:historyStore migrationSources:@[ source ]];
}

#pragma mark - Migration

- (BOOL)migrateIfNeededWithError:(NSError **)error {
    if (![[self historyStore] prepareStoreWithError:error]) {
        return NO;
    }

    if ([[self historyStore] isMigrationCompletedWithError:error]) {
        return YES;
    }

    NSError *firstSourceError = nil;
    BOOL didFailSource = NO;

    for (KayokoHistoryMigrationSource *source in [self migrationSources]) {
        BOOL sourceExists = NO;
        NSError *sourceError = nil;
        NSDictionary<NSString *, id> *legacyJSON = [self legacyHistoryJSONForSource:source
                                                                             exists:&sourceExists
                                                                              error:&sourceError];
        if (!legacyJSON) {
            if (!sourceExists) {
                continue;
            }
            didFailSource = YES;
            if (!firstSourceError) {
                firstSourceError = sourceError ?: [self migrationErrorForSource:source reason:@"Invalid legacy JSON"];
            }
            continue;
        }

        NSArray<NSDictionary<NSString *, id> *> *historyItems =
            [self preparedItemsFromLegacyJSON:legacyJSON
                                   primaryKey:kKayokoMigratorHistoryKey
                                  fallbackKey:@"History"
                                       source:source
                                        error:&sourceError];
        if (!historyItems) {
            didFailSource = YES;
            if (!firstSourceError) {
                firstSourceError =
                    sourceError ?: [self migrationErrorForSource:source reason:@"Unable to prepare history items"];
            }
            continue;
        }

        NSArray<NSDictionary<NSString *, id> *> *favoriteItems =
            [self preparedItemsFromLegacyJSON:legacyJSON
                                   primaryKey:kKayokoMigratorFavoritesKey
                                  fallbackKey:@"Favorites"
                                       source:source
                                        error:&sourceError];
        if (!favoriteItems) {
            didFailSource = YES;
            if (!firstSourceError) {
                firstSourceError =
                    sourceError ?: [self migrationErrorForSource:source reason:@"Unable to prepare favorite items"];
            }
            continue;
        }

        if (![[self historyStore] importItemDictionaries:historyItems
                                            toHistoryKey:kKayokoMigratorHistoryKey
                                                   error:&sourceError]) {
            didFailSource = YES;
            if (!firstSourceError) {
                firstSourceError =
                    sourceError ?: [self migrationErrorForSource:source reason:@"Unable to import history items"];
            }
            continue;
        }
        if (![[self historyStore] importItemDictionaries:favoriteItems
                                            toHistoryKey:kKayokoMigratorFavoritesKey
                                                   error:&sourceError]) {
            didFailSource = YES;
            if (!firstSourceError) {
                firstSourceError =
                    sourceError ?: [self migrationErrorForSource:source reason:@"Unable to import favorite items"];
            }
            continue;
        }
    }

    if (didFailSource) {
        if (error) {
            *error = firstSourceError;
        }
        return NO;
    }

    return [[self historyStore] markMigrationCompletedWithError:error];
}

#pragma mark - Legacy JSON

- (NSDictionary<NSString *, id> *)legacyHistoryJSONForSource:(KayokoHistoryMigrationSource *)source
                                                      exists:(BOOL *)exists
                                                       error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[source historyPath]]) {
        if (exists) {
            *exists = NO;
        }
        return nil;
    }

    if (exists) {
        *exists = YES;
    }

    NSData *jsonData = [NSData dataWithContentsOfFile:[source historyPath] options:0 error:error];
    if (!jsonData) {
        return nil;
    }

    if ([jsonData length] == 0) {
        return @{};
    }

    id json = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:error];
    if (![json isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    return json;
}

#pragma mark - Item Preparation

- (NSArray<NSDictionary<NSString *, id> *> *)preparedItemsFromLegacyJSON:(NSDictionary<NSString *, id> *)json
                                                              primaryKey:(NSString *)primaryKey
                                                             fallbackKey:(NSString *)fallbackKey
                                                                  source:(KayokoHistoryMigrationSource *)source
                                                                   error:(NSError **)error {
    NSArray<NSDictionary<NSString *, id> *> *items = [self itemsFromLegacyJSON:json
                                                                    primaryKey:primaryKey
                                                                   fallbackKey:fallbackKey];
    NSMutableArray<NSDictionary<NSString *, id> *> *preparedItems =
        [[NSMutableArray alloc] initWithCapacity:[items count]];

    for (id item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        NSDictionary<NSString *, id> *preparedItem = [self preparedItemDictionary:item source:source error:error];
        if (!preparedItem) {
            return nil;
        }
        [preparedItems addObject:preparedItem];
    }

    return preparedItems;
}

- (NSArray<NSDictionary<NSString *, id> *> *)itemsFromLegacyJSON:(NSDictionary<NSString *, id> *)json
                                                      primaryKey:(NSString *)primaryKey
                                                     fallbackKey:(NSString *)fallbackKey {
    id items = json[primaryKey];
    if (!items) {
        items = json[fallbackKey];
    }
    if (![items isKindOfClass:[NSArray class]]) {
        return @[];
    }
    return items;
}

- (NSDictionary<NSString *, id> *)preparedItemDictionary:(NSDictionary<NSString *, id> *)item
                                                  source:(KayokoHistoryMigrationSource *)source
                                                   error:(NSError **)error {
    NSString *imageName = [self stringValueFromDictionary:item key:kKayokoItemKeyImageName];
    if ([imageName length] == 0) {
        return item;
    }

    NSString *migratedImageName = [self copyImageNamed:imageName fromSource:source error:error];
    if (!migratedImageName) {
        return nil;
    }

    if ([migratedImageName isEqualToString:imageName]) {
        return item;
    }

    NSMutableDictionary<NSString *, id> *preparedItem = [item mutableCopy];
    preparedItem[kKayokoItemKeyImageName] = migratedImageName;

    NSString *content = [self stringValueFromDictionary:item key:kKayokoItemKeyContent];
    if ([content isEqualToString:imageName]) {
        preparedItem[kKayokoItemKeyContent] = migratedImageName;
    }

    return preparedItem;
}

#pragma mark - Image Copying

- (NSString *)copyImageNamed:(NSString *)imageName
                  fromSource:(KayokoHistoryMigrationSource *)source
                       error:(NSError **)error {
    if ([[source imagesPath] length] == 0) {
        return imageName;
    }

    NSString *sourcePath = [[source imagesPath] stringByAppendingPathComponent:imageName];
    NSString *standardizedSourcePath = [sourcePath stringByStandardizingPath];
    NSString *targetImagesPath = [[[self historyStore] imagesPath] stringByStandardizingPath];
    NSString *targetPath = [[targetImagesPath stringByAppendingPathComponent:imageName] stringByStandardizingPath];

    if ([standardizedSourcePath isEqualToString:targetPath]) {
        return imageName;
    }

    NSString *cachedImageName = [self copiedImageNamesBySourcePath][standardizedSourcePath];
    if (cachedImageName) {
        return cachedImageName;
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:standardizedSourcePath]) {
        return imageName;
    }

    NSString *migratedImageName = imageName;
    if ([fileManager fileExistsAtPath:targetPath]) {
        migratedImageName = [self uniqueImageNameForImageName:imageName inDirectory:targetImagesPath];
        targetPath = [targetImagesPath stringByAppendingPathComponent:migratedImageName];
    }

    if (![fileManager copyItemAtPath:standardizedSourcePath toPath:targetPath error:error]) {
        return nil;
    }

    [self copiedImageNamesBySourcePath][standardizedSourcePath] = migratedImageName;
    return migratedImageName;
}

- (NSString *)uniqueImageNameForImageName:(NSString *)imageName inDirectory:(NSString *)directoryPath {
    NSString *extension = [imageName pathExtension];
    NSString *basename = [imageName stringByDeletingPathExtension];
    NSFileManager *fileManager = [NSFileManager defaultManager];

    while (YES) {
        NSString *suffix = [[[NSUUID UUID] UUIDString] substringToIndex:8];
        NSString *candidate = [NSString stringWithFormat:@"%@-%@", basename, suffix];
        if ([extension length] > 0) {
            candidate = [candidate stringByAppendingPathExtension:extension];
        }

        NSString *candidatePath = [directoryPath stringByAppendingPathComponent:candidate];
        if (![fileManager fileExistsAtPath:candidatePath]) {
            return candidate;
        }
    }
}

#pragma mark - Value Mapping

- (NSString *)stringValueFromDictionary:(NSDictionary<NSString *, id> *)dictionary key:(NSString *)key {
    id value = dictionary[key];
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    return nil;
}

#pragma mark - Errors

- (NSError *)migrationErrorForSource:(KayokoHistoryMigrationSource *)source reason:(NSString *)reason {
    NSString *descriptionFormat = KayokoHistoryMigratorLocalizedString(
        @"Unable to migrate history source %@. Reinstalling Kayoko may resolve this issue.");
    NSString *description = [NSString stringWithFormat:descriptionFormat, [source identifier]];
    return [NSError
        errorWithDomain:kKayokoHistoryMigratorErrorDomain
                   code:1
               userInfo:@{NSLocalizedDescriptionKey : description, NSLocalizedFailureReasonErrorKey : reason ?: @""}];
}

@end
