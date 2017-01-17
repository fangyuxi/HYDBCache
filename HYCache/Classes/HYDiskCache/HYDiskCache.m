//
//  HYDiskCache.m
//  Pods
//
//  Created by fangyuxi on 16/4/5.
//
//

#import "HYDiskCache.h"
#import <CommonCrypto/CommonCrypto.h>
#import "HYDBRunnner.h"
\
NSString *const KHYDiskCacheFileSystemSpaceFullNotification = @"KHYDiskCacheFileSystemStorageSpaceFull";
NSString *const KHYDiskCacheWriteErrorNotification = @"KHYDiskCacheFileSystemStorageSpaceFull";
NSString *const KHYDiskCacheReadErrorNotification = @"KHYDiskCacheFileSystemStorageSpaceFull";

NSString *const KHYDiskCacheErrorKeyCacheName = @"KHYDiskCacheErrorKeyCacheName";
NSString *const KHYDiskCacheErrorKeyFileName = @"KHYDiskCacheErrorKeyFileName";
NSString *const KHYDiskCacheErrorKeyNSError = @"KHYDiskCacheErrorKeyNSError";
NSString *const KHYDiskCacheErrorKeyFreeSpace = @"KHYDiskCacheErrorKeyFreeSpace";

static NSString *const dataQueueNamePrefix = @"com.HYDiskCache.ConcurrentQueue.";

static NSString *const dataPath = @"data";
static NSString *const trushPath = @"trush";
static NSString *const metaPath = @"meta";

static int64_t _HYDiskSpaceFree()
{
    NSError *error = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:&error];
    if (error){
        return -1;
    }
    
    int64_t space =  [[attrs objectForKey:NSFileSystemFreeSize] longLongValue];
    if (space < 0){
        space = -1;
    }
    else if (space < 50 *  1024){
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:KHYDiskCacheFileSystemSpaceFullNotification object:@{KHYDiskCacheErrorKeyFreeSpace:@(space)}];
        });
    }
    
    return space;
}

///////////////////////////////////////////////////////////////////////////////
#pragma mark HYCacheBackgourndTask
///////////////////////////////////////////////////////////////////////////////
@interface _HYCacheBackgourndTask : NSObject

@property (nonatomic, assign) UIBackgroundTaskIdentifier taskId;

+ (instancetype)_startBackgroundTask;
- (void)_endTask;

@end

@implementation _HYCacheBackgourndTask

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        self.taskId = UIBackgroundTaskInvalid;
        self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
            
            UIBackgroundTaskIdentifier taskId = self.taskId;
            self.taskId = UIBackgroundTaskInvalid;
            
            [[UIApplication sharedApplication] endBackgroundTask:taskId];
        }];
        return self;
    }
    return nil;
}

+ (instancetype)_startBackgroundTask
{
    return [[self alloc] init];
}

- (void)_endTask
{
    UIBackgroundTaskIdentifier taskId = self.taskId;
    self.taskId = UIBackgroundTaskInvalid;
    
    [[UIApplication sharedApplication] endBackgroundTask:taskId];
}

@end

#pragma mark lock

dispatch_semaphore_t semaphoreLock;

static inline void lock()
{
    dispatch_semaphore_wait(semaphoreLock, DISPATCH_TIME_FOREVER);
}

static inline void unLock()
{
    dispatch_semaphore_signal(semaphoreLock);
}

///////////////////////////////////////////////////////////////////////////////
#pragma mark linked map used for LRU
///////////////////////////////////////////////////////////////////////////////
@interface _HYDiskCacheItem : NSObject<NSCoding> // not thread-safe
{
    @package
    NSString *key;
    NSData *value; //tmp may be nil
    NSUInteger byteCost;
    NSDate *inCacheDate;
    NSDate *lastAccessDate;
    NSTimeInterval maxAge;
    NSString *fileName;
    
    __unsafe_unretained _HYDiskCacheItem *preItem;
    __unsafe_unretained _HYDiskCacheItem *nextItem;
}

- (NSComparisonResult)compare:(_HYDiskCacheItem *)cacheItem;

@end

@implementation _HYDiskCacheItem

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    key = [aDecoder decodeObjectForKey:@"key"];
    value = [aDecoder decodeObjectForKey:@"value"];
    byteCost = [[aDecoder decodeObjectForKey:@"byteCost"] unsignedIntegerValue];
    inCacheDate = [aDecoder decodeObjectForKey:@"inCacheDate"];
    lastAccessDate = [aDecoder decodeObjectForKey:@"lastAccessDate"];
    maxAge = [[aDecoder decodeObjectForKey:@"maxAge"] doubleValue];
    fileName = [aDecoder decodeObjectForKey:@"fileName"];
    preItem = [aDecoder decodeObjectForKey:@"preItem"];
    nextItem = [aDecoder decodeObjectForKey:@"nextItem"];
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:key forKey:@"key"];
    [aCoder encodeObject:value forKey:@"value"];
    [aCoder encodeObject:@(byteCost) forKey:@"byteCost"];
    [aCoder encodeObject:inCacheDate forKey:@"inCacheDate"];
    [aCoder encodeObject:lastAccessDate forKey:@"lastAccessDate"];
    [aCoder encodeObject:@(maxAge) forKey:@"maxAge"];
    [aCoder encodeObject:fileName forKey:@"fileName"];
    [aCoder encodeObject:preItem forKey:@"preItem"];
    [aCoder encodeObject:nextItem forKey:@"nextItem"];
}

- (NSComparisonResult)compare:(_HYDiskCacheItem *)cacheItem
{
    if (!cacheItem) return NSOrderedSame;
    NSTimeInterval me = [lastAccessDate timeIntervalSince1970];
    NSTimeInterval you = [cacheItem->lastAccessDate timeIntervalSince1970];
    if (me < you)
    {
        return NSOrderedAscending;
    }
    else if (me > you)
    {
        return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"key:%@ inCachedate:%@ lastAccessDate %@",key,inCacheDate, lastAccessDate];
}

@end

@interface _HYDiskCacheItemLinkMap : NSObject //not thread-safe
{
    @package
    __unsafe_unretained _HYDiskCacheItem *_head;
    __unsafe_unretained _HYDiskCacheItem *_tail;
    
    NSMutableDictionary *_itemsDic;
    NSString *_metaPath;
    NSUInteger _totalByteCost;
}

- (void)_insertItemAtHead:(_HYDiskCacheItem *)item;

- (void)_bringItemToHead:(_HYDiskCacheItem *)item;

- (void)_removeItem:(_HYDiskCacheItem *)item;

- (_HYDiskCacheItem *)_removeTailItem;

- (void)_removeAllItem;

@end

@implementation _HYDiskCacheItemLinkMap

- (void)dealloc
{
    
}

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self)
    {
        _metaPath = path;
        NSString *path = [_metaPath stringByAppendingPathComponent:@"meta"];
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSMutableDictionary *items = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        if (items) {
            _itemsDic = items;
        }
        else{
            _itemsDic = [NSMutableDictionary new];
        }
        
        _totalByteCost = 0;
        _head = nil;
        _tail = nil;
        
        return self;
    }
    return nil;
}

- (void)_insertItemAtHead:(_HYDiskCacheItem *)item
{
    //CFDictionarySetValue(_itemsDic, (__bridge const void *)item->key, (__bridge const void *)item);
    [_itemsDic setObject:item forKey:item->key];
    _totalByteCost = _totalByteCost + item->byteCost;
    if (_head)
    {
        _head->preItem = item;
        item->nextItem = _head;
        item->preItem = nil;
        _head = item;
    }
    else
    {
        _head = item;
        _tail = item;
        _head = _tail;
    }
}

- (void)_bringItemToHead:(_HYDiskCacheItem *)item
{
    if (_head == item) return;
    
    if (_tail == item)
    {
        _tail = item->preItem;
        _tail->nextItem = nil;
    }
    else
    {
        item->nextItem->preItem = item->preItem;
        item->preItem->nextItem = item->nextItem;
    }
    
    item->nextItem = _head;
    item->preItem = nil;
    _head->preItem = item;
    _head = item;
}

- (void)_removeItem:(_HYDiskCacheItem *)item
{
    if (item->nextItem)
        item->nextItem->preItem = item->preItem;
    if (item->preItem)
        item->preItem->nextItem = item->nextItem;
    
    if (_head == item)
        _head = item->preItem;
    if (_tail == item)
        _tail = item->preItem;
    
    //CFDictionaryRemoveValue(_itemsDic, (__bridge const void *)item->key);
    [_itemsDic removeObjectForKey:item->key];
    _totalByteCost = _totalByteCost - item->byteCost;
}

- (_HYDiskCacheItem *)_removeTailItem
{
    _HYDiskCacheItem *item = _tail;
    if (_head == _tail)
    {
        _head = _tail = nil;
    }
    else
    {
        _tail = _tail->preItem;
        _tail->nextItem = nil;
    }
    
    //CFDictionaryRemoveValue(_itemsDic, (__bridge const void *)_tail->key);
    [_itemsDic removeObjectForKey:_tail->key];
    _totalByteCost = _totalByteCost - _tail->byteCost;
    return item;
}

- (void)_removeAllItem
{
    _head = nil;
    _tail = nil;
    //CFDictionaryRemoveAllValues(_itemsDic);
    [_itemsDic removeAllObjects];
    _totalByteCost = 0;
}

@end

///////////////////////////////////////////////////////////////////////////////
#pragma mark HYDiskStorage
///////////////////////////////////////////////////////////////////////////////

@interface _HYDiskFileStorage : NSObject //not thread-safe
{
    @package
    _HYDiskCacheItemLinkMap *_lruMap;
    NSString *_dataPath;
    NSString *_trashPath;
    NSString *_metaPath;
}

- (instancetype)initWithPath:(NSString *)path
                   trashPath:(NSString *)trashPath
                    metaPath:(NSString *)metaPath NS_DESIGNATED_INITIALIZER;

- (BOOL)_saveCacheValue:(NSData *)value key:(NSString *)key maxAge:(NSTimeInterval)maxAge;

- (NSData *)_cacheValueForKey:(NSString *)key;

- (BOOL)_removeValueForKey:(NSString *)key;
- (BOOL)_removeValueForKeys:(NSArray<NSString *> *)keys;
- (BOOL)_removeAllValues;

inline _HYDiskCacheItem *_p_itemForKey(NSString *key, _HYDiskCacheItemLinkMap *map);
inline void _p_removeItem(NSString *key, _HYDiskCacheItemLinkMap *map, _HYDiskCacheItem *item);

@end

@implementation _HYDiskFileStorage

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"_HYDiskFileStorage Must Have A Path" reason:@"Call initWithPath: instead." userInfo:nil];
    return [self initWithPath:nil trashPath:nil metaPath:nil];
}

- (instancetype)initWithPath:(NSString *)path
                   trashPath:(NSString *)trashPath
                    metaPath:(NSString *)metaPath
{
    self = [super init];
    if (self)
    {
        _dataPath = path;
        _trashPath = trashPath;
        _metaPath = metaPath;
        _lruMap = [[_HYDiskCacheItemLinkMap alloc] initWithPath:_metaPath];
        [self _p_initializeFileCacheRecord];
        return self;
    }
    return nil;
}

- (BOOL)_saveCacheValue:(NSData *)value key:(NSString *)key maxAge:(NSTimeInterval)maxAge
{
    if (key.length == 0)
        return NO;
    if (!value || ![value isKindOfClass:[NSData class]])
        return NO;
    
    //_HYDiskCacheItem *item = CFDictionaryGetValue(_lruMap->_itemsDic, (__bridge const void*)key);
    _HYDiskCacheItem *item = [_lruMap->_itemsDic objectForKey:key];
    if (!item)
    {
        item = [[_HYDiskCacheItem alloc] init];
        item->key = key;
        item->maxAge = maxAge;
        item->byteCost = value.length;
        item->inCacheDate = [NSDate date];
        item->lastAccessDate = [NSDate distantFuture];//暂无访问
        item->fileName = [self _p_fileNameForKey:item->key];
        [_lruMap _insertItemAtHead:item];
    }
    else
    {
        //如果item已经存在，那么更新totalByteCost
        _lruMap->_totalByteCost += value.length - item->byteCost;
        
        item->key = key;
        item->maxAge = maxAge;
        item->byteCost = value.length;
        item->inCacheDate = [NSDate date];
        item->lastAccessDate = [NSDate distantFuture];//暂无访问
        item->fileName = [self _p_fileNameForKey:item->key];
        
        [_lruMap _bringItemToHead:item];
    }
    BOOL writeResult = [self _p_fileWriteWithName:item->fileName data:value];
    BOOL setTimeResult = [self _p_setFileAccessDate:item->lastAccessDate forFileName:item->fileName];
    BOOL saveMetaResult = [self _p_metaWrite];
    if (!setTimeResult || !saveMetaResult)//访问时间插入失败，meta写入失败，删除刚刚写入的文件
    {
        [self _removeValueForKey:item->key];
    }
    return writeResult && setTimeResult && saveMetaResult;
}

- (NSData *)_cacheValueForKey:(NSString *)key
{
    if (key.length == 0 || ![key isKindOfClass:[NSString class]])
        return nil;
    _HYDiskCacheItem *item = _p_itemForKey(key, _lruMap);
    if (!item)
        return nil;
    NSData *data = [self _p_fileReadWithName:item->fileName];
    if (data)
    {
        [self _p_setFileAccessDate:[NSDate date] forFileName:item->fileName];
        item->lastAccessDate = [NSDate date];
        [_lruMap _bringItemToHead:item];
        return data;
    }
    return nil;
}

- (BOOL)_removeValueForKey:(NSString *)key
{
    if (key.length == 0 || ![key isKindOfClass:[NSString class]])
        return NO;
    
    _HYDiskCacheItem *item = _p_itemForKey(key, _lruMap);
    if (!item)
        return NO;
    
    _p_removeItem(key, _lruMap, item);
    return [self _p_fileDeleteWithName:item->fileName];
}

- (BOOL)_removeValueForKeys:(NSArray<NSString *> *)keys
{
    if (keys.count == 0) return NO;
    
    for (NSString *key in keys)
    {
        [self _removeValueForKey:key];
    }
    
    return YES;
}

- (BOOL)_removeAllValues
{
    if ([self _p_fileMoveAllToTrash])
    {
        [_lruMap _removeAllItem];
        [self _p_removeAllTrashFileInBackground];
        return YES;
    }
    return NO;
}
//初始化
- (void)_p_initializeFileCacheRecord
{
    NSArray *keys = [_lruMap->_itemsDic keysSortedByValueUsingSelector:@selector(compare:)];
    for (NSString *key in keys)
    {
        _HYDiskCacheItem *item = [_lruMap->_itemsDic objectForKey:key];
        if (item)
            [_lruMap _insertItemAtHead:item];
    }
}

//key 转 file url
- (NSString *)_p_fileNameForKey:(NSString *)key
{
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0],  result[1],  result[2],  result[3],
            result[4],  result[5],  result[6],  result[7],
            result[8],  result[9],  result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

- (BOOL)_p_setFileAccessDate:(NSDate *)date forFileName:(NSString *)fileName
{
    if (!date || !fileName) return NO;
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] setAttributes:@{NSFileModificationDate: date}
                                                    ofItemAtPath: [_dataPath stringByAppendingPathComponent:fileName]
                                                           error:&error];
    if(error) NSLog(@"%@", error);
    return success;
}

_HYDiskCacheItem * _p_itemForKey(NSString *key, _HYDiskCacheItemLinkMap *map)
{
    if (key)
        //return CFDictionaryGetValue(map->_itemsDic, (__bridge const void*)key);
        return [map->_itemsDic objectForKey:key];
    return nil;
}

void _p_removeItem(NSString *key, _HYDiskCacheItemLinkMap *map, _HYDiskCacheItem *item)
{
    if (item && map && key)
        [map _removeItem:item];
}

- (BOOL)_p_fileWriteWithName:(NSString *)fileName data:(NSData *)data
{
    NSString *path = [_dataPath stringByAppendingPathComponent:fileName];
    BOOL finish = [data writeToFile:path atomically:YES];
    if (!finish)
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:KHYDiskCacheWriteErrorNotification object:@{KHYDiskCacheErrorKeyCacheName:self,KHYDiskCacheErrorKeyFileName:fileName}];
            
            _HYDiskSpaceFree();
        });
        
    return finish;
}

- (BOOL)_p_metaWrite
{
    NSString *path = [_metaPath stringByAppendingPathComponent:@"meta"];
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_lruMap->_itemsDic];
    if (!data) {
        return NO;
    }
    BOOL finish = [data writeToFile:path atomically:YES];
    if (!finish)
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:KHYDiskCacheWriteErrorNotification object:@{KHYDiskCacheErrorKeyCacheName:self,KHYDiskCacheErrorKeyFileName:@"meta"}];
            
            _HYDiskSpaceFree();
        });
    
    return finish;
}

- (NSData *)_p_fileReadWithName:(NSString *)fileName
{
    NSString *path = [_dataPath stringByAppendingPathComponent:fileName];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data)
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:KHYDiskCacheReadErrorNotification object:@{KHYDiskCacheErrorKeyCacheName:self,KHYDiskCacheErrorKeyFileName:fileName}];
        });
    return data;
}

- (BOOL)_p_fileDeleteWithName:(NSString *)fileName
{
    NSString *path = [_dataPath stringByAppendingPathComponent:fileName];
    return [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (BOOL)_p_fileMoveAllToTrash
{
    CFUUIDRef uuidRef = CFUUIDCreate(NULL);
    CFStringRef uuid = CFUUIDCreateString(NULL, uuidRef);
    CFRelease(uuidRef);
    
    NSString *tmpPath = [_trashPath stringByAppendingPathComponent:(__bridge NSString *)(uuid)];
    BOOL suc = [[NSFileManager defaultManager] moveItemAtPath:_dataPath toPath:tmpPath error:nil];
    if (suc)
        suc = [[NSFileManager defaultManager] createDirectoryAtPath:_dataPath withIntermediateDirectories:YES attributes:nil error:NULL];
    CFRelease(uuid);
    return suc;
}

- (void)_p_removeAllTrashFileInBackground
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        NSArray *directoryContents = [manager contentsOfDirectoryAtPath:_trashPath error:NULL];
        for (NSString *path in directoryContents)
        {
            NSString *fullPath = [_trashPath stringByAppendingPathComponent:path];
            [manager removeItemAtPath:fullPath error:NULL];
        }
    });
}

@end


///////////////////////////////////////////////////////////////////////////////
#pragma mark HYDiskCache
///////////////////////////////////////////////////////////////////////////////

@interface HYDiskCache () // yeah all method & proterty thread-safe
{
    dispatch_queue_t _dataQueue;
    _HYDiskFileStorage *_storage;
}

@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *directoryPath;
@property (nonatomic, copy, readwrite) NSString *cachePath;
@property (nonatomic, copy, readwrite) NSString *cacheDataPath;
@property (nonatomic, copy, readwrite) NSString *cacheTrushPath;
@property (nonatomic, copy, readwrite) NSString *cacheMetaPath;

@end

@implementation HYDiskCache

@synthesize byteCostLimit = _byteCostLimit;
@synthesize totalByteCostNow = _totalByteCostNow;
@synthesize trimToMaxAgeInterval = _trimToMaxAgeInterval;
@synthesize customArchiveBlock = _customArchiveBlock;
@synthesize customUnarchiveBlock = _customUnarchiveBlock;

- (instancetype)init
{
    @throw [NSException exceptionWithName:@"HYDiskCache Must Have A Name" reason:@"Call initWithName: instead." userInfo:nil];
    
    return [self initWithName:@"" andDirectoryPath:@""];
}

- (instancetype)initWithName:(NSString *)name
{
    return [self initWithName:name andDirectoryPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]];
}

- (instancetype)initWithName:(NSString *)name
            andDirectoryPath:(NSString *)directoryPath
{
    if (!name ||
        name.length == 0 ||
        !directoryPath ||
        directoryPath.length == 0 ||
        ![name isKindOfClass:[NSString class]] ||
        ![directoryPath isKindOfClass:[NSString class]])
    {
        @throw [NSException exceptionWithName:@"HYDiskCache Must Have A Name"
                                       reason:@"The Name and DirectoryPath Could Not Be NIL Or Empty"
                                     userInfo:nil];
        return nil;
    }
    
    self = [super init];
    if (self)
    {
        _name = [name copy];
        _directoryPath = [directoryPath copy];
        
        _byteCostLimit = ULONG_MAX;
        _totalByteCostNow = 0;
        _trimToMaxAgeInterval = 20.0f;
        
        semaphoreLock = dispatch_semaphore_create(1);
        _dataQueue = dispatch_queue_create([dataQueueNamePrefix UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        //创建路径
        if (![self p_createPath])
        {
            NSLog(@"HYDiskCache Create Path Failed");
            return nil;
        }
        
        //由于加了锁，所以不影响初始化后对cache的存储操作
        lock();
        dispatch_async(_dataQueue, ^{
           
            _storage = [[_HYDiskFileStorage alloc] initWithPath:_cacheDataPath
                                                      trashPath:_cacheTrushPath
                                                       metaPath:_cacheMetaPath];
            unLock();
        });
        
        lock();
        _HYDiskFileStorage *storage = _storage;
        unLock();
        
        if(!storage) return nil;
        
        return self;
    }
    return nil;
}

#pragma mark private method

- (BOOL)p_createPath
{
    _cachePath = [[_directoryPath stringByAppendingPathComponent:_name] copy];
    _cacheDataPath = [[_cachePath stringByAppendingPathComponent:dataPath] copy];
    _cacheTrushPath = [[_cachePath stringByAppendingPathComponent:trushPath] copy];
    _cacheMetaPath = [[_cachePath stringByAppendingPathComponent:metaPath] copy];
    
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_cacheDataPath
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil] ||
        ![[NSFileManager defaultManager] createDirectoryAtPath:_cacheTrushPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil] ||
        ![[NSFileManager defaultManager] createDirectoryAtPath:_cacheMetaPath
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil])
    {
        return NO;
    }
    return YES;
}

#pragma mark store object

- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
        withBlock:(__nullable HYDiskCacheObjectBlock)block
{
    [self setObject:object forKey:key maxAge:DBL_MAX withBlock:block];
}

- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
           maxAge:(NSTimeInterval)maxAge
        withBlock:(__nullable HYDiskCacheObjectBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        [stronglySelf setObject:object forKey:key maxAge:maxAge];
        
        if (block)
        {
            block(stronglySelf, key, object);
        }
    });
}

- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
{
    [self setObject:object forKey:key maxAge:DBL_MAX];
}

- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
           maxAge:(NSTimeInterval)maxAge
{
    if (!object || !key || ![key isKindOfClass:[NSString class]] || key.length == 0)
        return;
    
    _HYCacheBackgourndTask *task = [_HYCacheBackgourndTask _startBackgroundTask];
    
    NSData *data;
    if (self.customArchiveBlock)
        data = self.customArchiveBlock(object);
    else
        data = [NSKeyedArchiver archivedDataWithRootObject:object];
    
    lock();
    [_storage _saveCacheValue:data key:key maxAge:maxAge];
    unLock();
    
    if (self.totalByteCostNow >= self.byteCostLimit)
    {
        [self trimToCostLimitWithBlock:^(HYDiskCache * _Nonnull cache) {
            
        }];
    }
    
    [task _endTask];
}

- (void)objectForKey:(id)key
           withBlock:(HYDiskCacheObjectBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        NSObject *object = [stronglySelf objectForKey:key];
        if (block)
        {
            block(stronglySelf, key, object);
        }
    });
}

- (id __nullable )objectForKey:(NSString *)key
{
    if (key.length == 0 || ![key isKindOfClass:[NSString class]])
        return nil;
    NSData *data;
    
    lock();
    _HYDiskCacheItem *item = _p_itemForKey(key, _storage->_lruMap);
    
    if (!item) {
        unLock();
        return nil;
    }
    
    NSTimeInterval objectMaxAge = item->maxAge;
    NSTimeInterval objectAgeSinceNow = -[item->inCacheDate timeIntervalSinceNow];
    NSDate *distantFuture = [NSDate distantFuture];
    if (objectAgeSinceNow >= objectMaxAge && ![item->inCacheDate isEqualToDate:distantFuture])
    {
        [_storage _removeValueForKey:item->key];
        item = _storage->_lruMap->_tail;
        unLock();
        return nil;
    }
    data = [_storage _cacheValueForKey:key];
    unLock();
    
    id object;
    if (self.customUnarchiveBlock)
        object = self.customUnarchiveBlock(data);
    else
        object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    
    return object;
}

- (void)removeObjectForKey:(NSString *)key
                 withBlock:(__nullable HYDiskCacheBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        [self removeObjectForKey:key];
        if (block)
        {
            block(stronglySelf);
        }
    });
}

- (void)removeObjectForKey:(NSString *)key
{
    if(![key isKindOfClass:[NSString class]] || key.length == 0) return;
    
    lock();
    [_storage _removeValueForKey:key];
    unLock();
}

- (void)removeObjectForKeys:(NSArray<NSString *> *)keys
                  withBlock:(__nullable HYDiskCacheBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        [self removeObjectForKeys:keys];
        if (block)
        {
            block(stronglySelf);
        }
    });
}

- (void)removeObjectForKeys:(NSArray<NSString *> *)keys
{
    if(![keys isKindOfClass:[NSArray class]] || keys.count == 0) return;
    
    lock();
    [_storage _removeValueForKeys:keys];
    unLock();
}

- (void)removeAllObjectWithBlock:(__nullable HYDiskCacheBlock)block
{
    __weak HYDiskCache *weakSelf = self;
    dispatch_async(_dataQueue, ^{
        
        __strong HYDiskCache *stronglySelf = weakSelf;
        [self removeAllObject];
        if (block)
        {
            block(stronglySelf);
        }
    });
}

- (void)removeAllObject
{
    lock();
    [_storage _removeAllValues];
    unLock();
}

- (void)containsObjectForKey:(id)key
                       block:(nullable HYDiskCacheObjectBlock)block
{
    if (!key) return ;
    [self objectForKey:key withBlock:block];
}

- (void)trimToCost:(NSUInteger)cost
             block:(nullable HYDiskCacheBlock)block;
{
    if (cost == 0)
    {
        [self removeAllObjectWithBlock:block];
    }
    else if (cost < self.totalByteCostNow)
    {
        __weak HYDiskCache *weakSelf = self;
        dispatch_async(_dataQueue, ^{
           
            __strong HYDiskCache *stronglySelf = weakSelf;
            lock();
            //do not use self.totalByteCostNow  avoid deadlock
            while (cost <= _storage->_lruMap->_totalByteCost)
            {
                _HYDiskCacheItem *item = _storage->_lruMap->_tail;
                if (item)
                {
                    [_storage _removeValueForKey:item->key];
                }
            }
            unLock();
            
            if (block)
                block(stronglySelf);
        });
    }
    return;
}

- (void)trimToCostLimitWithBlock:(nullable HYDiskCacheBlock)block
{
    [self trimToCost:self.byteCostLimit block:block];
}

- (void)p_trimToAgeLimitRecursively
{
    lock();
    NSTimeInterval trimInterval = _trimToMaxAgeInterval;
    __block _HYDiskCacheItem *item = _storage->_lruMap->_tail;
    unLock();
    
    NSDate *distantFuture = [NSDate distantFuture];
    while (item)
    {
        lock();
        NSTimeInterval objectMaxAge = item->maxAge;
        unLock();
        
        NSTimeInterval objectAgeSinceNow = -[item->inCacheDate timeIntervalSinceNow];
        if (objectAgeSinceNow >= objectMaxAge && ![item->inCacheDate isEqualToDate:distantFuture])
        {
            lock();
            [_storage _removeValueForKey:item->key];
            item = _storage->_lruMap->_tail;
            unLock();
        }
        else
        {
            item = nil;
        }
    }
    
    dispatch_time_t interval = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(trimInterval * NSEC_PER_SEC));
    
    __weak HYDiskCache *weakSelf = self;
    dispatch_after(interval, _dataQueue, ^{
        
        HYDiskCache *stronglySelf = weakSelf;
        [stronglySelf p_trimToAgeLimitRecursively];
    });
}


#pragma mark getter setter for thread-safe

- (NSUInteger)totalByteCostNow
{
    lock();
    NSUInteger cost = _storage->_lruMap->_totalByteCost;
    unLock();
    return cost;
}

- (NSUInteger)byteCostLimit
{
    lock();
    NSUInteger cost = _byteCostLimit;
    unLock();
    
    return cost;
}

- (void)setByteCostLimit:(NSUInteger)byteCostLimit
{
    lock();
    _byteCostLimit = byteCostLimit;
    unLock();
}

- (void)setTrimToMaxAgeInterval:(NSTimeInterval)trimToMaxAgeInterval
{
    lock();
    _trimToMaxAgeInterval = trimToMaxAgeInterval;
    unLock();
    
    [self p_trimToAgeLimitRecursively];
}

- (NSTimeInterval)trimToMaxAgeInterval
{
    lock();
    NSTimeInterval age = _trimToMaxAgeInterval;
    unLock();
    
    return age;
}

- (void)setCustomArchiveBlock:(NSData * _Nonnull (^)(id _Nonnull))customArchiveBlock
{
    lock();
    _customArchiveBlock = [customArchiveBlock copy];
    unLock();
}

- (NSData * _Nonnull(^)(id _Nonnull))customArchiveBlock
{
    lock();
    NSData *(^block)(id)  = _customArchiveBlock;
    unLock();
    return block;
}

- (void)setCustomUnarchiveBlock:(id  _Nonnull (^)(NSData * _Nonnull))customUnarchiveBlock
{
    lock();
    _customUnarchiveBlock = [customUnarchiveBlock copy];
    unLock();
}

- (id (^)(NSData *))customUnarchiveBlock
{
    lock();
    id (^block)(NSData *) = _customUnarchiveBlock;
    unLock();
    return block;
}

@end









