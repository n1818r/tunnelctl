#!/bin/bash

# --- Default Settings ---
REMOTE_HOST="localhost"
DEFAULT_SSH_USER="noor"
DEFAULT_SSH_HOST="noor.com"

SCRIPT_PATH="$(realpath "$0")"

# Services and their default remote ports
SERVICE_NAMES=("postgres" "mongodb" "redis","elasticsearch")
SERVICE_PORTS=(5432 27017 6379 9200)
LOCAL_PORTS=()

BACKGROUND=true
PEM_PATH=""
SHOW=false
KILL=false
CONFIGURE=""
CONFIGURE_SHOW=false
SELECTED_SERVICES=()

# Utility: get index of service
get_service_index() {
  local name="$1"
  for i in "${!SERVICE_NAMES[@]}"; do
    if [[ "${SERVICE_NAMES[i]}" == "$name" ]]; then
      echo "$i"
      return 0
    fi
  done
  echo "-1"
}

print_usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --service <name>       Select service (postgres, mongodb, redis)
  --custom <name> <port> Add custom service with remote port
  --port <name> <port>   Override default local port
  --key <path>           Path to SSH private key (.pem)
  --bg                   Run SSH tunnels in background (default: enabled)
  --show [all|<name>]    Show active tunnels
  --kill [all|<name>]    Kill active tunnels
  --configure user=xxx,host=yyy   Set SSH user and host (modifies this script)
  --configure show       Show current SSH config
  --help                 Show this help message
EOF
}

show_active_tunnels() {
  local filter_services=("$@")
  local found_any=false

  echo "🔍 Active SSH tunnels (listening on localhost ports):"
  for i in "${!SERVICE_NAMES[@]}"; do
    local service="${SERVICE_NAMES[i]}"
    if [[ ${#filter_services[@]} -gt 0 ]]; then
      if [[ ! " ${filter_services[*]} " =~ " $service " ]] && [[ ! " ${filter_services[*]} " =~ " all " ]]; then
        continue
      fi
    fi

    local local_port="${LOCAL_PORTS[i]:-${SERVICE_PORTS[i]}}"
    local pids
    pids=$(lsof -t -iTCP:"$local_port" -sTCP:LISTEN)

    if [ -n "$pids" ]; then
      found_any=true
      echo "  - $service : localhost:$local_port (PIDs: $pids)"
    fi
  done

  if ! $found_any; then
    echo "  None"
  fi
}

kill_tunnels() {
  local filter_services=("$@")
  echo "🛑 Killing SSH tunnels on local ports..."

  local found_any=false

  for i in "${!SERVICE_NAMES[@]}"; do
    local service="${SERVICE_NAMES[i]}"
    if [[ ${#filter_services[@]} -gt 0 ]]; then
      if [[ ! " ${filter_services[*]} " =~ " $service " ]] && [[ ! " ${filter_services[*]} " =~ " all " ]]; then
        continue
      fi
    fi

    local local_port="${LOCAL_PORTS[i]:-${SERVICE_PORTS[i]}}"
    local pids
    pids=$(lsof -t -iTCP:"$local_port" -sTCP:LISTEN)

    if [ -n "$pids" ]; then
      found_any=true
      for pid in $pids; do
        local cmdline
        cmdline=$(ps -p "$pid" -o comm=)
        if [[ "$cmdline" == *ssh* ]]; then
          kill "$pid"
          sleep 0.5
          if kill -0 "$pid" 2>/dev/null; then
            echo "❌ Failed to kill tunnel for $service on port $local_port (PID $pid)"
          else
            echo "✅ Killed tunnel for $service on port $local_port (PID $pid)"
          fi
        else
          echo "⚠️ Skipping non-SSH process on port $local_port (PID $pid)"
        fi
      done
    fi
  done

  if ! $found_any; then
    echo "No tunnels found to kill."
  fi
}

start_tunnel() {
  local service="$1"
  local remote_port="$2"
  local local_port="$3"

  if [ -z "$local_port" ]; then
    local_port="$remote_port"
  fi

  if lsof -iTCP:"$local_port" -sTCP:LISTEN -t >/dev/null; then
    echo "✅ Tunnel already running for $service at localhost:$local_port"
    return
  fi

  echo "🔄 Starting tunnel: $service → $REMOTE_HOST:$remote_port on localhost:$local_port"
  ssh -i "$PEM_PATH" -L "$local_port:$REMOTE_HOST:$remote_port" "$DEFAULT_SSH_USER@$DEFAULT_SSH_HOST" -N ${BACKGROUND:+-f} \
    && echo "✅ Tunnel started for $service"
}

update_script_config() {
  local new_user="$1"
  local new_host="$2"
  local tmp_file="${SCRIPT_PATH}.tmp"

  awk -v user="$new_user" -v host="$new_host" '
    BEGIN { updated_user=0; updated_host=0; }
    {
      if ($0 ~ /^DEFAULT_SSH_USER=/ && user != "") {
        print "DEFAULT_SSH_USER=\"" user "\""
        updated_user = 1
      } else if ($0 ~ /^DEFAULT_SSH_HOST=/ && host != "") {
        print "DEFAULT_SSH_HOST=\"" host "\""
        updated_host = 1
      } else {
        print $0
      }
    }
    END {
      if (!updated_user && user != "") print "DEFAULT_SSH_USER=\"" user "\""
      if (!updated_host && host != "") print "DEFAULT_SSH_HOST=\"" host "\""
    }
  ' "$SCRIPT_PATH" > "$tmp_file"

  mv "$tmp_file" "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"
  echo "✅ Updated SSH configuration:"
  echo "  SSH User: $new_user"
  echo "  SSH Host: $new_host"
}

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)
      SELECTED_SERVICES+=("$2")
      shift 2
      ;;
    --custom)
      SERVICE_NAMES+=("$2")
      SERVICE_PORTS+=("$3")
      shift 3
      ;;
    --port)
      idx=$(get_service_index "$2")
      if [[ "$idx" -ge 0 ]]; then
        LOCAL_PORTS[$idx]="$3"
      else
        echo "❌ Unknown service: $2"
        exit 1
      fi
      shift 3
      ;;
    --key)
      PEM_PATH="$2"
      shift 2
      ;;
    --bg)
      BACKGROUND=true
      shift
      ;;
    --show)
      SHOW=true
      if [[ "$2" =~ ^(all|postgres|mongodb|redis)$ ]]; then
        SHOW_FILTER=("$2")
        shift 2
      else
        shift
      fi
      ;;
    --kill)
      KILL=true
      if [[ "$2" =~ ^(all|postgres|mongodb|redis)$ ]]; then
        KILL_FILTER=("$2")
        shift 2
      else
        shift
      fi
      ;;
    --configure)
      if [[ "$2" == "show" ]]; then
        CONFIGURE_SHOW=true
      else
        CONFIGURE="$2"
      fi
      shift 2
      ;;
    --help)
      print_usage
      exit 0
      ;;
    *)
      echo "❌ Unknown argument: $1"
      print_usage
      exit 1
      ;;
  esac
done

# --- Configure logic ---
if [ "$CONFIGURE_SHOW" = true ]; then
  echo "🔧 Current SSH Configuration:"
  echo "  SSH User: $DEFAULT_SSH_USER"
  echo "  SSH Host: $DEFAULT_SSH_HOST"
  exit 0
fi

if [ -n "$CONFIGURE" ]; then
  user=$(echo "$CONFIGURE" | sed -n 's/.*user=\([^,]*\).*/\1/p')
  host=$(echo "$CONFIGURE" | sed -n 's/.*host=\([^,]*\).*/\1/p')
  if [ -z "$user" ] && [ -z "$host" ]; then
    echo "❌ Invalid configure format. Use: --configure user=...,host=..."
    exit 1
  fi
  update_script_config "$user" "$host"
  exit 0
fi

# --- Show / Kill ---
if $SHOW; then
  show_active_tunnels "${SHOW_FILTER[@]}"
  exit 0
fi

if $KILL; then
  kill_tunnels "${KILL_FILTER[@]}"
  exit 0
fi

# --- Start ---
if [ -z "$PEM_PATH" ] || [ "${#SELECTED_SERVICES[@]}" -eq 0 ]; then
  echo "❌ Missing required arguments: --service and --key are mandatory."
  print_usage
  exit 1
fi

for service in "${SELECTED_SERVICES[@]}"; do
  idx=$(get_service_index "$service")
  if [[ "$idx" -lt 0 ]]; then
    echo "❌ Unknown service: $service"
    exit 1
  fi
  remote_port="${SERVICE_PORTS[idx]}"
  local_port="${LOCAL_PORTS[idx]}"
  start_tunnel "$service" "$remote_port" "$local_port"
done

