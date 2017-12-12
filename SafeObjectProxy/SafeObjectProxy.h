//
//  SafeObjectProxy.h
//  admin
//
//  Created by admin on 2017/1/4.
//  Copyright © 2017年 admin. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef enum SafeObjectProxyType{
    SafeObjectProxyType_UnrecognizedSelector=1<<1,
    SafeObjectProxyType_Notification=1<<2,
    
    SafeObjectProxyType_Array=1<<3,
    SafeObjectProxyType_Dictionary=1<<4,
    SafeObjectProxyType_String=1<<5,
    SafeObjectProxyType_URL=1<<6,
    SafeObjectProxyType_FileManager=1<<7,
    
    SafeObjectProxyType_UIMainThread=1<<8,
    
    SafeObjectProxyType_KVCNormal=1<<9,
    SafeObjectProxyType_KVCUndefinedKey=1<<10,
    SafeObjectProxyType_KVCALL=(SafeObjectProxyType_KVCNormal|SafeObjectProxyType_KVCUndefinedKey),
    
    SafeObjectProxyType_DanglingPointer=1<<11,

    SafeObjectProxyType_Normal=(SafeObjectProxyType_Array|SafeObjectProxyType_Dictionary|SafeObjectProxyType_String|SafeObjectProxyType_URL|SafeObjectProxyType_FileManager),
    
    SafeObjectProxyType_ALL=(SafeObjectProxyType_UnrecognizedSelector|SafeObjectProxyType_Notification|SafeObjectProxyType_UIMainThread|SafeObjectProxyType_Array|SafeObjectProxyType_Dictionary|SafeObjectProxyType_String|SafeObjectProxyType_URL|SafeObjectProxyType_FileManager|SafeObjectProxyType_KVCALL|SafeObjectProxyType_DanglingPointer),
    
    
}SafeObjectProxyType;

//安保模块上报协议
@protocol SafeObjectReportProtocol

@required
/**
 上报防御的crash log
 
 @param log log无法抓到Notification的遗漏注销情况
 */
-(void)reportDefendCrashLog:(NSString*)log;

@end

@interface SafeObjectProxy :NSObject

/**
 安保系统完全启动
 */
+(void)startSafeObjectProxy;

/**
 安保系统只启动制定模块

 SafeObjectProxyType_DanglingPointer 开启野指针保护时
 需要使用addSafeDanglingPointerClassNames添加要保护的类名集合

 @param type 受保护模块
 */
+(void)startSafeObjectProxyWithType:(SafeObjectProxyType)type;

/**
 添加需要做野指针保护的类
 默认保护池最大值(允许不释放的对象最大数目)为100个
 
 @param classNames 受保护的类名数组
 */
+(void)addSafeDanglingPointerClassNames:(NSArray<NSString*>*)classNames;

/**
 添加需要做野指针保护的类
 
 @param classNames 受保护的类名数组
 @param undellocedMaxCount 保护池最大值(允许不释放的对象最大数目)
 */
+(void)addSafeDanglingPointerClassNames:(NSArray<NSString*>*)classNames undellocedMaxCount:(NSInteger)undellocedMaxCount;

@end
