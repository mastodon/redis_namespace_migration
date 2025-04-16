# Taken almost verbatim from https://www.mikeperham.com/2017/04/10/migrating-from-redis-namespace/

base_ns = ENV.fetch("REDIS_NAMESPACE")
prefix = "#{base_ns}:*"
cache_prefix = "#{base_ns}_cache:*"

redis_url = Mastodon::RedisConfiguration.new.base[:url]
redis = Redis.new(url: redis_url)

new_redis = Redis.new(url: ENV.fetch("NEW_REDIS_URL"))

migrate_script = <<-LUA
  local host = "#{new_redis.connection[:host]}"
  local port = #{new_redis.connection[:port]}
  local db = #{new_redis.connection[:db]}
  local keys = redis.call("keys", ARGV[1])
  local step = 1000
  for i = 1, #keys, step do
    redis.call("migrate", host, port, "", db, 5000, "KEYS", unpack(keys, i, math.min(i + step - 1, #keys)))
  end
LUA

remove_cache_script = <<-LUA
  local keys = redis.call("keys", ARGV[1])
  local step = 1000
  for i = 1, #keys, step do
    redis.call("del", unpack(keys, i, math.min(i + step - 1, #keys)))
  end
LUA

rename_script = <<-LUA
  local count = 0
  local keys = redis.call("keys", ARGV[1])
  for _, keyname in pairs(keys) do
    redis.call("rename", keyname, string.sub(keyname, ARGV[2]))
    count = count + 1
  end
  return count
LUA

start = Time.now
redis.eval(migrate_script, [], [prefix])
redis.eval(remove_cache_script, [], [cache_prefix])
count = new_redis.eval(rename_script, [], [prefix, prefix.size])
puts "Complete, migrated and renamed #{count} keys in #{Time.now - start} sec"
