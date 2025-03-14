#!/bin/bash

# Run arbitrary ruby scripts in Mastodon's rails environment
rails_runner() {
  docker compose run -T --rm web bundle exec rails runner - < "$1"
}

check_failure() {
  exit_code=$?
  if [ "$exit_code" -ne 0 ] ; then
    echo "$1"
    exit "$exit_code"
  fi
}

# Clean up
cleanup() {
  docker compose down --remove-orphans --volumes
  rm .env.production
}

# Make sure cleanup runs no matter where the script exits
trap cleanup EXIT

# Start with a config that _uses_ namespaces
cp .env.namespace .env.production

# Start postgresql and redis
docker compose up -d db redis

# Setup the database - this will fail if it already exists
# but that is fine
docker compose run --rm web bundle exec rails db:setup

# Enqueue a couple of jobs for sidekiq
rails_runner enqueue_initial_jobs.rb

# Put a value in the app redis and in the rails cache
rails_runner fill_cache_and_app_redis.rb

# Run sidekiq so it processes the jobs that are queued
# Allow it some time to finish and then stop the process.
docker compose run -d --rm web bundle exec sidekiq
sleep 10
docker compose kill -s TERM web

# Enqueue some additional jobs to get more variety of
# job states.
rails_runner enqueue_additional_jobs.rb

# Test that sidekiq stats match the expected numbers of jobs
rails_runner check_sidekiq_stats.rb
check_failure "Jobs stats do not match before key migration"

# Check that app redis key and cache value are still available.
rails_runner check_cache_and_app_redis.rb
check_failure "Checking cache and/or app keys before key migration failed"

# Migrate keys by removing the namespace
rails_runner remove_ns.rb

# Use a config _without_ namespaces
cp .env.no_namespace .env.production

# Test that sidekiq stats still match the expected numbers of jobs
rails_runner check_sidekiq_stats.rb
check_failure "Jobs stats do not match after key migration"

# Check that app redis key and cache value are still available.
rails_runner check_cache_and_app_redis.rb
check_failure "Checking cache and/or app keys after key migration failed"
