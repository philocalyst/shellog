#!/usr/bin/env bash

# Set the DEBUG level (0=disabled, 1=debug messages, 2=trace commands)
export DEBUG=1

# Configure BashLog settings
export BASHLOG_FILE=1
export BASHLOG_FILE_PATH="/tmp/example-app.log"
export BASHLOG_JSON=1
export BASHLOG_JSON_PATH="/tmp/example-app.log.json"
export BASHLOG_CONSOLE=1
export BASHLOG_CONSOLE_LEVEL="DEBUG"
export BASHLOG_SYSLOG=0  # Disable syslog for this example

# Source the BashLog library
# Assuming the improved bashlog script is saved as bashlog.sh in the same directory
source "$(dirname "$0")/log.sh"
# Function to simulate a user login

# Function to process a file
process_file() {
    local filename="$1"
    local start_time=$(date +%s)
    
    log_debug "Starting to process file: $filename"
    
    # Simulate file processing
    sleep 1
    
    # Count lines in the file (or simulate if file doesn't exist)
    local line_count=0
    if [ -f "$filename" ]; then
        line_count=$(wc -l < "$filename")
    else
        line_count=$((RANDOM % 100 + 50))
        log_warn "File not found, using simulated data" \
            "filename" "$filename" \
            "simulated_line_count" "$line_count"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log_notice "File processing complete" \
        "filename" "$filename" \
        "line_count" "$line_count" \
        "duration_s" "$duration"
}

# Main application function
main() {
    log_info "=== Example Application Started ==="
    
    # Process some files
    local files=("data.csv" "users.json" "config.yaml" "/etc/hosts")
    
    for file in "${files[@]}"; do
        process_file "$file"
    done
    
    # Simulate user logins
    local users=("john.doe" "jane.smith" "admin" "guest")
    local ips=("192.168.1.100" "10.0.0.5" "172.16.254.1" "127.0.0.1")
    
    # Test error handling with structured data
    if [ $((RANDOM % 4)) -eq 0 ]; then
        log_error "Database connection failed" \
            "db_host" "db.example.com" \
            "db_port" "5432" \
            "retry_count" "3" \
            "error_code" "ECONNREFUSED"
    fi
    
    # Test different log levels
    log_debug "This is a debug message with detailed information"
    log_info "This is an informational message"
    log_notice "This is a notice that should be looked at"
    log_warn "This is a warning that something might be wrong"
    log_error "This is an error that needs attention"
    log_crit "This is a critical error that needs immediate attention"
    log_alert "This is an alert that requires action"
    log_emerg "This is an emergency situation"
    
    # Demonstrate JSON value escaping
    log_info "Testing JSON escaping" \
        "quoted_text" "This has \"quotes\" inside" \
        "path" "/usr/local/bin:/usr/bin:/bin" \
        "json_example" "{\"key\": \"value\", \"nested\": {\"array\": [1, 2, 3]}}" \
        "multiline" "Line 1
Line 2
Line 3"
    
    log_info "=== Example Application Finished ==="
}

# Run the main function
main

# Display log locations
echo ""
echo "Log files created:"
echo "Text log: $BASHLOG_FILE_PATH"
echo "JSON log: $BASHLOG_JSON_PATH"

# Show sample of JSON logs if jq is available
if command -v jq >/dev/null 2>&1; then
    echo ""
    echo "Sample JSON log entries (first 2):"
    head -n 2 "$BASHLOG_JSON_PATH" | jq '.'
fi
