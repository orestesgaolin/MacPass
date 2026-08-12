#import "MPAutoFillPublicationRegistry.h"

#import "MPAutoFillGenerationStore.h"
#import "MPAutoFillErrors.h"

static const NSInteger MPAutoFillRegistrySchemaVersion = 1;

static BOOL MPAutoFillRegistryInteger(id value) {
  if (![value isKindOfClass:NSNumber.class]) return NO;
  double number = [value doubleValue];
  return isfinite(number) && floor(number) == number;
}

@interface MPAutoFillPublicationRegistry ()
@property(nonatomic, strong) NSURL *registryURL;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *records;
@property(nonatomic, strong) NSMapTable<NSDocument *, NSString *> *documentPublications;
@property(nonatomic, readwrite, getter=isAuthoritative) BOOL authoritative;
@end

@implementation MPAutoFillPublicationRegistry

+ (instancetype)sharedRegistry {
  static MPAutoFillPublicationRegistry *registry;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    registry = [[self alloc] init];
  });
  return registry;
}

- (NSArray<NSString *> *)publicationIdentifiers {
  @synchronized (self) {
    NSMutableOrderedSet<NSString *> *identifiers = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *record in self.records) [identifiers addObject:record[@"publication"]];
    return identifiers.array;
  }
}

- (NSArray<NSDictionary<NSString *,id> *> *)publicationSummaries {
  @synchronized (self) {
    NSMutableArray *summaries = [NSMutableArray arrayWithCapacity:self.records.count];
    for (NSDictionary *record in self.records) {
      NSMutableDictionary *summary = [@{
        @"publication": record[@"publication"],
        @"name": [record[@"path"] lastPathComponent] ?: @"Database",
      } mutableCopy];
      if ([record[@"published"] isKindOfClass:NSDate.class]) summary[@"published"] = record[@"published"];
      [summaries addObject:summary];
    }
    return summaries;
  }
}

- (instancetype)init {
  NSError *error = nil;
  NSURL *rootURL = [MPAutoFillGenerationStore appGroupRootURLWithFileManager:NSFileManager.defaultManager error:&error];
  return [self initWithRootURL:rootURL];
}

- (instancetype)initWithRootURL:(NSURL *)rootURL {
  self = [super init];
  if (self) {
    _records = [NSMutableArray array];
    _documentPublications = [NSMapTable weakToStrongObjectsMapTable];
    _authoritative = rootURL != nil;
    if (rootURL) {
      _registryURL = [rootURL URLByAppendingPathComponent:@"registry.plist"];
      NSError *readError = nil;
      NSData *data = [MPAutoFillGenerationStore registryDataAtRootURL:rootURL error:&readError];
      if (!data && readError.code != MPAutoFillErrorItemNotFound) {
        _authoritative = NO;
        _registryURL = nil;
        return self;
      }
      NSDictionary *root = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
      if (data && (![root isKindOfClass:NSDictionary.class] ||
          ![[NSSet setWithArray:@[@"schema", @"publications"]] isEqualToSet:
          [NSSet setWithArray:root.allKeys]] || !MPAutoFillRegistryInteger(root[@"schema"]) ||
          [root[@"schema"] integerValue] != MPAutoFillRegistrySchemaVersion ||
          ![root[@"publications"] isKindOfClass:NSArray.class])) {
        _authoritative = NO;
        _registryURL = nil;
        return self;
      }
      if (data) {
        NSMutableSet *publications = [NSMutableSet set];
        for (id record in root[@"publications"]) {
          if (![self validRecord:record] || [publications containsObject:record[@"publication"]]) {
            _authoritative = NO;
            [_records removeAllObjects];
            _registryURL = nil;
            return self;
          }
          [publications addObject:record[@"publication"]];
          [_records addObject:record];
        }
      }
    }
  }
  return self;
}

- (void)detachDocument:(NSDocument *)document {
  @synchronized (self) {
    [self.documentPublications removeObjectForKey:document];
  }
}

- (BOOL)validUUID:(NSString *)value {
  NSUUID *uuid = [value isKindOfClass:NSString.class] ? [[NSUUID alloc] initWithUUIDString:value] : nil;
  return uuid && [uuid.UUIDString.lowercaseString isEqualToString:value];
}

- (BOOL)validRecord:(id)value {
  if (![value isKindOfClass:NSDictionary.class]) return NO;
  NSDictionary *record = value;
  NSMutableSet *allowedKeys = [NSMutableSet setWithArray:@[@"publication", @"root", @"bookmark", @"path", @"published"]];
  if (![[NSSet setWithArray:record.allKeys] isSubsetOfSet:allowedKeys]) return NO;
  return [self validUUID:record[@"publication"]] && [self validUUID:record[@"root"]] &&
      [record[@"bookmark"] isKindOfClass:NSData.class] && [record[@"path"] isKindOfClass:NSString.class] &&
      (!record[@"published"] || [record[@"published"] isKindOfClass:NSDate.class]);
}

- (id)resourceIdentifierForURL:(NSURL *)URL {
  return [URL resourceValuesForKeys:@[NSURLFileResourceIdentifierKey] error:NULL][NSURLFileResourceIdentifierKey];
}

- (BOOL)record:(NSDictionary *)record matchesURL:(NSURL *)URL rootIdentifier:(NSString *)rootIdentifier {
  if (![record[@"root"] isEqualToString:rootIdentifier]) return NO;
  BOOL stale = NO;
  NSURL *bookmarkedURL = [NSURL URLByResolvingBookmarkData:record[@"bookmark"] options:0
                                            relativeToURL:nil bookmarkDataIsStale:&stale error:NULL];
  id expectedResource = bookmarkedURL ? [self resourceIdentifierForURL:bookmarkedURL] : nil;
  id actualResource = [self resourceIdentifierForURL:URL];
  if (expectedResource && actualResource && [expectedResource isEqual:actualResource]) return YES;
  return [record[@"path"] isEqualToString:URL.URLByStandardizingPath.path];
}

- (NSString *)publicationIdentifierForDocument:(NSDocument *)document
                                      sourceURL:(NSURL *)sourceURL
                                 rootIdentifier:(NSString *)rootIdentifier {
  @synchronized (self) {
    NSString *bound = [self.documentPublications objectForKey:document];
    if (bound) return bound;
    if (!sourceURL.isFileURL || ![self validUUID:rootIdentifier]) return nil;
    for (NSDictionary *record in self.records) {
      if ([self record:record matchesURL:sourceURL rootIdentifier:rootIdentifier]) {
        NSString *publication = record[@"publication"];
        [self.documentPublications setObject:publication forKey:document];
        return publication;
      }
    }
    return nil;
  }
}

- (BOOL)enablePublicationIdentifier:(NSString *)publicationIdentifier
                         forDocument:(NSDocument *)document
                           sourceURL:(NSURL *)sourceURL
                      rootIdentifier:(NSString *)rootIdentifier
                               error:(NSError **)error {
  if (![self validUUID:publicationIdentifier] || ![self validUUID:rootIdentifier] || !sourceURL.isFileURL || !self.registryURL) {
    if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteInvalidFileNameError userInfo:nil];
    return NO;
  }
  NSData *bookmark = [sourceURL bookmarkDataWithOptions:0 includingResourceValuesForKeys:@[NSURLFileResourceIdentifierKey]
                                           relativeToURL:nil error:error];
  if (!bookmark) return NO;
  @synchronized (self) {
    [self.records addObject:@{@"publication": publicationIdentifier, @"root": rootIdentifier,
                              @"bookmark": bookmark, @"path": sourceURL.URLByStandardizingPath.path}];
    if (![self writeRecordsWithError:error]) {
      [self.records removeLastObject];
      return NO;
    }
    [self.documentPublications setObject:publicationIdentifier forKey:document];
    return YES;
  }
}

- (BOOL)writeRecordsWithError:(NSError **)error {
    NSDictionary *root = @{@"schema": @(MPAutoFillRegistrySchemaVersion), @"publications": self.records};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:root format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;
    if (![NSFileManager.defaultManager createDirectoryAtURL:self.registryURL.URLByDeletingLastPathComponent
                                withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:error] ||
        ![data writeToURL:self.registryURL options:NSDataWritingAtomic error:error]) return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600}
                                    ofItemAtPath:self.registryURL.path error:NULL];
    return YES;
}

- (BOOL)movePublicationIdentifier:(NSString *)publicationIdentifier
                      forDocument:(NSDocument *)document
                        sourceURL:(NSURL *)sourceURL
                   rootIdentifier:(NSString *)rootIdentifier
                            error:(NSError **)error {
  NSData *bookmark = [sourceURL bookmarkDataWithOptions:0 includingResourceValuesForKeys:@[NSURLFileResourceIdentifierKey]
                                           relativeToURL:nil error:error];
  if (!bookmark) return NO;
  @synchronized (self) {
    NSUInteger index = [self.records indexOfObjectPassingTest:^BOOL(NSDictionary *record, NSUInteger index, BOOL *stop) {
      return [record[@"publication"] isEqualToString:publicationIdentifier];
    }];
    if (index == NSNotFound) return NO;
    NSDictionary *previous = self.records[index];
    self.records[index] = @{@"publication": publicationIdentifier, @"root": rootIdentifier,
                            @"bookmark": bookmark, @"path": sourceURL.URLByStandardizingPath.path};
    if (![self writeRecordsWithError:error]) {
      self.records[index] = previous;
      return NO;
    }
    [self.documentPublications setObject:publicationIdentifier forKey:document];
    return YES;
  }
}

- (BOOL)removePublicationIdentifier:(NSString *)publicationIdentifier error:(NSError **)error {
  @synchronized (self) {
    NSIndexSet *indexes = [self.records indexesOfObjectsPassingTest:^BOOL(NSDictionary *record, NSUInteger index, BOOL *stop) {
      return [record[@"publication"] isEqualToString:publicationIdentifier];
    }];
    if (indexes.count == 0) return YES;
    NSIndexSet *originalIndexes = [indexes copy];
    NSArray *removed = [self.records objectsAtIndexes:indexes];
    [self.records removeObjectsAtIndexes:indexes];
    if (![self writeRecordsWithError:error]) {
      [self.records insertObjects:removed atIndexes:originalIndexes];
      return NO;
    }
    NSMutableArray<NSDocument *> *documentsToDetach = [NSMutableArray array];
    for (NSDocument *document in self.documentPublications.keyEnumerator) {
      if ([[self.documentPublications objectForKey:document] isEqualToString:publicationIdentifier]) {
        [documentsToDetach addObject:document];
      }
    }
    for (NSDocument *document in documentsToDetach) [self.documentPublications removeObjectForKey:document];
    return YES;
  }
}

- (BOOL)markPublicationIdentifierPublished:(NSString *)publicationIdentifier atDate:(NSDate *)date error:(NSError **)error {
  @synchronized (self) {
    NSUInteger index = [self.records indexOfObjectPassingTest:^BOOL(NSDictionary *record, NSUInteger index, BOOL *stop) {
      return [record[@"publication"] isEqualToString:publicationIdentifier];
    }];
    if (index == NSNotFound || !date) return NO;
    NSDictionary *previous = self.records[index];
    NSMutableDictionary *updated = [previous mutableCopy];
    updated[@"published"] = date;
    self.records[index] = updated;
    if (![self writeRecordsWithError:error]) {
      self.records[index] = previous;
      return NO;
    }
    return YES;
  }
}

@end
