#!/bin/bash
# This is a test script to debug the summary display

# Initialize error counter
ERROR_COUNT=0

# Arrays to track test results
declare -A TEST_RESULTS
declare -a TEST_NAMES

# Function to record test result
record_test_result() {
    local test_name="$1"
    local result="$2"  # 0 for success, non-zero for failure
    
    TEST_NAMES+=("$test_name")
    if [ "$result" -eq 0 ]; then
        TEST_RESULTS["$test_name"]="PASS"
    else
        TEST_RESULTS["$test_name"]="FAIL"
    fi
}

# Add some fake test results
record_test_result "CUDA" 0
record_test_result "NCCL" 1
record_test_result "MPI" 0
record_test_result "Docker" 0
record_test_result "OFED" 1

# Add a skipped test
TEST_NAMES+=("GDRCopy")
TEST_RESULTS["GDRCopy"]="SKIP"

# Create a summary of validation results
echo -e "\n=== Validation Summary ==="

# Print a formatted summary table with Unicode symbols
echo "┌───────────────────────────────────────────────────────────────────────┐"
echo "│ Test Results Summary                                                  │"
echo "├───────────────────────────────────────────────────────────────────────┤"
echo "│ ✓ = Pass | ✗ = Fail | ⚠ = Skipped                                     │"
echo "├───────────────────────────────────────────────────────────────────────┤"

for test_name in "${TEST_NAMES[@]}"; do
    result="${TEST_RESULTS[$test_name]}"
    echo "Processing test: $test_name with result: $result"
    if [ "$result" == "PASS" ]; then
        printf "│ \033[32m✓\033[0m %-69s │\n" "$test_name"
    elif [ "$result" == "SKIP" ]; then
        printf "│ \033[33m⚠\033[0m %-69s │\n" "$test_name"
    else
        printf "│ \033[31m✗\033[0m %-69s │\n" "$test_name"
    fi
done

echo "└───────────────────────────────────────────────────────────────────────┘"
