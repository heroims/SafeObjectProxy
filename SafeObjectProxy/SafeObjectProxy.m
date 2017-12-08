//
//  SafeObjectProxy.m
//  admin
//
//  Created by admin on 2017/1/4.
//  Copyright © 2017年 admin. All rights reserved.
//

#import "SafeObjectProxy.h"

#if TARGET_OS_IPHONE
#import <objc/runtime.h>
#import <objc/message.h>
#else
#import <objc/objc-class.h>
#endif


@interface SafeObjectProxy()

+(instancetype)shareInstance;

/**
 动态创建方法，保证最少的动态创建方法
 
 @param aSelector 方法
 @param isStaticMethod 是否是静态方法
 */
-(void)addMethod:(SEL)aSelector isStaticMethod:(BOOL)isStaticMethod;


/**
 上报防御的crash log

 @param log log无法抓到Notification的遗漏添加情况
 */
-(void)_reportDefendCrashLog:(NSString*)log;

@end

#pragma mark - Swizzing

@interface NSObject (SOPSwizzle)

+ (BOOL)sops_swizzleMethod:(SEL)origSel_ withMethod:(SEL)altSel_ error:(NSError**)error_;
+ (BOOL)sops_swizzleClassMethod:(SEL)origSel_ withClassMethod:(SEL)altSel_ error:(NSError**)error_;

@end

#define SOPSetNSErrorFor(FUNC, ERROR_VAR, FORMAT,...)    \
if (ERROR_VAR) {    \
NSString *errStr = [NSString stringWithFormat:@"%s: " FORMAT,FUNC,##__VA_ARGS__]; \
*ERROR_VAR = [NSError errorWithDomain:@"NSCocoaErrorDomain" \
code:-1    \
userInfo:[NSDictionary dictionaryWithObject:errStr forKey:NSLocalizedDescriptionKey]]; \
}
#define SOPSetNSError(ERROR_VAR, FORMAT,...) SOPSetNSErrorFor(__func__, ERROR_VAR, FORMAT, ##__VA_ARGS__)

#if OBJC_API_VERSION >= 2
#define SOPGetClass(obj)    object_getClass(obj)
#else
#define SOPGetClass(obj)    (obj ? obj->isa : Nil)
#endif

@implementation NSObject (SOPSwizzle)

+ (BOOL)sops_swizzleMethod:(SEL)origSel_ withMethod:(SEL)altSel_ error:(NSError**)error_ {
#if OBJC_API_VERSION >= 2
    Method origMethod = class_getInstanceMethod(self, origSel_);
    if (!origMethod) {
#if TARGET_OS_IPHONE
        SOPSetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self class]);
#else
        SOPSetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self className]);
#endif
        return NO;
    }
    
    Method altMethod = class_getInstanceMethod(self, altSel_);
    if (!altMethod) {
#if TARGET_OS_IPHONE
        SOPSetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self class]);
#else
        SOPSetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self className]);
#endif
        return NO;
    }
    
    class_addMethod(self,
                    origSel_,
                    class_getMethodImplementation(self, origSel_),
                    method_getTypeEncoding(origMethod));
    class_addMethod(self,
                    altSel_,
                    class_getMethodImplementation(self, altSel_),
                    method_getTypeEncoding(altMethod));
    
    method_exchangeImplementations(class_getInstanceMethod(self, origSel_), class_getInstanceMethod(self, altSel_));
    return YES;
#else
    //    Scan for non-inherited methods.
    Method directOriginalMethod = NULL, directAlternateMethod = NULL;
    
    void *iterator = NULL;
    struct objc_method_list *mlist = class_nextMethodList(self, &iterator);
    while (mlist) {
        int method_index = 0;
        for (; method_index < mlist->method_count; method_index++) {
            if (mlist->method_list[method_index].method_name == origSel_) {
                assert(!directOriginalMethod);
                directOriginalMethod = &mlist->method_list[method_index];
            }
            if (mlist->method_list[method_index].method_name == altSel_) {
                assert(!directAlternateMethod);
                directAlternateMethod = &mlist->method_list[method_index];
            }
        }
        mlist = class_nextMethodList(self, &iterator);
    }
    
    //    If either method is inherited, copy it up to the target class to make it non-inherited.
    if (!directOriginalMethod || !directAlternateMethod) {
        Method inheritedOriginalMethod = NULL, inheritedAlternateMethod = NULL;
        if (!directOriginalMethod) {
            inheritedOriginalMethod = class_getInstanceMethod(self, origSel_);
            if (!inheritedOriginalMethod) {
#if TARGET_OS_IPHONE
                SOPSetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self class]);
#else
                SOPSetNSError(error_, @"original method %@ not found for class %@", NSStringFromSelector(origSel_), [self className]);
#endif
                return NO;
            }
        }
        if (!directAlternateMethod) {
            inheritedAlternateMethod = class_getInstanceMethod(self, altSel_);
            if (!inheritedAlternateMethod) {
#if TARGET_OS_IPHONE
                SOPSetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self class]);
#else
                SOPSetNSError(error_, @"alternate method %@ not found for class %@", NSStringFromSelector(altSel_), [self className]);
#endif
                return NO;
            }
        }
        
        int hoisted_method_count = !directOriginalMethod && !directAlternateMethod ? 2 : 1;
        struct objc_method_list *hoisted_method_list = malloc(sizeof(struct objc_method_list) + (sizeof(struct objc_method)*(hoisted_method_count-1)));
        hoisted_method_list->obsolete = NULL;    // soothe valgrind - apparently ObjC runtime accesses this value and it shows as uninitialized in valgrind
        hoisted_method_list->method_count = hoisted_method_count;
        Method hoisted_method = hoisted_method_list->method_list;
        
        if (!directOriginalMethod) {
            bcopy(inheritedOriginalMethod, hoisted_method, sizeof(struct objc_method));
            directOriginalMethod = hoisted_method++;
        }
        if (!directAlternateMethod) {
            bcopy(inheritedAlternateMethod, hoisted_method, sizeof(struct objc_method));
            directAlternateMethod = hoisted_method;
        }
        class_addMethods(self, hoisted_method_list);
    }
    
    //    Swizzle.
    IMP temp = directOriginalMethod->method_imp;
    directOriginalMethod->method_imp = directAlternateMethod->method_imp;
    directAlternateMethod->method_imp = temp;
    
    return YES;
#endif
}

+ (BOOL)sops_swizzleClassMethod:(SEL)origSel_ withClassMethod:(SEL)altSel_ error:(NSError**)error_ {
    return [SOPGetClass((id)self) sops_swizzleMethod:origSel_ withMethod:altSel_ error:error_];
}
@end

#define LOG_Error {if(error)NSLog(@"%@",error.debugDescription);error = nil;}

@interface NSObject (SafeObjectProxy)
@property(nonatomic,assign)BOOL sop_useNotification;
@end
@implementation NSObject (SafeObjectProxy)

#pragma mark - NSNotificationCenter

@dynamic sop_useNotification;

static const void *sop_useNotificationKey = &sop_useNotificationKey;

-(void)setSop_useNotification:(BOOL)sop_useNotification{
    objc_setAssociatedObject(self, sop_useNotificationKey, [NSNumber numberWithBool:sop_useNotification], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(BOOL)sop_useNotification{
    return [objc_getAssociatedObject(self, sop_useNotificationKey) boolValue];
}

-(void)sop_notification_dealloc{
    
    //NSNotificationCenter 遗漏处理
    if (self.sop_useNotification) {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
    
    [self sop_notification_dealloc];
}

#pragma mark - KVC

/**
 KVC 防御value或key为空
 */
-(void)sop_setValue:(id)value forKey:(NSString *)key{
    if (value==nil||key==nil) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ KVC key or value is  nil",NSStringFromClass([self class])]];
        return;
    }
    [self sop_setValue:value forKey:key];
}

/**
 KVC 防御value或keyPath为空
 */
-(void)sop_setValue:(id)value forKeyPath:(NSString *)keyPath{
    if (value==nil||keyPath==nil) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ KVC keyPath or value is  nil",NSStringFromClass([self class])]];
        return;
    }
    [self sop_setValue:value forKeyPath:keyPath];
}

/**
 KVC 切面添加未找到注册属性的处理
 */
-(void)sop_setValue:(id)value forUndefinedKey:(NSString *)key{
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ KVC undefinedKey",NSStringFromClass([self class])]];
}

#pragma mark - Unrecoginzed Selector

/**
 实例方法 Unrecoginzed Selector Crash
 */
-(id)sop_forwardingTargetForSelector:(SEL)aSelector{
    id safeObject=[self sop_hookStaticMethod:NO forwardingTargetForSelector:aSelector];
    if (safeObject) {
        return safeObject;
    }
    return [self sop_forwardingTargetForSelector:aSelector];
}


/**
 静态方法 Unrecoginzed Selector Crash
 */
-(id)sop_classForwardingTargetForSelector:(SEL)aSelector{
    
    id safeObject=[self sop_hookStaticMethod:YES forwardingTargetForSelector:aSelector];
    if (safeObject) {
        return safeObject;
    }
    return [self sop_classForwardingTargetForSelector:aSelector];
}


/**
 返回正确的签名函数，没有就创建

 @param isStaticMethod 是否是静态方法
 @param aSelector 方法
 */
-(id)sop_hookStaticMethod:(BOOL)isStaticMethod forwardingTargetForSelector:(SEL)aSelector{
    if ([self isKindOfClass:[NSNumber class]] && [NSString instancesRespondToSelector:aSelector]) {
        NSNumber *number = (NSNumber *)self;
        NSString *str = [number stringValue];
        return str;
    } else if ([self isKindOfClass:[NSString class]] && [NSNumber instancesRespondToSelector:aSelector]) {
        NSString *str = (NSString *)self;
        NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
        NSNumber *number = [formatter numberFromString:str];
        return number;
    }
    
    BOOL aBool = [self respondsToSelector:aSelector];
    NSMethodSignature *signatrue = [self methodSignatureForSelector:aSelector];
    
    if (!(aBool || signatrue)) {
        [[SafeObjectProxy shareInstance] addMethod:aSelector isStaticMethod:isStaticMethod];
        if (isStaticMethod) {
            [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@  unfind static method  %@",NSStringFromClass([self class]),NSStringFromSelector(aSelector)]];
            
            return [SafeObjectProxy class];
        }
        else{
            [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@  unfind method  %@",NSStringFromClass([self class]),NSStringFromSelector(aSelector)]];

            return [SafeObjectProxy shareInstance];
        }
    }
    return nil;
}

@end

#pragma mark - NSNotificationCenter

@interface NSNotificationCenter (SafeObjectProxy)
@end
@implementation NSNotificationCenter (SafeObjectProxy)

/**
 记录注册NSNotification动作
 */
-(void)sop_addObserver:(id)observer selector:(SEL)aSelector name:(NSNotificationName)aName object:(id)anObject{
    if ([observer isKindOfClass:[NSObject class]]) {
        [(NSObject*)observer setSop_useNotification:YES];
    }
    [self sop_addObserver:observer selector:aSelector name:aName object:anObject];
}

@end

#pragma mark - UI Main Thread

#if TARGET_OS_WATCH
#elif TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
@interface UIView(SafeObjectProxy)
@end
@implementation UIView(SafeObjectProxy)
-(void)sop_setNeedsLayout{
    if ([NSThread isMainThread]) {
        [self sop_setNeedsLayout];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ setNeedsLayout is not on main thread",NSStringFromClass([self class])]];

        [self sop_setNeedsLayout];
    });

}

-(void)sop_setNeedsDisplay{
    if ([NSThread isMainThread]) {
        [self sop_setNeedsDisplay];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ setNeedsDisplay is not on main thread",NSStringFromClass([self class])]];

        [self sop_setNeedsDisplay];
    });
}

-(void)sop_setNeedsDisplayInRect:(CGRect)rect{
    if ([NSThread isMainThread]) {
        [self sop_setNeedsDisplayInRect:rect];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ setNeedsDisplayInRect is not on main thread",NSStringFromClass([self class])]];

        [self sop_setNeedsDisplayInRect:rect];
    });
}
@end
#else
#import <AppKit/AppKit.h>
@interface NSView(SafeObjectProxy)
@end
@implementation NSView(SafeObjectProxy)

-(void)sop_setNeedsLayout:(BOOL)needsLayout{
    if ([NSThread isMainThread]) {
        [self sop_setNeedsLayout:needsLayout];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ setNeedsLayout is not on main thread",NSStringFromClass([self class])]];

        [self sop_setNeedsLayout:needsLayout];
    });
}

-(void)sop_setNeedsDisplay:(BOOL)needsDisplay{
    if ([NSThread isMainThread]) {
        [self sop_setNeedsDisplay:needsDisplay];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ setNeedsDisplay is not on main thread",NSStringFromClass([self class])]];

        [self sop_setNeedsDisplay:needsDisplay];
    });
}

-(void)sop_setNeedsDisplayInRect:(NSRect)invalidRect{
    if ([NSThread isMainThread]) {
        [self sop_setNeedsDisplayInRect:invalidRect];
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ setNeedsDisplayInRect is not on main thread",NSStringFromClass([self class])]];

        [self sop_setNeedsDisplayInRect:invalidRect];
    });
}
@end
#endif

#pragma mark - Array

@interface NSArray(SafeObjectProxy)
@end
@implementation NSArray(SafeObjectProxy)


/**
 * 崩溃情况：NSArrary 一般在初始化时候崩溃,（初始化有空值） __NSPlaceholderArray initWithObjects:count:
 */
-(id)sop_initWithObjects:(const id [])objects count:(NSUInteger)cnt
{
    for (int i=0; i<cnt; i++) {
        if(objects[i] == nil){
            [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ init objects contain nil",NSStringFromClass([self class])]];
            return nil;
        }
    }
    
    return [self sop_initWithObjects:objects count:cnt];
}

/**
 *  崩溃情况：index越界
 */
-(id)sop_objectAtIndex:(int)index{
    if(index>=0 && index < self.count)
    {
        return [self sop_objectAtIndex:index];
    }
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index is outside of the bounds",NSStringFromClass([self class])]];
    return nil;
}

/**
 *  崩溃情况：anObject = nil
 */
- (NSArray *)sop_arrayByAddingObject:(id)anObject {
    
    if (!anObject) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ add array is nil",NSStringFromClass([self class])]];

        return self;
    }
    return [self sop_arrayByAddingObject:anObject];
}


/**
 *  崩溃情况：idx越界
 */
-(id)sop_objectAtIndexedSubscript:(NSUInteger)idx{
    if (idx<self.count) {
        return [self sop_objectAtIndexedSubscript:idx];
    }
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index is outside of the bounds",NSStringFromClass([self class])]];

    return nil;
}

@end

@interface NSMutableArray(SafeObjectProxy)
@end
@implementation NSMutableArray(SafeObjectProxy)

/**
 *  崩溃情况：anObject = nil
 */
-(void)sop_addObject:(id)anObject
{
    if(anObject != nil){
        [self sop_addObject:anObject];
        return;
    }
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ object is nil",NSStringFromClass([self class])]];

}

/**
 *  崩溃情况：1.index越界 2.anObject = nil
 */
- (void)sop_insertObject:(id)anObject atIndex:(NSUInteger)index {
    
    if (index > self.count) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index is outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if (!anObject) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ object is nil",NSStringFromClass([self class])]];

        return;
    }
    
    [self sop_insertObject:anObject atIndex:index];
}

/**
 *  崩溃情况：index越界
 */
- (void)sop_removeObjectAtIndex:(NSUInteger)index {
    
    if (index >= self.count) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index is outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    return [self sop_removeObjectAtIndex:index];
}

/**
 *  崩溃情况：1.index越界 2.anObject = nil
 */
- (void)sop_replaceObjectAtIndex:(NSUInteger)index withObject:(id)anObject
{
    if (index >= self.count) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index is outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if (!anObject) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ object is nil",NSStringFromClass([self class])]];

        return;
    }
    
    [self sop_replaceObjectAtIndex:index withObject:anObject];
    
}

/**
 *  崩溃情况：1.indexes 中含有越界index
 */
- (void)sop_removeObjectsAtIndexes:(NSIndexSet *)indexes {
    
    NSMutableIndexSet *mutableSet = [[NSMutableIndexSet alloc] init];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
        if (idx < self.count) {
            [mutableSet addIndex:idx];
            
        }
        else{
            [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ indexs contains index outside of the bounds",NSStringFromClass([self class])]];
        }
    }];
    
    [self sop_removeObjectsAtIndexes:mutableSet];
    
#if __has_feature(objc_arc)
#else
    [mutableSet autorelease];
#endif
    
}

/**
 *  崩溃情况：range 超出[0,count)范围时
 */
- (void)sop_removeObjectsInRange:(NSRange)range {
    //range包含与[0,count)
    NSInteger maxIndexInRange = range.location + range.length - 1;
    if (maxIndexInRange < self.count) {
        [self sop_removeObjectsInRange:range];
        return;
    }
    //无交集
    if (range.location >= self.count) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ range outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    //有交集
    while (maxIndexInRange >= self.count) {
        maxIndexInRange --;
    }
    NSRange finalRange = NSMakeRange(range.location, maxIndexInRange - range.location + 1);
    [self sop_removeObjectsInRange:finalRange];
    
}
@end

#pragma mark - Dictionary

@interface NSDictionary(SafeObjectProxy)
@end
@implementation NSDictionary(SafeObjectProxy)

/**
 * 崩溃情况：__NSPlaceholderDictionary 一般在初始化时候崩溃,（初始化有空值） __NSPlaceholderDictionary initWithObjects:forKeys:count:
 */
- (id)sop_initWithObjects:(id *)objects forKeys:(id<NSCopying> *)keys count:(NSUInteger)cnt {
    
    NSUInteger newCount = 0;
    for (int i = 0; i<cnt; i++) {
        if (!(keys[i]&&objects[i])) {
            break;
        }
        newCount ++;
    }
    return [self sop_initWithObjects:objects forKeys:keys count:newCount];
}

/**
 *  崩溃情况：aKey = nil
 */
-(id)sop_objectForKey:(id)aKey
{
    if(aKey == nil)
        return nil;
    id value = [self sop_objectForKey:aKey];
    return value;
}
@end

@interface NSMutableDictionary(SafeObjectProxy)
@end
@implementation NSMutableDictionary(SafeObjectProxy)

/**
 *  崩溃情况：1.aKey = nil 2.anObject = nil
 */
-(void)sop_setObject:(id)anObject forKey:(id<NSCopying>)aKey{
    if(anObject == nil || aKey == nil){
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ object or key is nil",NSStringFromClass([self class])]];
        return;
    }
    
    [self sop_setObject:anObject forKey:aKey];
}

/**
 *  崩溃情况：akey = nil
 */
- (void)sop_removeObjectForKey:(id)akey {
    if (!akey) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ key is nil",NSStringFromClass([self class])]];

        return;
    }
    [self sop_removeObjectForKey:akey];
}

@end

#pragma mark - URL

@interface NSURL(SafeObjectProxy)
@end;
@implementation NSURL(SafeObjectProxy)

/**
 *  崩溃情况：path = nil
 */
+(id)sop_fileURLWithPath:(NSString *)path isDirectory:(BOOL)isDir
{
    if(path == nil){
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ path is nil",NSStringFromClass([self class])]];
        return nil;
    }
    
    return [self sop_fileURLWithPath:path isDirectory:isDir];
}
@end

#pragma mark - FileManager

@interface NSFileManager(SafeObjectProxy)
@end
@implementation NSFileManager(SafeObjectProxy)

/**
 *  崩溃情况：url = nil
 */
-(NSDirectoryEnumerator *)sop_enumeratorAtURL:(NSURL *)url includingPropertiesForKeys:(NSArray *)keys options:(NSDirectoryEnumerationOptions)mask errorHandler:(BOOL (^)(NSURL *, NSError *))handler
{
    if(url == nil){
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ url is nil",NSStringFromClass([self class])]];

        return nil;
    }
    
    return [self sop_enumeratorAtURL:url includingPropertiesForKeys:keys options:mask errorHandler:handler];
}
@end

#pragma mark - String

@interface NSAttributedString (SafeObjectProxy)
@end
@implementation NSAttributedString (SafeObjectProxy)


/**
 防御str为空
 */
-(instancetype)sop_initWithString:(NSString *)str{
    if (str) {
        return [self sop_initWithString:str];
    }
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ string is nil",NSStringFromClass([self class])]];

    return nil;
}

/**
 防御str为空
 */
-(instancetype)sop_initWithString:(NSString *)str attributes:(NSDictionary<NSString *,id> *)attrs{
    if (str) {
        return [self sop_initWithString:str attributes:attrs];
    }
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ string is nil",NSStringFromClass([self class])]];

    return nil;
}

/**
 防御attrStr为空
 */
-(instancetype)sop_initWithAttributedString:(NSAttributedString *)attrStr{
    if (attrStr) {
        return [self sop_initWithAttributedString:attrStr];
    }
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ string is nil",NSStringFromClass([self class])]];

    return nil;
}

@end

@interface NSString (SafeObjectProxy)
@end
@implementation NSString (SafeObjectProxy)

/**
 从from位置截取字符串 对应 __NSCFConstantString NSTaggedPointerString
 
 @param from 截取起始位置
 @return 截取的子字符串
 */
- (NSString *)sop_substringFromIndex:(NSUInteger)from {
    if (from > self.length ) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return nil;
    }

    return [self sop_substringFromIndex:from];
}

/**
 从开始截取到to位置的字符串  对应  __NSCFConstantString NSTaggedPointerString
 
 @param to 截取终点位置
 @return 返回截取的字符串
 */
- (NSString *)sop_substringToIndex:(NSUInteger)to {
    if (to > self.length ) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return nil;
    }
    return [self sop_substringToIndex:to];
}

/**
 搜索指定 字符串  对应  __NSCFConstantString NSTaggedPointerString
 
 @param searchString 指定 字符串
 @param mask 比较模式
 @param rangeOfReceiverToSearch 搜索 范围
 @param locale 本地化
 @return 返回搜索到的字符串 范围
 */
- (NSRange)sop_rangeOfString:(NSString *)searchString options:(NSStringCompareOptions)mask range:(NSRange)rangeOfReceiverToSearch locale:(nullable NSLocale *)locale {
    if (!searchString) {
        searchString = self;
    }
    BOOL isError=NO;
    if (rangeOfReceiverToSearch.location > self.length) {
        rangeOfReceiverToSearch = NSMakeRange(0, self.length);
    }
    else{
        isError=YES;
    }
    
    if (rangeOfReceiverToSearch.length > self.length) {
        rangeOfReceiverToSearch = NSMakeRange(0, self.length);
    }
    else{
        isError=YES;
    }
    
    if ((rangeOfReceiverToSearch.location + rangeOfReceiverToSearch.length) > self.length) {
        rangeOfReceiverToSearch = NSMakeRange(0, self.length);
    }
    else{
        isError=YES;
    }
    
    if (isError) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];
    }
    
    return [self sop_rangeOfString:searchString options:mask range:rangeOfReceiverToSearch locale:locale];
}


/**
 截取指定范围的字符串  对应  __NSCFConstantString NSTaggedPointerString
 
 @param range 指定的范围
 @return 返回截取的字符串
 */
- (NSString *)sop_substringWithRange:(NSRange)range {
    if (range.location > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return nil;
    }
    
    if (range.length > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return nil;
    }
    
    if ((range.location + range.length) > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return nil;
    }
    return [self sop_substringWithRange:range];
}

/**
 获取对应字符
 
 @param index 指定位置
 @return 返回对应字符
 */
- (unichar)sop_characterAtIndex:(NSUInteger)index {
    if (index >= [self length]) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return 0;
    }
    return [self sop_characterAtIndex:index];
}

@end

@interface NSMutableString (SafeObjectProxy)
@end
@implementation NSMutableString (SafeObjectProxy)

-(instancetype)sop_initWithString:(NSString *)aString{
    if (aString) {
        return [self sop_initWithString:aString];
    }
    [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ string is nil",NSStringFromClass([self class])]];

    return nil;
}

- (void)sop_replaceCharactersInRange:(NSRange)range withString:(NSString *)aString {
    if (range.location > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if (range.length > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if ((range.location + range.length) > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if (aString) {
        [self sop_replaceCharactersInRange:range withString:aString];
    }
}

- (void)sop_insertString:(NSString *)aString atIndex:(NSUInteger)index {
    if (index >= [self length]) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if (aString) {
        [self sop_insertString:aString atIndex:index];
    }
    else{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ string is nil",NSStringFromClass([self class])]];
    }
}

- (void)sop_deleteCharactersInRange:(NSRange)range {
    if (range.location > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if (range.length > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    if ((range.location + range.length) > self.length) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ index outside of the bounds",NSStringFromClass([self class])]];

        return;
    }
    
    [self sop_deleteCharactersInRange:range];
}

- (void)sop_appendString:(NSString *)aString {
    if (aString) {
        [self sop_appendString:aString];
    }
    else{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ string is nil",NSStringFromClass([self class])]];
    }
}

- (void)sop_appendFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    if (!format) {
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ format is nil",NSStringFromClass([self class])]];

        return;
    }
    va_list arguments;
    va_start(arguments, format);
    NSString *formatStr = [[NSString alloc]initWithFormat:format arguments:arguments];
#if __has_feature(objc_arc)
#else
    [formatStr autorelease];
#endif
    [self sop_appendFormat:@"%@",formatStr];
    va_end(arguments);
}

- (void)sop_setString:(NSString *)aString {
    if (aString) {
        [self sop_setString:aString];
    }
    else{
        [[SafeObjectProxy shareInstance] _reportDefendCrashLog:[NSString stringWithFormat:@"%@ string is nil",NSStringFromClass([self class])]];
    }
}

@end

#pragma mark - SafeObjectProxy 安全协议实现

@implementation SafeObjectProxy

int smartFunction(id target, SEL cmd, ...) {
    return 0;
}

+(instancetype)shareInstance{
    static SafeObjectProxy *instance;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance=[[[self class] alloc] init];
    });
    return instance;
}

-(void)addMethod:(SEL)aSelector isStaticMethod:(BOOL)isStaticMethod{
    BOOL aBool = [self respondsToSelector:aSelector];
    NSMethodSignature *signatrue = [self methodSignatureForSelector:aSelector];
    
    if (aBool || signatrue) {
        return;
    }
    
    NSString *selName = NSStringFromSelector(aSelector);
    
    NSMutableString *tmpString = [[NSMutableString alloc] initWithFormat:@"%@", selName];
    
    int count = (int)[tmpString replaceOccurrencesOfString:@":"
                                                withString:@"_"
                                                   options:NSCaseInsensitiveSearch
                                                     range:NSMakeRange(0, selName.length)];
    
    NSMutableString *val = [[NSMutableString alloc] initWithString:@"i@:"];
    
    for (int i = 0; i < count; i++) {
        [val appendString:@"@"];
    }
    const char *funcTypeEncoding = [val UTF8String];
    class_addMethod(isStaticMethod?object_getClass([self class]):[self class], aSelector, (IMP)smartFunction, funcTypeEncoding);
    
}

-(void)_reportDefendCrashLog:(NSString*)log{
    if ([self conformsToProtocol:objc_getProtocol("SafeObjectReportProtocol")]) {
        [(SafeObjectProxy<SafeObjectReportProtocol>*)self reportDefendCrashLog:log];
    }
}

+(void)startSafeObjectProxy{
    [SafeObjectProxy startSafeObjectProxyWithType:SafeObjectProxyType_ALL];
}

+(void)startSafeObjectProxyWithType:(SafeObjectProxyType)type{
    NSError* error = nil;
    
    if (type&SafeObjectProxyType_Array) {
        [objc_getClass("__NSPlaceholderArray") sops_swizzleMethod:@selector(initWithObjects:count:) withMethod:@selector(sop_initWithObjects:count:) error:&error];
        LOG_Error
        
        [objc_getClass("__NSSingleObjectArrayI") sops_swizzleMethod:@selector(objectAtIndex:) withMethod:@selector(sop_objectAtIndex:) error:&error];
        LOG_Error
        
        [objc_getClass("__NSArrayI") sops_swizzleMethod:@selector(objectAtIndexedSubscript:) withMethod:@selector(sop_objectAtIndexedSubscript:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayI") sops_swizzleMethod:@selector(objectAtIndex:) withMethod:@selector(sop_objectAtIndex:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayI") sops_swizzleMethod:@selector(arrayByAddingObject:) withMethod:@selector(sop_arrayByAddingObject:) error:&error];
        LOG_Error
        
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(objectAtIndexedSubscript:) withMethod:@selector(sop_objectAtIndexedSubscript:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(objectAtIndex:) withMethod:@selector(sop_objectAtIndex:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(addObject:) withMethod:@selector(sop_addObject:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(insertObject:atIndex:) withMethod:@selector(sop_insertObject:atIndex:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(removeObjectAtIndex:) withMethod:@selector(sop_removeObjectAtIndex:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(replaceObjectAtIndex:withObject:) withMethod:@selector(sop_replaceObjectAtIndex:withObject:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(removeObjectsAtIndexes:) withMethod:@selector(sop_removeObjectsAtIndexes:) error:&error];
        LOG_Error
        [objc_getClass("__NSArrayM") sops_swizzleMethod:@selector(removeObjectsInRange:) withMethod:@selector(sop_removeObjectsInRange:) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_Dictionary) {
        [objc_getClass("__NSPlaceholderDictionary") sops_swizzleMethod:@selector(initWithObjects:forKeys:count:) withMethod:@selector(sop_initWithObjects:forKeys:count:) error:&error];
        LOG_Error
        
        [objc_getClass("__NSDictionaryI") sops_swizzleMethod:@selector(objectForKey:) withMethod:@selector(sop_objectForKey:) error:&error];
        LOG_Error
        
        [objc_getClass("__NSDictionaryM") sops_swizzleMethod:@selector(objectForKey:) withMethod:@selector(sop_objectForKey:) error:&error];
        LOG_Error
        [objc_getClass("__NSDictionaryM") sops_swizzleMethod:@selector(setObject:forKey:) withMethod:@selector(sop_setObject:forKey:) error:&error];
        LOG_Error
        [objc_getClass("__NSDictionaryM") sops_swizzleMethod:@selector(removeObjectForKey:) withMethod:@selector(sop_removeObjectForKey:) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_URL) {
        [NSURL sops_swizzleClassMethod:@selector(fileURLWithPath:isDirectory:) withClassMethod:@selector(sop_fileURLWithPath:isDirectory:) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_FileManager) {
        [NSFileManager sops_swizzleMethod:@selector(enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:) withMethod:@selector(sop_enumeratorAtURL:includingPropertiesForKeys:options:errorHandler:) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_Notification) {
        [NSNotificationCenter sops_swizzleMethod:@selector(addObserver:selector:name:object:) withMethod:@selector(sop_addObserver:selector:name:object:) error:&error];
        LOG_Error
        
        [NSObject sops_swizzleMethod:NSSelectorFromString(@"dealloc") withMethod:@selector(sop_notification_dealloc) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_UnrecognizedSelector) {
        [NSObject sops_swizzleMethod:@selector(forwardingTargetForSelector:) withMethod:@selector(sop_forwardingTargetForSelector:) error:&error];
        LOG_Error
        [NSObject sops_swizzleClassMethod:@selector(forwardingTargetForSelector:) withClassMethod:@selector(sop_classForwardingTargetForSelector:) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_String) {
        [objc_getClass("NSConcreteAttributedString") sops_swizzleMethod:@selector(initWithString:) withMethod:@selector(sop_initWithString:) error:&error];
        LOG_Error
        [objc_getClass("NSConcreteAttributedString") sops_swizzleMethod:@selector(initWithString:attributes:) withMethod:@selector(sop_initWithString:attributes:) error:&error];
        LOG_Error
        [objc_getClass("NSConcreteAttributedString") sops_swizzleMethod:@selector(initWithAttributedString:) withMethod:@selector(sop_initWithAttributedString:) error:&error];
        LOG_Error
        [objc_getClass("NSConcreteMutableAttributedString") sops_swizzleMethod:@selector(initWithString:) withMethod:@selector(sop_initWithString:) error:&error];
        LOG_Error
        [objc_getClass("NSConcreteMutableAttributedString") sops_swizzleMethod:@selector(initWithString:attributes:) withMethod:@selector(sop_initWithString:attributes:) error:&error];
        LOG_Error
        
        
        [objc_getClass("__NSCFConstantString") sops_swizzleMethod:@selector(substringFromIndex:) withMethod:@selector(sop_substringFromIndex:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFConstantString") sops_swizzleMethod:@selector(substringToIndex:) withMethod:@selector(sop_substringToIndex:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFConstantString") sops_swizzleMethod:@selector(rangeOfString:options:range:locale:) withMethod:@selector(sop_rangeOfString:options:range:locale:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFConstantString") sops_swizzleMethod:@selector(substringWithRange:) withMethod:@selector(sop_substringWithRange:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFConstantString") sops_swizzleMethod:@selector(characterAtIndex:) withMethod:@selector(sop_characterAtIndex:) error:&error];
        LOG_Error
        
        
        [objc_getClass("NSTaggedPointerString") sops_swizzleMethod:@selector(substringFromIndex:) withMethod:@selector(sop_substringFromIndex:) error:&error];
        LOG_Error
        [objc_getClass("NSTaggedPointerString") sops_swizzleMethod:@selector(substringToIndex:) withMethod:@selector(sop_substringToIndex:) error:&error];
        LOG_Error
        [objc_getClass("NSTaggedPointerString") sops_swizzleMethod:@selector(rangeOfString:options:range:locale:) withMethod:@selector(sop_rangeOfString:options:range:locale:) error:&error];
        LOG_Error
        [objc_getClass("NSTaggedPointerString") sops_swizzleMethod:@selector(substringWithRange:) withMethod:@selector(sop_substringWithRange:) error:&error];
        LOG_Error
        [objc_getClass("NSTaggedPointerString") sops_swizzleMethod:@selector(characterAtIndex:) withMethod:@selector(sop_characterAtIndex:) error:&error];
        LOG_Error
        
        [objc_getClass("__NSCFString") sops_swizzleMethod:@selector(replaceCharactersInRange:withString:) withMethod:@selector(sop_replaceCharactersInRange:withString:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFString") sops_swizzleMethod:@selector(insertString:atIndex:) withMethod:@selector(sop_insertString:atIndex:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFString") sops_swizzleMethod:@selector(deleteCharactersInRange:) withMethod:@selector(sop_deleteCharactersInRange:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFString") sops_swizzleMethod:@selector(appendString:) withMethod:@selector(sop_appendString:) error:&error];
        LOG_Error
        [objc_getClass("__NSCFString") sops_swizzleMethod:@selector(appendFormat:) withMethod:@selector(sop_appendFormat:) error:&error];
        LOG_Error
        
        [objc_getClass("NSPlaceholderMutableString") sops_swizzleMethod:@selector(initWithString:) withMethod:@selector(sop_initWithString:) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_UIMainThread) {
#if TARGET_OS_IPHONE
        [UIView sops_swizzleMethod:@selector(setNeedsLayout) withMethod:@selector(sop_setNeedsLayout) error:&error];
        LOG_Error
        [UIView sops_swizzleMethod:@selector(setNeedsDisplay) withMethod:@selector(sop_setNeedsDisplay) error:&error];
        LOG_Error
        [UIView sops_swizzleMethod:@selector(setNeedsDisplayInRect:) withMethod:@selector(sop_setNeedsDisplayInRect:) error:&error];
        LOG_Error
#else
        [NSView sops_swizzleMethod:@selector(setNeedsLayout:) withMethod:@selector(sop_setNeedsLayout:) error:&error];
        LOG_Error
        [NSView sops_swizzleMethod:@selector(setNeedsDisplay:) withMethod:@selector(sop_setNeedsDisplay:) error:&error];
        LOG_Error
        [NSView sops_swizzleMethod:@selector(setNeedsDisplayInRect:) withMethod:@selector(sop_setNeedsDisplayInRect:) error:&error];
        LOG_Error
#endif

    }
    
    if (type&SafeObjectProxyType_KVCNormal) {
        [NSObject sops_swizzleMethod:@selector(setValue:forKey:) withMethod:@selector(sop_setValue:forKey:) error:&error];
        LOG_Error
        [NSObject sops_swizzleMethod:@selector(setValue:forKeyPath:) withMethod:@selector(sop_setValue:forKeyPath:) error:&error];
        LOG_Error
    }
    
    if (type&SafeObjectProxyType_KVCUndefinedKey) {
        [NSObject sops_swizzleMethod:@selector(setValue:forUndefinedKey:) withMethod:@selector(sop_setValue:forUndefinedKey:) error:&error];
        LOG_Error
    }
}
@end

