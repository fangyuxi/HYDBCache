//
//  HYDBRunnner.h
//  Pods
//
//  Created by fangyuxi on 2017/1/16.
//
//

#import <Foundation/Foundation.h>
#import "HYDiskCacheItem.h"

NS_ASSUME_NONNULL_BEGIN
/**
 同sqlite3进行交互
 
 使用我们自己编译的sqlite3库，要比苹果自带的快，同时也可进行源码级的优化
 */

@interface HYDBRunnner : NSObject

@property (nonatomic, assign) BOOL errorLogsEnabled;

#pragma mark - Initializer

/**
 Designated initializer.
 
 @param path 数据库地址的路径(不包含文件名)，会自动创建中间文件夹
 @return runner实例
 */
- (nullable instancetype)initWithDBPath:(NSString *)path NS_DESIGNATED_INITIALIZER;

// do not use
- (instancetype)init UNAVAILABLE_ATTRIBUTE;
// do not use
+ (instancetype)new UNAVAILABLE_ATTRIBUTE;


#pragma mark open close db

/**
 open DB

 @return result
 */
- (BOOL)open;


/**
 close DB

 @return result
 */
- (BOOL)close;

#pragma mark save item

/**
 保存 item
 
 @param item One Item
 @return is succeed
 */
- (BOOL)saveItem:(HYDiskCacheItem *)item;

/**
 save to db
 
 @param key 'key'
 @param value 'value is s NSDate instance'
 @param fileName 'fileName'
 @return is succeed
 */
- (BOOL)saveWithKey:(NSString *)key
              value:(NSData *)value
           fileName:(NSString *)fileName;

#pragma mark remove item

/**
 删除 item

 @param item 'item'
 @return is succeed
 */
- (BOOL)removeItem:(HYDiskCacheItem *)item;


/**
 remove  item with item's 'key'

 @param  key a item's 'key'
 @return is succeed
 */
- (BOOL)removeItemWithKey:(NSString *)key;


/**
 remove all

 @return is succeed
 */
- (BOOL)removeAllItems;

#pragma mark get cache info

/**
 返回指定key对应的条数，原则上只有一条或者没有

 @param key key
 @return count
 */
- (NSInteger)getItemCountWithKey:(NSString *)key;

/**
 返回目前缓存的总大小

 @return size
 */
- (NSInteger)getTotalItemSize;

/**
 返回缓存数目

 @return count
 */
- (NSInteger)getTotalItemCount;

@end

NS_ASSUME_NONNULL_END











