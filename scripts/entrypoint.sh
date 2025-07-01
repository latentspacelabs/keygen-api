#!/usr/bin/env bash
set -e

if [ -f tmp/pids/server.pid ]
then
  rm -f tmp/pids/server.pid
fi

case "$@"
in
setup)
  echo "Running command: bundle exec rails keygen:setup"
  exec bundle exec rails keygen:setup
  ;;
release)
  echo "Running command: bundle exec rails db:migrate"
  exec bundle exec rails db:migrate
  ;;
web)
  echo "Running command: bundle exec rails server -b $BIND -p $PORT"
  exec bundle exec rails server -b "$BIND" -p "$PORT"
  ;;
console)
  echo "Running command: bundle exec rails console"
  exec bundle exec rails console
  ;;
worker)
  echo "Running command: bundle exec sidekiq"
  exec bundle exec sidekiq
  ;;
all)
  echo "Running setup..."
  bundle exec rails keygen:setup
  
  echo "Starting worker and web processes..."
  # Start worker in background
  bundle exec sidekiq &
  WORKER_PID=$!
  
  # Start web server in foreground
  echo "Running command: bundle exec rails server -b $BIND -p $PORT"
  exec bundle exec rails server -b "$BIND" -p "$PORT"
  ;;
*)
  echo "Running command: $@"
  exec "$@"
  ;;
esac
