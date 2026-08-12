#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, MPAutoFillSaveAction) {
  MPAutoFillSaveActionNone = 0,
  MPAutoFillSaveActionPublish,
  MPAutoFillSaveActionChooseSaveAsPublication,
};

FOUNDATION_EXPORT MPAutoFillSaveAction MPAutoFillSaveActionForResult(NSSaveOperationType operation,
                                                                     BOOL saveSucceeded,
                                                                     BOOL publicationEnabled);
