#!/usr/bin/env bash
set -e

if [ -f tmp/pids/server.pid ]
then
  rm -f tmp/pids/server.pid
fi

# Function to check if setup has already been run
check_setup_complete() {
  echo "Checking if setup is needed..."
  
  # Check if database is accessible
  if ! bundle exec rails runner "exit 0" 2>/dev/null; then
    echo "Database not accessible, will run setup..."
    return 1
  fi
  
  # Check if any accounts exist
  if bundle exec rails runner "exit Account.count > 0 ? 0 : 1" 2>/dev/null; then
    echo "Setup already completed - accounts exist"
    return 0
  else
    echo "No accounts found, setup needed"
    return 1
  fi
}

# Function to run setup safely
run_setup_safely() {
  if check_setup_complete; then
    echo "Setup already completed, skipping..."
    return 0
  fi
  
  echo "Running setup..."
  
  # Set NO_SECRETS to run setup non-interactively
  export NO_SECRETS=1
  export DISABLE_DATABASE_ENVIRONMENT_CHECK=1
  
  # Run setup with error handling
  if bundle exec rails keygen:setup; then
    echo "Setup completed successfully"
    return 0
  else
    echo "Setup failed, but continuing..."
    return 1
  fi
}

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
  echo "Starting Keygen with setup check..."
  
  # Run setup safely (will skip if already done)
  run_setup_safely
  
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
