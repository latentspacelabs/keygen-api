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

# Function to kill existing worker processes
kill_existing_workers() {
  echo "Checking for existing worker processes..."
  
  # Find Sidekiq processes
  WORKER_PIDS=$(pgrep -f "sidekiq" || true)
  
  if [ -n "$WORKER_PIDS" ]; then
    echo "Found existing worker processes: $WORKER_PIDS"
    echo "Killing existing worker processes..."
    echo "$WORKER_PIDS" | xargs kill -TERM
    
    # Wait a moment for graceful shutdown
    sleep 2
    
    # Force kill if still running
    REMAINING_PIDS=$(pgrep -f "sidekiq" || true)
    if [ -n "$REMAINING_PIDS" ]; then
      echo "Force killing remaining worker processes: $REMAINING_PIDS"
      echo "$REMAINING_PIDS" | xargs kill -KILL
    fi
    
    echo "Worker processes killed"
  else
    echo "No existing worker processes found"
  fi
}

# Function to kill existing web processes
kill_existing_web() {
  echo "Checking for existing web processes..."
  
  # Check for Rails server PID file
  if [ -f tmp/pids/server.pid ]; then
    SERVER_PID=$(cat tmp/pids/server.pid)
    if kill -0 "$SERVER_PID" 2>/dev/null; then
      echo "Found existing Rails server process: $SERVER_PID"
      echo "Killing existing Rails server process..."
      kill -TERM "$SERVER_PID"
      
      # Wait a moment for graceful shutdown
      sleep 2
      
      # Force kill if still running
      if kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Force killing Rails server process: $SERVER_PID"
        kill -KILL "$SERVER_PID"
      fi
      
      echo "Rails server process killed"
    fi
  fi
  
  # Also check for any Rails server processes by name
  RAILS_PIDS=$(pgrep -f "rails server" || true)
  
  if [ -n "$RAILS_PIDS" ]; then
    echo "Found additional Rails server processes: $RAILS_PIDS"
    echo "Killing additional Rails server processes..."
    echo "$RAILS_PIDS" | xargs kill -TERM
    
    # Wait a moment for graceful shutdown
    sleep 2
    
    # Force kill if still running
    REMAINING_PIDS=$(pgrep -f "rails server" || true)
    if [ -n "$REMAINING_PIDS" ]; then
      echo "Force killing remaining Rails server processes: $REMAINING_PIDS"
      echo "$REMAINING_PIDS" | xargs kill -KILL
    fi
    
    echo "Additional Rails server processes killed"
  fi
  
  # Clean up PID file
  rm -f tmp/pids/server.pid
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
  echo "Checking for existing web processes..."
  kill_existing_web
  
  echo "Running command: bundle exec rails server -b $BIND -p $PORT"
  exec bundle exec rails server -b "$BIND" -p "$PORT"
  ;;
console)
  echo "Running command: bundle exec rails console"
  exec bundle exec rails console
  ;;
worker)
  echo "Checking for existing worker processes..."
  kill_existing_workers
  
  echo "Running command: bundle exec sidekiq"
  exec bundle exec sidekiq
  ;;
all)
  echo "Starting Keygen with setup check..."
  
  # Run setup safely (will skip if already done)
  run_setup_safely
  
  echo "Checking for existing processes..."
  kill_existing_workers
  kill_existing_web
  
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
