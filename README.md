# 简介

`HYDBCache`提供了`HYMemoryCache`和`HYDiskCache`，并通过`HYCache`进行包装

# 特性

* 内存缓存支持常见的缓存功能，并且支持LRU淘汰算法
* 磁盘缓存包含了数据库缓存和文件缓存两部分，会根据文件大小自动选择存储到数据库还是文件，当文件超过16K的时候直接存储到数据库，大于20k的文件，meta信息存储在，数据本身存储在文件中，支持LRU，支持非NSCoding协议对象
* 采用自己编译的sqlite，比Apple自带的快，并且有几项优化，第一关闭了内存统计，第二开启了mapping，第三关闭了所有线程操作的锁，采用外部单一的锁进行并发控制

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

iOS 7.0 and uppper

## Installation

```ruby
pod "HYDBCache"
```

## Author

fangyuxi, fangyuxi@58.com

## License

HYDBCache is available under the MIT license. See the LICENSE file for more info.
