# Taken almost verbatim from https://www.mikeperham.com/2017/04/10/migrating-from-redis-namespace/

base_ns = ENV.fetch("REDIS_NAMESPACE")
prefix = "#{base_ns}:*"
cache_prefix = "#{base_ns}_cache:*"

################################
# Point to your Redis instance
redis = Redis.new(host: "redis", db: 0)

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
