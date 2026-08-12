#import "MPAutoFillErrors.h"

#import <Security/Security.h>

NSErrorDomain const MPAutoFillErrorDomain = @"dev.roszkowski.macpass.autofill";

NSError *MPAutoFillError(MPAutoFillErrorCode code,
                         NSString *description,
                         NSError *underlyingError) {
  NSMutableDictionary *userInfo = [@{NSLocalizedDescriptionKey: description} mutableCopy];
  if (underlyingError) {
    userInfo[NSUnderlyingErrorKey] = underlyingError;
  }
  return [NSError errorWithDomain:MPAutoFillErrorDomain code:code userInfo:userInfo];
}

NSError *MPAutoFillKeychainError(OSStatus status, NSString *operation) {
  MPAutoFillErrorCode code = MPAutoFillErrorKeychainUnavailable;
  switch (status) {
    case errSecItemNotFound:
      code = MPAutoFillErrorItemNotFound;
      break;
    case errSecInteractionNotAllowed:
      code = MPAutoFillErrorUserInteractionRequired;
      break;
    case errSecUserCanceled:
      code = MPAutoFillErrorUserCancelled;
      break;
    case errSecAuthFailed:
      code = MPAutoFillErrorAuthenticationFailed;
      break;
  }
  NSError *underlyingError = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
  return MPAutoFillError(code, operation, underlyingError);
}

NSError *MPAutoFillSecurityError(NSError *securityError, NSString *operation) {
  if ([securityError.domain isEqualToString:NSOSStatusErrorDomain]) {
    switch ((OSStatus)securityError.code) {
      case errSecInteractionNotAllowed:
      case errSecUserCanceled:
      case errSecAuthFailed:
        return MPAutoFillKeychainError((OSStatus)securityError.code, operation);
    }
  }
  return MPAutoFillError(MPAutoFillErrorDecryptionFailed, operation, securityError);
}
