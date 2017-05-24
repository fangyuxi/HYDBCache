#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "HYCache.h"
#import "HYDBStorage.h"
#import "HYDiskCache.h"
#import "HYDiskCacheItem.h"
#import "HYFileStorage.h"
#import "sqlite3.h"
#import "HYMemoryCache.h"

FOUNDATION_EXPORT double HYDBCacheVersionNumber;
FOUNDATION_EXPORT const unsigned char HYDBCacheVersionString[];

