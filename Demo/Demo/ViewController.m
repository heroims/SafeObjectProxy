//
//  ViewController.m
//  Demo
//
//  Created by admin on 2017/12/8.
//  Copyright © 2017年 admin. All rights reserved.
//

#import "ViewController.h"
#import "SafeObjectProxy.h"

@interface SafeObjectProxy(Report)<SafeObjectReportProtocol>
@end
@implementation SafeObjectProxy(Report)
-(void)reportDefendCrashLog:(NSString *)log{
    NSArray *array=[NSThread callStackSymbols];
    NSLog(@"crash log:%@\n%@",log,array);
}
@end

@protocol AAAA<NSObject>
+(void)aaaaaaa;
@end

@interface ViewController()<AAAA>
@end
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [SafeObjectProxy startSafeObjectProxy];
    
    NSArray *arr=@[@""];
    arr[3];
    arr=[arr arrayByAddingObjectsFromArray:nil];
    
    [self performSelector:@selector(ddddddd)];
    
    [ViewController aaaaaaa];
    // Do any additional setup after loading the view.
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end
