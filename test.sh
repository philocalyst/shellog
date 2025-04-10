#!/usr/bin/env bash

# Exit on errors, undefined variables, and propagate pipe failures
set -eo pipefail

# --- Configuration ---

# Set the DEBUG level (0=disabled, 1=debug messages, 2=trace commands)
export DEBUG=1 # Set to 1 or higher to see debug/trace logs from SHELLOG

# Configure SHELLOG settings (can be overridden by environment variables)
export SHELLOG_FILE=${SHELLOG_FILE:-1}
export SHELLOG_FILE_PATH=${SHELLOG_FILE_PATH:-"/tmp/bashansi_test.log"}
export SHELLOG_JSON=${SHELLOG_JSON:-1}
export SHELLOG_JSON_PATH=${SHELLOG_JSON_PATH:-"/tmp/bashansi_test.log.json"}
export SHELLOG_CONSOLE=${SHELLOG_CONSOLE:-1}
export SHELLOG_CONSOLE_LEVEL=${SHELLOG_CONSOLE_LEVEL:-"INFO"} # Log INFO and above to console
export SHELLOG_SYSLOG=${SHELLOG_SYSLOG:-0} # Disable syslog for this script
export SHELLOG_SYSLOG_TAG="bashansi_test"
# Increase rotation size if performance logs are large
export SHELLOG_ROTATION_SIZE=${SHELLOG_ROTATION_SIZE:-10485760} # 10MB

# --- Dependencies and Setup ---

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
LOG_SCRIPT="$SCRIPT_DIR/shellog"
ANSI_SCRIPT="$SCRIPT_DIR/bashansi/ansi" # Path to the ansi script itself
BASHANSI_DIR="$SCRIPT_DIR/bashansi"

# Check if log.sh exists
if [ ! -f "$LOG_SCRIPT" ]; then
    echo "FATAL: log.sh not found at $LOG_SCRIPT" >&2
    exit 1
fi

# Source the SHELLOG library AFTER setting configurations
. "$LOG_SCRIPT"

# --- Functions ---

# Check for required command-line tools
check_dependencies() {
    log_info "Checking for required tools..."
    local missing_deps=0
    local deps=("git" "wc" "stat" "shellcheck" "hyperfine" "jq" "find")

    # Check if jq is actually available, even if SHELLOG thinks it is
    if ! command -v jq >/dev/null 2>&1; then
         SHELLOG_HAS_JQ=0 # Update SHELLOG's internal flag if needed
         log_warn "jq command not found. JSON logs will use basic formatting."
    fi

    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            log_debug "Dependency check PASSED: $dep"
        else
            log_warn "Dependency check FAILED: $dep is not installed or not in PATH."
            missing_deps=$((missing_deps + 1))
        fi
    done

    # Check ansi script itself
     if [ ! -x "$ANSI_SCRIPT" ]; then
        log_error "ANSI script not found or not executable at $ANSI_SCRIPT"
        missing_deps=$((missing_deps + 1))
    fi


    if [ "$missing_deps" -gt 0 ]; then
        log_error "$missing_deps critical dependencies are missing. Cannot proceed reliably."
        # Decide whether to exit or continue with reduced functionality
        # exit 1 # Uncomment to make missing dependencies fatal
    else
         log_info "All required dependencies found."
    fi
    # Return non-zero if hyperfine is missing, as it's core to this script's extended goal
    if ! command -v hyperfine >/dev/null 2>&1; then
        log_warn "Hyperfine not found, skipping performance tests."
        return 1
    fi
    return 0
}

# Report statistics about files in the bashansi directory
report_file_stats() {
    log_info "Gathering file statistics for '$BASHANSI_DIR'..."
    local total_files=$(find "$BASHANSI_DIR" -type f | wc -l)
    local total_size=$(find "$BASHANSI_DIR" -type f -print0 | xargs -0 stat -f "%z %N" %s | awk '{s+=$1} END {print s}')
    local ansi_script_size=$(stat -f "%z %N" %s "$ANSI_SCRIPT" 2>/dev/null || echo "N/A")
    local ansi_script_lines=$(wc -l < "$ANSI_SCRIPT" 2>/dev/null || echo "N/A")
    local log_script_size=$(stat -f "%z %N" %s "$LOG_SCRIPT" 2>/dev/null || echo "N/A")
    local log_script_lines=$(wc -l < "$LOG_SCRIPT" 2>/dev/null || echo "N/A")

    log_notice "Codebase File Statistics" \
        "directory" "$BASHANSI_DIR" \
        "total_files" "$total_files" \
        "total_size_bytes" "$total_size" \
        "ansi_script_size_bytes" "$ansi_script_size" \
        "ansi_script_lines" "$ansi_script_lines" \
        "log_script_size_bytes" "$log_script_size" \
        "log_script_lines" "$log_script_lines"

     # Log details for each file
     find "$BASHANSI_DIR" -type f -print0 | while IFS= read -r -d $'\0' file; do
        local size=$(stat -f "%z %N" "$file")
        local lines=$(wc -l < "$file" | awk '{print $1}') # awk to remove leading space from wc
        local rel_path="${file#$SCRIPT_DIR/}"
        log_debug "File Details" "path" "$rel_path" "size_bytes" "$size" "lines" "$lines"
    done

}

# Report Git repository status
report_git_status() {
    log_info "Checking Git repository status..."
    if [ ! -d "$SCRIPT_DIR/.git" ]; then
        log_warn "Not a Git repository or .git directory not found at $SCRIPT_DIR"
        return
    fi

    if ! command -v git >/dev/null 2>&1; then
        log_warn "git command not found, cannot report Git status."
        return
    fi

    local commit_hash=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "N/A")
    local branch=$(git -C "$SCRIPT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
    # Check for uncommitted changes (porcelain returns output if changes exist)
    local changes=$(git -C "$SCRIPT_DIR" status --porcelain | wc -l)
    local status_msg

    if [ "$changes" -eq 0 ]; then
        status_msg="Clean"
        log_notice "Git Status" "branch" "$branch" "commit" "$commit_hash" "status" "$status_msg"
    else
        status_msg="Modified ($changes files)"
        log_warn "Git Status" "branch" "$branch" "commit" "$commit_hash" "status" "$status_msg"
        # Log specific changes at debug level
        local changed_files=$(git -C "$SCRIPT_DIR" status --porcelain)
        log_debug "Git changes detected:"$'\n'"$changed_files"
    fi
}

# Run shellcheck on relevant scripts
run_shellcheck() {
    log_info "Running ShellCheck..."
    if ! command -v shellcheck >/dev/null 2>&1; then
        log_warn "shellcheck command not found, skipping linting."
        return
    fi

    local files_to_check=()
    # Find shell scripts and the main ansi script (even if no .sh extension)
    while IFS= read -r -d $'\0' file; do
        # Heuristic: check files ending in .sh OR the main ansi/log scripts
        if [[ "$file" == *.sh ]] || [[ "$file" == "$ANSI_SCRIPT" ]] || [[ "$file" == "$LOG_SCRIPT" ]] || [[ "$file" == "$0" ]]; then
             # Basic check for shebang to avoid checking non-shell files without extension
             if head -n 1 "$file" | grep -q -E '^#!(/usr)?/bin/(env +)?(ba|da|z|k)?sh'; then
                files_to_check+=("$file")
             else
                 log_debug "Skipping shellcheck for '$file' (no shell shebang detected)."
             fi
        fi
    done < <(find "$SCRIPT_DIR" -type f \( -name '*.sh' -o -path "$ANSI_SCRIPT" -o -path "$LOG_SCRIPT" -o -path "$0" \) -print0)


    local total_issues=0
    for file in "${files_to_check[@]}"; do
         local rel_path="${file#$SCRIPT_DIR/}"
         log_debug "Running shellcheck on: $rel_path"
         # Capture output, check exit code separately
         local output
         output=$(shellcheck "$file" 2>&1)
         local exit_code=$?

        if [ "$exit_code" -eq 0 ]; then
            log_info "ShellCheck PASSED: $rel_path"
        else
            # shellcheck uses exit code 1 for issues found, 2+ for errors
            local issue_count=$(echo "$output" | wc -l) # Crude count
            total_issues=$((total_issues + issue_count))
            log_warn "ShellCheck FOUND ISSUES ($issue_count) in: $rel_path"
            # Log each line of the output as a separate debug message for clarity in JSON
            while IFS= read -r line; do
                log_debug "ShellCheck Output ($rel_path): $line"
            done <<< "$output"

            # Log the full output block as well for context in text logs
            log_debug "Full ShellCheck output for $rel_path:"$'\n'"$output"

            if [ "$exit_code" -gt 1 ]; then
                 log_error "ShellCheck encountered an error (code $exit_code) while checking $rel_path"
            fi
        fi
    done

    if [ "$total_issues" -eq 0 ]; then
        log_notice "ShellCheck Summary: All checked files passed."
    else
        log_warn "ShellCheck Summary: Found a total of $total_issues issues across checked files."
    fi
}

# Run performance tests using hyperfine
run_performance_tests() {
    log_info "Starting performance tests with hyperfine..."

    if ! check_dependencies ; then
       log_warn "Hyperfine dependency missing, cannot run performance tests."
       return # Exit this function specifically
    fi

    # Ensure the ansi script is executable
    chmod +x "$ANSI_SCRIPT" || { log_error "Failed to make $ANSI_SCRIPT executable"; return 1; }

    local hyperfine_output_file="/tmp/bashansi_hyperfine_results.txt"
    local hyperfine_json_output="/tmp/bashansi_hyperfine_results.json"
    local cmd_prefix="\"$ANSI_SCRIPT\"" # Quote path in case of spaces

    # Define commands to benchmark
    # Using full path to ansi script
    local benchmark_commands=(
        "--command-name 'simple_green'    '$cmd_prefix --green \"Test Output\"'"
        "--command-name 'bold_blue'       '$cmd_prefix --bold --blue \"Test Output\"'"
        "--command-name 'bg_color_code'   '$cmd_prefix --bg-color=196 --red \"Color Code\"'"
        "--command-name 'pos_and_text'    '$cmd_prefix --position=5,10 \"Positioned\"'"
        "--command-name 'multi_attr'      '$cmd_prefix --bold --italic --underline --yellow \"Complex Text\"'"
        "--command-name 'help_output'     '$cmd_prefix --help'"
        # Add more relevant commands if needed
        # Avoid reporting commands here as they interact with stdin/terminal
    )

    log_debug "Running hyperfine with commands: ${benchmark_commands[*]}"

    # Run hyperfine, capturing stdout (results) and exporting JSON
    # Redirect stderr to /dev/null to hide progress bars from main log
    # Use eval carefully here to handle the array of command strings correctly
    if eval hyperfine --warmup 2 --runs 5 \
        "${benchmark_commands[@]}" \
        --export-json "$hyperfine_json_output" \
        2>/dev/null > "$hyperfine_output_file"; then

        log_notice "Hyperfine performance tests completed successfully."
        log_info "Raw hyperfine results saved to: $hyperfine_output_file"
        log_info "JSON hyperfine results saved to: $hyperfine_json_output"

        # Log the summary output from the text file
        if [ -s "$hyperfine_output_file" ]; then
            log_debug "--- Hyperfine Summary Start ---"
            while IFS= read -r line; do
                # Log each line of the summary
                 log_info "Perf Summary: $line"
            done < "$hyperfine_output_file"
            log_debug "--- Hyperfine Summary End ---"
        fi

        # If jq is available, parse and log key metrics from JSON more nicely
        if [ "$SHELLOG_HAS_JQ" -eq 1 ] && [ -s "$hyperfine_json_output" ]; then
             log_debug "Parsing hyperfine JSON results..."
             jq -c '.results[] | {command: .command, mean: .mean, stddev: .stddev, median: .median, min: .min, max: .max, runs: .times | length}' "$hyperfine_json_output" | while IFS= read -r result_line; do
                # Log each result object as a structured log entry
                local cmd=$(echo "$result_line" | jq -r '.command')
                local mean=$(echo "$result_line" | jq -r '.mean')
                local median=$(echo "$result_line" | jq -r '.median')
                local min=$(echo "$result_line" | jq -r '.min')
                local max=$(echo "$result_line" | jq -r '.max')
                 log_notice "Performance Result" \
                     "command" "$cmd" \
                     "mean_s" "$mean" \
                     "median_s" "$median" \
                     "min_s" "$min" \
                     "max_s" "$max"
             done
         else
             log_info "jq not available or JSON file empty, skipping detailed JSON parsing for logs."
        fi

    else
        local exit_code=$?
        log_error "Hyperfine command failed with exit code $exit_code."
        if [ -s "$hyperfine_output_file" ]; then
            log_info "Partial hyperfine output:"$'\n'"$(cat "$hyperfine_output_file")"
        fi
         # Optionally try to read the JSON even on failure
         if [ -s "$hyperfine_json_output" ]; then
             log_info "Partial hyperfine JSON output:"$'\n'"$(cat "$hyperfine_json_output")"
         fi
    fi

    # Clean up temporary files (optional)
    # rm -f "$hyperfine_output_file" "$hyperfine_json_output"
}


# --- Main Execution ---

log_info "===== Starting BashANSI Test ====="
log_info "Logging to Console: $SHELLOG_CONSOLE (Level: $SHELLOG_CONSOLE_LEVEL)"
log_info "Logging to File: $SHELLOG_FILE (Path: $SHELLOG_FILE_PATH)"
log_info "Logging to JSON: $SHELLOG_JSON (Path: $SHELLOG_JSON_PATH)"
log_info "Logging to Syslog: $SHELLOG_SYSLOG"

# Run checks sequentially, logging progress
check_dependencies # Check basic dependencies first
report_file_stats
report_git_status
run_shellcheck

# Only run performance tests if hyperfine is available (checked in check_dependencies return)
if command -v hyperfine >/dev/null 2>&1; then
   run_performance_tests
else
   log_warn "Skipping performance tests because hyperfine is not installed."
fi


log_info "===== BashANSI Test Finished ====="
echo # Add a newline for cleaner separation in the terminal

# Display log locations at the end
echo "test execution complete."
echo "Log files potentially created/updated:"
[ "$SHELLOG_CONSOLE" -eq 1 ] && echo "  - Console output above (Level >= $SHELLOG_CONSOLE_LEVEL)"
[ "$SHELLOG_FILE" -eq 1 ] && [ -n "$SHELLOG_FILE_PATH" ] && echo "  - Text log: $SHELLOG_FILE_PATH"
[ "$SHELLOG_JSON" -eq 1 ] && [ -n "$SHELLOG_JSON_PATH" ] && echo "  - JSON log: $SHELLOG_JSON_PATH"
[ -f "/tmp/bashansi_hyperfine_results.txt" ] && echo "  - Hyperfine raw results: /tmp/bashansi_hyperfine_results.txt"
[ -f "/tmp/bashansi_hyperfine_results.json" ] && echo "  - Hyperfine JSON results: /tmp/bashansi_hyperfine_results.json"

exit 0
