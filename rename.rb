# Based on code from https://www.mikeperham.com/2017/04/10/migrating-from-redis-namespace/

redis_config = Mastodon::RedisConfiguration.new

base_ns = redis_config.base[:namespace]
prefix = "#{base_ns}:*"
cache_prefix = "#{base_ns}_cache:*"

redis_url = redis_config.base[:url]
redis = Redis.new(url: redis_url)

script = <<-LUA
  local count = 0
  local keys = redis.call("keys", ARGV[1])
  for _, keyname in pairs(keys) do
    redis.call("rename", keyname, string.sub(keyname, ARGV[2]))
    count = count + 1
  end
  return count
LUA

start = Time.now
count = redis.eval(script, [], [prefix, prefix.size])
cache_count = redis.eval(script, [], [cache_prefix, prefix.size])
puts "Complete, migrated #{count + cache_count} keys in #{Time.now - start} sec"
