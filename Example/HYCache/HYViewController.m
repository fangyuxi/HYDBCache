//
//  HYViewController.m
//  HYCache
//
//  Created by fangyuxi on 01/17/2017.
//  Copyright (c) 2017 fangyuxi. All rights reserved.
//

#import "HYViewController.h"
#import "HYDBRunnner.h"

dispatch_semaphore_t semaphoreLock;

static inline void lock()
{
    dispatch_semaphore_wait(semaphoreLock, DISPATCH_TIME_FOREVER);
}

static inline void unLock()
{
    dispatch_semaphore_signal(semaphoreLock);
}


@interface HYViewController ()
{
    HYDBRunnner *runner;
}
@end

@implementation HYViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    semaphoreLock = dispatch_semaphore_create(1);
    
	// Do any additional setup after loading the view, typically from a nib.
    NSLog(@"%ld", sizeof(int));
    NSLog(@"%ld", sizeof(long));
    NSLog(@"%ld", sizeof(long long));
    NSLog(@"%ld", sizeof(float));
    NSLog(@"%ld", sizeof(double));
    NSLog(@"%ld", sizeof(char));
    NSLog(@"%ld", sizeof(void *));
    NSLog(@"%ld", sizeof(NSInteger));

    
    NSString *path = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    path = [path stringByAppendingPathComponent:@"fangyuxi"];
    runner = [[HYDBRunnner alloc] initWithDBPath:path];
    
    
    if ([runner open]) {
        for (NSInteger index = 0; index < 10000; ++index) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
               
                lock();
                [runner saveWithKey:[@(index) stringValue] value:[[@(index) stringValue] dataUsingEncoding:NSUTF8StringEncoding] fileName:[@(index + 1000000) stringValue]];
                unLock();
                
                NSLog(@"%ld", index);
                lock();
                [runner removeItemWithKey:[@(index) stringValue]];
                unLock();
                
                lock();
                NSInteger end = [runner getTotalItemCount];
                NSLog(@"%ld", end);
                unLock();
            });
        }
    }
    
    
    if ([runner close]) {
        runner = nil;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
