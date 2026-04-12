# Backup Script Improvement Plan

## Current Issues
1. **Code Duplication**: The backup logic is repeated twice (for `homer` and `youtubedl-material`)
2. **No Error Handling**: No validation that source/destination directories exist
3. **No Exit Code Checking**: rsync exit codes are not checked to verify successful completion

## Proposed Improvements

### 1. Create a Reusable Backup Function
- **What**: Extract the backup logic into a function called `backup_pvc()`
- **Why**: Eliminates code repetition and makes it easy to add more backup targets
- **How**: Function will accept parameters:
  - `pvc_dir_middle` - The PVC directory UUID prefix
  - `app` - Application name
  - `pvc_dir_suffix` - The PVC directory suffix
  - Function constructs paths and performs backup

### 2. Add Source Directory Validation
- **What**: Check if `source_dir` exists before attempting rsync
- **Why**: Provides clear error messages instead of failing silently or with cryptic rsync errors
- **How**: Use `if [ ! -d "$source_dir" ]; then` to check existence
- **Action**: Exit with error code if directory doesn't exist

### 3. Add Destination Directory Validation
- **What**: Ensure `destination_dir` exists or can be created
- **Why**: Prevents rsync failures due to missing parent directories
- **How**: Use `mkdir -p` to create destination directory if it doesn't exist

### 4. Check rsync Exit Codes
- **What**: Capture and check rsync's exit status (`$?`)
- **Why**: Detect and report backup failures immediately
- **How**: Check exit code after rsync completes; exit with error if rsync failed

## Implementation Steps
1. Add error handling utility functions (optional, for cleaner code)
2. Create the `backup_pvc()` function with all error handling
3. Replace both backup blocks with function calls
4. Add set -e or explicit exit handling for script robustness

## Final Implementation - Using Associative Array and Loop
- **What**: Define apps in an associative array where app name is the key
- **Why**: Eliminates repetitive if statements and makes adding new apps trivial
- **How**: 
  - Create `declare -A apps_to_backup` associative array
  - Store format: `[app_name]="pvc_dir_middle:pvc_dir_suffix"`
  - Loop through array keys with `for app in "${!apps_to_backup[@]}"`
  - Parse the combined value using IFS (internal field separator)
  - Call `backup_pvc()` for each app in the loop
- **Benefits**:
  - Easy to add new apps: just add one line to the array
  - No duplicate if statements
  - Scalable and maintainable
  - Clear configuration at the top of the script
