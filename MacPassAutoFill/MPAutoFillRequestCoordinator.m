#import "MPAutoFillRequestCoordinator.h"

#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/SecTask.h>

#import "MPAutoFillConstants.h"
#import "MPAutoFillCredentialIdentifier.h"
#import "MPAutoFillCredentialRecord.h"
#import "MPAutoFillEnvelopeCrypto.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillGenerationStore.h"
#import "MPAutoFillKeychainStore.h"
#import "MPAutoFillServiceMatcher.h"
#import "MPAutoFillSnapshot.h"
#import "MPAutoFillVaultIndex.h"

static BOOL MPAutoFillRegistryInteger(id value) {
  if (![value isKindOfClass:NSNumber.class]) return NO;
  double number = [value doubleValue];
  return isfinite(number) && floor(number) == number;
}

@interface MPAutoFillCredentialSelection ()
@property(nonatomic, readwrite, copy) NSString *title;
@property(nonatomic, readwrite, copy) NSString *username;
@property(nonatomic, readwrite, strong) ASPasswordCredential *credential;
@property(nonatomic, readwrite) int64_t rank;
@property(nonatomic, readwrite) NSUInteger serviceOrder;
@end

@implementation MPAutoFillCredentialSelection
@end

@interface MPAutoFillRequestCoordinator ()
@property(nonatomic, strong) MPAutoFillGenerationStore *generationStore;
@property(nonatomic, strong) id<MPAutoFillPrivateKeyStore> keychainStore;
@property(nonatomic, strong) NSURL *rootURL;
@end

@implementation MPAutoFillRequestCoordinator

+ (instancetype)sharedCoordinator {
  static MPAutoFillRequestCoordinator *coordinator;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    SecTaskRef task = SecTaskCreateFromSelf(NULL);
    NSString *applicationIdentifier = task ? CFBridgingRelease(SecTaskCopyValueForEntitlement(
        task, CFSTR("com.apple.application-identifier"), NULL)) : nil;
    if (task) CFRelease(task);
    NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    NSRange bundleRange = [applicationIdentifier rangeOfString:bundleIdentifier options:NSBackwardsSearch];
    NSString *prefix = bundleRange.location != NSNotFound ?
        [applicationIdentifier substringToIndex:bundleRange.location] : nil;
    if (!prefix) return;

    MPAutoFillKeychainStore *keychainStore = [[MPAutoFillKeychainStore alloc]
        initWithAccessGroup:[prefix stringByAppendingString:MPAutoFillSharedKeychainAccessGroupSuffix]];
    NSError *error = nil;
    NSURL *rootURL = [MPAutoFillGenerationStore appGroupRootURLWithFileManager:NSFileManager.defaultManager
                                                                         error:&error];
    MPAutoFillGenerationStore *generationStore = rootURL ? [[MPAutoFillGenerationStore alloc]
        initWithRootURL:rootURL currentGenerationStore:keychainStore error:&error] : nil;
    if (generationStore) {
      coordinator = [[self alloc] initWithGenerationStore:generationStore
          keychainStore:(id<MPAutoFillPrivateKeyStore>)keychainStore rootURL:rootURL];
    }
  });
  return coordinator;
}

- (instancetype)initWithGenerationStore:(MPAutoFillGenerationStore *)generationStore
                           keychainStore:(id<MPAutoFillPrivateKeyStore>)keychainStore
                                 rootURL:(NSURL *)rootURL {
  self = [super init];
  if (self) {
    _generationStore = generationStore;
    _keychainStore = keychainStore;
    _rootURL = rootURL;
  }
  return self;
}

- (MPAutoFillSnapshot *)snapshotForGeneration:(MPAutoFillGeneration *)generation context:(LAContext *)context
                           interactionAllowed:(BOOL)interactionAllowed
                                        error:(NSError **)error {
  context.localizedReason = @"Fill a password from MacPass";
  SecKeyRef privateKey = [self.keychainStore copyPrivateKeyForPublicationIdentifier:generation.publicationIdentifier
                                                              authenticationContext:context
                                                                 interactionAllowed:interactionAllowed
                                                                              error:error];
  if (!privateKey) return nil;
  MPAutoFillSnapshot *snapshot = [MPAutoFillEnvelopeCrypto decryptEnvelope:generation.encryptedSecrets
                                                            withPrivateKey:privateKey
                                                    publicationIdentifier:generation.publicationIdentifier
                                                     generationIdentifier:generation.generationIdentifier
                                                              indexDigest:generation.indexDigest
                                                                    error:error];
  CFRelease(privateKey);
  return snapshot;
}

- (BOOL)record:(MPAutoFillCredentialRecord *)record
    matchesServiceIdentifier:(ASCredentialServiceIdentifier *)serviceIdentifier {
  MPAutoFillServiceIdentifierType type;
  switch (serviceIdentifier.type) {
    case ASCredentialServiceIdentifierTypeDomain:
      type = MPAutoFillServiceIdentifierTypeDomain;
      break;
    case ASCredentialServiceIdentifierTypeURL:
      type = MPAutoFillServiceIdentifierTypeURL;
      break;
    default:
      return NO;
  }
  for (NSString *credentialService in record.serviceIdentifiers) {
    if ([MPAutoFillServiceMatcher credentialServiceIdentifier:credentialService
                           matchesRequestedServiceIdentifier:serviceIdentifier.identifier type:type]) return YES;
  }
  return NO;
}

- (BOOL)record:(MPAutoFillCredentialRecord *)record matchesIndexRecord:(MPAutoFillVaultIndexRecord *)indexRecord {
  return [record.entryIdentifier isEqualToString:indexRecord.entryIdentifier] &&
      [record.title isEqualToString:indexRecord.title] &&
      [record.username isEqualToString:indexRecord.username] &&
      [record.serviceIdentifiers isEqualToArray:indexRecord.serviceIdentifiers] &&
      record.modificationTime == indexRecord.modificationTime && record.rank == indexRecord.rank;
}

- (ASPasswordCredential *)credentialForIdentity:(ASPasswordCredentialIdentity *)identity
                               interactionAllowed:(BOOL)interactionAllowed
                                            error:(NSError **)error {
  MPAutoFillCredentialIdentifier *identifier = identity.recordIdentifier ?
      [MPAutoFillCredentialIdentifier identifierWithRecordIdentifier:identity.recordIdentifier error:error] : nil;
  if (!identifier) {
    if (error && !*error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The credential identity is invalid.", nil);
    return nil;
  }
  NSArray<NSString *> *publications = [self publicationIdentifiersWithError:error];
  if (!publications || ![publications containsObject:identifier.publicationIdentifier]) {
    if (publications && error) *error = MPAutoFillError(MPAutoFillErrorItemNotFound,
        @"The credential publication is no longer available.", nil);
    return nil;
  }

  MPAutoFillGeneration *generation = [self.generationStore
      currentGenerationForPublicationIdentifier:identifier.publicationIdentifier error:error];
  if (!generation) return nil;
  MPAutoFillSnapshot *snapshot = [self snapshotForGeneration:generation
                                                     context:[[LAContext alloc] init]
                                          interactionAllowed:interactionAllowed error:error];
  if (!snapshot) return nil;

  MPAutoFillCredentialRecord *record = nil;
  MPAutoFillVaultIndexRecord *indexRecord = nil;
  for (MPAutoFillCredentialRecord *candidate in snapshot.records) {
    if ([candidate.entryIdentifier isEqualToString:identifier.entryIdentifier]) { record = candidate; break; }
  }
  for (MPAutoFillVaultIndexRecord *candidate in generation.index.records) {
    if ([candidate.entryIdentifier isEqualToString:identifier.entryIdentifier]) { indexRecord = candidate; break; }
  }
  if (!record || !indexRecord || ![self record:record matchesIndexRecord:indexRecord] ||
      ![self record:record matchesServiceIdentifier:identity.serviceIdentifier]) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorItemNotFound, @"The requested credential is not available.", nil);
    return nil;
  }
  return [[ASPasswordCredential alloc] initWithUser:record.username password:record.password];
}

- (NSArray<NSString *> *)publicationIdentifiersWithError:(NSError **)error {
  NSURL *registryURL = [self.rootURL URLByAppendingPathComponent:@"registry.plist"];
  NSError *readError = nil;
  NSData *data = [MPAutoFillGenerationStore registryDataAtRootURL:registryURL.URLByDeletingLastPathComponent
                                                           error:&readError];
  if (!data && readError.code == MPAutoFillErrorItemNotFound) return @[];
  if (!data) {
    if (error) *error = readError;
    return nil;
  }
  NSDictionary *root = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                                          format:NULL error:error] : nil;
  NSSet *rootKeys = [root isKindOfClass:NSDictionary.class] ? [NSSet setWithArray:root.allKeys] : nil;
  NSArray *publications = [rootKeys isEqualToSet:[NSSet setWithArray:@[@"schema", @"publications"]]] &&
      MPAutoFillRegistryInteger(root[@"schema"]) && [root[@"schema"] integerValue] == 1 &&
      [root[@"publications"] isKindOfClass:NSArray.class] ? root[@"publications"] : nil;
  if (!publications) {
    if (error && !*error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"The AutoFill registry is invalid.", nil);
    return nil;
  }
  NSMutableArray<NSString *> *identifiers = [NSMutableArray arrayWithCapacity:publications.count];
  NSMutableSet<NSString *> *uniqueIdentifiers = [NSMutableSet setWithCapacity:publications.count];
  for (id value in publications) {
    NSDictionary *record = [value isKindOfClass:NSDictionary.class] ? value : nil;
    NSSet *recordKeys = record ? [NSSet setWithArray:record.allKeys] : nil;
    NSSet *requiredKeys = [NSSet setWithArray:@[@"publication", @"root", @"bookmark", @"path"]];
    NSMutableSet *allowedKeys = [requiredKeys mutableCopy];
    [allowedKeys addObject:@"published"];
    NSString *identifier = [requiredKeys isSubsetOfSet:recordKeys] && [recordKeys isSubsetOfSet:allowedKeys] ?
        record[@"publication"] : nil;
    NSUUID *uuid = [identifier isKindOfClass:NSString.class] ? [[NSUUID alloc] initWithUUIDString:identifier] : nil;
    NSString *rootIdentifier = record[@"root"];
    NSUUID *rootUUID = [rootIdentifier isKindOfClass:NSString.class] ? [[NSUUID alloc] initWithUUIDString:rootIdentifier] : nil;
    if (!uuid || ![uuid.UUIDString.lowercaseString isEqualToString:identifier] || recordKeys.count == 0 ||
        !rootUUID || ![rootUUID.UUIDString.lowercaseString isEqualToString:rootIdentifier] ||
        ![record[@"bookmark"] isKindOfClass:NSData.class] || ![record[@"path"] isKindOfClass:NSString.class] ||
        (record[@"published"] && ![record[@"published"] isKindOfClass:NSDate.class]) ||
        [uniqueIdentifiers containsObject:identifier]) {
      if (error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot, @"The AutoFill registry contains an invalid publication.", nil);
      return nil;
    }
    [uniqueIdentifiers addObject:identifier];
    [identifiers addObject:identifier];
  }
  return identifiers;
}

- (NSArray<MPAutoFillCredentialSelection *> *)credentialsForServiceIdentifiers:
    (NSArray<ASCredentialServiceIdentifier *> *)serviceIdentifiers error:(NSError **)error {
  NSArray<NSString *> *publications = [self publicationIdentifiersWithError:error];
  if (!publications) return nil;
  NSMutableArray<MPAutoFillCredentialSelection *> *selections = [NSMutableArray array];
  LAContext *context = [[LAContext alloc] init];
  for (NSString *publication in publications) {
    MPAutoFillGeneration *generation = [self.generationStore
        currentGenerationForPublicationIdentifier:publication error:error];
    if (!generation) return nil;
    MPAutoFillSnapshot *snapshot = [self snapshotForGeneration:generation context:context
                                             interactionAllowed:YES error:error];
    if (!snapshot) return nil;
    NSMutableDictionary<NSString *, MPAutoFillVaultIndexRecord *> *indexRecords =
        [NSMutableDictionary dictionaryWithCapacity:generation.index.records.count];
    for (MPAutoFillVaultIndexRecord *indexRecord in generation.index.records) {
      if (indexRecords[indexRecord.entryIdentifier]) {
        if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch,
            @"The AutoFill index contains duplicate credentials.", nil);
        return nil;
      }
      indexRecords[indexRecord.entryIdentifier] = indexRecord;
    }
    if (indexRecords.count != snapshot.records.count) {
      if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch,
          @"The AutoFill index does not match its encrypted credentials.", nil);
      return nil;
    }
    for (MPAutoFillCredentialRecord *record in snapshot.records) {
      MPAutoFillVaultIndexRecord *indexRecord = indexRecords[record.entryIdentifier];
      if (!indexRecord || ![self record:record matchesIndexRecord:indexRecord]) {
        if (error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch,
            @"The AutoFill index does not match its encrypted credentials.", nil);
        return nil;
      }
      NSUInteger serviceOrder = serviceIdentifiers.count;
      for (NSUInteger index = 0; index < serviceIdentifiers.count; index++) {
        if ([self record:record matchesServiceIdentifier:serviceIdentifiers[index]]) { serviceOrder = index; break; }
      }
      MPAutoFillCredentialSelection *selection = [[MPAutoFillCredentialSelection alloc] init];
      selection.title = record.title;
      selection.username = record.username;
      selection.rank = record.rank;
      selection.serviceOrder = serviceOrder;
      selection.credential = [[ASPasswordCredential alloc] initWithUser:record.username password:record.password];
      [selections addObject:selection];
    }
  }
  [selections sortUsingComparator:^NSComparisonResult(MPAutoFillCredentialSelection *left,
                                                       MPAutoFillCredentialSelection *right) {
    if (left.serviceOrder != right.serviceOrder) return left.serviceOrder < right.serviceOrder ? NSOrderedAscending : NSOrderedDescending;
    if (left.rank != right.rank) return left.rank > right.rank ? NSOrderedAscending : NSOrderedDescending;
    NSComparisonResult title = [left.title localizedStandardCompare:right.title];
    return title != NSOrderedSame ? title : [left.username localizedStandardCompare:right.username];
  }];
  return selections;
}

@end
