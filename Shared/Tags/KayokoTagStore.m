//
//  KayokoTagStore.m
//  Kayoko
//

#import "KayokoTagStore.h"
#import "KayokoTag.h"

#import "KayokoPaths.h"

NSString *const kKayokoTagStoreErrorDomain = @"com.82flex.kayoko.tag-store";

static NSString *const kKayokoTagStoreDataDirectoryPath = @"/var/mobile/Library/com.82flex.kayoko";
static NSString *const kKayokoTagStoreFileName = @"tags-v4.plist";

@interface KayokoTagStore ()
@property(nonatomic, copy, readwrite) NSString *tagsPath;
@property(nonatomic, strong, readwrite) NSBundle *localizationBundle;
@end

@implementation KayokoTagStore

+ (NSString *)defaultTagsPath {
    return [KayokoRootPath(kKayokoTagStoreDataDirectoryPath) stringByAppendingPathComponent:kKayokoTagStoreFileName];
}

- (instancetype)initWithTagsPath:(NSString *)tagsPath localizationBundle:(NSBundle *)localizationBundle {
    self = [super init];
    if (self) {
        _tagsPath = [tagsPath copy];
        _localizationBundle = localizationBundle ?: [NSBundle mainBundle];
    }
    return self;
}

- (NSMutableArray<KayokoTag *> *)loadTagsWithError:(NSError **)error {
    if (![self ensureDefaultTagsFileExistsWithError:error]) {
        return nil;
    }

    return [self readTagsWithError:error];
}

- (NSMutableArray<KayokoTag *> *)readTagsWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[self tagsPath]]) {
        return [[NSMutableArray alloc] init];
    }

    NSData *plistData = [NSData dataWithContentsOfFile:[self tagsPath] options:0 error:error];
    if (!plistData) {
        return nil;
    }

    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id propertyList = [NSPropertyListSerialization propertyListWithData:plistData
                                                                options:NSPropertyListImmutable
                                                                 format:&format
                                                                  error:error];
    if (![propertyList isKindOfClass:[NSArray class]]) {
        [self populateError:error code:1 message:@"Kayoko tag plist root must be an array"];
        return nil;
    }

    NSMutableArray<KayokoTag *> *tags = [[NSMutableArray alloc] init];
    for (id item in (NSArray *)propertyList) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            [self populateError:error code:2 message:@"Kayoko tag plist contains a non-dictionary item"];
            return nil;
        }

        KayokoTag *tag = [KayokoTag tagWithDictionary:item];
        if (!tag) {
            [self populateError:error code:3 message:@"Kayoko tag plist contains an invalid tag"];
            return nil;
        }
        [tags addObject:tag];
    }

    return tags;
}

- (BOOL)ensureDefaultTagsFileExistsWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[self tagsPath]]) {
        return YES;
    }

    return [self saveTags:[self defaultTags] error:error];
}

- (BOOL)saveTags:(NSArray<KayokoTag *> *)tags error:(NSError **)error {
    if (![self prepareDataDirectoryWithError:error]) {
        return NO;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *propertyList =
        [[NSMutableArray alloc] initWithCapacity:[tags count]];
    for (KayokoTag *tag in tags) {
        [propertyList addObject:[tag dictionaryRepresentation]];
    }

    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:propertyList
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:error];
    if (!plistData) {
        return NO;
    }

    return [plistData writeToFile:[self tagsPath] options:NSDataWritingAtomic error:error];
}

- (BOOL)restoreDefaultTagsWithError:(NSError **)error {
    return [self saveTags:[self defaultTags] error:error];
}

#pragma mark - Private

- (NSArray<KayokoTag *> *)defaultTags {
    return @[
        [KayokoTag tagWithTitle:[self localizedStringForKey:@"Red"] hexColor:@"#EF7571FF"],
        [KayokoTag tagWithTitle:[self localizedStringForKey:@"Orange"] hexColor:@"#F3AC6DFF"],
        [KayokoTag tagWithTitle:[self localizedStringForKey:@"Yellow"] hexColor:@"#FAE06DFF"],
        [KayokoTag tagWithTitle:[self localizedStringForKey:@"Green"] hexColor:@"#86D885FF"],
        [KayokoTag tagWithTitle:[self localizedStringForKey:@"Blue"] hexColor:@"#66A5F9FF"],
        [KayokoTag tagWithTitle:[self localizedStringForKey:@"Purple"] hexColor:@"#D469EEFF"],
        [KayokoTag tagWithTitle:[self localizedStringForKey:@"Gray"] hexColor:@"#ADADB0FF"]
    ];
}

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"Tags"] ?: key;
}

- (BOOL)prepareDataDirectoryWithError:(NSError **)error {
    NSString *directoryPath = [[self tagsPath] stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:directoryPath]) {
        return YES;
    }

    return [fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:error];
}

- (void)populateError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (!error) {
        return;
    }

    *error = [NSError errorWithDomain:kKayokoTagStoreErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey : message ?: @"Kayoko tag store error"}];
}

@end
