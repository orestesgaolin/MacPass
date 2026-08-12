#import "MPAutoFillSavePolicy.h"

MPAutoFillSaveAction MPAutoFillSaveActionForResult(NSSaveOperationType operation,
                                                    BOOL saveSucceeded,
                                                    BOOL publicationEnabled) {
  if (!saveSucceeded || !publicationEnabled || operation == NSSaveToOperation) {
    return MPAutoFillSaveActionNone;
  }
  if (operation == NSSaveAsOperation) {
    return MPAutoFillSaveActionChooseSaveAsPublication;
  }
  return MPAutoFillSaveActionPublish;
}
