//
//  HYDBRunnner.m
//  Pods
//
//  Created by fangyuxi on 2017/1/16.
//
//

#import "HYDBStorage.h"
#import "sqlite3.h"

static const NSUInteger kMaxErrorRetryCount = 10;
static const NSTimeInterval kMinRetryTimeInterval = 2.0;
static const int kPathLengthMax = PATH_MAX - 64;

static NSString *const kDBName = @"manifest.sqlite";                ///<数据库主文件
static NSString *const kDBShmFileName = @"manifest.sqlite-shm"; ///<开启wal模式后的缓存文件
static NSString *const kDBWalFileName = @"manifest.sqlite-wal"; //<开启wal模式后的缓冲文件，可以选择手动标记checkpoint，本次实现选择自动checkpoint

//开启mmap 大小控制在5M
#define kSQLiteMMapSize (50*1024*1024)

// query result callback
typedef NSInteger(^HYDBRunnerExecuteStatementsCallbackBlock)(NSDictionary *resultsDictionary);

@interface HYDBStorage ()
{
    sqlite3 *_db;
    CFMutableDictionaryRef _dbStmtCache;
    NSTimeInterval _dbLastOpenErrorTime;
    NSUInteger _dbOpenErrorCount;
    
    NSString *_rootPath;
    NSString *_dbPath;
}

@end

@implementation HYDBStorage

// query callback. avoid clang blabla.
NSInteger _HYDBRunnerExecuteBulkSQLCallback(void *theBlockAsVoid,
                                      int columns,
                                      char **values,
                                      char **names);
NSInteger _HYDBRunnerExecuteBulkSQLCallback(void *theBlockAsVoid,
                                      int columns,
                                      char **values,
                                      char **names) {
    
    if (!theBlockAsVoid) {
        return SQLITE_OK;
    }
    
    NSInteger (^execCallbackBlock)(NSDictionary *resultsDictionary) = (__bridge NSInteger (^)(NSDictionary *__strong))(theBlockAsVoid);
    
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:(NSUInteger)columns];
    
    for (NSInteger i = 0; i < columns; i++) {
        NSString *key = [NSString stringWithUTF8String:names[i]];
        id value = values[i] ? [NSString stringWithUTF8String:values[i]] : [NSNull null];
        [dictionary setObject:value forKey:key];
    }
    
    return execCallbackBlock(dictionary);
}

- (void)dealloc
{
    [self _close];
}

- (instancetype)init {
    @throw [NSException exceptionWithName:@"HYDBStorage error" reason:@"请使用指定初始化函数" userInfo:nil];
    return nil;
}

- (instancetype)initWithDBPath:(NSString *)path
{
    self = [super init];
    _dbPath = [path copy];
    NSError *error;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:_dbPath
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&error]) {
            NSLog(@"HYDBStorage init path error:%@", error);
            return nil;
    }
    _rootPath = [path copy];
    _dbPath = [_rootPath stringByAppendingPathComponent:kDBName];
    if ([self _open]){
        if ([self _createTable]) {
            return self;
        }
        else {
            [self _close];
            return nil;
        }
    }
    else {
        return nil;
    }
    return nil;
}

- (BOOL)_open
{
    if (_db){
        return YES;
    }
    
    //关闭内存申请统计
    sqlite3_config(SQLITE_CONFIG_MEMSTATUS, 0);
    //尝试打开mmap
    sqlite3_config(SQLITE_CONFIG_MMAP_SIZE, (SInt64)kSQLiteMMapSize, (SInt64)-1);
    //多个线程可以共享connection
    sqlite3_config(SQLITE_CONFIG_SINGLETHREAD);
  
    NSInteger result = sqlite3_open(_dbPath.UTF8String, &_db);
    if (result == SQLITE_OK) {
        CFDictionaryKeyCallBacks keyCallbacks = kCFCopyStringDictionaryKeyCallBacks;
        CFDictionaryValueCallBacks valueCallbacks = {0};
        _dbStmtCache = CFDictionaryCreateMutable(CFAllocatorGetDefault(), 0, &keyCallbacks, &valueCallbacks);
        _dbLastOpenErrorTime = 0;
        _dbOpenErrorCount = 0;
        return YES;
    } else {
        _db = NULL;
        if (_dbStmtCache) {
            CFRelease(_dbStmtCache);
        }
        _dbStmtCache = NULL;
        _dbLastOpenErrorTime = CACurrentMediaTime();
        _dbOpenErrorCount++;
        
        if (_logsEnabled) {
            NSLog(@"%s line:%d sqlite open failed (%d).",
                  __FUNCTION__,
                  __LINE__,
                  result);
        }
        return NO;
    }
}

//如果调用的是'sqlite3_close' 如果关闭过程中有未执行完毕的语句会返回 'SQLITE_BUSY'
//如果调用的是'sqlite3_close_v2' 如果关闭过程中有未执行完毕的语句 那么数据库会持续
//一直冻结状态，知道所有语句执行完毕。
- (BOOL)_close {
    if (!_db) {
        return YES;
    }
    
    NSInteger  result = 0;
    BOOL retry = NO;
    BOOL stmtFinalized = NO;
    
    if (_dbStmtCache) {
        CFRelease(_dbStmtCache);
    }
    _dbStmtCache = NULL;
    
    do {
        retry = NO;
        result = sqlite3_close(_db);
        if (result == SQLITE_BUSY || result == SQLITE_LOCKED) {
            if (!stmtFinalized) {
                stmtFinalized = YES;
                sqlite3_stmt *stmt;
                while ((stmt = sqlite3_next_stmt(_db, nil)) != 0) {
                    sqlite3_finalize(stmt);
                    retry = YES;
                }
            }
        } else if (result != SQLITE_OK) {
            if (_logsEnabled) {
                NSLog(@"%s line:%d sqlite close failed (%d).",
                      __FUNCTION__,
                      __LINE__,
                      result);
            }
        }
    } while (retry);
    _db = NULL;
    return YES;
}

- (BOOL)_check {
    if (!_db) {
        if (_dbOpenErrorCount < kMaxErrorRetryCount &&
            CACurrentMediaTime() - _dbLastOpenErrorTime > kMinRetryTimeInterval) {
            return [self _open] && [self _createTable];
        } else {
            return NO;
        }
    }
    return YES;
}

// create table and index
- (BOOL)_createTable {
    NSString *sql = @"pragma journal_mode = wal; create table if not exists manifest (key text, filename text, size integer, value blob, in_time integer, last_access_time integer, max_age integer, primary key(key)); create index if not exists last_access_time_idx on manifest(last_access_time);";
    return [self _executeStatements:sql];
}

// no stmt cache
- (BOOL)_executeStatements:(NSString *)sql {
    return [self _executeStatements:sql withResultBlock:nil];
}

- (BOOL)_executeStatements:(NSString *)sql
           withResultBlock:(HYDBRunnerExecuteStatementsCallbackBlock)block {
    
    int rc;
    char *errmsg = nil;
    
    rc = sqlite3_exec(_db,
                      [sql UTF8String],
                      block ? _HYDBRunnerExecuteBulkSQLCallback : nil, (__bridge void *)(block),
                      &errmsg);
    
    if (errmsg && _logsEnabled) {
        NSLog(@"Error inserting batch: %s", errmsg);
        sqlite3_free(errmsg);
    }
    
    return (rc == SQLITE_OK);
}

- (sqlite3_stmt *)_prepareStmt:(NSString *)sql {
    if (![self _check] || sql.length == 0) {
        return NULL;
    }
    sqlite3_stmt *stmt = (sqlite3_stmt *)CFDictionaryGetValue(_dbStmtCache, (__bridge const void *)(sql));
    if (!stmt) {
        int result = sqlite3_prepare_v2(_db, sql.UTF8String, -1, &stmt, NULL);
        if (result != SQLITE_OK) {
            if (_logsEnabled) NSLog(@"%s line:%d sqlite stmt prepare error (%d): %s", __FUNCTION__, __LINE__, result, sqlite3_errmsg(_db));
            return NULL;
        }
        //CFDictionarySetValue(_dbStmtCache, (__bridge const void *)(sql), stmt);
    } else {
        sqlite3_reset(stmt);
    }
    return stmt;
}

- (NSString *)_sqlParameterDependentOnKeys:(NSArray *)keys {
    NSMutableString *string = [NSMutableString new];
    for (NSUInteger i = 0,max = keys.count; i < max; i++) {
        [string appendString:@"?"];
        if (i + 1 != max) {
            [string appendString:@","];
        }
    }
    return string;
}

- (BOOL)_updateAccessTimeWithKey:(NSString *)key {
    NSString *sql = @"update manifest set last_access_time = ?1 where key = ?2;";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) return NO;
    sqlite3_bind_int(stmt, 1, (NSInteger)time(NULL));
    sqlite3_bind_text(stmt, 2, key.UTF8String, -1, NULL);
    int result = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (result != SQLITE_DONE) {
        if (_logsEnabled) {
            NSLog(@"%s line:%d sqlite update error (%d): %s",
                  __FUNCTION__,
                  __LINE__,
                  result,
                  sqlite3_errmsg(_db));
        }
        return NO;
    }
    return YES;
}


- (BOOL)saveItem:(HYDiskCacheItem *)item shouldStoreValueInDB:(BOOL)store
{
    if (item && item.key && item.key.length > 0) {
        return [self saveItemWithKey:item.key
                               value:item.value
                            fileName:item.fileName
                              maxAge:item.maxAge
                shouldStoreValueInDB:store];
    }
    return NO;
}

- (BOOL)saveItemWithKey:(NSString *)key
                  value:(NSData *)value
               fileName:(NSString *)fileName
                 maxAge:(NSInteger)maxAge
   shouldStoreValueInDB:(BOOL)store{
    
    if (!key || key.length == 0) {
        return NO;
    }
    
    NSString *sql = @"insert or replace into manifest (key, filename, size, value, in_time, last_access_time, max_age) values (?1, ?2, ?3, ?4, ?5, ?6, ?7);";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return NO;
    }
    NSInteger timestamp = (NSInteger)time(NULL);
    sqlite3_bind_text(stmt, 1, key.UTF8String, -1, NULL);
    sqlite3_bind_text(stmt, 2, fileName.UTF8String, -1, NULL);
    sqlite3_bind_int(stmt, 3, (NSInteger)value.length);
    if (store) {
        sqlite3_bind_blob(stmt, 4, value.bytes, (int)value.length, 0);
    }
    else {
        sqlite3_bind_blob(stmt, 4, NULL, 0, 0);
    }
    sqlite3_bind_int(stmt, 5, timestamp);
    sqlite3_bind_int(stmt, 6, timestamp);
    sqlite3_bind_int(stmt, 7, maxAge);
    int result = sqlite3_step(stmt);
    sqlite3_finalize(stmt);
    if (result != SQLITE_DONE) {
        if (_logsEnabled){
            NSLog(@"%s line:%d sqlite insert error (%d): %s",
                  __FUNCTION__,
                  __LINE__,
                  result,
                  sqlite3_errmsg(_db));
        }
        return NO;
    }
    return YES;
}

- (HYDiskCacheItem *)getItemForKey:(NSString *)key
{
    if (!key || key.length == 0) {
        return nil;
    }
    
    NSString *sql = @"select key, filename, size, value, in_time, last_access_time ,max_age from manifest where key = ?1;";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return nil;
    }
    sqlite3_bind_text(stmt, 1, key.UTF8String, -1, NULL);
    
    HYDiskCacheItem *item = nil;
    int result = sqlite3_step(stmt);
    
    if (result == SQLITE_ROW) {
        
        item = [HYDiskCacheItem new];
        char *theKey = (char *)sqlite3_column_text(stmt, 0);
        char *filename = (char *)sqlite3_column_text(stmt, 1);
        NSInteger size = sqlite3_column_int(stmt, 2);
        NSInteger length = sqlite3_column_bytes(stmt, 3);
        char *value = NULL;
        (length > 0) ? (value = sqlite3_column_blob(stmt, 3)) : (value = NULL);
        NSInteger in_time = sqlite3_column_int(stmt, 4);
        NSInteger last_access_time = sqlite3_column_int(stmt, 5);
        NSInteger max_age = sqlite3_column_int(stmt, 6);
        
        (key == NULL) ? (item.key = @"") : (item.key = [NSString stringWithUTF8String:theKey]);
        (filename == NULL) ? (item.fileName = @"") : (item.fileName = [NSString stringWithUTF8String:filename]);
        item.size = size;
        (value == NULL) ? (item.value = nil) : (item.value = [NSData dataWithBytes:value length:length]);
        item.inTimeStamp = in_time;
        item.lastAccessTimeStamp = last_access_time;
        item.maxAge = max_age;
        
        //更新访问时间
        [self _updateAccessTimeWithKey:key];
    }
    else {
        if (result != SQLITE_DONE) {
            if (_logsEnabled) {
                NSLog(@"%s line:%d sqlite query error (%d): %s",
                      __FUNCTION__,
                      __LINE__,
                      result,
                      sqlite3_errmsg(_db));
            }
        }
    }
    sqlite3_finalize(stmt);
    return item;
}

- (BOOL)removeItem:(HYDiskCacheItem *)item
{
    if (item && item.key && item.key.length > 0) {
        return [self removeItemWithKey:item.key];
    }
    return NO;
}



- (BOOL)removeItemWithKey:(NSString *)key
{
    NSString *sql = @"delete from manifest where key = ?1;";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return NO;
    }
    sqlite3_bind_text(stmt, 1, key.UTF8String, -1, NULL);
    
    NSInteger result = sqlite3_step(stmt);
    if (result != SQLITE_DONE) {
        if (_logsEnabled) {
            NSLog(@"%s line:%d db delete error (%d): %s",
                  __FUNCTION__,
                  __LINE__,
                  result,
                  sqlite3_errmsg(_db));
        }
        return NO;
    }
    return YES;
}

- (BOOL)removeAllItems
{
    NSString *sql = @"delete from manifest";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return NO;
    }

    NSInteger result = sqlite3_step(stmt);
    if (result != SQLITE_DONE) {
        if (_logsEnabled) {
            NSLog(@"%s line:%d db delete error (%d): %s",
                  __FUNCTION__,
                  __LINE__,
                  result,
                  sqlite3_errmsg(_db));
        }
        return NO;
    }
    return YES;
}


- (NSInteger)getItemCountWithKey:(NSString *)key {
    NSString *sql = @"select count(key) from manifest where key = ?1;";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return -1;
    }
    sqlite3_bind_text(stmt, 1, key.UTF8String, -1, NULL);
    NSInteger result = sqlite3_step(stmt);
    if (result != SQLITE_ROW) {
        if (_logsEnabled){
            NSLog(@"%s line:%d sqlite query error (%d): %s",
                  __FUNCTION__,
                  __LINE__,
                  result,
                  sqlite3_errmsg(_db));
        }
        return -1;
    }
    return sqlite3_column_int(stmt, 0);
}

- (NSInteger)getTotalItemSize {
    NSString *sql = @"select sum(size) from manifest;";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return -1;
    }
    NSInteger result = sqlite3_step(stmt);
    if (result != SQLITE_ROW) {
        if (_logsEnabled){
            NSLog(@"%s line:%d sqlite query error (%d): %s",
                  __FUNCTION__,
                  __LINE__,
                  result,
                  sqlite3_errmsg(_db));
        }
        return -1;
    }
    return sqlite3_column_int(stmt, 0);
}

- (NSInteger)getTotalItemCount {
    NSString *sql = @"select count(*) from manifest;";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return -1;
    }
    int result = sqlite3_step(stmt);
    if (result != SQLITE_ROW) {
        if (_logsEnabled){
            NSLog(@"%s line:%d sqlite query error (%d): %s",
                  __FUNCTION__,
                  __LINE__,
                  result,
                  sqlite3_errmsg(_db));
        }
        return -1;
    }
    return sqlite3_column_int(stmt, 0);
}

- (BOOL)reset
{
    if (_db) {
        if ([self _close]) {
            _db = NULL;
            _dbStmtCache = NULL;
        }
    }
    [[NSFileManager defaultManager] removeItemAtPath:[_rootPath
                                                      stringByAppendingPathComponent:kDBName] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[_rootPath
                                                      stringByAppendingPathComponent:kDBShmFileName] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[_rootPath
                                                      stringByAppendingPathComponent:kDBWalFileName] error:nil];
    if ([self _open]){
        if ([self _createTable]) {
            return YES;
        }
        else {
            [self _close];
            return NO;
        }
    }
    else {
        return NO;
    }
}

@end
