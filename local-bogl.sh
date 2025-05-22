#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BOGL_PATH="$(realpath "$SCRIPT_DIR/../bogl")"
BOGL_EDITOR_PATH="$(realpath "$SCRIPT_DIR/../bogl-editor")"
COMPOSE_PROJECT_NAME="bogl"
FRONTEND_URL="http://localhost"

# Verify paths exist
if [ ! -d "$BOGL_PATH" ]; then
  echo "Error: Backend directory not found at $BOGL_PATH"
  exit 1
fi

if [ ! -d "$BOGL_EDITOR_PATH" ]; then
  echo "Error: Frontend directory not found at $BOGL_EDITOR_PATH"
  exit 1
fi

show_usage() {
  echo "Usage: $0 [start|stop]"
  echo "  start  - Build images, start services, and open browser"
  echo "  stop   - Stop services and clean up"
  exit 1
}

check_docker() {
  if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running or not accessible"
    exit 1
  fi
}

check_docker_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    echo "Error: Docker Compose is not available"
    echo "Please install Docker Compose or use a newer version of Docker that includes it"
    exit 1
  fi
}

build_images() {
  CURRENT_DIR="$(pwd)"
  
  echo "Building bogl backend image..."
  cd "$BOGL_PATH" || { echo "Error: Cannot access $BOGL_PATH"; exit 1; }
  docker build -t bogl .
  
  echo "Building bogl-editor frontend image..."
  cd "$BOGL_EDITOR_PATH" || { echo "Error: Cannot access $BOGL_EDITOR_PATH"; exit 1; }
  docker build -t bogl-editor .
  
  cd "$CURRENT_DIR"
}

start_services() {
  echo "Starting services with Docker Compose..."
  cd "$SCRIPT_DIR"
  docker compose --project-name "$COMPOSE_PROJECT_NAME" up -d
}

wait_for_services() {
  echo "Waiting for services to be ready..."
  
  check_service() {
    local service_name="$1"
    local max_wait=60  # Maximum wait time in seconds
    local waited=0
    
    echo -n "Waiting for ${service_name} service..."
    
    while [ $waited -lt $max_wait ]; do
      # Check if container is running and healthy
      if docker compose --project-name "$COMPOSE_PROJECT_NAME" ps --services --filter "status=running" | grep -q "^${service_name}$"; then
        echo " Ready!"
        return 0
      fi
      
      echo -n "."
      sleep 1
      waited=$((waited + 1))
    done
    
    echo " Timed out waiting for ${service_name} service!"
    echo "Current service status:"
    docker compose --project-name "$COMPOSE_PROJECT_NAME" ps
    return 1
  }
  
  check_service "bogl" || { echo "Failed to start bogl service"; exit 1; }
  check_service "bogl-editor" || { echo "Failed to start bogl-editor service"; exit 1; }
  
  # Give services a moment to fully initialize
  sleep 3
  echo "All services are running!"
}

open_browser() {
  echo "Opening browser at $FRONTEND_URL..."
  
  # Try to detect the platform and open browser accordingly
  case "$(uname -s)" in
    Darwin)
      open "$FRONTEND_URL"
      ;;
    Linux)
      if command -v xdg-open >/dev/null; then
        xdg-open "$FRONTEND_URL"
      elif command -v gnome-open >/dev/null; then
        gnome-open "$FRONTEND_URL"
      else
        echo "Cannot detect how to open the browser on this system."
        echo "Please open $FRONTEND_URL manually in your browser."
      fi
      ;;
    CYGWIN*|MINGW*|MSYS*)
      start "$FRONTEND_URL"
      ;;
    *)
      echo "Unknown operating system. Please open $FRONTEND_URL manually in your browser."
      ;;
  esac
}

stop_services() {
  echo "Stopping services..."
  cd "$SCRIPT_DIR"
  docker compose --project-name "$COMPOSE_PROJECT_NAME" down
  
  echo "Services stopped successfully!"
}

show_status() {
  echo "Current service status:"
  cd "$SCRIPT_DIR"
  docker compose --project-name "$COMPOSE_PROJECT_NAME" ps
}

if [ $# -ne 1 ]; then
  show_usage
fi

check_docker
check_docker_compose

case "$1" in
  start)
    echo "Starting bogl environment..."
    build_images
    start_services
    wait_for_services
    show_status
    open_browser
    
    echo "All done! Your bogl environment is up and running."
    echo "Frontend is available at: $FRONTEND_URL"
    echo ""
    echo "To view logs: docker compose --project-name $COMPOSE_PROJECT_NAME logs -f"
    echo "To stop: $0 stop"
    ;;
    
  stop)
    echo "Stopping bogl environment..."
    stop_services
    echo "Environment stopped successfully!"
    ;;
    
  *)
    show_usage
    ;;
esac

exit 0