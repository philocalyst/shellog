# Changelog

All notable changes to this project will be documented in this file.  
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] – 2025-04-23

### Added
• MIT license file  
• README.md with project overview, features, usage examples, dependencies and installation instructions  
• `shellog` library script (renamed from `log.sh`) providing:  
  – basic and structured logging functions (`log`, `log_<level>`, `log_<level>_data`)  
  – JSON output (with or without `jq`) via `_create_json_entry`  
  – automatic log rotation, directory creation, and colored console output (via `bashansi`)  
• `test.sh`: comprehensive test suite with:  
  – `check_dependencies`, `report_file_stats`, `report_git_status`, `run_shellcheck`, `run_performance_tests`  
  – structured logging of dependency checks, file statistics, Git status, lint results, and performance benchmarks  

### Changed
• Renamed project and APIs from **BashLog** to **ShelLog** (`shellog`, `SHELLOG_*` variables)  
• Switched shebangs back to `#!/usr/bin/env bash`  
• Changed import style to dot-sourcing (`. bashansi/ansi`)  
• Updated `bashansi` submodule to commit `48db3506775eb11f231ea09a95d7276b93867f0a`  
• Refactored `shellog`:  
  – introduced helper functions `_get_severity`, `_get_color`, `_ensure_log_dir`  
  – unified JSON handling in `_create_json_entry`  
  – enhanced console filtering and JSON-to-STDOUT support  
  – removed legacy `BASHLOG_FILE` toggle option  
• Adjusted test script (`test.sh`) to use the new `log_*` interface  
• Updated README code block language markers from `bash` to `diff` where appropriate  
• Clarified initialization log message  

### Removed
• Build-status badge and shield from README  
• Redundant `BASHLOG_FILE` option in `shellog`  
• Dead code and obsolete conditionals in `shellog`  

### Fixed
• Corrected license author attribution in `LICENSE`  
• Fixed variable-naming typos (`BASHLOG` → `SHELLOG`) throughout scripts  
• Improved exception-message formatting in logging internals  

---

[Unreleased]: https://github.com/YOUR_USERNAME/shellog/compare/v0.1.0...HEAD  
[0.1.0]:       https://github.com/YOUR_USERNAME/shellog/compare/...v0.1.0
