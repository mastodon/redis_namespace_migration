base_ns = ENV.fetch("REDIS_NAMESPACE")
prefix = "#{base_ns}:*"
cache_prefix = "#{base_ns}_cache:*"

redis_url = Mastodon::RedisConfiguration.new.base[:url]
redis = Redis.new(url: redis_url)

errors = redis.keys(cache_prefix).size

exit (-1 * errors)
