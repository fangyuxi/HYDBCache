//
//  HYDiskCache.h
//  <https://github.com/fangyuxi/HDBYCache>
//
//  Created by fangyuxi on 16/4/5.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.

#import <Foundation/Foundation.h>


NS_ASSUME_NONNULL_BEGIN

/**
 Notifications Type
 */
extern NSString *const KHYDiskCacheFileSystemStorageFullNotification;

/**
 Notifications Keys
 */
extern NSString *const KHYDiskCacheErrorKeyFreeSpace;

/**
 MaxAge forever young
 */
extern NSInteger const KHYCacheItemMaxAge;

@class HYDiskCache;

typedef void (^HYDiskCacheBlock) (HYDiskCache *cache);
typedef void (^HYDiskCacheObjectBlock) (HYDiskCache *cache, NSString *key, id _Nullable object);


/**
 线程安全
 */
@interface HYDiskCache : NSObject

/**
 禁用初始化方法
 */
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;


/**
 创建缓存

 @param name 缓存名字
 @return 缓存对象
 */
- (nullable instancetype)initWithName:(NSString *)name;


/**
 指定初始化方法

 @param name 缓存名字
 @param directoryPath 缓存路径
 @return 缓存对象
 */
- (nullable instancetype)initWithName:(NSString *)name
               directoryPath:(nullable NSString *)directoryPath NS_DESIGNATED_INITIALIZER;

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *directoryPath;

/**
 当前的cost，当超过byteCostLimit的时候，移除策略为LRU
 */
@property (nonatomic, assign, readonly) NSUInteger totalCostNow;

/**
 设置最大cost 默认 ULONG_MAX
 */
@property (nonatomic, assign) NSUInteger costLimit;

/**
 移除时间间隔 cache会定期移除已经超过maxAge的对象 默认40秒
 */
@property (nonatomic, assign) NSInteger trimToMaxAgeInterval;

/**
 对于没有遵循NSCoding协议的一类对象，可以在这个block中定义自己的archive逻辑
 */
@property (nonatomic, nullable, copy) NSData *(^customArchiveBlock)(id object);

@property (nonatomic, nullable, copy) id (^customUnarchiveBlock)(NSData *data);


/**
 异步存储
 
 Notice: 对象的maxAge为最大

 @param object 'object'
 @param key 'key'
 @param block 'result'
 */
- (void)setObject:(id _Nullable)object
           forKey:(NSString *)key
        withBlock:(HYDiskCacheObjectBlock)block;

/**
 异步存储
 
 @param object 'object'
 @param key 'key'
 @param maxAge 'maxAge'
 @param block 'result'
 */
- (void)setObject:(id _Nullable)object
           forKey:(NSString *)key
           maxAge:(NSInteger)maxAge
        withBlock:(HYDiskCacheObjectBlock)block;

/**
 同步存储对象，有效期为最大
 
 @param object 存储的对象，如果为空，则不会插入，如果存在，会删除原有对象
 @param key    存储对象的键，如果为空，则不会插入
 */
- (void)setObject:(id _Nullable)object
           forKey:(NSString *)key;

/**
 同步存储对象
 
 @param object 存储的对象，如果为空，则不会插入，如果存在，会删除原有对象
 @param key    存储对象的键，如果为空，则不会插入
 @param maxAge 存储的最大时间
 */
- (void)setObject:(id _Nullable)object
           forKey:(NSString *)key
           maxAge:(NSInteger)maxAge;

/**
 异步获取对象，该方法会立即返回，获取完毕之后block会在内部的concurrent queue中回调
 
 @param key   存储对象的键，不能为空
 @param block 返回值 key object  cache object
 */
- (void)objectForKey:(id)key
           withBlock:(HYDiskCacheObjectBlock)block;

/**
 同步获取对象，该方法会阻塞调用的线程，直到获取完成
 
 @param key 存储对象的键，不能为空
 @return 如果没找到相应object则返回空
 */
- (nullable id)objectForKey:(NSString *)key;

/**
 异步移除对象，移除完毕之后block会在内部的concurrent queue中回调
 
 @param key   存储对象的键，不能为空
 @param block 返回值 cache object
 */
- (void)removeObjectForKey:(NSString *)key
                 withBlock:(HYDiskCacheBlock)block;

/**
 同步移除对象
 
 @param key 存储对象的键，不能为空
 */
- (void)removeObjectForKey:(NSString *)key;

/**
 异步移除所有对象，移除完毕之后block会在内部的concurrent queue中回调
 
 @param block 返回值 cache object
 */
- (void)removeAllObjectWithBlock:(HYDiskCacheBlock)block;

/**
 同步移除所有对象
 */
- (void)removeAllObject;

/**
 查询是否包含这个key value
 
 @param key 存储对象的键，不能为空
 @return 是否包含
 */
- (BOOL)containsObjectForKey:(id)key;

/**
 移除对象，直到totalCostNow <= cost
 
 @param cost  cost
 @param block 移除完毕之后block会在内部的concurrent queue中回调
 */
- (void)trimToCost:(NSUInteger)cost
             block:(HYDiskCacheBlock)block;

/**
 移除对象，直到totalCostNow <= costLimit
 
 @param block 移除完毕之后block会在内部的concurrent queue中回调
 */
- (void)trimToCostLimitWithBlock:(HYDiskCacheBlock)block;

@end

NS_ASSUME_NONNULL_END












