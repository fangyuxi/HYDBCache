//
//  HYMemoryCache.h
//  <https://github.com/fangyuxi/HDBYCache>
//
//  Created by fangyuxi on 16/4/5.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class HYMemoryCache;

typedef void (^HYMemoryCacheBlock) (HYMemoryCache *cache);
typedef void (^HYMemoryCacheObjectBlock) (HYMemoryCache *cache, NSString *key, id _Nullable object);


@interface HYMemoryCache : NSObject

/**
 禁用初始化方法
 */
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;

/**
 指定初始化方法

 @param name 缓存名
 @return 缓存对象
 */
- (nullable instancetype)initWithName:(NSString *)name NS_DESIGNATED_INITIALIZER;

/**
 缓存名
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 当前的缓存大小
 */
@property (nonatomic, assign, readonly) NSUInteger costNow;

/**
 设置缓存最大存储，默认为最大
 */
@property (nonatomic, assign) NSUInteger costLimit;

/**
 缓存会定期清除存储时间已经超过MaxAge的对象，此属性为设置此移除时间，默认30秒
 */
@property (nonatomic, assign) NSTimeInterval trimToMaxAgeInterval;

/**
 默认 true
 */
@property(nonatomic, assign) BOOL removeObjectWhenAppReceiveMemoryWarning;

/**
 默认 false
 */
@property(nonatomic, assign) BOOL removeObjectWhenAppEnterBackground;


/**
 异步存储
 
 Notice!! 对象的MaxAge为LDBL_MAX.此方法不会记录object的cost，这样会影响缓存的清理工作，如果是ttl缓存
          那么可以忽略这个影响，如果对缓存的内存控制做了设置，那么请关注下面的方法:
 
 '- (void)setObject:(id _Nullable)object
             forKey:(id)key
             withCost:(NSUInteger)cost
             withBlock:(HYMemoryCacheObjectBlock)block'

 @param object 'object'
 @param key 'key'
 @param block 'result'
 */
- (void)setObject:(id _Nullable)object
           forKey:(id)key
        withBlock:(HYMemoryCacheObjectBlock)block;


/**
 同步存储对象
 
 Notice!! 对象的MaxAge为LDBL_MAX.此方法不会记录object的cost，这样会影响缓存的清理工作，如果是ttl缓存
          那么可以忽略这个影响，如果对缓存的内存控制做了设置，那么请关注下面的方法:
 
 '- (void)setObject:(id _Nullable)object
             forKey:(id)key
             withCost:(NSUInteger)cost'

 @param object 'object'
 @param key 'key'
 */
- (void)setObject:(id _Nullable)object
           forKey:(id)key;


/**
 异步存储对象
 
 Notice!! 对象的MaxAge为LDBL_MAX

 @param object 'object'
 @param key 'key'
 @param cost 'cost'
 @param block 'result'
 */
- (void)setObject:(id _Nullable)object
           forKey:(id)key
         withCost:(NSUInteger)cost
        withBlock:(HYMemoryCacheObjectBlock)block;

/**
 异步存储对象
 
 Notice!! 对象的MaxAge为LDBL_MAX
 
 @param object 'object'
 @param key 'key'
 @param cost 'cost'
 @param maxAge 'maxAge'
 @param block 'result'
 */
- (void)setObject:(id _Nullable)object
           forKey:(id)key
         withCost:(NSUInteger)cost
           maxAge:(NSTimeInterval)maxAge
        withBlock:(HYMemoryCacheObjectBlock)block;

/**
 同步存储对象
 
 Notice!! 对象的MaxAge为LDBL_MAX
 
 @param object 'object'
 @param key 'key'
 @param cost 'cost'
 */
- (void)setObject:(id _Nullable)object
           forKey:(id)key
         withCost:(NSUInteger)cost;

/**
 同步存储对象
 
 Notice!! 对象的MaxAge为LDBL_MAX
 
 @param object 'object'
 @param key 'key'
 @param cost 'cost'
 @param maxAge 'maxAge'
 */
- (void)setObject:(id _Nullable)object
           forKey:(id)key
           maxAge:(NSTimeInterval)maxAge
         withCost:(NSUInteger)cost;

/**
 异步获取
 
 @param key 'key'
 @param block 'result'
 */
- (void)objectForKey:(id)key
           withBlock:(HYMemoryCacheObjectBlock)block;


/**
 同步获取

 @param key 'key'
 @return 'object'
 */
- (nullable id)objectForKey:(NSString *)key;



/**
 异步移除

 @param key 'key'
 @param block 'result'
 */
- (void)removeObjectForKey:(id)key
                 withBlock:(HYMemoryCacheObjectBlock)block;

/**
 同步移除
 
 @param key 'key'
 */
- (void)removeObjectForKey:(id)key;


/**
 异步移除所有

 @param block 'ressult'
 */
- (void)removeAllObjectWithBlock:(HYMemoryCacheBlock)block;


/**
 同步移除所有对象
 */
- (void)removeAllObject;


/**
 是否包含

 @param key 'key'
 @return 'result'
 */
- (BOOL)containsObjectForKey:(id)key;


/**
 移除对象，直到缓存大小小于cost

 @param cost '目标cost'
 @param block 'result'
 */
- (void)trimToCost:(NSUInteger)cost block:(HYMemoryCacheBlock)block;

/**
 移除对象，直到缓存大小小于constLimit
 
 @param block 'result'
 */
- (void)trimToCostLimitWithBlock:(HYMemoryCacheBlock)block;

@end

NS_ASSUME_NONNULL_END
