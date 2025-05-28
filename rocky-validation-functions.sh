#!/bin/bash
# Rocky Linux validation helper functions

# check if the file is present
function check_exists {
    ls $1
    if [ $? -eq 0 ]
    then
        echo "$1 [OK]"
        return 0
    else
        echo "*** Error - $1 not found!" >&2
        ERROR_COUNT=$((ERROR_COUNT+1))
        return 1
    fi
}

# check exit code
function check_exit_code {
    exit_code=$?
    if [ $exit_code -eq 0 ]
    then
        echo "[OK] : $1"
        return 0
    else
        echo "*** Error - $2!" >&2
        echo "*** Failed with exit code - $exit_code" >&2
        ERROR_COUNT=$((ERROR_COUNT+1))
        return 1
    fi
}

# Function to perform a test with error handling
function run_test_with_error_handling {
    local test_name="$1"
    local test_function="$2"
    
    echo "Checking $test_name..."
    if ! $test_function; then
        echo "$test_name verification failed"
        ERROR_COUNT=$((ERROR_COUNT+1))
        record_test_result "$test_name" 1
        return 1
    fi
    record_test_result "$test_name" 0
    return 0
}

# Handle module dependency and record skip status
function handle_module_dependency {
    local module_name="$1"
    local test_name="$2"
    
    if ! module avail $module_name &>/dev/null; then
        echo "Required module $module_name for $test_name not found."
        TEST_NAMES+=("$test_name")
        TEST_RESULTS["$test_name"]="SKIP"
        return 1
    fi
    return 0
}
