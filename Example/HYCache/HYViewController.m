//
//  HYViewController.m
//  HYCache
//
//  Created by fangyuxi on 01/17/2017.
//  Copyright (c) 2017 fangyuxi. All rights reserved.
//

#import "HYViewController.h"
#import "WBCacheBenchMaker.h"

@interface HYViewController ()
{
    
}
@end

@implementation HYViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[[WBCacheBenchMaker alloc] init ] startDisk];
    });
}

@end
