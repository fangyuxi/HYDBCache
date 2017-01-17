//
//  HYDBRunnner.m
//  Pods
//
//  Created by fangyuxi on 2017/1/16.
//
//

#import "HYDBRunnner.h"
#import "sqlite3.h"

static const NSUInteger kMaxErrorRetryCount = 8;
static const NSTimeInterval kMinRetryTimeInterval = 2.0;
static const int kPathLengthMax = PATH_MAX - 64;
static NSString *const kDBName = @"meta.sqlite";

// query result callback
typedef NSInteger(^HYDBRunnerExecuteStatementsCallbackBlock)(NSDictionary *resultsDictionary);

@interface HYDBRunnner ()
{
    sqlite3 *_db;
    CFMutableDictionaryRef _dbStmtCache;
    NSTimeInterval _dbLastOpenErrorTime;
    NSUInteger _dbOpenErrorCount;
    
    NSString *_dbPath;
}

@end

@implementation HYDBRunnner

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

- (instancetype)init {
    @throw [NSException exceptionWithName:@"HYDBRunner error" reason:@"请使用指定初始化函数" userInfo:nil];
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
            NSLog(@"YYKVStorage init error:%@", error);
            return nil;
    }
    _dbPath = [path stringByAppendingPathComponent:kDBName];
    if ([self open] && [self _dbInitialize]) {
        return self;
    }
    else {
        [self close];
        return nil;
    }
    return nil;
}

- (BOOL)open
{
    if (_db){
        return YES;
    }
    sqlite3_config(SQLITE_CONFIG_MEMSTATUS, 0);
    
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
        
        if (_errorLogsEnabled) {
            NSLog(@"%s line:%d sqlite open failed (%d).",
                  __FUNCTION__,
                  __LINE__,
                  result);
        }
        return NO;
    }
}

- (BOOL)close {
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
            if (_errorLogsEnabled) {
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

- (BOOL)saveItem:(HYDiskCacheItem *)item
{
    if (item && item.key && item.key.length > 0) {
        return [self saveWithKey:item.key value:item.value fileName:item.fileName];
    }
    return NO;
}

- (BOOL)removeItem:(HYDiskCacheItem *)item
{
    if (item && item.key && item.key.length > 0) {
        return [self removeItemWithKey:item.key];
    }
    return NO;
}

- (BOOL)saveWithKey:(NSString *)key
                value:(NSData *)value
             fileName:(NSString *)fileName{
    NSString *sql = @"insert or replace into manifest (key, filename, size, value, modification_time, last_access_time) values (?1, ?2, ?3, ?4, ?5, ?6);";
    sqlite3_stmt *stmt = [self _prepareStmt:sql];
    if (!stmt) {
        return NO;
    }
    NSInteger timestamp = (NSInteger)time(NULL);
    sqlite3_bind_text(stmt, 1, key.UTF8String, -1, NULL);
    sqlite3_bind_text(stmt, 2, fileName.UTF8String, -1, NULL);
    sqlite3_bind_int(stmt, 3, (NSInteger)value.length);
    if (fileName.length == 0) {
        sqlite3_bind_blob(stmt, 4, value.bytes, (int)value.length, 0);
    } else {
        sqlite3_bind_blob(stmt, 4, NULL, 0, 0);
    }
    sqlite3_bind_int(stmt, 5, timestamp);
    sqlite3_bind_int(stmt, 6, timestamp);
    
    int result = sqlite3_step(stmt);
    if (result != SQLITE_DONE) {
        if (_errorLogsEnabled){
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
        if (_errorLogsEnabled) {
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
        if (_errorLogsEnabled) {
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
        if (_errorLogsEnabled){
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
        if (_errorLogsEnabled){
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
        if (_errorLogsEnabled){
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



- (BOOL)_check {
    if (!_db) {
        if (_dbOpenErrorCount < kMaxErrorRetryCount &&
            CACurrentMediaTime() - _dbLastOpenErrorTime > kMinRetryTimeInterval) {
            return [self open] && [self _dbInitialize];
        } else {
            return NO;
        }
    }
    return YES;
}

// create table and index
- (BOOL)_dbInitialize {
    NSString *sql = @"pragma journal_mode = wal; pragma synchronous = normal; create table if not exists manifest (key text, filename text, size integer, value blob, modification_time integer, last_access_time integer, primary key(key)); create index if not exists last_access_time_idx on manifest(last_access_time);";
    return [self _executeStatements:sql];
}

// no cache
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
    
    if (errmsg && _errorLogsEnabled) {
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
            if (_errorLogsEnabled) NSLog(@"%s line:%d sqlite stmt prepare error (%d): %s", __FUNCTION__, __LINE__, result, sqlite3_errmsg(_db));
            return NULL;
        }
        CFDictionarySetValue(_dbStmtCache, (__bridge const void *)(sql), stmt);
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

@end
