//
//  HYDiskCacheItem.h
//  Pods
//
//  Created by fangyuxi on 2017/1/17.
//
//

#import <Foundation/Foundation.h>

/**
 disk cache item
 */

@interface HYDiskCacheItem : NSObject

@property (nonatomic, strong) NSString *key;            ///< key
@property (nonatomic, strong) NSData *value;            ///< value
@property (nonatomic, strong) NSString *fileName;       ///< filename key.md5 by default
@property (nonatomic) NSInteger size;                   ///< size
@property (nonatomic) NSInteger inTimeStamp;            ///< inCache time stamp
@property (nonatomic) NSInteger lastAccessTimeStamp;    ///< the lasted access time stamp

@end
