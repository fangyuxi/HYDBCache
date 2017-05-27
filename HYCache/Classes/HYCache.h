//
//  HYCache.h
//  <https://github.com/fangyuxi/HDBYCache>
//
//  Created by fangyuxi on 16/4/15.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.

#import "HYMemoryCache.h"
#import "HYDiskCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface HYCache : NSObject

/**
 内存缓存
 */
@property (nonatomic, readonly) HYMemoryCache *memCache;

/**
 闪存缓存
 */
@property (nonatomic, readonly) HYDiskCache *diskCache;

/**
 禁用初始化方法
 */
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;


/**
 创建内存缓存和闪存缓存 路径默认为 NSCachesDirectory

 @param name 缓存名字
 @return 缓存
 */
- (nullable instancetype)initWithName:(NSString *)name;


/**
 指定初始化方法

 @param name 缓存名字
 @param directoryPath 缓存路径 默认为 NSCachesDirectory
 @return 缓存
 */
- (nullable instancetype)initWithName:(NSString *)name
                          directoryPath:(nullable NSString *)directoryPath NS_DESIGNATED_INITIALIZER;

/**
 同步获取数据

 @param key 'key'
 @return 'object'
 */
- (nullable id)objectForKey:(NSString *)key;

/**
 异步获取
 
 @param key `key`
 @param block 在非主线程中运行
 */
- (void)objectForKey:(NSString *)key
           withBlock:(void (^)(NSString *key ,id _Nullable object))block;

/**
 同步存储Object
 
 @param key    key
 @param inDisk 是否同时存储在disk中
 */
- (void)setObject:(id<NSCoding> _Nullable)object
           forKey:(NSString *)key
           inDisk:(BOOL)inDisk;

/**
 异步存储Object
 
 @param key    key
 @param inDisk 是否存储在disk中
 @param block  block 回调 非主线程
 */
- (void)setObject:(id<NSCoding> _Nullable)object
           forKey:(NSString *)key
           inDisk:(BOOL)inDisk
        withBlock:(void(^)())block;


/**
 同步移除所有对象
 */
- (void)removeAllObjects;

/**
 异步移除所有数据

 @param block 在非主线程中运行
 */
- (void)removeAllObjectsWithBlock:(void(^)())block;

@end

NS_ASSUME_NONNULL_END
