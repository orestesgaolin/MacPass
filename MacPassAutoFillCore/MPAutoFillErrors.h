#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const MPAutoFillErrorDomain;

typedef NS_ERROR_ENUM(MPAutoFillErrorDomain, MPAutoFillErrorCode) {
  MPAutoFillErrorInvalidArgument = 1,
  MPAutoFillErrorUnsupportedSchema,
  MPAutoFillErrorMalformedSnapshot,
  MPAutoFillErrorLimitExceeded,
  MPAutoFillErrorContextMismatch,
  MPAutoFillErrorCryptoAlgorithmUnsupported,
  MPAutoFillErrorEncryptionFailed,
  MPAutoFillErrorDecryptionFailed,
  MPAutoFillErrorKeychainUnavailable,
  MPAutoFillErrorItemNotFound,
  MPAutoFillErrorUserInteractionRequired,
  MPAutoFillErrorUserCancelled,
  MPAutoFillErrorAuthenticationFailed,
  MPAutoFillErrorStorageUnavailable,
  MPAutoFillErrorUnsafeFile,
  MPAutoFillErrorGenerationIncomplete,
};

FOUNDATION_EXPORT NSError *MPAutoFillError(MPAutoFillErrorCode code,
                                           NSString *description,
                                           NSError * _Nullable underlyingError);
FOUNDATION_EXPORT NSError *MPAutoFillKeychainError(OSStatus status, NSString *operation);
FOUNDATION_EXPORT NSError *MPAutoFillSecurityError(NSError *securityError, NSString *operation);

NS_ASSUME_NONNULL_END
