## 序言
我是非典型理科男号主。 关注后你可以收获**最硬核的知识分享， 最有趣的互联网故事**

![](/Users/didi/data/code/samdyli.github.io/blog/_posts/339d7ad2-0a2c-4bf1-81a9-e294cb957953.png)

上一篇文章《Redis为什么这么快》介绍了Redis性能评估工具，以及Redis高性能的原因。详细请见：
这篇我们将从业务的视角，讲解下影响Redis性能的因素以及如何提升Redis使用的性能。

## 从用户到Redis请求过程分析

以最常用场景缓存为例，流量从用户到Redis Server的过程如下所示：


![image](/Users/didi/data/code/samdyli.github.io/blog/_posts/0247cddc-2fc8-4642-b136-a621f2e375d1.png)


1. 用户访问后端服务器，调用对应的Controller
2. Controller命中缓存记录，通过Jedis客户端调用Reids从缓存获取记录。
如果使用的Jedis连接池获取Jedis对象，从Jedis连接池获取一个Jedis连接实例。
3. Jedis使用Redis序列化协议(RESP)将命令编码，放到Redis Server输入缓冲区中。
4. Redis Server从输入缓冲区获取命令并执行。
5. 执行结束后将执行结果放入到输出缓冲区。
6. Jedis客户端从输出缓冲区获取执行结果并返回给Controller。
7. Controller执行完业务逻辑相应用户的请求。

从上面时序图可以看出，用户请求通过Redis client经由网路到达Redis Server。

因此在考虑使用Redis性能的时候要从客户端和服务端两个角度考虑。 对于业务方来说， 合理使用Redis特性比Redis服务器的优化可操作性更强，也更容易获得好的效果。 

下面将从业务优化和服务器优化两个方面介绍Redis的优化。 

### 业务优化

查询本地redis的延迟通常低于1毫秒，而查询同一个数据中心的redis的延迟通常低于5毫秒。也就是说，网络传输的损耗为实际操作用时的5倍。

因此，从客户端角度，如何减少网络耗时至关重要。

#### 使用连接池减少建立连接和销毁连接的时间开销

Jedis是Java语言使用最多的Redis客户端。 Jedis支持直连和连接池的两种方式。

直连的方式：

```
# 1. 生成一个Jedis对象，这个对象负责和指定Redis实例进行通信 
Jedis jedis = new Jedis("127.0.0.1", 6379); 
# 2. jedis执行set操作 
jedis.set("hello", "world"); 
# 3. jedis执行get操作 value="world" 
String value = jedis.get("hello");
```

所谓直连是指Jedis每次都会新建TCP 连接，使用后再断开连接。 我们都知道新建TCP连接经过3次握手，释放TCP连接经过4次挥手，新建和回收是非常耗时操作。对于频繁访问Redis的场景显然不是高效的使用方式。

Jedis也提供了连接池的方式。
![节选自：《Redis开发和运维》](/Users/didi/data/code/samdyli.github.io/blog/_posts/a318ce97-a9b9-4aa1-bfb2-02d350513b70.png) 
<center>节选自：《Redis开发和运维》</center>

```
// common-pool连接池配置，这里使用默认配置
GenericObjectPoolConfig poolConfig = new GenericObjectPoolConfig(); // 初始化Jedis连接池 
JedisPool jedisPool = new JedisPool(poolConfig, "127.0.0.1", 6379);
Jedis jedis = null; try {
  // 1. 从连接池获取jedis对象 
  jedis = jedisPool.getResource(); 
  // 2. 执行操作 
  jedis.get("hello"); 
} catch (Exception e) { 
    logger.error(e.getMessage(),e); 
} finally { 
  if (jedis != null) { 
  // 如果使用JedisPool，close操作不是关闭连接，代表归还连接池 
  jedis.close(); 
  } 
}
```

#### 使用Pipeline或者Lua脚本减少请求次数

通过连接池，减少建立和断开TCP连接的时间开销。 另外，redis提供了其他三种方式，通过减少请求次数提升性能。
(1) 批量操作的命令，如mget，mset等
(2) pipeline方式
(3) Lua脚本


#### pipeline方式

使用redis-benchmark在Intel(R) Xeon(R) CPU E5520 @ 2.27GHz对比pipeline（每次16个命令）和普通请求。

使用pipeline的情况：
```
$ ./redis-benchmark -r 1000000 -n 2000000 -t get,set,lpush,lpop -P 16 -q
SET: 552028.75 requests per second
GET: 707463.75 requests per second
LPUSH: 767459.75 requests per second
LPOP: 770119.38 requests per second
Intel(R) Xeon(R) CPU E5520 @ 2.27GHz (without pipelining)
```

无pipeline的情况：

```
$ ./redis-benchmark -r 1000000 -n 2000000 -t get,set,lpush,lpop -q
SET: 122556.53 requests per second
GET: 123601.76 requests per second
LPUSH: 136752.14 requests per second
LPOP: 132424.03 requests per second
```

从benchmark的结果可以看出，使用pipeline技术比没有使用性能提升5-10倍左右。 

Jedis支持Pipeline特性，我们知道 Redis提供了mget、mset方法，但是并没有提供mdel方法，如果想实现这个功 能，可以借助Pipeline来模拟批量删除，虽然不会像mget和mset那样是一个原 子命令，但是在绝大数场景下可以使用。

```
public void mdel(List<String> keys) { 
  Jedis jedis = new Jedis("127.0.0.1"); 
  // 1)生成pipeline对象 Pipe   
  line pipeline = jedis.pipelined(); 
  // 2)pipeline执行命令，注意此时命令并未真正执行 
  for (String key : keys) { 
      pipeline.del(key);
  }
  // 3)执行命令 
  pipeline.sync(); 
}
```

将del命令封装到pipeline中，可以调用pipeline.del（String key），此时不会真正的 执行命令。 

使用pipeline.sync（）完成此次pipeline对象的调用。 

除了pipeline.sync（），还可以使用pipeline.syncAndReturnAll（）将 pipeline的命令进行返回。

##### pipeline提升性能的原因

pipeline提升性能的一个原因是减少了命令总的RTT时间(往返时延), 另外一方面减少 总的系统调用的次数。 

> RTT(Round-Trip Time)： 往返时延。在计算机网络中它是一个重要的性能指标，表示从发送端发送数据开始，到发送端收到来自接收端的确认（接收端收到数据后便立即发送确认），总共经历的时延。往返延时(RTT)由三个部分决定：即链路的传播时间、末端系统的处理时间以及路由器的缓存中的排队和处理时间。其中，前面两个部分的值作为一个TCP连接相对固定，路由器的缓存中的排队和处理时间会随着整个网络拥塞程度的变化而变化。所以RTT的变化在一定程度上反映了网络拥塞程度的变化。简单来说就是发送方从发送数据开始，到收到来自接受方的确认信息所经历的时间。

##### pipline和lua脚本的不同
Redis原生支持Lua语言，并且提供了通过客戶端执行lua脚本的命令。 

![Redis Lua脚本相关命令脑图](/Users/didi/data/code/samdyli.github.io/blog/_posts/a80c74f9-2f0c-4eea-b4da-fa62d61492e0.png)

比如我们可以用Lua脚本在低版本的Redis上实现分布式锁。

```
local current current = redis.call('incr',KEYS[1]) 

if tonumber(current) == 1 
then 
redis.call('expire',KEYS[1], ARGV[1]) 
end 

return current
```

调用EVAL命令可以传入不定的KEY和ARGS的值， 这些值被可以通过KEY[i]和ARGV[i]访问对应的入参，并且通过return返回执行结果。 

更多的Lua脚本，会在其他文章中介绍。 

可以关注微信公众号：非典型理科男，查看全部文章列表阅读Lua脚本相关的文章。 

pipeline和Lua比较：

(1) 返回结果不同： pipeline会把命令执行结果都返回出来， lua脚本只有一个返回结果。

(2) 使用场景不同： lua脚本可以提供复杂逻辑运算并且提供了缓存脚本的功能，提升像原生命令一样的性能体验。 因此lua脚本可以用在处理逻辑复杂，不需要返回或者只返回操作结果的场景。 pipeline用在合并命令减少执行开销和redis server压力的场景下。 


在使用pipeline时有几个注意事项：

(1) pipeline执行命令虽然没有明确的执行命令数量的限制，但是建议限制执行命令数量。 执行命令数量过多一方面占用网络带宽，另一方面会阻塞客户端。

## Redis Server性能影响因素

影响Redis Server性能主要有硬件、数据分布和配置有关。 

### 硬件因素
Redis喜欢下面的硬件条件：

1. 高带宽，低延迟的网络： Redis的性能中网络带宽和延迟通常是最大短板。因此，需要选择高带宽，低延迟的网络。
2. 大缓存快速 CPU： 而不是多核。这种场景下面，比较推荐 Intel CPU。AMD CPU 可能只有 Intel CPU 的一半性能（通过对 Nehalem EP/Westmere EP/Sandy 平台的对比）。 当其他条件相当时候，CPU 就成了 redis-benchmark 的限制因素。
3. 大对象(>10k)存储时内存和带宽显得尤其重要。 但是更重要是优化大对象的存储。 
4. 将Redis运行在物理机器上：Redis 在 VM 上会变慢。虚拟化对普通操作会有额外的消耗，Redis 对系统调用和网络终端不会有太多的 overhead。建议把 Redis 运行在物理机器上。


### 大Value的影响
包大小影响Redis的相应速度。 以太网网数据包在 1500 bytes 以下时， 将多条命令包装成 pipelining 可以大大提高效率。事实上，处理 10 bytes，100 bytes， 1000 bytes 的请求时候，吞吐量是差不多的，详细可以见下图。


![不同数据包大小下的并发量](/Users/didi/data/code/samdyli.github.io/blog/_posts/4e4ab010-6312-4f8e-ae2f-dce274989f3e.png)

所以，当大value(>10k)存在时要及时优化掉。 

参考文档：

1.  [Redis Benchmark](http://www.redis.cn/topics/benchmarks.html)
2.  [Redis 命令合集](http://redisdoc.com/script/evalsha.html)


![img](/Users/didi/data/code/samdyli.github.io/blog/_posts/a3d8ddb9-7852-462f-8492-076f112bb1cb.png)


![img](/Users/didi/data/code/samdyli.github.io/blog/_posts/e3b5ae90-c7c9-4851-b420-56c42cece4d9.png)

​										[什么是架构设计？架构设计看这篇文章就够了](https://mp.weixin.qq.com/s?__biz=MzIzNDUwMzkwNg==&mid=2247483734&idx=1&sn=bd3b956f88d7f51fc04a3f66a51713a9&chksm=e8f42adbdf83a3cd949b56cbb94462dedcef5f473c4f48582c438b2f36383d426cdc6938b013&scene=21#wechat_redirect)

​										[Redis为什么这么快？](https://mp.weixin.qq.com/s?__biz=MzIzNDUwMzkwNg==&mid=2247483721&idx=1&sn=24b191b3d69487d056ad0717daab6400&chksm=e8f42ac4df83a3d2b1b3c54612c5460be60f51fc97c088c73969312045ee2c43365595bc3f1d&scene=21&token=322415904&lang=zh_CN#wechat_redirect)

​										[重磅：解读2020年最新JVM生态报告](https://mp.weixin.qq.com/s?__biz=MzIzNDUwMzkwNg==&mid=2247483706&idx=1&sn=625eab1339bcfafcac207e29f79fbdab&chksm=e8f42ab7df83a3a10e803eec3106c3e4c7297a952885f22e6b2e751fbe1c92789a9bab51d2e7&scene=21#wechat_redirect)

​										[BIO,NIO,AIO 总结](https://mp.weixin.qq.com/s?__biz=MzIzNDUwMzkwNg==&mid=2247483712&idx=1&sn=feabc22cbe7b51532ec13b6e22e7cf8c&chksm=e8f42acddf83a3db2b24752552fb0e46d05176e1e00d11e8db7b15cd6e1e34844e2cc01c5b1b&scene=21#wechat_redirect)

​										[JDK8的新特性，你知道多少？](https://mp.weixin.qq.com/s?__biz=MzIzNDUwMzkwNg==&mid=2247483704&idx=1&sn=527990343f8ef0402febe2dc7e9e0ff3&chksm=e8f42ab5df83a3a3775ddc302f0f5facdbec38229e4067a51ed42f9cce874ea2fc9832a6ea01&scene=21#wechat_redirect)


​										回复“资料”，免费获取 一份独家呕心整理的技术资料！

![img](/Users/didi/data/code/samdyli.github.io/blog/_posts/91a901db-4003-4322-88f5-b13608db52e0.png)

