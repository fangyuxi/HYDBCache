//
//  HYCache.m
//  Pods
//
//  Created by fangyuxi on 16/4/15.
//
//

#import "HYCache.h"

@interface HYCache ()

@property (nonatomic, readwrite) HYMemoryCache *memCache;
@property (nonatomic, readwrite) HYDiskCache *diskCache;

@end

@implementation HYCache

- (instancetype)initWithName:(NSString *)name{
    return [self initWithName:name
                directoryPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]];
}

- (nullable instancetype)initWithName:(NSString *)name
                          directoryPath:(nullable NSString *)directoryPath{
    self = [super init];
    if (self){
        _memCache = [[HYMemoryCache alloc] initWithName:name];
        _diskCache = [[HYDiskCache alloc] initWithName:name directoryPath:directoryPath];
        
        if (!_memCache ||!_diskCache) {
            _memCache = nil;
            _diskCache = nil;
            return nil;
        }
        return self;
    }
    return nil;
}

- (nullable id)objectForKey:(NSString *)key{
    if (!key) {
        return nil;
    }
    id object = [self.memCache objectForKey:key];
    if (!object){
        object = [self.diskCache objectForKey:key];
        if (object) {
            [self.memCache setObject:object forKey:key];
        }
    }
    return object;
}

- (void)objectForKey:(NSString *)key
           withBlock:(void (^)(NSString *key ,id _Nullable object))block{
    if (!block){
        return;
    }
    id object = [self.memCache objectForKey:key];
    if (object){
        block(key, object);
    }else{
        [self.diskCache objectForKey:key withBlock:^(HYDiskCache * _Nonnull cache, NSString * _Nonnull key, id _Nullable object) {
            [self.memCache setObject:object forKey:key];
            block(key, object);
        }];
    }
}

- (void)setObject:(_Nullable id<NSCoding>)object
           forKey:(NSString *)key
                 inDisk:(BOOL)inDisk{
    [self.memCache setObject:object forKey:key];
    if (inDisk) {
        [_diskCache setObject:object forKey:key];
    }
}

- (void)setObject:(_Nullable id<NSCoding>)object
           forKey:(NSString *)key
           inDisk:(BOOL)inDisk
        withBlock:(void(^)())block{
    if (!block){
        return;
    }
    [self.memCache setObject:object forKey:key];
    if (inDisk) {
        [_diskCache setObject:object forKey:key withBlock:^(HYDiskCache * _Nonnull cache, NSString * _Nonnull key, id _Nullable object) {
            block();
        }];
    }
}

- (void)removeAllObjects{
    [self.memCache removeAllObject];
    [self.diskCache removeAllObject];
}

- (void)removeAllObjectsWithBlock:(void(^)())block{
    [self.memCache removeAllObject];
    [self.diskCache removeAllObjectWithBlock:^(HYDiskCache * _Nonnull cache) {
        block();
    }];
}

@end




