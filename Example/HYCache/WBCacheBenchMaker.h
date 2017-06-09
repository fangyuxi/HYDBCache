//
//  WBCacheBenchMaker.h
//  HYCache
//
//  Created by fangyuxi on 2017/3/30.
//  Copyright © 2017年 fangyuxi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WBCacheBenchMaker : NSObject

- (void)writeSmallWithBlock:(void(^)(NSString *log))block;
- (void)writeLargeWithBlock:(void(^)(NSString *log))block;
- (void)writeLargeMultiThreadLargeWithBlock:(void(^)(NSString *log))block;
- (void)writeSmallMultiThreadLargeWithBlock:(void(^)(NSString *log))block;

@end
