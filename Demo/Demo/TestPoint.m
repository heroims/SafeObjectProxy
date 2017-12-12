//
//  TestPoint.m
//  Demo
//
//  Created by admin on 2017/12/12.
//  Copyright © 2017年 admin. All rights reserved.
//

#import "TestPoint.h"
@interface SSS:NSObject
@end
@implementation SSS
-(void)a{
    NSLog(@"111");
}
@end
@implementation TestPoint

-(instancetype)init{
    if (self=[super init]) {
        SSS *sss=[[SSS alloc] init];
        [sss release];
        
        [sss a];
    }
    return self;
}
@end
