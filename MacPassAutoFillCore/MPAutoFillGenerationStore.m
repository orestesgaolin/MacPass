#import "MPAutoFillGenerationStore.h"

#import <CommonCrypto/CommonDigest.h>
#import <dirent.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

#import "MPAutoFillConstants.h"
#import "MPAutoFillErrors.h"
#import "MPAutoFillVaultIndex.h"

const NSUInteger MPAutoFillMaximumEncryptedSecretsBytes = 8 * 1024 * 1024;
const NSUInteger MPAutoFillMaximumRegistryBytes = 1024 * 1024;
static const NSUInteger MPAutoFillMaximumGenerationsPerPublication = 1024;
static const NSUInteger MPAutoFillMaximumPublications = 1024;

static BOOL MPAutoFillStoreUUID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 36 ||
      ![value canBeConvertedToEncoding:NSASCIIStringEncoding]) return NO;
  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
  return uuid && [uuid.UUIDString.lowercaseString isEqualToString:value];
}

static NSError *MPAutoFillPOSIXError(MPAutoFillErrorCode code, NSString *description) {
  NSError *underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
  return MPAutoFillError(code, description, underlying);
}

static BOOL MPAutoFillValidateDescriptor(int descriptor, BOOL directory, NSError **error) {
  struct stat status;
  if (fstat(descriptor, &status) != 0) {
    if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"AutoFill storage could not be inspected.");
    return NO;
  }
  BOOL expectedType = directory ? S_ISDIR(status.st_mode) : S_ISREG(status.st_mode);
  BOOL valid = expectedType && status.st_uid == geteuid() && (status.st_mode & 0077) == 0;
  if (!directory) valid = valid && status.st_nlink == 1;
  if (!valid) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorUnsafeFile, @"AutoFill storage has an unsafe type, owner, mode, or link count.", nil);
    return NO;
  }
  return YES;
}

static BOOL MPAutoFillSyncDescriptor(int descriptor, NSError **error) {
  if (fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0) return YES;
  if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"AutoFill storage could not be synchronized.");
  return NO;
}

static int MPAutoFillOpenDirectoryAt(int parent, const char *name, BOOL create, NSError **error) {
  if (create && mkdirat(parent, name, 0700) == 0) {
    if (!MPAutoFillSyncDescriptor(parent, error)) return -1;
  } else if (create && errno != EEXIST) {
      if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"An AutoFill storage directory could not be created.");
      return -1;
  }
  int descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (descriptor < 0) {
    if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"An AutoFill storage directory could not be opened.");
    return -1;
  }
  if (!MPAutoFillValidateDescriptor(descriptor, YES, error)) {
    close(descriptor);
    return -1;
  }
  return descriptor;
}

static BOOL MPAutoFillWriteFile(int directory, const char *name, NSData *data, NSError **error) {
  int descriptor = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
  if (descriptor < 0) {
    if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"An immutable AutoFill generation file could not be created.");
    return NO;
  }
  BOOL success = fchmod(descriptor, 0600) == 0;
  const uint8_t *bytes = data.bytes;
  NSUInteger offset = 0;
  while (success && offset < data.length) {
    ssize_t written = write(descriptor, bytes + offset, data.length - offset);
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) {
      success = NO;
      break;
    }
    offset += (NSUInteger)written;
  }
  if (success) success = MPAutoFillSyncDescriptor(descriptor, error);
  if (close(descriptor) != 0) success = NO;
  if (!success && error && !*error) {
    *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"An AutoFill generation file could not be written.");
  }
  return success;
}

static NSData *MPAutoFillReadFile(int directory, const char *name, NSUInteger maximumSize, NSError **error) {
  int descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (descriptor < 0) {
    if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorGenerationIncomplete, @"An AutoFill generation file is missing.");
    return nil;
  }
  struct stat status;
  BOOL valid = MPAutoFillValidateDescriptor(descriptor, NO, error) &&
      fstat(descriptor, &status) == 0 && status.st_size > 0 && (uint64_t)status.st_size <= maximumSize;
  if (!valid) {
    if (error && !*error) *error = MPAutoFillError(MPAutoFillErrorLimitExceeded, @"An AutoFill generation file has an invalid size.", nil);
    close(descriptor);
    return nil;
  }
  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)status.st_size];
  uint8_t *bytes = data.mutableBytes;
  NSUInteger offset = 0;
  while (offset < data.length) {
    ssize_t count = read(descriptor, bytes + offset, data.length - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    offset += (NSUInteger)count;
  }
  close(descriptor);
  if (offset != data.length) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorGenerationIncomplete, @"An AutoFill generation file is truncated.", nil);
    return nil;
  }
  return [data copy];
}

static NSData *MPAutoFillReadRegistryFile(int directory, NSError **error) {
  int descriptor = openat(directory, "registry.plist", O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
  if (descriptor < 0) {
    if (error) *error = errno == ENOENT ?
        MPAutoFillError(MPAutoFillErrorItemNotFound, @"The AutoFill registry does not exist.", nil) :
        MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"The AutoFill registry could not be opened.");
    return nil;
  }
  struct stat status;
  BOOL valid = MPAutoFillValidateDescriptor(descriptor, NO, error) &&
      fstat(descriptor, &status) == 0 && status.st_size > 0 &&
      (uint64_t)status.st_size <= MPAutoFillMaximumRegistryBytes;
  if (!valid) {
    if (error && !*error) *error = MPAutoFillError(MPAutoFillErrorLimitExceeded,
        @"The AutoFill registry has an invalid size.", nil);
    close(descriptor);
    return nil;
  }
  NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)status.st_size];
  NSUInteger offset = 0;
  while (offset < data.length) {
    ssize_t count = read(descriptor, (uint8_t *)data.mutableBytes + offset, data.length - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    offset += (NSUInteger)count;
  }
  close(descriptor);
  if (offset != data.length) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorMalformedSnapshot,
        @"The AutoFill registry is truncated.", nil);
    return nil;
  }
  return [data copy];
}

static NSData *MPAutoFillIndexSHA256(NSData *data) {
  uint8_t digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  return [NSData dataWithBytes:digest length:sizeof(digest)];
}

@interface MPAutoFillGeneration ()
@property(nonatomic, readwrite, copy) NSString *publicationIdentifier;
@property(nonatomic, readwrite, copy) NSString *generationIdentifier;
@property(nonatomic, readwrite, strong) MPAutoFillVaultIndex *index;
@property(nonatomic, readwrite, copy) NSData *indexData;
@property(nonatomic, readwrite, copy) NSData *indexDigest;
@property(nonatomic, readwrite, copy) NSData *encryptedSecrets;
@end

@implementation MPAutoFillGeneration
@end

@interface MPAutoFillGenerationStore ()
@property(nonatomic, strong) NSURL *rootURL;
@property(nonatomic, strong) id<MPAutoFillCurrentGenerationStore> currentGenerationStore;
@property(nonatomic, strong) NSMutableSet<NSString *> *publishingGenerationIdentifiers;
@end

@implementation MPAutoFillGenerationStore

+ (NSURL *)appGroupRootURLWithFileManager:(NSFileManager *)fileManager error:(NSError **)error {
  NSURL *container = [fileManager containerURLForSecurityApplicationGroupIdentifier:MPAutoFillAppGroupIdentifier];
  if (!container) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorStorageUnavailable, @"The AutoFill App Group container is unavailable.", nil);
    return nil;
  }
  return [container URLByAppendingPathComponent:@"AutoFill" isDirectory:YES];
}

+ (NSData *)registryDataAtRootURL:(NSURL *)rootURL error:(NSError **)error {
  if (!rootURL.isFileURL) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument,
        @"The AutoFill registry root is invalid.", nil);
    return nil;
  }
  int root = open(rootURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (root < 0 || !MPAutoFillValidateDescriptor(root, YES, error)) {
    if (root >= 0) close(root);
    if (error && !*error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable,
        @"The AutoFill registry root could not be opened.");
    return nil;
  }
  NSData *data = MPAutoFillReadRegistryFile(root, error);
  close(root);
  return data;
}

- (instancetype)initWithRootURL:(NSURL *)rootURL
          currentGenerationStore:(id<MPAutoFillCurrentGenerationStore>)currentGenerationStore
                           error:(NSError **)error {
  if (!rootURL.isFileURL || !currentGenerationStore) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The generation store configuration is invalid.", nil);
    return nil;
  }
  NSFileManager *manager = NSFileManager.defaultManager;
  if (![manager createDirectoryAtURL:rootURL withIntermediateDirectories:YES
                          attributes:@{NSFilePosixPermissions: @0700} error:error]) return nil;
  int descriptor = open(rootURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (descriptor < 0 || !MPAutoFillValidateDescriptor(descriptor, YES, error)) {
    if (descriptor >= 0) close(descriptor);
    return nil;
  }
  fchmod(descriptor, 0700);
  int vaults = MPAutoFillOpenDirectoryAt(descriptor, "Vaults", YES, error);
  if (vaults >= 0) close(vaults);
  close(descriptor);
  if (vaults < 0) return nil;
  self = [super init];
  if (self) {
    _rootURL = rootURL;
    _currentGenerationStore = currentGenerationStore;
    _publishingGenerationIdentifiers = [NSMutableSet set];
  }
  return self;
}

- (int)openGenerationsForPublicationIdentifier:(NSString *)publicationIdentifier create:(BOOL)create error:(NSError **)error {
  if (!MPAutoFillStoreUUID(publicationIdentifier)) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    return -1;
  }
  int root = open(self.rootURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (root < 0 || !MPAutoFillValidateDescriptor(root, YES, error)) {
    if (root >= 0) close(root);
    return -1;
  }
  int vaults = MPAutoFillOpenDirectoryAt(root, "Vaults", NO, error);
  close(root);
  if (vaults < 0) return -1;
  int publication = MPAutoFillOpenDirectoryAt(vaults, publicationIdentifier.UTF8String, create, error);
  close(vaults);
  if (publication < 0) return -1;
  int generations = MPAutoFillOpenDirectoryAt(publication, "generations", create, error);
  close(publication);
  return generations;
}

- (MPAutoFillGeneration *)readGeneration:(NSString *)generationIdentifier
                    publicationIdentifier:(NSString *)publicationIdentifier
                                    error:(NSError **)error {
  int generations = [self openGenerationsForPublicationIdentifier:publicationIdentifier create:NO error:error];
  if (generations < 0) return nil;
  int generation = MPAutoFillOpenDirectoryAt(generations, generationIdentifier.UTF8String, NO, error);
  close(generations);
  if (generation < 0) return nil;
  NSData *indexData = MPAutoFillReadFile(generation, "index.plist", MPAutoFillMaximumVaultIndexBytes, error);
  NSData *secrets = indexData ? MPAutoFillReadFile(generation, "secrets.bin", MPAutoFillMaximumEncryptedSecretsBytes, error) : nil;
  close(generation);
  if (!indexData || !secrets) return nil;
  MPAutoFillVaultIndex *index = [MPAutoFillVaultIndex indexWithSerializedData:indexData
      expectedPublicationIdentifier:publicationIdentifier expectedGenerationIdentifier:generationIdentifier error:error];
  if (!index) return nil;
  MPAutoFillGeneration *result = [[MPAutoFillGeneration alloc] init];
  result.publicationIdentifier = publicationIdentifier;
  result.generationIdentifier = generationIdentifier;
  result.index = index;
  result.indexData = indexData;
  result.indexDigest = MPAutoFillIndexSHA256(indexData);
  result.encryptedSecrets = secrets;
  return result;
}

- (BOOL)publishIndexData:(NSData *)indexData
          validatedIndex:(MPAutoFillVaultIndex *)index
        encryptedSecrets:(NSData *)encryptedSecrets
                   error:(NSError **)error {
  @synchronized (self) {
  if (![indexData isKindOfClass:NSData.class] || indexData.length == 0 ||
      indexData.length > MPAutoFillMaximumVaultIndexBytes ||
      ![index isKindOfClass:MPAutoFillVaultIndex.class] ||
      ![encryptedSecrets isKindOfClass:NSData.class] || encryptedSecrets.length == 0 ||
      encryptedSecrets.length > MPAutoFillMaximumEncryptedSecretsBytes) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Generation data is invalid.", nil);
    return NO;
  }
  MPAutoFillVaultIndex *parsed = [MPAutoFillVaultIndex indexWithSerializedData:indexData
      expectedPublicationIdentifier:index.publicationIdentifier
      expectedGenerationIdentifier:index.generationIdentifier error:error];
  NSData *validatedIndexData = parsed ? [index serializedDataWithError:error] : nil;
  if (!parsed || ![validatedIndexData isEqualToData:indexData]) {
    if (error && !*error) *error = MPAutoFillError(MPAutoFillErrorContextMismatch, @"Serialized and validated index data differ.", nil);
    return NO;
  }
  int generations = [self openGenerationsForPublicationIdentifier:index.publicationIdentifier create:YES error:error];
  if (generations < 0) return NO;
  [self.publishingGenerationIdentifiers addObject:index.generationIdentifier];
  if (mkdirat(generations, index.generationIdentifier.UTF8String, 0700) != 0) {
    if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"The immutable generation already exists or could not be created.");
    close(generations);
    [self.publishingGenerationIdentifiers removeObject:index.generationIdentifier];
    return NO;
  }
  if (!MPAutoFillSyncDescriptor(generations, error)) {
    close(generations);
    [self.publishingGenerationIdentifiers removeObject:index.generationIdentifier];
    return NO;
  }
  int generation = MPAutoFillOpenDirectoryAt(generations, index.generationIdentifier.UTF8String, NO, error);
  if (generation < 0) {
    close(generations);
    return NO;
  }
  BOOL success = MPAutoFillWriteFile(generation, "index.plist", indexData, error) &&
      MPAutoFillWriteFile(generation, "secrets.bin", encryptedSecrets, error) &&
      MPAutoFillSyncDescriptor(generation, error) && MPAutoFillSyncDescriptor(generations, error);
  close(generation);
  close(generations);
  if (!success) {
    [self.publishingGenerationIdentifiers removeObject:index.generationIdentifier];
    return NO;
  }
  MPAutoFillGeneration *validated = [self readGeneration:index.generationIdentifier
                                  publicationIdentifier:index.publicationIdentifier error:error];
  if (!validated || ![validated.indexData isEqualToData:indexData] ||
      ![validated.encryptedSecrets isEqualToData:encryptedSecrets]) {
    [self.publishingGenerationIdentifiers removeObject:index.generationIdentifier];
    return NO;
  }
  BOOL activated = [self.currentGenerationStore setCurrentGeneration:index.generationIdentifier
                                             forPublicationIdentifier:index.publicationIdentifier error:error];
  [self.publishingGenerationIdentifiers removeObject:index.generationIdentifier];
  return activated;
  }
}

- (MPAutoFillGeneration *)currentGenerationForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  if (!MPAutoFillStoreUUID(publicationIdentifier)) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
    return nil;
  }
  NSString *generation = [self.currentGenerationStore currentGenerationForPublicationIdentifier:publicationIdentifier error:error];
  if (!generation) return nil;
  if (!MPAutoFillStoreUUID(generation)) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorGenerationIncomplete, @"The active generation identifier is malformed.", nil);
    return nil;
  }
  return [self readGeneration:generation publicationIdentifier:publicationIdentifier error:error];
}

- (NSArray<NSString *> *)publicationIdentifiersWithError:(NSError **)error {
  int root = open(self.rootURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (root < 0 || !MPAutoFillValidateDescriptor(root, YES, error)) {
    if (root >= 0) close(root);
    return nil;
  }
  int vaults = MPAutoFillOpenDirectoryAt(root, "Vaults", NO, error);
  close(root);
  if (vaults < 0) return nil;
  int duplicate = dup(vaults);
  DIR *directory = duplicate >= 0 ? fdopendir(duplicate) : NULL;
  if (!directory) {
    if (duplicate >= 0) close(duplicate);
    close(vaults);
    if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable,
        @"Publication storage could not be enumerated.");
    return nil;
  }
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
  BOOL valid = YES;
  struct dirent *entry;
  while ((entry = readdir(directory)) != NULL) {
    NSString *name = [NSString stringWithUTF8String:entry->d_name];
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;
    int publication = openat(vaults, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (!MPAutoFillStoreUUID(name) || publication < 0 ||
        !MPAutoFillValidateDescriptor(publication, YES, error) || identifiers.count >= MPAutoFillMaximumPublications) {
      if (publication >= 0) close(publication);
      valid = NO;
      if (error && !*error) *error = MPAutoFillError(MPAutoFillErrorUnsafeFile,
          @"Publication storage contains unexpected data.", nil);
      break;
    }
    close(publication);
    [identifiers addObject:name];
  }
  closedir(directory);
  close(vaults);
  return valid ? [identifiers sortedArrayUsingSelector:@selector(compare:)] : nil;
}

- (BOOL)removeOrphanedGenerationsForPublicationIdentifier:(NSString *)publicationIdentifier
                                     retainingGenerations:(NSSet<NSString *> *)retainedGenerationIdentifiers
                                                     limit:(NSUInteger)limit
                                                     error:(NSError **)error {
  @synchronized (self) {
  if (!MPAutoFillStoreUUID(publicationIdentifier) || ![retainedGenerationIdentifiers isKindOfClass:NSSet.class] || limit == 0) {
    if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"Generation cleanup arguments are invalid.", nil);
    return NO;
  }
  NSError *pointerError = nil;
  NSString *current = [self.currentGenerationStore currentGenerationForPublicationIdentifier:publicationIdentifier error:&pointerError];
  if (!current && pointerError.code != MPAutoFillErrorItemNotFound) {
    if (error) *error = pointerError;
    return NO;
  }
  NSMutableSet *protected = [retainedGenerationIdentifiers mutableCopy];
  if (current) [protected addObject:current];
  [protected unionSet:self.publishingGenerationIdentifiers];
  int generations = [self openGenerationsForPublicationIdentifier:publicationIdentifier create:NO error:error];
  if (generations < 0) return NO;
  int duplicate = dup(generations);
  DIR *directory = duplicate >= 0 ? fdopendir(duplicate) : NULL;
  if (!directory) {
    if (duplicate >= 0) close(duplicate);
    close(generations);
    if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"Generation cleanup could not enumerate storage.");
    return NO;
  }
  NSUInteger removed = 0;
  struct dirent *entry;
  while ((entry = readdir(directory)) != NULL) {
    if (removed >= limit) break;
    NSString *name = [NSString stringWithUTF8String:entry->d_name];
    if (!MPAutoFillStoreUUID(name) || [protected containsObject:name]) continue;
    int child = openat(generations, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (child < 0 || !MPAutoFillValidateDescriptor(child, YES, NULL)) {
      if (child >= 0) close(child);
      continue;
    }
    unlinkat(child, "index.plist", 0);
    unlinkat(child, "secrets.bin", 0);
    close(child);
    if (unlinkat(generations, entry->d_name, AT_REMOVEDIR) != 0) continue;
    removed++;
  }
  closedir(directory);
  BOOL synced = MPAutoFillSyncDescriptor(generations, error);
  close(generations);
  return synced;
  }
}

- (BOOL)removePublicationDataForPublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  @synchronized (self) {
    if (!MPAutoFillStoreUUID(publicationIdentifier)) {
      if (error) *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The publication identifier is invalid.", nil);
      return NO;
    }
    int root = open(self.rootURL.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (root < 0 || !MPAutoFillValidateDescriptor(root, YES, error)) {
      if (root >= 0) close(root);
      return NO;
    }
    int vaults = MPAutoFillOpenDirectoryAt(root, "Vaults", NO, error);
    close(root);
    if (vaults < 0) return NO;
    int publication = openat(vaults, publicationIdentifier.UTF8String,
                             O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (publication < 0 && errno == ENOENT) {
      close(vaults);
      return YES;
    }
    if (publication < 0 || !MPAutoFillValidateDescriptor(publication, YES, error)) {
      if (publication >= 0) close(publication);
      close(vaults);
      return NO;
    }
    int generations = MPAutoFillOpenDirectoryAt(publication, "generations", NO, error);
    if (generations < 0) {
      close(publication);
      close(vaults);
      return NO;
    }
    int duplicate = dup(generations);
    DIR *directory = duplicate >= 0 ? fdopendir(duplicate) : NULL;
    if (!directory) {
      if (duplicate >= 0) close(duplicate);
      close(generations);
      close(publication);
      close(vaults);
      if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"Publication cleanup could not enumerate storage.");
      return NO;
    }
    BOOL success = YES;
    NSUInteger count = 0;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
      NSString *name = [NSString stringWithUTF8String:entry->d_name];
      if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) continue;
      if (!MPAutoFillStoreUUID(name) || ++count > MPAutoFillMaximumGenerationsPerPublication) {
        success = NO;
        if (error) *error = MPAutoFillError(MPAutoFillErrorUnsafeFile, @"Publication storage contains unexpected data.", nil);
        break;
      }
      int child = openat(generations, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
      if (child < 0 || !MPAutoFillValidateDescriptor(child, YES, error) ||
          unlinkat(child, "index.plist", 0) != 0 || unlinkat(child, "secrets.bin", 0) != 0) {
        if (child >= 0) close(child);
        success = NO;
        if (error && !*error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"Publication generation files could not be removed.");
        break;
      }
      close(child);
      if (unlinkat(generations, entry->d_name, AT_REMOVEDIR) != 0) {
        success = NO;
        if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"A publication generation could not be removed.");
        break;
      }
    }
    closedir(directory);
    if (success) success = MPAutoFillSyncDescriptor(generations, error);
    close(generations);
    if (success && unlinkat(publication, "generations", AT_REMOVEDIR) != 0) {
      success = NO;
      if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"Publication storage could not be removed.");
    }
    close(publication);
    if (success && unlinkat(vaults, publicationIdentifier.UTF8String, AT_REMOVEDIR) != 0) {
      success = NO;
      if (error) *error = MPAutoFillPOSIXError(MPAutoFillErrorStorageUnavailable, @"Publication storage could not be removed.");
    }
    if (success) success = MPAutoFillSyncDescriptor(vaults, error);
    close(vaults);
    return success;
  }
}

@end
