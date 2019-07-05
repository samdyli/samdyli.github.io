资源列表：<https://cloud.tencent.com/developer/article/1005481>

1. select 为什么首先将被监控的fds列表从用户态拷贝到内核空间？ 为什么需要对被监控的fds做大小限制，大小限制为1024。

2. select有什么问题？

   （1） fds数量限制问题

   （2）fds从用户态向内核态拷贝的问题

   （3）遍历所有socket状态的问题

3. epool怎么解决select的三个问题？ 