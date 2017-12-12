//
//  SafeDanglingPoint.m
//  Demo
//
//  Created by admin on 2017/12/12.
//  Copyright © 2017年 admin. All rights reserved.
//

#import "SafeDanglingPointer.h"
#import "SafeObjectProxy.h"

#import <objc/runtime.h>
#import <list>

@interface SafeObjectProxy()

@property(nonatomic,readonly)NSArray *danglingPointerClassNames;
@property(nonatomic,readonly)NSInteger undellocedMaxCount;

+(instancetype)shareInstance;

@end

@interface SafeObjectRealProxy:NSProxy
@end

@implementation SafeObjectRealProxy

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector {
    return [[SafeObjectProxy shareInstance] methodSignatureForSelector:aSelector];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation {
    [anInvocation invokeWithTarget:[SafeObjectProxy shareInstance]];
}

@end

static std::list<id> undellocedList;

@implementation NSObject (SafeDanglingPointer)

- (void)sdp_danglingPointer_dealloc {
    Class selfClazz = object_getClass(self);
    
    BOOL needProtect = NO;
    
    for (NSString *className in [SafeObjectProxy shareInstance].danglingPointerClassNames) {
        Class clazz = objc_getClass([className UTF8String]);
        if (clazz == selfClazz) {
            needProtect = YES;
            break;
        }
    }
    
    if (needProtect) {
        objc_destructInstance(self);
        object_setClass(self, [SafeObjectRealProxy class]);
        
        undellocedList.size();
        if (undellocedList.size() >= [SafeObjectProxy shareInstance].undellocedMaxCount) {
            id object = undellocedList.front();
            undellocedList.pop_front();
            free(object);
        }
        undellocedList.push_back(self);
    } else {
        [self sdp_danglingPointer_dealloc];
    }
}

@end

