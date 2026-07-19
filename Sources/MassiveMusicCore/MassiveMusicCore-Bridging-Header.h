#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL MassiveMusicWriteM4AHeader(
    NSURL *url,
    NSDictionary<NSString *, id> *info,
    NSError **error
);

FOUNDATION_EXPORT NSDictionary<NSString *, id> *MassiveMusicReadM4AMetadata(
    NSURL *url,
    NSError **error
);
