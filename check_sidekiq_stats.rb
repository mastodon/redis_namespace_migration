expected = {
  enqueued: 1,
  scheduled: 1,
  processed: 6,
  failed: 4,
  retry: 3,
  dead: 0
}

stats = Sidekiq::Stats.new

actual = {
  enqueued: stats.enqueued,
  scheduled: stats.scheduled_size,
  processed: stats.processed,
  failed: stats.failed,
  retry: stats.retry_size,
  dead: stats.dead_size
}

unless actual == expected
  puts "Comparison of results failed"
  puts "Expected:"
  p expected
  puts "Got:"
  p actual
  exit -1
end
