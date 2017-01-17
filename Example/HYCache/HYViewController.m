//
//  HYViewController.m
//  HYCache
//
//  Created by fangyuxi on 01/17/2017.
//  Copyright (c) 2017 fangyuxi. All rights reserved.
//

#import "HYViewController.h"
#import "HYDBRunnner.h"

@interface HYViewController ()

@end

@implementation HYViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
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
    HYDBRunnner *runner = [[HYDBRunnner alloc] initWithDBPath:path];
    
    
    if ([runner open]) {
        for (NSInteger index = 0; index < 10000; ++index) {
            [runner saveWithKey:[@(index) stringValue] value:[[@(index) stringValue] dataUsingEncoding:NSUTF8StringEncoding] fileName:[@(index + 1000000) stringValue]];
            
            NSInteger count = [runner getTotalItemCount];
            NSLog(@"%ld", count);
        }
    }
    
    [runner removeItemWithKey:[@200 stringValue]];
    [runner removeItemWithKey:[@100 stringValue]];
    [runner removeItemWithKey:[@300 stringValue]];
    [runner removeItemWithKey:[@2500 stringValue]];
    [runner removeAllItems];
    NSInteger end = [runner getTotalItemCount];
    NSLog(@"%ld", end);
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
