#!/bin/bash

# Test runner for deploy scripts
# Finds and executes all test-001_* scripts in the tests/deploy directory
# Usage: ./test-deploy.sh [environment] [region]
#   environment: dev, qa, or prod (optional, defaults to dev)
#   region: AWS region (optional, defaults to us-west-2)

set -eu

# Get current directory (tests/deploy/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse command line arguments
TEST_ENV="${1:-dev}"
TEST_REGION="${2:-us-west-2}"

# Test results tracking
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
FAILED_TEST_NAMES=()

#------------------------------------------------------------------------------
# Utility functions
#------------------------------------------------------------------------------
print_header() {
    echo
    echo "=================================================================="
    echo "                    DEPLOY TESTS RUNNER"
    echo "=================================================================="
    echo "Directory: $SCRIPT_DIR"
    echo "Project Root: $PROJECT_ROOT"
    echo "Environment: $TEST_ENV"
    echo "Region: $TEST_REGION"
    echo
}

print_test_separator() {
    echo
    echo "------------------------------------------------------------------"
    echo
}

print_summary() {
    echo
    echo "=================================================================="
    echo "                    TEST SUMMARY"
    echo "=================================================================="
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    if [ $FAILED_TESTS -gt 0 ]; then
        echo
        echo "Failed Tests:"
        for test_name in "${FAILED_TEST_NAMES[@]}"; do
            echo "  ❌ $test_name"
        done
        echo
        echo "❌ Some tests failed!"
        exit 1
    else
        echo
        echo "🎉 All tests passed!"
        exit 0
    fi
}

run_test_script() {
    local test_script="$1"
    local test_name
    test_name=$(basename "$test_script")
    
    echo "🔄 Running: $test_name"
    echo "   Script: $test_script"
    echo "   Environment: $TEST_ENV"
    echo "   Region: $TEST_REGION"
    
    # Run the test script with environment and region parameters
    if "$test_script" "$TEST_ENV" "$TEST_REGION"; then
        echo "✅ PASSED: $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ FAILED: $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_TEST_NAMES+=("$test_name")
    fi
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

#------------------------------------------------------------------------------
# Main execution
#------------------------------------------------------------------------------
main() {
    print_header
    
    # Find all test-001_* scripts in the current directory
    local test_scripts=()
    while IFS= read -r -d '' script; do
        test_scripts+=("$script")
    done < <(find "$SCRIPT_DIR" -name "test-001_*.sh" -type f -executable -print0 | sort -z)
    
    if [ ${#test_scripts[@]} -eq 0 ]; then
        echo "⚠️  No test-001_*.sh scripts found in $SCRIPT_DIR"
        echo "   Make sure test scripts exist and are executable"
        exit 1
    fi
    
    echo "Found ${#test_scripts[@]} test script(s):"
    for script in "${test_scripts[@]}"; do
        echo "  - $(basename "$script")"
    done
    
    print_test_separator
    
    # Execute each test script
    for script in "${test_scripts[@]}"; do
        run_test_script "$script"
        print_test_separator
    done
    
    print_summary
}

# Check if script is being run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi