#import "MPAutoFillCredentialIdentifier.h"

#import "MPAutoFillErrors.h"

static BOOL MPAutoFillIdentifierCanonicalUUID(NSString *value) {
  if (![value isKindOfClass:NSString.class] || value.length != 36 ||
      ![value canBeConvertedToEncoding:NSASCIIStringEncoding]) {
    return NO;
  }
  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
  return uuid && [uuid.UUIDString.lowercaseString isEqualToString:value];
}

@interface MPAutoFillCredentialIdentifier ()
@property(nonatomic, readwrite, copy) NSString *publicationIdentifier;
@property(nonatomic, readwrite, copy) NSString *entryIdentifier;
@property(nonatomic, readwrite, copy) NSString *recordIdentifier;
@end

@implementation MPAutoFillCredentialIdentifier

+ (instancetype)identifierWithPublicationIdentifier:(NSString *)publicationIdentifier
                                      entryIdentifier:(NSString *)entryIdentifier
                                                error:(NSError **)error {
  if (!MPAutoFillIdentifierCanonicalUUID(publicationIdentifier) ||
      !MPAutoFillIdentifierCanonicalUUID(entryIdentifier)) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The credential identifier contains an invalid UUID.", nil);
    }
    return nil;
  }

  MPAutoFillCredentialIdentifier *identifier = [[self alloc] init];
  identifier.publicationIdentifier = publicationIdentifier;
  identifier.entryIdentifier = entryIdentifier;
  identifier.recordIdentifier = [NSString stringWithFormat:@"v1:%@:%@", publicationIdentifier, entryIdentifier];
  return identifier;
}

+ (instancetype)identifierWithRecordIdentifier:(NSString *)recordIdentifier error:(NSError **)error {
  if (![recordIdentifier isKindOfClass:NSString.class] ||
      ![recordIdentifier canBeConvertedToEncoding:NSASCIIStringEncoding]) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The credential identifier is malformed.", nil);
    }
    return nil;
  }
  NSArray<NSString *> *components = [recordIdentifier componentsSeparatedByString:@":"];
  if (components.count != 3 || ![components[0] isEqualToString:@"v1"]) {
    if (error) {
      *error = MPAutoFillError(MPAutoFillErrorInvalidArgument, @"The credential identifier version or structure is invalid.", nil);
    }
    return nil;
  }
  return [self identifierWithPublicationIdentifier:components[1] entryIdentifier:components[2] error:error];
}

@end
