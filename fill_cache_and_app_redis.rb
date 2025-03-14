Rails.cache.write("migration_test_key", "abc1")

include Redisable

redis.set("another_migration_test", "def2")

500_000.times { |i| redis.set("large_numbers_#{i}", "test") }
