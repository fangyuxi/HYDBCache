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
    [[[WBCacheBenchMaker alloc] init ] start];

}

@end
