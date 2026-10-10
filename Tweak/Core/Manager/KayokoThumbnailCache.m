//
//  KayokoThumbnailCache.m
//  Kayoko
//

#import "KayokoThumbnailCache.h"
#import "KayokoPaths.h"

#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <sys/stat.h>

static NSUInteger const kKayokoThumbnailMemoryCacheCountLimit = 80;
static NSUInteger const kKayokoThumbnailMemoryCacheCostLimit = 24 * 1024 * 1024;
static NSUInteger const kKayokoThumbnailPendingWriteCountLimit = 16;
static NSUInteger const kKayokoThumbnailPendingWriteCostLimit = 16 * 1024 * 1024;
static CGFloat const kKayokoThumbnailDiskCacheJPEGQuality = 0.9;
static NSString *const kKayokoThumbnailDefaultCacheDirectoryPath =
    @"/var/mobile/Library/Caches/com.82flex.kayoko/thumbnails/v2";
static NSString *const kKayokoThumbnailCacheRecipeVersion = @"2";
static unsigned char const kKayokoThumbnailContainerMagic[] = {'K', 'Y', 'T', '2'};
static NSUInteger const kKayokoThumbnailContainerHeaderLength =
    sizeof(kKayokoThumbnailContainerMagic) + sizeof(uint64_t) + CC_SHA256_DIGEST_LENGTH;
static NSUInteger const kKayokoThumbnailContainerPayloadLimit = 32 * 1024 * 1024;

@implementation KayokoThumbnailCache {
    NSString *_cacheDirectoryPath;
    NSFileManager *_fileManager;
    dispatch_queue_t _decodeQueue;
    dispatch_queue_t _writeQueue;
    NSCache<NSString *, UIImage *> *_memoryCache;
    NSLock *_requestLock;
    NSMutableDictionary<NSString *, NSMutableArray *> *_completionsByRequestKey;
    NSUInteger _pendingWriteCount;
    NSUInteger _pendingWriteCost;
}

+ (NSString *)defaultCacheDirectoryPath {
    return KayokoUserPath(kKayokoThumbnailDefaultCacheDirectoryPath);
}

- (instancetype)init {
    return [self initWithCacheDirectoryPath:[[self class] defaultCacheDirectoryPath]];
}

- (instancetype)initWithCacheDirectoryPath:(NSString *)cacheDirectoryPath {
    self = [super init];
    if (self) {
        _cacheDirectoryPath = [cacheDirectoryPath copy];
        _fileManager = [[NSFileManager alloc] init];
        _decodeQueue =
            dispatch_queue_create("com.82flex.kayoko.queue.thumbnail", DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        _writeQueue = dispatch_queue_create("com.82flex.kayoko.queue.thumbnail-write",
                                            DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        _memoryCache = [[NSCache alloc] init];
        [_memoryCache setCountLimit:kKayokoThumbnailMemoryCacheCountLimit];
        [_memoryCache setTotalCostLimit:kKayokoThumbnailMemoryCacheCostLimit];
        _requestLock = [[NSLock alloc] init];
        _completionsByRequestKey = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (nullable NSString *)sourceFingerprintForImagePath:(NSString *)imagePath {
    struct stat sourceInfo;
    if (stat([imagePath fileSystemRepresentation], &sourceInfo) != 0 || !S_ISREG(sourceInfo.st_mode)) {
        return nil;
    }

    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld", (unsigned long long)sourceInfo.st_dev,
                                      (unsigned long long)sourceInfo.st_ino, (long long)sourceInfo.st_size,
                                      (long long)sourceInfo.st_mtimespec.tv_sec, sourceInfo.st_mtimespec.tv_nsec];
}

- (NSString *)requestKeyForImageName:(NSString *)imageName targetSize:(CGSize)targetSize scale:(CGFloat)scale {
    NSUInteger targetPixelWidth = (NSUInteger)MAX(ceil(targetSize.width * scale), 1);
    NSUInteger targetPixelHeight = (NSUInteger)MAX(ceil(targetSize.height * scale), 1);
    NSUInteger scaleThousandths = (NSUInteger)MAX(llround(scale * 1000), 1);
    return [NSString stringWithFormat:@"%@|%@|%lux%lu|%lu", kKayokoThumbnailCacheRecipeVersion, imageName,
                                      (unsigned long)targetPixelWidth, (unsigned long)targetPixelHeight,
                                      (unsigned long)scaleThousandths];
}

- (NSString *)diskCacheKeyForRequestKey:(NSString *)requestKey sourceFingerprint:(NSString *)sourceFingerprint {
    NSString *logicalKey = [NSString stringWithFormat:@"%@|%@", requestKey, sourceFingerprint];
    NSData *keyData = [logicalKey dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([keyData bytes], (CC_LONG)[keyData length], digest);

    NSMutableString *cacheKey = [[NSMutableString alloc] initWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [cacheKey appendFormat:@"%02x", digest[index]];
    }
    return cacheKey;
}

- (NSUInteger)memoryCostForImage:(UIImage *)image {
    CGImageRef imageRef = [image CGImage];
    if (!imageRef) {
        return 0;
    }

    size_t bytesPerRow = CGImageGetBytesPerRow(imageRef);
    size_t height = CGImageGetHeight(imageRef);
    if (height > 0 && bytesPerRow > NSUIntegerMax / height) {
        return NSUIntegerMax;
    }
    return bytesPerRow * height;
}

- (nullable UIImage *)loadThumbnailFromDiskAtPath:(NSString *)cachePath scale:(CGFloat)scale {
    NSData *containerData = [NSData dataWithContentsOfFile:cachePath options:NSDataReadingMappedIfSafe error:nil];
    if (!containerData) {
        if ([_fileManager fileExistsAtPath:cachePath]) {
            [_fileManager removeItemAtPath:cachePath error:nil];
        }
        return nil;
    }

    // ImageIO accepts some truncated JPEGs, so validate the complete payload before decoding it.
    if ([containerData length] < kKayokoThumbnailContainerHeaderLength) {
        [_fileManager removeItemAtPath:cachePath error:nil];
        return nil;
    }
    const unsigned char *containerBytes = [containerData bytes];
    if (memcmp(containerBytes, kKayokoThumbnailContainerMagic, sizeof(kKayokoThumbnailContainerMagic)) != 0) {
        [_fileManager removeItemAtPath:cachePath error:nil];
        return nil;
    }

    uint64_t encodedLengthBigEndian = 0;
    memcpy(&encodedLengthBigEndian, containerBytes + sizeof(kKayokoThumbnailContainerMagic), sizeof(uint64_t));
    uint64_t encodedLength = CFSwapInt64BigToHost(encodedLengthBigEndian);
    NSUInteger actualEncodedLength = [containerData length] - kKayokoThumbnailContainerHeaderLength;
    if (encodedLength != actualEncodedLength || actualEncodedLength > kKayokoThumbnailContainerPayloadLimit) {
        [_fileManager removeItemAtPath:cachePath error:nil];
        return nil;
    }

    const unsigned char *storedDigest = containerBytes + sizeof(kKayokoThumbnailContainerMagic) + sizeof(uint64_t);
    const unsigned char *encodedBytes = containerBytes + kKayokoThumbnailContainerHeaderLength;
    unsigned char actualDigest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(encodedBytes, (CC_LONG)actualEncodedLength, actualDigest);
    if (memcmp(storedDigest, actualDigest, CC_SHA256_DIGEST_LENGTH) != 0) {
        [_fileManager removeItemAtPath:cachePath error:nil];
        return nil;
    }

    NSData *encodedData =
        [containerData subdataWithRange:NSMakeRange(kKayokoThumbnailContainerHeaderLength, actualEncodedLength)];
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)encodedData, NULL);
    if (!imageSource) {
        [_fileManager removeItemAtPath:cachePath error:nil];
        return nil;
    }

    if (CGImageSourceGetCount(imageSource) != 1 ||
        CGImageSourceGetStatusAtIndex(imageSource, 0) != kCGImageStatusComplete) {
        CFRelease(imageSource);
        [_fileManager removeItemAtPath:cachePath error:nil];
        return nil;
    }

    NSDictionary *options = @{
        (NSString *)kCGImageSourceShouldCache : @YES,
        (NSString *)kCGImageSourceShouldCacheImmediately : @YES,
    };
    CGImageRef imageRef = CGImageSourceCreateImageAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
    CFRelease(imageSource);
    if (!imageRef) {
        [_fileManager removeItemAtPath:cachePath error:nil];
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];
    CFRelease(imageRef);
    return image;
}

- (NSUInteger)maximumPixelSizeForImageProperties:(NSDictionary<NSString *, id> *)properties
                                      targetSize:(CGSize)targetSize
                                           scale:(CGFloat)scale {
    CGFloat targetPixelWidth = MAX(ceil(targetSize.width * scale), 1);
    CGFloat targetPixelHeight = MAX(ceil(targetSize.height * scale), 1);
    CGFloat imagePixelWidth = [properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat imagePixelHeight = [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    NSUInteger orientation = [properties[(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue];
    if (orientation >= 5 && orientation <= 8) {
        CGFloat swappedWidth = imagePixelHeight;
        imagePixelHeight = imagePixelWidth;
        imagePixelWidth = swappedWidth;
    }

    if (imagePixelWidth <= 0 || imagePixelHeight <= 0) {
        return (NSUInteger)ceil(MAX(targetPixelWidth, targetPixelHeight));
    }

    CGFloat fillScale = MAX(targetPixelWidth / imagePixelWidth, targetPixelHeight / imagePixelHeight);
    CGFloat thumbnailPixelWidth = imagePixelWidth * fillScale;
    CGFloat thumbnailPixelHeight = imagePixelHeight * fillScale;
    return (NSUInteger)ceil(MAX(thumbnailPixelWidth, thumbnailPixelHeight));
}

- (nullable UIImage *)generateThumbnailFromImagePath:(NSString *)imagePath
                                          targetSize:(CGSize)targetSize
                                               scale:(CGFloat)scale {
    NSURL *imageURL = [NSURL fileURLWithPath:imagePath];
    CGImageSourceRef imageSource = CGImageSourceCreateWithURL((__bridge CFURLRef)imageURL, NULL);
    if (!imageSource) {
        return nil;
    }

    NSDictionary<NSString *, id> *properties =
        CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL));
    NSUInteger maximumPixelSize = [self maximumPixelSizeForImageProperties:properties ?: @{}
                                                                targetSize:targetSize
                                                                     scale:scale];
    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform : @YES,
        (NSString *)kCGImageSourceShouldCacheImmediately : @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize : @(maximumPixelSize),
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
    CFRelease(imageSource);
    if (!thumbnail) {
        return nil;
    }

    UIImage *thumbnailImage = [UIImage imageWithCGImage:thumbnail scale:scale orientation:UIImageOrientationUp];
    CFRelease(thumbnail);
    return thumbnailImage;
}

- (BOOL)imageHasAlpha:(UIImage *)image {
    CGImageAlphaInfo alpha = CGImageGetAlphaInfo([image CGImage]);
    return alpha == kCGImageAlphaFirst || alpha == kCGImageAlphaLast || alpha == kCGImageAlphaPremultipliedFirst ||
           alpha == kCGImageAlphaPremultipliedLast;
}

- (void)persistThumbnailImage:(UIImage *)image atPath:(NSString *)cachePath {
    CGImageRef imageRef = [image CGImage];
    if (!imageRef) {
        return;
    }

    NSMutableData *encodedData = [[NSMutableData alloc] init];
    BOOL preservesAlpha = [self imageHasAlpha:image];
    NSString *typeIdentifier = preservesAlpha ? @"public.png" : @"public.jpeg";
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)encodedData,
                                                                         (__bridge CFStringRef)typeIdentifier, 1, NULL);
    if (!destination) {
        return;
    }

    NSDictionary *properties =
        preservesAlpha
            ? @{}
            : @{(NSString *)kCGImageDestinationLossyCompressionQuality : @(kKayokoThumbnailDiskCacheJPEGQuality)};
    CGImageDestinationAddImage(destination, imageRef, (__bridge CFDictionaryRef)properties);
    BOOL encoded = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    if (!encoded) {
        return;
    }

    if ([encodedData length] > kKayokoThumbnailContainerPayloadLimit) {
        return;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256([encodedData bytes], (CC_LONG)[encodedData length], digest);
    uint64_t encodedLengthBigEndian = CFSwapInt64HostToBig([encodedData length]);
    NSMutableData *containerData =
        [[NSMutableData alloc] initWithCapacity:kKayokoThumbnailContainerHeaderLength + [encodedData length]];
    [containerData appendBytes:kKayokoThumbnailContainerMagic length:sizeof(kKayokoThumbnailContainerMagic)];
    [containerData appendBytes:&encodedLengthBigEndian length:sizeof(encodedLengthBigEndian)];
    [containerData appendBytes:digest length:sizeof(digest)];
    [containerData appendData:encodedData];

    if (![_fileManager createDirectoryAtPath:_cacheDirectoryPath
                 withIntermediateDirectories:YES
                                  attributes:@{NSFilePosixPermissions : @0700}
                                       error:nil]) {
        return;
    }
    [containerData writeToFile:cachePath options:NSDataWritingAtomic error:nil];
}

- (BOOL)enqueueCompletion:(KayokoThumbnailCompletion)completion forRequestKey:(NSString *)requestKey {
    [_requestLock lock];
    UIImage *cachedThumbnail = [_memoryCache objectForKey:requestKey];
    if (cachedThumbnail) {
        [_requestLock unlock];
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(cachedThumbnail);
        });
        return NO;
    }

    NSMutableArray *completions = _completionsByRequestKey[requestKey];
    if (completions) {
        [completions addObject:[completion copy]];
        [_requestLock unlock];
        return NO;
    }

    _completionsByRequestKey[requestKey] = [NSMutableArray arrayWithObject:[completion copy]];
    [_requestLock unlock];
    return YES;
}

- (void)finishRequestForRequestKey:(NSString *)requestKey image:(nullable UIImage *)image {
    [_requestLock lock];
    NSArray *completions = [_completionsByRequestKey[requestKey] copy];
    [_completionsByRequestKey removeObjectForKey:requestKey];
    [_requestLock unlock];

    dispatch_async(dispatch_get_main_queue(), ^{
      for (KayokoThumbnailCompletion completion in completions) {
          completion(image);
      }
    });
}

- (void)thumbnailForImageName:(NSString *)imageName
                    imagePath:(NSString *)imagePath
                   targetSize:(CGSize)targetSize
                        scale:(CGFloat)scale
                   completion:(KayokoThumbnailCompletion)completion {
    if ([imageName length] == 0 || [imagePath length] == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
          completion(nil);
        });
        return;
    }

    // Stored image files are write-once and migrations rename collisions, so disk validation can stay off this path.
    NSString *requestKey = [self requestKeyForImageName:imageName targetSize:targetSize scale:scale];
    if (![self enqueueCompletion:completion forRequestKey:requestKey]) {
        return;
    }

    dispatch_async(_decodeQueue, ^{
      NSString *sourceFingerprint = [self sourceFingerprintForImagePath:imagePath];
      if ([sourceFingerprint length] == 0) {
          [self finishRequestForRequestKey:requestKey image:nil];
          return;
      }

      NSString *diskCacheKey = [self diskCacheKeyForRequestKey:requestKey sourceFingerprint:sourceFingerprint];
      NSString *cachePath =
          [_cacheDirectoryPath stringByAppendingPathComponent:[diskCacheKey stringByAppendingPathExtension:@"thumb"]];
      UIImage *thumbnailImage = [self loadThumbnailFromDiskAtPath:cachePath scale:scale];
      BOOL generatedFromSource = thumbnailImage == nil;
      if (!thumbnailImage) {
          thumbnailImage = [self generateThumbnailFromImagePath:imagePath targetSize:targetSize scale:scale];
      }
      NSString *currentFingerprint = [self sourceFingerprintForImagePath:imagePath];
      if (![currentFingerprint isEqualToString:sourceFingerprint]) {
          [self finishRequestForRequestKey:requestKey image:nil];
          return;
      }

      NSUInteger thumbnailCost = thumbnailImage ? [self memoryCostForImage:thumbnailImage] : 0;
      if (thumbnailImage) {
          [_memoryCache setObject:thumbnailImage forKey:requestKey cost:thumbnailCost];
      }
      [self finishRequestForRequestKey:requestKey image:thumbnailImage];

      if (thumbnailImage && generatedFromSource) {
          NSUInteger writeCost = MAX(thumbnailCost, 1);
          BOOL shouldPersist = NO;
          [_requestLock lock];
          if (_pendingWriteCount < kKayokoThumbnailPendingWriteCountLimit &&
              writeCost <= kKayokoThumbnailPendingWriteCostLimit - _pendingWriteCost) {
              _pendingWriteCount++;
              _pendingWriteCost += writeCost;
              shouldPersist = YES;
          }
          [_requestLock unlock];

          if (shouldPersist) {
              // Bound optional writes so rapid scrolling cannot retain an unbounded set of decoded images.
              dispatch_async(_writeQueue, ^{
                [self persistThumbnailImage:thumbnailImage atPath:cachePath];
                [_requestLock lock];
                _pendingWriteCount--;
                _pendingWriteCost -= writeCost;
                [_requestLock unlock];
              });
          }
      }
    });
}

- (void)removeAllMemoryCachedThumbnails {
    [_memoryCache removeAllObjects];
}

- (void)performWhenIdle:(dispatch_block_t)completion {
    dispatch_async(_decodeQueue, ^{
      dispatch_async(_writeQueue, ^{
        dispatch_async(dispatch_get_main_queue(), completion);
      });
    });
}

@end
