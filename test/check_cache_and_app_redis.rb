errors = 0

if (actual = Rails.cache.fetch("migration_test_key")) != "abc1"
  errors += 1
  puts "Error fetching cached value, expected: 'abc1', got: #{actual}"
end

include Redisable

if (actual = redis.get("another_migration_test")) != "def2"
  errors += 1
  puts "Error fetching app redis key, expected: 'def2', got: #{actual}"
end

exit (-1 * errors)
