# Taken almost verbatim from https://www.mikeperham.com/2017/04/10/migrating-from-redis-namespace/

base_ns = ENV.fetch("REDIS_NAMESPACE")
prefix = "#{base_ns}:*"
cache_prefix = "#{base_ns}_cache:*"

redis_url = Mastodon::RedisConfiguration.new.base[:url]
redis = Redis.new(url: redis_url)

new_redis = Redis.new(url: ENV.fetch("NEW_REDIS_URL"))

migrate_script = <<-LUA
  local keys = redis.call("keys", ARGV[1])
  local step = 1000
  for i = 1, #keys, step do
    redis.call("migrate", ARGV[2], ARGV[3], "", ARGV[4], 5000, "KEYS", unpack(keys, i, math.min(i + step - 1, #keys)))
  end
LUA

migrate_script_auth = <<-LUA
  local keys = redis.call("keys", ARGV[1])
  local step = 1000
  for i = 1, #keys, step do
    redis.call("migrate", ARGV[2], ARGV[3], "", ARGV[4], 5000, "AUTH", ARGV[5], "KEYS", unpack(keys, i, math.min(i + step - 1, #keys)))
  end
LUA

migrate_script_auth2 = <<-LUA
  local keys = redis.call("keys", ARGV[1])
  local step = 1000
  for i = 1, #keys, step do
    redis.call("migrate", ARGV[2], ARGV[3], "", ARGV[4], 5000, "AUTH2", ARGV[5], ARGV[6], "KEYS", unpack(keys, i, math.min(i + step - 1, #keys)))
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
if new_redis._client.username
  redis.eval(migrate_script_auth2, [], [prefix, new_redis.connection[:host], new_redis.connection[:port], new_redis.connection[:db], new_redis._client.username, new_redis._client.password])
elsif new_redis._client.password
  redis.eval(migrate_script_auth, [], [prefix, new_redis.connection[:host], new_redis.connection[:port], new_redis.connection[:db], new_redis._client.password])
else
  redis.eval(migrate_script, [], [prefix, new_redis.connection[:host], new_redis.connection[:port], new_redis.connection[:db]])
end
redis.eval(remove_cache_script, [], [cache_prefix])
count = new_redis.eval(rename_script, [], [prefix, prefix.size])
puts "Complete, migrated and renamed #{count} keys in #{Time.now - start} sec"
