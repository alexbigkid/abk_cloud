#!/bin/bash

# Test script for remove-001_setup-env.sh
# Validates that the script properly removes config files and terraform.tfvars.json files

set -eu

# Get project root directory (two levels up from tests/remove/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test configuration
TEST_ENV="${1:-dev}"
TEST_REGION="${2:-us-west-2}"
CONFIG_FILE="$PROJECT_ROOT/config.$TEST_ENV.yml"
TERRAFORM_ENVS_DIR="$PROJECT_ROOT/terraform/envs"
COMMON_LIB_FILE="$PROJECT_ROOT/common-lib.sh"
DEPLOY_SCRIPT="$PROJECT_ROOT/deploy-001_setup-env.sh"
REMOVE_SCRIPT="$PROJECT_ROOT/remove-001_setup-env.sh"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

#------------------------------------------------------------------------------
# Test utility functions
#------------------------------------------------------------------------------
print_test_header() {
    echo
    echo "=========================================="
    echo "Testing remove-001_setup-env.sh"
    echo "Environment: $TEST_ENV"
    echo "Region: $TEST_REGION"
    echo "=========================================="
    echo
}

print_test_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"

    if [ "$result" = "PASS" ]; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        if [ -n "$details" ]; then
            echo "   Details: $details"
        fi
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
}

print_test_summary() {
    echo
    echo "=========================================="
    echo "TEST SUMMARY"
    echo "=========================================="
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"

    if [ $TESTS_FAILED -gt 0 ]; then
        echo
        echo "Failed Tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo
        exit 1
    else
        echo
        echo "🎉 All tests passed!"
        echo
        exit 0
    fi
}

#------------------------------------------------------------------------------
# Setup functions
#------------------------------------------------------------------------------
setup_test_files() {
    echo "-> ${FUNCNAME[0]}"

    # Set required environment variables for the scripts (only if not already set)
    export ABK_DEPLOYMENT_ENV="$TEST_ENV"
    export ABK_PRJ_NAME="${ABK_PRJ_NAME:-test-project}"
    export LOG_LEVEL="${LOG_LEVEL:-debug}"
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test-key}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test-secret}"

    # First run deploy script to create files
    echo "Running deploy script to create test files..."
    if (cd "$PROJECT_ROOT" && ./deploy-001_setup-env.sh "$TEST_ENV" "$TEST_REGION"); then
        echo "✅ Deploy script completed successfully"
    else
        echo "❌ Deploy script failed - cannot proceed with remove tests"
        exit 1
    fi
    echo "<- ${FUNCNAME[0]}"
}

collect_files_before_remove() {
    echo "-> ${FUNCNAME[0]}"

    # Collect config files
    if [ -f "$CONFIG_FILE" ]; then
        echo "Found config file: $CONFIG_FILE"
    fi

    # Collect terraform.tfvars.json files
    TFVARS_FILES_BEFORE=()
    while IFS= read -r -d '' tfvars_file; do
        TFVARS_FILES_BEFORE+=("$tfvars_file")
    done < <(find "$TERRAFORM_ENVS_DIR" -name "terraform.tfvars.json" -type f -print0 2>/dev/null || true)

    echo "Found ${#TFVARS_FILES_BEFORE[@]} terraform.tfvars.json files before removal"
    echo "<- ${FUNCNAME[0]}"
}

#------------------------------------------------------------------------------
# Test functions
#------------------------------------------------------------------------------
test_config_file_removed() {
    echo "-> ${FUNCNAME[0]}"
    local test_name="Config file removed"

    if [ ! -f "$CONFIG_FILE" ]; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "Config file still exists: $CONFIG_FILE"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_vars_files_removed() {
    echo "-> ${FUNCNAME[0]}"
    local test_name="Terraform tfvars files removed"
    local remaining_files=()

    # Check if terraform envs directory exists
    if [ ! -d "$TERRAFORM_ENVS_DIR" ]; then
        print_test_result "$test_name" "PASS" "Terraform envs directory does not exist"
        return
    fi

    # Check if any terraform.tfvars.json files remain
    while IFS= read -r -d '' tfvars_file; do
        remaining_files+=("$tfvars_file")
    done < <(find "$TERRAFORM_ENVS_DIR" -name "terraform.tfvars.json" -type f -print0 2>/dev/null || true)

    if [ ${#remaining_files[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "All terraform.tfvars.json files removed"
    else
        local details="Remaining files: ${remaining_files[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_specific_files_removed() {
    echo "-> ${FUNCNAME[0]}"
    local test_name="Specific expected files removed"
    local missing_removals=()

    # Check that specific files from the deploy phase were removed
    for file in "${TFVARS_FILES_BEFORE[@]}"; do
        if [ -f "$file" ]; then
            missing_removals+=("$file")
        fi
    done

    if [ ${#missing_removals[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "All expected files were removed"
    else
        local details="Files not removed: ${missing_removals[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_remove_script_success() {
    echo "-> ${FUNCNAME[0]}"
    local test_name="Remove script execution successful"

    echo "Running remove-001_setup-env.sh..."
    if (cd "$PROJECT_ROOT" && ./remove-001_setup-env.sh "$TEST_ENV" "$TEST_REGION"); then
        print_test_result "$test_name" "PASS"
        echo "<- ${FUNCNAME[0]} (0)"
        return 0
    else
        print_test_result "$test_name" "FAIL" "Remove script failed to execute"
        echo "<- ${FUNCNAME[0]} (1)"
        return 1
    fi
}

test_cleanup_idempotent() {
    local test_name="Remove script idempotent (safe to run multiple times)"
    echo "-> ${FUNCNAME[0]}"

    echo "Running remove script second time to test idempotency..."
    if (cd "$PROJECT_ROOT" && ./remove-001_setup-env.sh "$TEST_ENV" "$TEST_REGION"); then
        print_test_result "$test_name" "PASS" "Remove script runs safely when files already removed"
    else
        print_test_result "$test_name" "FAIL" "Remove script failed on second run"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_template_files_preserved() {
    local test_name="Template files preserved"
    local missing_templates=()
    echo "-> ${FUNCNAME[0]}"

    # Check that important template files are not removed
    local template_files=(
        "$PROJECT_ROOT/config.yml"
        "$PROJECT_ROOT/common-lib.sh"
        "$PROJECT_ROOT/deploy-001_setup-env.sh"
        "$PROJECT_ROOT/remove-001_setup-env.sh"
    )

    for file in "${template_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_templates+=("$file")
        fi
    done

    if [ ${#missing_templates[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "All template files preserved"
    else
        local details="Missing template files: ${missing_templates[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

#------------------------------------------------------------------------------
# Main test execution
#------------------------------------------------------------------------------
main() {
    print_test_header

    # Verify prerequisites
    if [ ! -f "$COMMON_LIB_FILE" ]; then
        echo "❌ ERROR: $COMMON_LIB_FILE not found at $COMMON_LIB_FILE"
        exit 1
    fi

    if [ ! -f "$DEPLOY_SCRIPT" ]; then
        echo "❌ ERROR: deploy-001_setup-env.sh not found at $DEPLOY_SCRIPT"
        exit 1
    fi

    if [ ! -f "$REMOVE_SCRIPT" ]; then
        echo "❌ ERROR: remove-001_setup-env.sh not found at $REMOVE_SCRIPT"
        exit 1
    fi

    # Setup: Create files to be removed
    setup_test_files
    collect_files_before_remove

    echo
    echo "Running tests..."

    # Test the remove script execution
    if ! test_remove_script_success; then
        echo "❌ Remove script failed - cannot continue with removal tests"
        exit 1
    fi

    # Test that files were properly removed
    test_config_file_removed || echo "❌ test_config_file_removed"
    test_terraform_vars_files_removed || echo "❌ test_terraform_vars_files_removed"
    test_specific_files_removed || echo "❌ test_specific_files_removed"
    test_template_files_preserved || echo "❌ test_template_files_preserved"

    # Test idempotency
    test_cleanup_idempotent || echo "❌ test_cleanup_idempotent"

    print_test_summary
}

# Run tests
main "$@"
