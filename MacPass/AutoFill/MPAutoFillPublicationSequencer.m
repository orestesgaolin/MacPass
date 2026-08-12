#import "MPAutoFillPublicationSequencer.h"

@interface MPAutoFillPublicationSequencer ()
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *nextTokens;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *latestSuccessfulTokens;
@end

@implementation MPAutoFillPublicationSequencer

- (instancetype)init {
  self = [super init];
  if (self) {
    _nextTokens = [NSMutableDictionary dictionary];
    _latestSuccessfulTokens = [NSMutableDictionary dictionary];
  }
  return self;
}

- (uint64_t)beginSaveForPublicationIdentifier:(NSString *)publicationIdentifier {
  @synchronized (self) {
    uint64_t token = self.nextTokens[publicationIdentifier].unsignedLongLongValue + 1;
    self.nextTokens[publicationIdentifier] = @(token);
    return token;
  }
}

- (BOOL)registerSuccessfulSaveToken:(uint64_t)saveToken publicationIdentifier:(NSString *)publicationIdentifier {
  @synchronized (self) {
    uint64_t latest = self.latestSuccessfulTokens[publicationIdentifier].unsignedLongLongValue;
    if (saveToken < latest) return NO;
    self.latestSuccessfulTokens[publicationIdentifier] = @(saveToken);
    return YES;
  }
}

- (void)invalidatePublicationIdentifier:(NSString *)publicationIdentifier {
  @synchronized (self) {
    uint64_t token = self.nextTokens[publicationIdentifier].unsignedLongLongValue + 1;
    self.nextTokens[publicationIdentifier] = @(token);
    self.latestSuccessfulTokens[publicationIdentifier] = @(token);
  }
}

- (BOOL)performIfCurrentToken:(uint64_t)saveToken
        publicationIdentifier:(NSString *)publicationIdentifier
                       action:(BOOL (^)(NSError **error))action
                        error:(NSError **)error {
  @synchronized (self) {
    if (self.latestSuccessfulTokens[publicationIdentifier].unsignedLongLongValue != saveToken) return NO;
    return action(error);
  }
}

@end
