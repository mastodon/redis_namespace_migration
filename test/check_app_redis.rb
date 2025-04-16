errors = 0

include Redisable

if (actual = redis.get("another_migration_test")) != "def2"
  errors += 1
  puts "Error fetching app redis key, expected: 'def2', got: #{actual}"
end

exit (-1 * errors)
