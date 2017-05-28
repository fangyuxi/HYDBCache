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

- (void)startDisk{
    //[self writeLarge];
    [self writeSmall];
    //[self writeLargeMultiThreadLarge];
    [self writeLargeMultiThreadSmall];
}

- (void)writeSmall{
    HYDiskCache *hyDisk = [[HYDiskCache alloc] initWithName:@"hyDiskSmall"];
    
    NSInteger count = 10000;
    NSMutableArray *keys = [NSMutableArray new];
    for (int i = 0; i < count; i++) {
        NSString *key = @(i).description;
        [keys addObject:key];
    }
    NSMutableData *dataValue = [NSMutableData new];
    for (int i = 0; i < 15 * 1024; i++) {
        [dataValue appendBytes:&i length:1];
    }
    
    NSTimeInterval begin, end, time;
    
    printf("\n===========================\n");
    printf("hyDisk cache set 1000 key-value pairs (value is NSData(15KB))\n");
    
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

- (void)writeLargeMultiThreadLarge{
    __block HYDiskCache *hyDisk = [[HYDiskCache alloc] initWithName:@"hyDiskMultiThreadLarge"];
    
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
    
    __block NSTimeInterval begin, end, time;
    
    printf("\n===========================\n");
    printf("hyDisk cache set 1000 key-value pairs MultiThread (value is NSData(100KB))\n");
    
    
    dispatch_group_t group = dispatch_group_create();
    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            dispatch_group_enter(group);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [hyDisk setObject:dataValue forKey:keys[i]];
                dispatch_group_leave(group);
            });
        }
    }
    dispatch_notify(group, dispatch_get_main_queue(), ^(){
        end = CACurrentMediaTime();
        time = end - begin;
        printf("hyDisk cache MultiThread large time:     %8.2f\n", time * 1000);
    });
}

- (void)writeLargeMultiThreadSmall{
    HYDiskCache *hyDisk = [[HYDiskCache alloc] initWithName:@"hyDiskMultiThreadSmall"];
    
    NSInteger count = 1000;
    NSMutableArray *keys = [NSMutableArray new];
    for (int i = 0; i < count; i++) {
        NSString *key = @(i).description;
        [keys addObject:key];
    }
    NSMutableData *dataValue = [NSMutableData new];
    for (int i = 0; i < 15 * 1024; i++) {
        [dataValue appendBytes:&i length:1];
    }
    
    __block NSTimeInterval begin, end, time;
    
    printf("\n===========================\n");
    printf("hyDisk cache set 1000 key-value pairs MultiThread (value is NSData(15KB))\n");
    
    
    dispatch_group_t group = dispatch_group_create();
    begin = CACurrentMediaTime();
    @autoreleasepool {
        for (int i = 0; i < count; i++) {
            dispatch_group_enter(group);
            [hyDisk setObject:dataValue forKey:keys[i] withBlock:^(HYDiskCache * _Nonnull cache, NSString * _Nonnull key, id  _Nullable object) {
                dispatch_group_leave(group);
            }];
        }
    }
    dispatch_notify(group, dispatch_get_main_queue(), ^(){
        end = CACurrentMediaTime();
        time = end - begin;
        printf("hyDisk cache MultiThread large time:     %8.2f\n", time * 1000);
    });
}


@end
