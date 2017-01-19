//
//  HYViewController.m
//  HYCache
//
//  Created by fangyuxi on 01/17/2017.
//  Copyright (c) 2017 fangyuxi. All rights reserved.
//

#import "HYViewController.h"
#import "HYDBStorage.h"
#import "HYDiskCacheItem.h"
#import "HYDiskCache.h"

dispatch_semaphore_t semaphoreLock;

//static inline void lock()
//{
//    dispatch_semaphore_wait(semaphoreLock, DISPATCH_TIME_FOREVER);
//}
//
//static inline void unLock()
//{
//    dispatch_semaphore_signal(semaphoreLock);
//}


@interface HYViewController ()
{
    HYDiskCache *cache;
}
@end

@implementation HYViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    semaphoreLock = dispatch_semaphore_create(1);
    
    NSString *path = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    path = [path stringByAppendingPathComponent:@"fangyuxi"];
//    runner = [[HYDBStorage alloc] initWithDBPath:path];
//    
//    HYDiskCacheItem *item = [[HYDiskCacheItem alloc] init];
//    item.key = @"1";
//    item.value = [@"fangyuxi" dataUsingEncoding:NSUTF8StringEncoding];
//    item.fileName = @"1";
//    item.size = item.value.length;
//    
//    //[runner saveWithKey:[@(1) stringValue] value:[[@(1) stringValue] dataUsingEncoding:NSUTF8StringEncoding] fileName:[@(1) stringValue]];
//    
//    [runner saveItem:item shouldStoreValueInDB:YES];
//    [runner getItemForKey:@"1"];

    
    cache = [[HYDiskCache alloc] initWithName:@"cache" andDirectoryPath:path];
    
    for (NSInteger index = 0; index < 10000; ++index) {
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            
            [cache setObject:@(index) forKey:[@(index) stringValue]];
            NSLog(@"%ld", index);
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"read: %@", [cache objectForKey:[@(index) stringValue]]);
            });
        });
    }
    
    
    
    
    
//    for (NSInteger index = 0; index < 10000; ++index) {
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
//            
//            lock();
//            [runner saveWithKey:[@(index) stringValue] value:[[@(index) stringValue] dataUsingEncoding:NSUTF8StringEncoding] fileName:[@(index + 1000000) stringValue]];
//            unLock();
//            
//            NSLog(@"%ld", (long)index);
//            lock();
//            [runner removeItemWithKey:[@(index) stringValue]];
//            unLock();
//            
//            lock();
//            NSInteger end = [runner getTotalItemCount];
//            NSLog(@"%ld", (long)end);
//            unLock();
//        });
//    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
