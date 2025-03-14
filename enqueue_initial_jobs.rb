include Redisable
redis.flushall

2.times do
  RemovalWorker.perform_async(12345)
end

3.times do
  AfterUnallowDomainWorker.perform_async({a: 2})
end

RefollowWorker.perform_async(12345)
