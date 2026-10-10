//
//  KayokoPurchaseAuthorization.m
//  Kayoko
//

#import "KayokoPurchaseAuthorization.h"

#import <HBLog.h>
#import <Security/Security.h>
#import <TargetConditionals.h>
#import <dlfcn.h>
#import <sys/sysctl.h>

NSString *const kKayokoPurchaseAuthorizationProductIdentifier = @"com.82flex.kayoko";

static NSString *const kKayokoPurchaseAuthorizationErrorDomain = @"com.82flex.kayoko.purchase-authorization";
static NSString *const kKayokoSileoAccessGroup = @"org.coolstar.Sileo";
static NSString *const kKayokoZebraCurrentAccessGroup = @"com.apple.mobilesafari";
static NSString *const kKayokoZebraLegacyAccessGroup = @"xyz.willy.Zebra";
static NSString *const kKayokoAppleAccessGroup = @"apple";
static NSString *const kKayokoSileoPaymentTokenService = @"SileoPaymentToken";
static NSString *const kKayokoZebraCurrentPaymentTokenService = @"com.getzbra.zebra2";
static NSString *const kKayokoZebraLegacyPaymentTokenService = @"xyz.willy.Zebra";
static NSString *const kKayokoCredentialMirrorService = @"com.82flex.kayoko.havoc-credential";
static NSString *const kKayokoCredentialMirrorAccount = @"sileo-havoc";
static NSString *const kKayokoAuthorizationFlagService = @"com.82flex.kayoko.authorization";
static NSString *const kKayokoAuthorizationFlagAccount = @"com.82flex.kayoko";
static NSString *const kKayokoHavocRepositoryURLString = @"https://havoc.app/";

static NSInteger const kKayokoPurchaseAuthorizationErrorKeychain = 1;
static NSInteger const kKayokoPurchaseAuthorizationErrorNoCredential = 2;
static NSInteger const kKayokoPurchaseAuthorizationErrorInvalidCredential = 3;

@class KayokoHavocCredential;

static NSError *KayokoAuthorizationError(NSInteger code, NSString *message);
static NSArray<NSDictionary *> *KayokoCopyKeychainItemAttributes(NSString *service, NSString *accessGroup,
                                                                 NSError **error);
static NSArray<NSDictionary *> *KayokoCopyKeychainItems(NSString *service, NSString *accessGroup, NSError **error);
static NSData *KayokoCopyKeychainData(NSString *service, NSString *account, NSString *accessGroup, NSError **error);
static BOOL KayokoDeleteKeychainItems(NSString *service, NSString *account, NSString *accessGroup, NSError **error);
static BOOL KayokoSaveKeychainData(NSData *data, NSString *service, NSString *account, NSString *accessGroup,
                                   NSError **error);
static KayokoHavocCredential *KayokoCopyMirroredCredential(NSError **error);
static KayokoHavocCredential *KayokoCreateHavocCredential(NSString *token, NSString *providerBaseURL,
                                                          BOOL providerEndpointNeedsResolution, NSString *source,
                                                          NSError **error);
static KayokoHavocCredential *KayokoCopySileoHavocCredential(NSError **error);
static KayokoHavocCredential *KayokoCopyZebraHavocCredential(NSError **error);
static BOOL KayokoSaveMirroredCredential(KayokoHavocCredential *credential, NSError **error);
static NSError *KayokoCombinedCredentialError(NSError *sileoError, NSError *zebraError);
static NSString *KayokoCredentialErrorMessage(NSError *error, NSString *fallback);
static void KayokoCheckPurchaseWithCredential(KayokoHavocCredential *credential,
                                              void (^completion)(KayokoPurchaseAuthorizationResult *result));
static void KayokoCheckPurchaseWithProviderBaseURL(KayokoHavocCredential *credential, NSString *providerBaseURL,
                                                   void (^completion)(KayokoPurchaseAuthorizationResult *result));
static void KayokoFetchPaymentEndpointForRepositoryURL(NSString *repositoryURLString,
                                                       void (^completion)(NSString *endpoint, NSError *error,
                                                                          NSInteger statusCode,
                                                                          NSString *statusMessage));
static NSDictionary *KayokoSelectSileoTokenItem(NSArray<NSDictionary *> *tokenItems, NSString *endpoint);
static NSDictionary *KayokoCopyZebraTokenItem(NSString *service, NSString *accessGroup, NSString *endpoint,
                                              NSError **error);
static NSDictionary *KayokoSelectZebraTokenItem(NSArray<NSDictionary *> *tokenItems, NSString *endpoint);
static NSString *KayokoNormalizeProviderBaseURL(NSString *URLString);
static NSArray<NSString *> *KayokoZebraCandidateAccounts(NSString *endpoint);
static BOOL KayokoProviderAccountLooksLikeHavoc(NSString *account);
static BOOL KayokoProviderBaseURLNeedsEndpointResolution(NSString *providerBaseURL);
static BOOL KayokoZebraTokenAccountIsPaymentSecret(NSString *account);
static NSString *KayokoCopyUniqueDeviceIdentifier(void);
static NSString *KayokoCopyHardwareMachine(void);
static NSString *KayokoHTTPStatusMessage(NSInteger statusCode);

@interface KayokoHavocCredential : NSObject
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) NSString *providerBaseURL;
@property(nonatomic, copy) NSString *udid;
@property(nonatomic, copy) NSString *device;
@property(nonatomic, copy) NSString *source;
@property(nonatomic, assign) BOOL providerEndpointNeedsResolution;
@property(nonatomic, strong) NSDate *syncedAt;
@end

@implementation KayokoHavocCredential
@end

@implementation KayokoPurchaseAuthorizationResult

#pragma mark - Lifecycle

- (instancetype)initWithState:(KayokoPurchaseAuthorizationState)state
                        error:(NSError *)error
                   statusCode:(NSInteger)statusCode
                statusMessage:(NSString *)statusMessage {
    self = [super init];
    if (self) {
        _state = state;
        _error = error;
        _statusCode = statusCode;
        _statusMessage = [statusMessage copy];
    }
    return self;
}

@end

@implementation KayokoPurchaseAuthorization

#pragma mark - Credential Mirroring

+ (BOOL)mirrorHavocCredentialToAppleAccessGroupWithError:(NSError **)error {
    return [self mirrorHavocCredentialToAppleAccessGroupWithSource:nil error:error];
}

+ (BOOL)mirrorHavocCredentialToAppleAccessGroupWithSource:(NSString *_Nullable *_Nullable)source
                                                    error:(NSError **)error {
#if TARGET_OS_SIMULATOR
    if (source) {
        *source = @"simulator";
    }
    return YES;
#endif
    if (source) {
        *source = nil;
    }

    NSError *sileoError = nil;
    KayokoHavocCredential *credential = KayokoCopySileoHavocCredential(&sileoError);
    if (!credential) {
        NSError *zebraError = nil;
        credential = KayokoCopyZebraHavocCredential(&zebraError);
        if (!credential) {
            if (error) {
                *error = KayokoCombinedCredentialError(sileoError, zebraError);
            }
            return NO;
        }
    }

    if (!KayokoSaveMirroredCredential(credential, error)) {
        return NO;
    }

    if (source) {
        *source = [credential.source copy];
    }
    return YES;
}

+ (BOOL)mirrorSileoHavocCredentialToAppleAccessGroupWithError:(NSError **)error {
#if TARGET_OS_SIMULATOR
    return YES;
#endif
    KayokoHavocCredential *credential = KayokoCopySileoHavocCredential(error);
    if (!credential) {
        return NO;
    }

    return KayokoSaveMirroredCredential(credential, error);
}

#pragma mark - Authorization State

+ (BOOL)hasAuthorizationPassFlagWithError:(NSError **)error {
#if DEBUG || TARGET_OS_SIMULATOR
    HBLogDebug(@"Kayoko: Havoc authorization check bypassed for debug/simulator build");
    return YES;
#else
    NSData *flagData = KayokoCopyKeychainData(kKayokoAuthorizationFlagService, kKayokoAuthorizationFlagAccount,
                                              kKayokoAppleAccessGroup, error);
    return [flagData length] > 0;
#endif
}

+ (BOOL)setAuthorizationPassFlagWithError:(NSError **)error {
#if TARGET_OS_SIMULATOR
    return YES;
#endif
    NSData *flagData = [kKayokoPurchaseAuthorizationProductIdentifier dataUsingEncoding:NSUTF8StringEncoding];
    return KayokoSaveKeychainData(flagData, kKayokoAuthorizationFlagService, kKayokoAuthorizationFlagAccount,
                                  kKayokoAppleAccessGroup, error);
}

+ (BOOL)clearAuthorizationStateWithError:(NSError **)error {
#if TARGET_OS_SIMULATOR
    return YES;
#endif
    if (!KayokoDeleteKeychainItems(kKayokoCredentialMirrorService, nil, kKayokoAppleAccessGroup, error)) {
        return NO;
    }

    return KayokoDeleteKeychainItems(kKayokoAuthorizationFlagService, nil, kKayokoAppleAccessGroup, error);
}

#pragma mark - Purchase Check

+ (void)checkMirroredPurchaseWithCompletion:(void (^)(KayokoPurchaseAuthorizationResult *result))completion {
#if TARGET_OS_SIMULATOR
    completion([[KayokoPurchaseAuthorizationResult alloc] initWithState:KayokoPurchaseAuthorizationStatePurchased
                                                                 error:nil
                                                            statusCode:200
                                                         statusMessage:nil]);
    return;
#endif
    HBLogDebug(@"Kayoko: Havoc authorization check started");

    NSError *credentialError = nil;
    KayokoHavocCredential *credential = KayokoCopyMirroredCredential(&credentialError);
    if (!credential) {
        HBLogDebug(@"Kayoko: Havoc authorization check missing mirrored credential error=%@", credentialError);
        KayokoPurchaseAuthorizationResult *result =
            [[KayokoPurchaseAuthorizationResult alloc] initWithState:KayokoPurchaseAuthorizationStateMissingCredential
                                                               error:credentialError
                                                          statusCode:0
                                                       statusMessage:nil];
        completion(result);
        return;
    }

    HBLogDebug(@"Kayoko: Havoc authorization using mirrored credential source=%@ providerBaseURL=%@ "
               @"needsEndpointResolution=%@",
               credential.source ?: @"unknown", credential.providerBaseURL,
               credential.providerEndpointNeedsResolution ? @"YES" : @"NO");
    KayokoCheckPurchaseWithCredential(credential, completion);
}

@end

#pragma mark - Errors

static NSError *KayokoAuthorizationError(NSInteger code, NSString *message) {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : message ?: @"Kayoko authorization failed."};
    return [NSError errorWithDomain:kKayokoPurchaseAuthorizationErrorDomain code:code userInfo:userInfo];
}

static NSError *KayokoCombinedCredentialError(NSError *sileoError, NSError *zebraError) {
    NSString *sileoMessage = KayokoCredentialErrorMessage(sileoError, @"not found");
    NSString *zebraMessage = KayokoCredentialErrorMessage(zebraError, @"not found");
    NSString *message = [NSString
        stringWithFormat:@"Unable to find a Havoc payment token (Sileo: %@; Zebra: %@).", sileoMessage, zebraMessage];
    return KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorNoCredential, message);
}

static NSString *KayokoCredentialErrorMessage(NSError *error, NSString *fallback) {
    NSString *message = [error localizedDescription] ?: fallback;
    message = [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    while ([message hasSuffix:@"."]) {
        message = [message substringToIndex:[message length] - 1];
    }
    return [message length] > 0 ? message : fallback;
}

#pragma mark - Purchase Check

static void KayokoCheckPurchaseWithCredential(KayokoHavocCredential *credential,
                                              void (^completion)(KayokoPurchaseAuthorizationResult *result)) {
    if (!credential.providerEndpointNeedsResolution) {
        KayokoCheckPurchaseWithProviderBaseURL(credential, credential.providerBaseURL, completion);
        return;
    }

    HBLogDebug(@"Kayoko: Havoc authorization resolving payment endpoint repositoryURL=%@", credential.providerBaseURL);
    NSURL *repositoryURL = [NSURL URLWithString:credential.providerBaseURL];
    if (!repositoryURL) {
        HBLogDebug(@"Kayoko: Havoc authorization cannot resolve endpoint because repositoryURL is invalid");
        KayokoPurchaseAuthorizationResult *result =
            [[KayokoPurchaseAuthorizationResult alloc] initWithState:KayokoPurchaseAuthorizationStateMissingCredential
                                                               error:nil
                                                          statusCode:0
                                                       statusMessage:nil];
        completion(result);
        return;
    }

    KayokoFetchPaymentEndpointForRepositoryURL(
        credential.providerBaseURL,
        ^(NSString *endpoint, NSError *error, NSInteger statusCode, NSString *statusMessage) {
          if ([endpoint length] == 0) {
              HBLogDebug(@"Kayoko: Havoc authorization endpoint resolution failed status=%ld statusMessage=%@ "
                         @"error=%@",
                         (long)statusCode, statusMessage, error);
              KayokoPurchaseAuthorizationState state = error ? KayokoPurchaseAuthorizationStateNetworkFailed
                                                             : KayokoPurchaseAuthorizationStateInvalidResponse;
              KayokoPurchaseAuthorizationResult *result =
                  [[KayokoPurchaseAuthorizationResult alloc] initWithState:state
                                                                     error:error
                                                                statusCode:statusCode
                                                             statusMessage:statusMessage];
              completion(result);
              return;
          }

          HBLogDebug(@"Kayoko: Havoc authorization resolved payment endpoint=%@", endpoint);
          KayokoCheckPurchaseWithProviderBaseURL(credential, endpoint, completion);
        });
}

static void KayokoCheckPurchaseWithProviderBaseURL(KayokoHavocCredential *credential, NSString *providerBaseURL,
                                                   void (^completion)(KayokoPurchaseAuthorizationResult *result)) {
    NSURL *baseURL = [NSURL URLWithString:providerBaseURL];
    NSURL *requestURL = [baseURL URLByAppendingPathComponent:@"user_info"];
    if (!requestURL) {
        HBLogDebug(@"Kayoko: Havoc authorization cannot create user_info URL providerBaseURL=%@", providerBaseURL);
        KayokoPurchaseAuthorizationResult *result =
            [[KayokoPurchaseAuthorizationResult alloc] initWithState:KayokoPurchaseAuthorizationStateMissingCredential
                                                               error:nil
                                                          statusCode:0
                                                       statusMessage:nil];
        completion(result);
        return;
    }

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:requestURL
                                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                            timeoutInterval:15.0];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{@"token" : credential.token, @"udid" : credential.udid, @"device" : credential.device};
    NSError *bodyError = nil;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&bodyError];
    if (!bodyData) {
        HBLogDebug(@"Kayoko: Havoc authorization failed to serialize user_info request body error=%@", bodyError);
        KayokoPurchaseAuthorizationResult *result =
            [[KayokoPurchaseAuthorizationResult alloc] initWithState:KayokoPurchaseAuthorizationStateInvalidResponse
                                                               error:bodyError
                                                          statusCode:0
                                                       statusMessage:nil];
        completion(result);
        return;
    }
    [request setHTTPBody:bodyData];

    HBLogDebug(@"Kayoko: Havoc authorization sending user_info request URL=%@ source=%@", requestURL,
               credential.source ?: @"unknown");
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                HBLogDebug(@"Kayoko: Havoc authorization user_info request failed error=%@", error);
                KayokoPurchaseAuthorizationResult *result = [[KayokoPurchaseAuthorizationResult alloc]
                    initWithState:KayokoPurchaseAuthorizationStateNetworkFailed
                            error:error
                       statusCode:0
                    statusMessage:nil];
                completion(result);
                return;
            }

            NSHTTPURLResponse *HTTPResponse =
                [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
            NSInteger statusCode = [HTTPResponse statusCode];
            NSString *statusMessage = KayokoHTTPStatusMessage(statusCode);
            if (statusCode < 200 || statusCode >= 300 || !data) {
                HBLogDebug(@"Kayoko: Havoc authorization user_info invalid HTTP response status=%ld "
                           @"statusMessage=%@ hasData=%@",
                           (long)statusCode, statusMessage, data ? @"YES" : @"NO");
                KayokoPurchaseAuthorizationResult *result = [[KayokoPurchaseAuthorizationResult alloc]
                    initWithState:KayokoPurchaseAuthorizationStateInvalidResponse
                            error:nil
                       statusCode:statusCode
                    statusMessage:statusMessage];
                completion(result);
                return;
            }

            NSError *JSONError = nil;
            id JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
            NSDictionary *dictionary = [JSON isKindOfClass:[NSDictionary class]] ? JSON : nil;
            NSArray *items = [dictionary[@"items"] isKindOfClass:[NSArray class]] ? dictionary[@"items"] : nil;
            if (!dictionary || !items) {
                HBLogDebug(@"Kayoko: Havoc authorization user_info JSON invalid status=%ld "
                           @"statusMessage=%@ error=%@ JSONClass=%@",
                           (long)statusCode, statusMessage, JSONError, NSStringFromClass([JSON class]));
                KayokoPurchaseAuthorizationResult *result = [[KayokoPurchaseAuthorizationResult alloc]
                    initWithState:KayokoPurchaseAuthorizationStateInvalidResponse
                            error:JSONError
                       statusCode:statusCode
                    statusMessage:statusMessage];
                completion(result);
                return;
            }

            NSMutableArray<NSString *> *productIdentifiers = [[NSMutableArray alloc] init];
            for (id item in items) {
                if ([item isKindOfClass:[NSString class]]) {
                    [productIdentifiers addObject:item];
                }
            }
            HBLogDebug(@"Kayoko: Havoc authorization purchased product identifiers=%@", productIdentifiers);

            BOOL purchased = NO;
            for (NSString *productIdentifier in productIdentifiers) {
                if ([productIdentifier isEqualToString:kKayokoPurchaseAuthorizationProductIdentifier]) {
                    purchased = YES;
                    break;
                }
            }
            HBLogDebug(@"Kayoko: Havoc authorization product %@ purchased=%@",
                       kKayokoPurchaseAuthorizationProductIdentifier, purchased ? @"YES" : @"NO");

            KayokoPurchaseAuthorizationResult *result = [[KayokoPurchaseAuthorizationResult alloc]
                initWithState:purchased ? KayokoPurchaseAuthorizationStatePurchased
                                        : KayokoPurchaseAuthorizationStateNotPurchased
                        error:nil
                   statusCode:statusCode
                statusMessage:statusMessage];
            completion(result);
          }];
    [task resume];
}

#pragma mark - Keychain

static NSMutableDictionary *KayokoKeychainQuery(NSString *service, NSString *account, NSString *accessGroup) {
    NSMutableDictionary *query = [@{
        (__bridge NSString *)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge NSString *)kSecAttrService : service
    } mutableCopy];
    if ([account length] > 0) {
        query[(__bridge NSString *)kSecAttrAccount] = account;
    }
    if ([accessGroup length] > 0) {
        query[(__bridge NSString *)kSecAttrAccessGroup] = accessGroup;
    }
    return query;
}

static NSData *KayokoCopyKeychainData(NSString *service, NSString *account, NSString *accessGroup, NSError **error) {
    NSMutableDictionary *query = KayokoKeychainQuery(service, account, accessGroup);
    query[(__bridge NSString *)kSecReturnData] = @YES;
    query[(__bridge NSString *)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        if (error && status != errSecItemNotFound) {
            *error = KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorKeychain,
                                              [NSString stringWithFormat:@"Keychain read failed: %d", (int)status]);
        }
        if (result) {
            CFRelease(result);
        }
        return nil;
    }

    NSData *data = [(__bridge NSData *)result copy];
    if (result) {
        CFRelease(result);
    }
    return data;
}

static NSArray<NSDictionary *> *KayokoCopyKeychainItemAttributes(NSString *service, NSString *accessGroup,
                                                                 NSError **error) {
    NSMutableDictionary *query = KayokoKeychainQuery(service, nil, accessGroup);
    query[(__bridge NSString *)kSecReturnAttributes] = @YES;
    query[(__bridge NSString *)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        if (error && status != errSecItemNotFound) {
            *error =
                KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorKeychain,
                                         [NSString stringWithFormat:@"Keychain attributes failed: %d", (int)status]);
        }
        if (result) {
            CFRelease(result);
        }
        return @[];
    }

    NSArray *items = [(__bridge NSArray *)result copy];
    if (result) {
        CFRelease(result);
    }
    return [items isKindOfClass:[NSArray class]] ? items : @[];
}

static NSArray<NSDictionary *> *KayokoCopyKeychainItems(NSString *service, NSString *accessGroup, NSError **error) {
    NSMutableDictionary *query = KayokoKeychainQuery(service, nil, accessGroup);
    query[(__bridge NSString *)kSecReturnAttributes] = @YES;
    query[(__bridge NSString *)kSecReturnData] = @YES;
    query[(__bridge NSString *)kSecMatchLimit] = (__bridge id)kSecMatchLimitAll;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) {
        if (error && status != errSecItemNotFound) {
            *error =
                KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorKeychain,
                                         [NSString stringWithFormat:@"Keychain enumeration failed: %d", (int)status]);
        }
        if (result) {
            CFRelease(result);
        }
        return @[];
    }

    NSArray *items = [(__bridge NSArray *)result copy];
    if (result) {
        CFRelease(result);
    }
    return [items isKindOfClass:[NSArray class]] ? items : @[];
}

static BOOL KayokoDeleteKeychainItems(NSString *service, NSString *account, NSString *accessGroup, NSError **error) {
    NSMutableDictionary *deleteQuery = KayokoKeychainQuery(service, account, accessGroup);
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)deleteQuery);
    if (status != errSecSuccess && status != errSecItemNotFound) {
        if (error) {
            *error = KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorKeychain,
                                              [NSString stringWithFormat:@"Keychain delete failed: %d", (int)status]);
        }
        return NO;
    }
    return YES;
}

static BOOL KayokoSaveKeychainData(NSData *data, NSString *service, NSString *account, NSString *accessGroup,
                                   NSError **error) {
    NSMutableDictionary *deleteQuery = KayokoKeychainQuery(service, account, accessGroup);
    SecItemDelete((__bridge CFDictionaryRef)deleteQuery);

    NSMutableDictionary *addQuery = KayokoKeychainQuery(service, account, accessGroup);
    addQuery[(__bridge NSString *)kSecValueData] = data;
    addQuery[(__bridge NSString *)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    addQuery[(__bridge NSString *)kSecAttrSynchronizable] = @NO;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, nil);
    if (status != errSecSuccess) {
        if (error) {
            *error = KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorKeychain,
                                              [NSString stringWithFormat:@"Keychain write failed: %d", (int)status]);
        }
        return NO;
    }
    return YES;
}

#pragma mark - Credentials

static KayokoHavocCredential *KayokoCreateHavocCredential(NSString *token, NSString *providerBaseURL,
                                                          BOOL providerEndpointNeedsResolution, NSString *source,
                                                          NSError **error) {
    NSString *udid = KayokoCopyUniqueDeviceIdentifier();
    NSString *device = KayokoCopyHardwareMachine();
    if ([providerBaseURL length] == 0 || [token length] == 0 || [udid length] == 0 || [device length] == 0) {
        if (error) {
            *error = KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorInvalidCredential,
                                              @"The Havoc credential is incomplete.");
        }
        return nil;
    }

    KayokoHavocCredential *credential = [[KayokoHavocCredential alloc] init];
    credential.token = token;
    credential.providerBaseURL = KayokoNormalizeProviderBaseURL(providerBaseURL);
    credential.udid = udid;
    credential.device = device;
    credential.source = source;
    credential.providerEndpointNeedsResolution = providerEndpointNeedsResolution;
    credential.syncedAt = [NSDate date];
    return credential;
}

static KayokoHavocCredential *KayokoCopySileoHavocCredential(NSError **error) {
    NSArray<NSDictionary *> *tokenItems =
        KayokoCopyKeychainItems(kKayokoSileoPaymentTokenService, kKayokoSileoAccessGroup, error);
    if ([tokenItems count] == 0) {
        if (error && !*error) {
            *error = KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorNoCredential,
                                              @"No Sileo payment token was found.");
        }
        return nil;
    }

    NSDictionary *selectedItem = KayokoSelectSileoTokenItem(tokenItems, nil);
    if (!selectedItem) {
        if (error) {
            *error = KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorNoCredential,
                                              @"No Havoc payment token was found in Sileo.");
        }
        return nil;
    }

    NSString *providerBaseURL = selectedItem[(__bridge NSString *)kSecAttrAccount];
    NSData *tokenData = selectedItem[(__bridge NSString *)kSecValueData];
    NSString *token = [[NSString alloc] initWithData:tokenData encoding:NSUTF8StringEncoding];
    return KayokoCreateHavocCredential(token, providerBaseURL, NO, @"sileo", error);
}

static KayokoHavocCredential *KayokoCopyZebraHavocCredential(NSError **error) {
    NSArray<NSString *> *accessGroups = @[ kKayokoZebraCurrentAccessGroup, kKayokoZebraLegacyAccessGroup ];
    NSArray<NSString *> *services = @[ kKayokoZebraCurrentPaymentTokenService, kKayokoZebraLegacyPaymentTokenService ];
    NSError *lastError = nil;
    for (NSString *accessGroup in accessGroups) {
        for (NSString *service in services) {
            NSError *tokenError = nil;
            NSDictionary *selectedItem = KayokoCopyZebraTokenItem(service, accessGroup, nil, &tokenError);
            if (!selectedItem) {
                lastError = tokenError ?: lastError;
                continue;
            }

            NSString *account = selectedItem[(__bridge NSString *)kSecAttrAccount];
            NSData *tokenData = selectedItem[(__bridge NSString *)kSecValueData];
            NSString *token = [[NSString alloc] initWithData:tokenData encoding:NSUTF8StringEncoding];
            BOOL needsEndpointResolution = KayokoProviderBaseURLNeedsEndpointResolution(account);
            return KayokoCreateHavocCredential(token, account, needsEndpointResolution, @"zebra", error);
        }
    }

    if (error) {
        *error = lastError
                     ?: KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorNoCredential,
                                                 @"No Havoc payment token was found in Zebra.");
    }
    return nil;
}

static BOOL KayokoSaveMirroredCredential(KayokoHavocCredential *credential, NSError **error) {
    NSMutableDictionary *payload = [@{
        @"token" : credential.token,
        @"providerBaseURL" : KayokoNormalizeProviderBaseURL(credential.providerBaseURL),
        @"udid" : credential.udid,
        @"device" : credential.device,
        @"providerEndpointNeedsResolution" : @(credential.providerEndpointNeedsResolution),
        @"syncedAt" : @([credential.syncedAt timeIntervalSince1970])
    } mutableCopy];
    if ([credential.source length] > 0) {
        payload[@"source"] = credential.source;
    }

    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:error];
    if (!payloadData) {
        return NO;
    }

    return KayokoSaveKeychainData(payloadData, kKayokoCredentialMirrorService, kKayokoCredentialMirrorAccount,
                                  kKayokoAppleAccessGroup, error);
}

static KayokoHavocCredential *KayokoCopyMirroredCredential(NSError **error) {
    NSData *data = KayokoCopyKeychainData(kKayokoCredentialMirrorService, kKayokoCredentialMirrorAccount,
                                          kKayokoAppleAccessGroup, error);
    if (!data) {
        if (error && !*error) {
            *error = KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorNoCredential,
                                              @"No mirrored Havoc credential was found.");
        }
        return nil;
    }

    NSError *JSONError = nil;
    id JSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:&JSONError];
    NSDictionary *dictionary = [JSON isKindOfClass:[NSDictionary class]] ? JSON : nil;
    NSString *token = [dictionary[@"token"] isKindOfClass:[NSString class]] ? dictionary[@"token"] : nil;
    NSString *providerBaseURL =
        [dictionary[@"providerBaseURL"] isKindOfClass:[NSString class]] ? dictionary[@"providerBaseURL"] : nil;
    NSString *udid = [dictionary[@"udid"] isKindOfClass:[NSString class]] ? dictionary[@"udid"] : nil;
    NSString *device = [dictionary[@"device"] isKindOfClass:[NSString class]] ? dictionary[@"device"] : nil;
    NSNumber *syncedAt = [dictionary[@"syncedAt"] isKindOfClass:[NSNumber class]] ? dictionary[@"syncedAt"] : nil;
    NSString *source = [dictionary[@"source"] isKindOfClass:[NSString class]] ? dictionary[@"source"] : nil;
    NSNumber *providerEndpointNeedsResolution =
        [dictionary[@"providerEndpointNeedsResolution"] isKindOfClass:[NSNumber class]]
            ? dictionary[@"providerEndpointNeedsResolution"]
            : nil;

    if ([token length] == 0 || [providerBaseURL length] == 0 || [udid length] == 0 || [device length] == 0) {
        if (error) {
            *error = JSONError
                         ?: KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorInvalidCredential,
                                                     @"The mirrored Havoc credential is incomplete.");
        }
        return nil;
    }

    KayokoHavocCredential *credential = [[KayokoHavocCredential alloc] init];
    credential.token = token;
    credential.providerBaseURL = KayokoNormalizeProviderBaseURL(providerBaseURL);
    credential.udid = udid;
    credential.device = device;
    credential.source = source;
    credential.providerEndpointNeedsResolution = [providerEndpointNeedsResolution boolValue];
    credential.syncedAt = [NSDate dateWithTimeIntervalSince1970:[syncedAt doubleValue]];
    return credential;
}

static NSDictionary *KayokoSelectSileoTokenItem(NSArray<NSDictionary *> *tokenItems, NSString *endpoint) {
    NSString *normalizedEndpoint = KayokoNormalizeProviderBaseURL(endpoint);
    for (NSDictionary *item in tokenItems) {
        NSString *account = item[(__bridge NSString *)kSecAttrAccount];
        if ([KayokoNormalizeProviderBaseURL(account) isEqualToString:normalizedEndpoint]) {
            return item;
        }
    }

    NSMutableArray<NSDictionary *> *havocCandidates = [[NSMutableArray alloc] init];
    for (NSDictionary *item in tokenItems) {
        NSString *account = item[(__bridge NSString *)kSecAttrAccount];
        if (KayokoProviderAccountLooksLikeHavoc(account)) {
            [havocCandidates addObject:item];
        }
    }
    return [havocCandidates count] == 1 ? [havocCandidates firstObject] : nil;
}

static NSDictionary *KayokoCopyZebraTokenItem(NSString *service, NSString *accessGroup, NSString *endpoint,
                                              NSError **error) {
    NSError *directError = nil;
    for (NSString *account in KayokoZebraCandidateAccounts(endpoint)) {
        NSData *tokenData = KayokoCopyKeychainData(service, account, accessGroup, &directError);
        if ([tokenData length] > 0) {
            return @{(__bridge NSString *)kSecAttrAccount : account, (__bridge NSString *)kSecValueData : tokenData};
        }
    }

    NSError *attributesError = nil;
    NSArray<NSDictionary *> *tokenItems = KayokoCopyKeychainItemAttributes(service, accessGroup, &attributesError);
    NSDictionary *selectedItem = KayokoSelectZebraTokenItem(tokenItems, endpoint);
    if (!selectedItem) {
        if (error) {
            *error = attributesError ?: directError;
        }
        return nil;
    }

    NSString *account = selectedItem[(__bridge NSString *)kSecAttrAccount];
    NSError *dataError = nil;
    NSData *tokenData = KayokoCopyKeychainData(service, account, accessGroup, &dataError);
    if ([tokenData length] == 0) {
        if (error) {
            *error = dataError
                         ?: KayokoAuthorizationError(kKayokoPurchaseAuthorizationErrorNoCredential,
                                                     @"The selected Zebra Havoc token was empty.");
        }
        return nil;
    }

    NSMutableDictionary *item = [selectedItem mutableCopy];
    item[(__bridge NSString *)kSecValueData] = tokenData;
    return item;
}

static NSDictionary *KayokoSelectZebraTokenItem(NSArray<NSDictionary *> *tokenItems, NSString *endpoint) {
    NSString *normalizedEndpoint = KayokoNormalizeProviderBaseURL(endpoint);
    NSString *normalizedRepository = KayokoNormalizeProviderBaseURL(kKayokoHavocRepositoryURLString);
    for (NSDictionary *item in tokenItems) {
        NSString *account = item[(__bridge NSString *)kSecAttrAccount];
        if (KayokoZebraTokenAccountIsPaymentSecret(account)) {
            continue;
        }
        NSString *normalizedAccount = KayokoNormalizeProviderBaseURL(account);
        if ([normalizedAccount isEqualToString:normalizedEndpoint] ||
            [normalizedAccount isEqualToString:normalizedRepository]) {
            return item;
        }
    }

    NSMutableArray<NSDictionary *> *havocCandidates = [[NSMutableArray alloc] init];
    for (NSDictionary *item in tokenItems) {
        NSString *account = item[(__bridge NSString *)kSecAttrAccount];
        if (!KayokoZebraTokenAccountIsPaymentSecret(account) && KayokoProviderAccountLooksLikeHavoc(account)) {
            [havocCandidates addObject:item];
        }
    }
    return [havocCandidates count] == 1 ? [havocCandidates firstObject] : nil;
}

#pragma mark - Havoc Endpoint

static void KayokoFetchPaymentEndpointForRepositoryURL(NSString *repositoryURLString,
                                                       void (^completion)(NSString *endpoint, NSError *error,
                                                                          NSInteger statusCode,
                                                                          NSString *statusMessage)) {
    NSURL *baseURL = [NSURL URLWithString:repositoryURLString];
    NSURL *URL = [baseURL URLByAppendingPathComponent:@"payment_endpoint"];
    if (!URL) {
        completion(nil, nil, 0, nil);
        return;
    }

    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] initWithURL:URL
                                                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                            timeoutInterval:8.0];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *HTTPResponse =
                [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
            if (error) {
                completion(nil, error, 0, nil);
                return;
            }

            NSInteger statusCode = [HTTPResponse statusCode];
            NSString *statusMessage = KayokoHTTPStatusMessage(statusCode);
            if (statusCode < 200 || statusCode >= 300 || !data) {
                completion(nil, nil, statusCode, statusMessage);
                return;
            }

            NSString *endpoint = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            endpoint = [endpoint stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([endpoint length] == 0 || ![NSURL URLWithString:endpoint]) {
                completion(nil, nil, statusCode, statusMessage);
                return;
            }

            completion(endpoint, nil, statusCode, statusMessage);
          }];
    [task resume];
}

static NSString *KayokoNormalizeProviderBaseURL(NSString *URLString) {
    NSString *normalized =
        [URLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([normalized length] > 0 && ![normalized hasSuffix:@"/"]) {
        normalized = [normalized stringByAppendingString:@"/"];
    }
    return normalized ?: @"";
}

static NSArray<NSString *> *KayokoZebraCandidateAccounts(NSString *endpoint) {
    NSMutableArray<NSString *> *accounts = [[NSMutableArray alloc] init];
    void (^addAccount)(NSString *) = ^(NSString *account) {
      NSString *trimmed = [account stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([trimmed length] == 0 || [accounts containsObject:trimmed]) {
          return;
      }
      [accounts addObject:trimmed];
    };

    addAccount(kKayokoHavocRepositoryURLString);
    addAccount([kKayokoHavocRepositoryURLString
        stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]]);
    addAccount(endpoint);
    addAccount(KayokoNormalizeProviderBaseURL(endpoint));
    return accounts;
}

static BOOL KayokoProviderAccountLooksLikeHavoc(NSString *account) {
    NSURL *URL = [NSURL URLWithString:account];
    NSString *host = [[URL host] lowercaseString];
    return [host containsString:@"havoc"] || [[account lowercaseString] containsString:@"havoc"];
}

static BOOL KayokoProviderBaseURLNeedsEndpointResolution(NSString *providerBaseURL) {
    NSString *normalizedProviderBaseURL = KayokoNormalizeProviderBaseURL(providerBaseURL);
    NSString *normalizedRepositoryURL = KayokoNormalizeProviderBaseURL(kKayokoHavocRepositoryURLString);
    return [normalizedProviderBaseURL isEqualToString:normalizedRepositoryURL];
}

static BOOL KayokoZebraTokenAccountIsPaymentSecret(NSString *account) {
    NSString *trimmed = [account stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [[trimmed lowercaseString] hasSuffix:@"payment"];
}

#pragma mark - Device Identity

static NSString *KayokoCopyUniqueDeviceIdentifier(void) {
    void *gestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_GLOBAL | RTLD_LAZY);
    if (!gestalt) {
        return nil;
    }
    typedef CFTypeRef (*MGCopyAnswerFunc)(CFStringRef);
    MGCopyAnswerFunc MGCopyAnswer = (MGCopyAnswerFunc)dlsym(gestalt, "MGCopyAnswer");
    if (!MGCopyAnswer) {
        return nil;
    }
    CFTypeRef value = MGCopyAnswer(CFSTR("UniqueDeviceID"));
    NSString *identifier =
        [(__bridge id)value isKindOfClass:[NSString class]] ? [(__bridge NSString *)value copy] : nil;
    if (value) {
        CFRelease(value);
    }
    return identifier;
}

static NSString *KayokoCopyHardwareMachine(void) {
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) != 0 || size == 0) {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:size];
    if (sysctlbyname("hw.machine", [data mutableBytes], &size, NULL, 0) != 0) {
        return nil;
    }
    return [NSString stringWithUTF8String:[data bytes]];
}

#pragma mark - HTTP

static NSString *KayokoHTTPStatusMessage(NSInteger statusCode) {
    if (statusCode <= 0) {
        return nil;
    }

    NSString *localized = [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
    NSString *message = [localized length] > 0 ? [localized capitalizedString] : @"HTTP Error";
    return [NSString stringWithFormat:@"%ld %@", (long)statusCode, message];
}
