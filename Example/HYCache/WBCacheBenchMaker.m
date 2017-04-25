//
//  WBCacheBenchMaker.m
//  HYCache
//
//  Created by fangyuxi on 2017/3/30.
//  Copyright © 2017年 fangyuxi. All rights reserved.
//

#import "WBCacheBenchMaker.h"
#import "HYDBStorage.h"
#import "HYDiskCacheItem.h"
#import "HYDiskCache.h"

@implementation WBCacheBenchMaker

- (void)start{
    [self writeLarge];
}

- (void)writeSmall{
    
}

- (void)writeLarge{
    HYDiskCache *hyDisk = [[HYDiskCache alloc] initWithName:@"hyDiskLarge"];
    
    NSInteger count = 1000;
    NSMutableArray *keys = [NSMutableArray new];
    for (int i = 0; i < count; i++) {
        NSString *key = @(i).description;
        [keys addObject:key];
    }
    NSMutableData *dataValue = [NSMutableData new];
    for (int i = 0; i < 100 * 1024; i++) {
        [dataValue appendBytes:&i length:1];
    }
    
    NSTimeInterval begin, end, time;
    
    printf("\n===========================\n");
    printf("hyDisk cache set 1000 key-value pairs (value is NSData(100KB))\n");
    
    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            [hyDisk setObject:dataValue forKey:keys[i]];
        }
    }
    end = CACurrentMediaTime();
    time = end - begin;
    printf("hyDisk cache large time:     %8.2f\n", time * 1000);
}

@end
