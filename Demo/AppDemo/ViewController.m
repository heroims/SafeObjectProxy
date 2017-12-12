//
//  ViewController.m
//  AppDemo
//
//  Created by admin on 2017/12/12.
//  Copyright © 2017年 admin. All rights reserved.
//

#import "ViewController.h"
#import "SafeObjectProxy.h"
#import "TestPoint.h"
@interface ViewController ()
+(void)aaaaaaa;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [SafeObjectProxy startSafeObjectProxy];
    [SafeObjectProxy addSafeDanglingPointerClassNames:@[@"SSS"]];

    NSArray *arr=@[@""];
    arr[3];
    arr=[arr arrayByAddingObjectsFromArray:nil];
    
    [self performSelector:@selector(ddddddd)];
    
    NSLog(@"1");
    TestPoint *a=[[TestPoint alloc] init];
    NSLog(@"2");
    [ViewController aaaaaaa];
    NSLog(@"3");
    [((NSString*)[NSNull null]) substringToIndex:10];
    [((NSString*)nil) substringToIndex:10];


}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
