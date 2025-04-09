
# ShelLog: A Lightweight Logging Library for Bash Scripts

ShelLog provides a flexible, feature-rich, and dependency free logging solution for your Bash scripts. As long as you have a shell interpreter, it works. It allows you to easily log messages to various destinations like the console, files, JSON files, and syslog, with support for different log levels, structured data, automatic log rotation, and colored console output.

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/YOUR_USERNAME/shellog)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT) ## Features

* **Multiple Log Levels:** Supports standard syslog levels (DEBUG, INFO, NOTICE, WARN, ERROR, CRIT, ALERT, EMERG).
* **Multiple Output Destinations:**
    * **Console:** Colored output to stdout/stderr (configurable level threshold).
    * **File:** Plain text log file with automatic rotation based on size.
    * **JSON:** Structured JSON log file (enhanced with `jq` if available).
    * **Syslog:** Native logging via the `logger` command.
* **Structured Data:** Append key-value pairs to your log messages, which are included in JSON output.
* **Configurable:** Easily configure behavior via environment variables (paths, formats, levels, rotation size, etc.).
* **Log Rotation:** Automatically rotates plain text and JSON log files when they exceed a configured size.
* **Colorized Console Output:** Uses ANSI escape codes via the `bashansi` library for readable, colored console logs.
* **Debug Mode:** Built-in debugging support (`DEBUG` variable) for command tracing and interactive debugging on errors.
* **Dependency Aware:** Checks for `jq` availability for enhanced JSON formatting.
* **Error Handling:** Internal error handling for logging failures.

## Dependencies

* **Bash:** Version 4+ recommended.
* **`bashansi` library:** Bundled.
* **`jq` (Optional):** Recommended for properly formatted and escaped JSON output. ShelLog will fall back to basic string manipulation if `jq` is not found.
* **`logger`:** Required for syslog output. Usually available by default on Linux systems.
* **Standard Unix Utilities:** `date`, `stat`, `dirname`, `mkdir`, `mv`, `tr`, `sed`, `basename`.

## Installation

1.  **Obtain `shellog` and `bashansi`:**
    * Download or clone this directory.

2.  **Integrate into your script:**
    Source the `shellog` file at the beginning of your script *after* setting any custom configuration variables.

    ```bash
    #!/usr/bin/env bash

    # Optional: Override ShelLog configuration variables HERE
    # Example: Log only warnings and above to console
    + export SHELLOG_CONSOLE_LEVEL="WARN"
    + export SHELLOG_FILE_PATH="/var/log/my_app/my_script.log"
    + export SHELLOG_JSON=1 # Enable JSON logging
    + export SHELLOG_SYSLOG=1 # Enable Syslog logging

    # Source the ShelLog library
    + source /path/to/shellog
    # Or if shellog is in the same directory:
    # source "$(dirname "$0")/shellog"

    # Your script logic starts here...
    + log_info "Script started."
    # ... rest of your script
    ```

## Usage

### Basic Logging

The primary way to log is using the `log` function or the level-specific helper functions.

```bash
# Using the main log function
log <level> <message>

# Using helper functions
log_debug "Detailed information for developers."
log_info "Informational message about progress."
log_notice "Normal but significant condition."
log_warn "Warning conditions."
log_error "Error conditions."
log_crit "Critical conditions."
log_alert "Action must be taken immediately."
log_emerg "System is unusable."
```
