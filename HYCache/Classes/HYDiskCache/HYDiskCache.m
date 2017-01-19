//
//  HYDiskCache.m
//  Pods
//
//  Created by fangyuxi on 16/4/5.
//
//

#import "HYDiskCache.h"
#import <CommonCrypto/CommonCrypto.h>
#import "HYDBStorage.h"
#import "HYFileStorage.h"

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
static NSString *const metaPath = @"manifest";

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

#pragma mark MD5

static NSString *HYMD5(NSString *string) {
    if (!string) return nil;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
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

#pragma mark space free

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
    else if (space < 20 *  1024){
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[NSNotificationCenter defaultCenter] postNotificationName:KHYDiskCacheFileSystemSpaceFullNotification object:@{KHYDiskCacheErrorKeyFreeSpace:@(space)}];
        });
    }
    
    return space;
}


#pragma mark HYCacheBackgourndTask

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


#pragma mark HYDiskCache

@interface HYDiskCache ()
{
    dispatch_queue_t _dataQueue; ///< concurrent queue
    HYDBStorage     *_db;        ///< db storage
    HYFileStorage   *_file;      ///< file storage
}

@property (nonatomic, copy, readwrite) NSString *name;
@property (nonatomic, copy, readwrite) NSString *directoryPath;
@property (nonatomic, copy, readwrite) NSString *cachePath;
@property (nonatomic, copy, readwrite) NSString *cacheDataPath;
@property (nonatomic, copy, readwrite) NSString *cacheTrushPath;
@property (nonatomic, copy, readwrite) NSString *cacheManifestPath;

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
           
            _db = [[HYDBStorage alloc] initWithDBPath:_cacheManifestPath];
            _file = [[HYFileStorage alloc] initWithPath:_cacheDataPath trashPath:_cacheTrushPath];
            unLock();
        });
        
        lock();
        if (!_db || !_file) {
            _db = nil;
            _file = nil;
            unLock();
            
            return nil;
        }
        unLock();
        
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
    _cacheManifestPath = [[_cachePath stringByAppendingPathComponent:metaPath] copy];
    
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_cacheDataPath
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:nil] ||
        ![[NSFileManager defaultManager] createDirectoryAtPath:_cacheTrushPath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil] ||
        ![[NSFileManager defaultManager] createDirectoryAtPath:_cacheManifestPath
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
    [self setObject:object forKey:key maxAge:-1]; //never
}

- (void)setObject:(id<NSCoding>)object
           forKey:(NSString *)key
           maxAge:(NSInteger)maxAge
{
    if (!object || !key || ![key isKindOfClass:[NSString class]] || key.length == 0){
        return;
    }
    
    if (object == nil) {
        [self removeObjectForKey:key];
        return;
    }
    
    _HYCacheBackgourndTask *task = [_HYCacheBackgourndTask _startBackgroundTask];
    
    NSData *data;
    if (self.customArchiveBlock)
        data = self.customArchiveBlock(object);
    else
        data = [NSKeyedArchiver archivedDataWithRootObject:object];
    
    lock();
    NSString *fileName = HYMD5(key);
    BOOL finishDB = [_db saveItemWithKey:key
                   value:data
                fileName:fileName
                  maxAge:maxAge
    shouldStoreValueInDB:NO];
    BOOL finishWrite = [_file writeData:data fileName:fileName];
    if (!finishWrite) {
        [_db removeItemWithKey:key];
    }
    unLock();
    
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
    if (key.length == 0 || ![key isKindOfClass:[NSString class]]){
        return nil;
    }
        
    NSData *data;
    
    lock();
    HYDiskCacheItem *item = [_db getItemForKey:key];
    
    if (!item) {
        unLock();
        return nil;
    }
    if (item.maxAge != -1 && (NSInteger)time(NULL) - item.inTimeStamp > item.maxAge) {
        unLock();
        return nil;
    }
    data = [_file fileReadWithName:item.fileName];
    unLock();
    
    id object;
    if (self.customUnarchiveBlock){
        object = self.customUnarchiveBlock(data);
    }
    else{
        @try {
            object = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        }
        @catch (NSException *exception) {
            [self removeObjectForKey:key];
            object = nil;
        }
        
    }
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
    //[_storage _removeValueForKey:key];
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
    //[_storage _removeValueForKeys:keys];
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
    //[_storage _removeAllValues];
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
//    if (cost == 0)
//    {
//        [self removeAllObjectWithBlock:block];
//    }
//    else if (cost < self.totalByteCostNow)
//    {
//        __weak HYDiskCache *weakSelf = self;
//        dispatch_async(_dataQueue, ^{
//           
//            __strong HYDiskCache *stronglySelf = weakSelf;
//            lock();
//            //do not use self.totalByteCostNow  avoid deadlock
//            while (cost <= _storage->_lruMap->_totalByteCost)
//            {
//                _HYDiskCacheItem *item = _storage->_lruMap->_tail;
//                if (item)
//                {
//                    [_storage _removeValueForKey:item->key];
//                }
//            }
//            unLock();
//            
//            if (block)
//                block(stronglySelf);
//        });
//    }
//    return;
}

- (void)trimToCostLimitWithBlock:(nullable HYDiskCacheBlock)block
{
    [self trimToCost:self.byteCostLimit block:block];
}

- (void)p_trimToAgeLimitRecursively
{
//    lock();
//    NSTimeInterval trimInterval = _trimToMaxAgeInterval;
//    __block _HYDiskCacheItem *item = _storage->_lruMap->_tail;
//    unLock();
//    
//    NSDate *distantFuture = [NSDate distantFuture];
//    while (item)
//    {
//        lock();
//        NSTimeInterval objectMaxAge = item->maxAge;
//        unLock();
//        
//        NSTimeInterval objectAgeSinceNow = -[item->inCacheDate timeIntervalSinceNow];
//        if (objectAgeSinceNow >= objectMaxAge && ![item->inCacheDate isEqualToDate:distantFuture])
//        {
//            lock();
//            [_storage _removeValueForKey:item->key];
//            item = _storage->_lruMap->_tail;
//            unLock();
//        }
//        else
//        {
//            item = nil;
//        }
//    }
//    
//    dispatch_time_t interval = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(trimInterval * NSEC_PER_SEC));
//    
//    __weak HYDiskCache *weakSelf = self;
//    dispatch_after(interval, _dataQueue, ^{
//        
//        HYDiskCache *stronglySelf = weakSelf;
//        [stronglySelf p_trimToAgeLimitRecursively];
//    });
}


#pragma mark getter setter for thread-safe

- (NSUInteger)totalByteCostNow
{
//    lock();
//    NSUInteger cost = _storage->_lruMap->_totalByteCost;
//    unLock();
//    return cost;
    return 0;
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









