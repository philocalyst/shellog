#!/usr/bin/env dash

# BashLog: A lightweight logging library for dash/bash scripts
# Usage: source this file, then use log <level> <message> [data_key data_value ...]
# Example: log info "Starting process" 
#          log info "User logged in" username "john.doe" ip "192.168.1.1"

# Exit on errors, undefined variables, and propagate pipe failures
set -eo pipefail

source bashansi/ansi

# Configuration with defaults (can be overridden before sourcing)
: "${BASHLOG_DATE_FORMAT:=+%F %T}"
: "${BASHLOG_FILE:=0}"
: "${BASHLOG_FILE_PATH:=/tmp/$(basename "$0").log}"
: "${BASHLOG_JSON:=0}"
: "${BASHLOG_JSON_PATH:=/tmp/$(basename "$0").log.json}"
: "${BASHLOG_SYSLOG:=0}"
: "${BASHLOG_SYSLOG_TAG:=$(basename "$0")}"
: "${BASHLOG_SYSLOG_FACILITY:=local0}"
: "${BASHLOG_CONSOLE:=1}"      
: "${BASHLOG_CONSOLE_LEVEL:=INFO}" # Minimum level for console output
: "${BASHLOG_ROTATION_SIZE:=5242880}" # 5MB log rotation
: "${DEBUG:=0}"

# Check for jq availability
if command -v jq >/dev/null 2>&1; then
  BASHLOG_HAS_JQ=1
else
  BASHLOG_HAS_JQ=0
  [ "$BASHLOG_JSON" -eq 1 ] && echo "Warning: jq not found, falling back to basic JSON formatting" >&2
fi

# Internal function to handle exceptions within the logging system
_log_exception() {
  (
    BASHLOG_FILE=0
    BASHLOG_JSON=0
    BASHLOG_SYSLOG=0
    BASHLOG_CONSOLE=1
    
    ansi --bold --red "%s [ERROR] Logging Exception: %s\n" "$(date "$BASHLOG_DATE_FORMAT")" "$*" >&2
  )
}

# Check if the log needs to be rotated
_rotate_log() {
  local log_file="$1"
  
  if [ -f "$log_file" ] && [ "$(stat -c %s "$log_file" 2>/dev/null || stat -f %z "$log_file")" -gt "$BASHLOG_ROTATION_SIZE" ]; then
    local backup="${log_file}.$(date +%Y%m%d%H%M%S)"
    mv "$log_file" "$backup" || _log_exception "Failed to rotate log file"
    log info "Rotated log file to $backup"
  fi
}

# Function to create JSON log entry with jq
_create_json_entry() {
  local timestamp="$1"
  local level="$2"
  local message="$3"
  local timestamp_s="$4"
  local pid="$5"
  
  if [ "$BASHLOG_HAS_JQ" -eq 1 ]; then
    # Using jq to properly escape and format the JSON
    jq -n \
      --arg ts "$timestamp" \
      --arg ts_s "$timestamp_s" \
      --arg lvl "$level" \
      --arg msg "$message" \
      --arg pid "$pid" \
      --arg app "$(basename "$0")" \
      '{
        timestamp: $ts,
        timestamp_epoch: $ts_s|tonumber,
        level: $lvl,
        message: $msg,
        pid: $pid|tonumber,
        application: $app
      }'
  else
    # Fallback for systems without jq - basic escaping
    local json_msg="$(echo "$message" | sed 's/"/\\"/g')"
    printf '{"timestamp":"%s","timestamp_epoch":%s,"level":"%s","message":"%s","pid":%s,"application":"%s"}' \
      "$timestamp" "$timestamp_s" "$level" "$json_msg" "$pid" "$(basename "$0")"
  fi
}

# Function to add structured data to log
log_with_data() {
  local level="$1"
  local message="$2"
  shift 2
  
  # Check if additional data is provided
  if [ "$#" -eq 0 ]; then
    log "$level" "$message"
    return
  fi
  
  # Process normal logging without JSON data
  local date_format="$BASHLOG_DATE_FORMAT"
  local date="$(date "$date_format")"
  local date_s="$(date "+%s")"
  local pid="$$"
  local upper="$(echo "$level" | tr '[:lower:]' '[:upper:]')"
  
  # Define severity levels (RFC 5424)
  local severity
  case "$upper" in
    "DEBUG")   severity=7 ;;
    "INFO")    severity=6 ;;
    "NOTICE")  severity=5 ;;
    "WARN")    severity=4 ;;
    "ERROR")   severity=3 ;;
    "CRIT")    severity=2 ;;
    "ALERT")   severity=1 ;;
    "EMERG")   severity=0 ;;
    *)         
      _log_exception "Invalid log level: $upper"
      severity=3
      upper="ERROR"
      ;;
  esac
  
  # Handle regular logging to console/file/syslog
  if [ "$BASHLOG_CONSOLE" -eq 1 ] || [ "$BASHLOG_FILE" -eq 1 ] || [ "$BASHLOG_SYSLOG" -eq 1 ]; then
    log "$level" "$message"
  fi
  
  # Special JSON handling for structured data
  if [ "$BASHLOG_JSON" -eq 1 ]; then
    # Rotate log if needed
    _rotate_log "$BASHLOG_JSON_PATH"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$BASHLOG_JSON_PATH")" 2>/dev/null || true
    
    # Create JSON with structured data
    if [ "$BASHLOG_HAS_JQ" -eq 1 ]; then
      # Build data arguments for jq
      local jq_args=(
        --arg ts "$date"
        --arg ts_s "$date_s"
        --arg lvl "$upper"
        --arg msg "$message"
        --arg pid "$pid"
        --arg app "$(basename "$0")"
      )
      
      # Build the JSON data object
      local data_json="{"
      local first=1
      
      while [ "$#" -gt 0 ]; do
        if [ "$first" -eq 0 ]; then
          data_json="${data_json},"
        fi
        
        local key="$1"
        local value="$2"
        shift 2 || break
        
        # Add to jq args
        jq_args+=(--arg "k_$key" "$key" --arg "v_$key" "$value")
        
        # Add to data JSON
        data_json="${data_json}\$k_$key: \$v_$key"
        first=0
      done
      
      data_json="${data_json}}"
      
      # Create full JSON entry with jq
      jq -n "${jq_args[@]}" \
        "{
          timestamp: \$ts,
          timestamp_epoch: \$ts_s|tonumber,
          level: \$lvl,
          message: \$msg,
          pid: \$pid|tonumber,
          application: \$app,
          data: $data_json
        }" >> "$BASHLOG_JSON_PATH" || _log_exception "Failed to write to JSON log file: $BASHLOG_JSON_PATH"
    else
      # Fallback without jq - basic structured data
      local json_msg="$(echo "$message" | sed 's/"/\\"/g')"
      local data_json='"data":{'
      local first=1
      
      while [ "$#" -gt 0 ]; do
        if [ "$first" -eq 0 ]; then
          data_json="${data_json},"
        fi
        
        local key="$1"
        local value="$2"
        shift 2 || break
        
        # Escape the value
        local esc_value="$(echo "$value" | sed 's/"/\\"/g')"
        
        # Add to data JSON
        data_json="${data_json}\"$key\":\"$esc_value\""
        first=0
      done
      
      data_json="${data_json}}"
      
      printf '{"timestamp":"%s","timestamp_epoch":%s,"level":"%s","message":"%s","pid":%s,"application":"%s",%s}\n' \
        "$date" "$date_s" "$upper" "$json_msg" "$pid" "$(basename "$0")" "$data_json" \
        >> "$BASHLOG_JSON_PATH" || _log_exception "Failed to write to JSON log file: $BASHLOG_JSON_PATH"
    fi
  fi
}

# Main logging function
log() {
  local date_format="$BASHLOG_DATE_FORMAT"
  local date="$(date "$date_format")"
  local date_s="$(date "+%s")"
  local pid="$$"

  # Validate log level argument
  if [ "$#" -lt 2 ]; then
    _log_exception "Usage: log <level> <message>"
    return 1
  fi

  local level="$1"
  local upper="$(echo "$level" | tr '[:lower:]' '[:upper:]')"
  local debug_level="$DEBUG"

  shift 1
  local line="$*"

  # Define severity levels (RFC 5424)
  local severity
  case "$upper" in
    "DEBUG")   severity=7 ;;
    "INFO")    severity=6 ;;
    "NOTICE")  severity=5 ;;
    "WARN")    severity=4 ;;
    "ERROR")   severity=3 ;;
    "CRIT")    severity=2 ;;
    "ALERT")   severity=1 ;;
    "EMERG")   severity=0 ;;
    *)         
      _log_exception "Invalid log level: $upper"
      severity=3
      upper="ERROR"
      ;;
  esac

  # Log if debug is enabled or if severity is appropriate
  if [ "$debug_level" -gt 0 ] || [ "$severity" -lt 7 ]; then
    # Syslog output
    if [ "$BASHLOG_SYSLOG" -eq 1 ]; then
      logger \
        --id="$pid" \
        -t "$BASHLOG_SYSLOG_TAG" \
        -p "$BASHLOG_SYSLOG_FACILITY.$severity" \
        "$upper: $line" \
        || _log_exception "Failed to write to syslog"
    fi

    # File output
    if [ "$BASHLOG_FILE" -eq 1 ]; then
      # Rotate log if needed
      _rotate_log "$BASHLOG_FILE_PATH"
      
      # Ensure log directory exists
      mkdir -p "$(dirname "$BASHLOG_FILE_PATH")" 2>/dev/null || true
      
      printf "%s [%s] %s\n" "$date" "$upper" "$line" >> "$BASHLOG_FILE_PATH" \
        || _log_exception "Failed to write to log file: $BASHLOG_FILE_PATH"
    fi

    # JSON output
    if [ "$BASHLOG_JSON" -eq 1 ]; then
      # Rotate log if needed
      _rotate_log "$BASHLOG_JSON_PATH"
      
      # Ensure log directory exists
      mkdir -p "$(dirname "$BASHLOG_JSON_PATH")" 2>/dev/null || true
      
      # Create JSON entry using jq or fallback method
      _create_json_entry "$date" "$upper" "$line" "$date_s" "$pid" >> "$BASHLOG_JSON_PATH" \
        || _log_exception "Failed to write to JSON log file: $BASHLOG_JSON_PATH"
    fi
  fi

  # Console output with colors
  if [ "$BASHLOG_CONSOLE" -eq 1 ]; then
    # Check if console level threshold is met
    local console_level_num
    case "$(echo "$BASHLOG_CONSOLE_LEVEL" | tr '[:lower:]' '[:upper:]')" in
      "DEBUG")   console_level_num=7 ;;
      "INFO")    console_level_num=6 ;;
      "NOTICE")  console_level_num=5 ;;
      "WARN")    console_level_num=4 ;;
      "ERROR")   console_level_num=3 ;;
      "CRIT")    console_level_num=2 ;;
      "ALERT")   console_level_num=1 ;;
      "EMERG")   console_level_num=0 ;;
      *)         console_level_num=6 ;; # Default to INFO
    esac
    
    if [ "$severity" -le "$console_level_num" ] || [ "$debug_level" -gt 0 -a "$upper" = "DEBUG" ]; then
      local color
      case "$upper" in
        "DEBUG")   color='blue' ;; # Blue
        "INFO")    color='green' ;; # Green
        "NOTICE")  color='cyan' ;; # Cyan
        "WARN")    color='yellow' ;; # Yellow
        "ERROR")   color='red' ;; # Red
        "CRIT")    color='white' ;; # Bold Red
        "ALERT")   color='magenta' ;; # Bold Magenta
        "EMERG")   color='black' ;; # White on Red background
        *)         color='black' ;; # Default
      esac
      
      local std_line="${date} [${upper}] ${line}"
      
      # Output to the appropriate file descriptor
      if [ "$upper" = "ERROR" ] || [ "$upper" = "CRIT" ] || [ "$upper" = "ALERT" ] || [ "$upper" = "EMERG" ]; then
        ansi --${color} --bold "$std_line" >&2
      else
        ansi --${color} --bold "$std_line"
      fi
      
      # Debug shell for errors if DEBUG > 0
      if [ "$upper" = "ERROR" ] && [ "$debug_level" -gt 0 ]; then
        printf "Here's a shell to debug with. 'exit 0' to continue. Other exit codes will abort - parent shell will terminate.\n"
        (bash || exit "$?") || exit "$?"
      fi
    fi
  fi
}

# Log functions for each level
log_debug() { log debug "$@"; }
log_info() { log info "$@"; }
log_notice() { log notice "$@"; }
log_warn() { log warn "$@"; }
log_error() { log error "$@"; }
log_crit() { log crit "$@"; }
log_alert() { log alert "$@"; }
log_emerg() { log emerg "$@"; }

# Log functions with data for each level
log_debug_data() { log_with_data debug "$@"; }
log_info_data() { log_with_data info "$@"; }
log_notice_data() { log_with_data notice "$@"; }
log_warn_data() { log_with_data warn "$@"; }
log_error_data() { log_with_data error "$@"; }
log_crit_data() { log_with_data crit "$@"; }
log_alert_data() { log_with_data alert "$@"; }
log_emerg_data() { log_with_data emerg "$@"; }

# Function to set all log destinations
set_log_destinations() {
  local console="${1:-1}"
  local file="${2:-0}"
  local json="${3:-0}"
  local syslog="${4:-0}"
  
  BASHLOG_CONSOLE="$console"
  BASHLOG_FILE="$file"
  BASHLOG_JSON="$json"
  BASHLOG_SYSLOG="$syslog"
}

# Command tracing via trap 
if [ "$DEBUG" -gt 0 ]; then
  declare prev_cmd="null"
  declare this_cmd="null"
  trap 'prev_cmd=$this_cmd; this_cmd=$BASH_COMMAND' DEBUG \
    && log debug 'DEBUG trap set' \
    || log error 'DEBUG trap failed to set'

  # Enable command tracing if DEBUG > 1
  if [ "$DEBUG" -gt 1 ]; then
    trap 'prev_cmd=$this_cmd; this_cmd=$BASH_COMMAND; log_debug "EXEC: $this_cmd"' DEBUG
  fi
fi

# Log library initialization
log_info "BashLog initialized with jq support: $BASHLOG_HAS_JQ (PID: $$)"
