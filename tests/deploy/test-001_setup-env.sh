#!/bin/bash

# Test script for deploy-001_setup-env.sh
# Validates that the script creates proper config files and terraform.tfvars.json files

set -eu

# Get project root directory (two levels up from tests/deploy/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test configuration
TEST_ENV="dev"
TEST_REGION="us-west-2"
EXPECTED_CONFIG_FILE="$PROJECT_ROOT/config.$TEST_ENV.yml"
TERRAFORM_ENVS_DIR="$PROJECT_ROOT/terraform/envs"
COMMON_LIB_FILE="$PROJECT_ROOT/common-lib.sh"
DEPLOY_SCRIPT="$PROJECT_ROOT/deploy-001_setup-env.sh"

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
    echo "Testing deploy-001_setup-env.sh"
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
        ((TESTS_PASSED++))
    else
        echo "❌ FAIL: $test_name"
        if [ -n "$details" ]; then
            echo "   Details: $details"
        fi
        ((TESTS_FAILED++))
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
# Test functions
#------------------------------------------------------------------------------
test_config_file_created() {
    local test_name="Config file created"
    
    if [ -f "$EXPECTED_CONFIG_FILE" ]; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "File $EXPECTED_CONFIG_FILE does not exist"
    fi
}

test_config_file_no_variables() {
    local test_name="Config file has no unresolved variables"
    
    if [ ! -f "$EXPECTED_CONFIG_FILE" ]; then
        print_test_result "$test_name" "FAIL" "Config file does not exist"
        return
    fi
    
    # Check for any remaining $ variables (should be resolved)
    local unresolved_vars
    unresolved_vars=$(grep -c '\$[A-Z_][A-Z0-9_]*' "$EXPECTED_CONFIG_FILE" || true)
    
    if [ "$unresolved_vars" -eq 0 ]; then
        print_test_result "$test_name" "PASS"
    else
        local vars_found
        vars_found=$(grep '\$[A-Z_][A-Z0-9_]*' "$EXPECTED_CONFIG_FILE" || true)
        print_test_result "$test_name" "FAIL" "Found $unresolved_vars unresolved variables: $vars_found"
    fi
}

test_config_file_content() {
    local test_name="Config file contains expected values"
    
    if [ ! -f "$EXPECTED_CONFIG_FILE" ]; then
        print_test_result "$test_name" "FAIL" "Config file does not exist"
        return
    fi
    
    # Check for expected environment and region values
    local has_env
    local has_region
    has_env=$(grep -c "abk_deployment_env: $TEST_ENV" "$EXPECTED_CONFIG_FILE" || true)
    has_region=$(grep -c "abk_deployment_region: $TEST_REGION" "$EXPECTED_CONFIG_FILE" || true)
    
    if [ "$has_env" -gt 0 ] && [ "$has_region" -gt 0 ]; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "Missing expected env ($has_env) or region ($has_region) values"
    fi
}

test_terraform_vars_files_created() {
    local test_name="Terraform tfvars files created"
    local missing_files=()
    local found_files=0
    
    # Check common directory
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        while IFS= read -r -d '' project_dir; do
            local tfvars_file="$project_dir/terraform.tfvars.json"
            if [ -f "$tfvars_file" ]; then
                ((found_files++))
            else
                missing_files+=("$tfvars_file")
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/common" -print0)
    fi
    
    # Check environment-specific directory
    if [ -d "$TERRAFORM_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r -d '' project_dir; do
            local tfvars_file="$project_dir/terraform.tfvars.json"
            if [ -f "$tfvars_file" ]; then
                ((found_files++))
            else
                missing_files+=("$tfvars_file")
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" -print0)
    fi
    
    if [ ${#missing_files[@]} -eq 0 ] && [ $found_files -gt 0 ]; then
        print_test_result "$test_name" "PASS" "Found $found_files terraform.tfvars.json files"
    else
        local details="Found $found_files files"
        if [ ${#missing_files[@]} -gt 0 ]; then
            details="$details, Missing: ${missing_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
}

test_terraform_vars_valid_json() {
    local test_name="Terraform tfvars files contain valid JSON"
    local invalid_files=()
    local valid_files=0
    
    # Find all terraform.tfvars.json files
    while IFS= read -r -d '' tfvars_file; do
        if jq empty "$tfvars_file" 2>/dev/null; then
            ((valid_files++))
        else
            invalid_files+=("$tfvars_file")
        fi
    done < <(find "$TERRAFORM_ENVS_DIR" -name "terraform.tfvars.json" -type f -print0 2>/dev/null || true)
    
    if [ ${#invalid_files[@]} -eq 0 ] && [ $valid_files -gt 0 ]; then
        print_test_result "$test_name" "PASS" "All $valid_files tfvars files contain valid JSON"
    else
        local details="Valid: $valid_files"
        if [ ${#invalid_files[@]} -gt 0 ]; then
            details="$details, Invalid JSON: ${invalid_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
}

test_terraform_vars_content() {
    local test_name="Terraform tfvars files contain expected content"
    local files_with_content=0
    local empty_files=()
    
    # Find all terraform.tfvars.json files and check content
    while IFS= read -r -d '' tfvars_file; do
        if [ -s "$tfvars_file" ]; then
            # Check if file contains expected environment values
            if grep -q "\"$TEST_ENV\"" "$tfvars_file" 2>/dev/null; then
                ((files_with_content++))
            else
                empty_files+=("$tfvars_file (no env values)")
            fi
        else
            empty_files+=("$tfvars_file (empty)")
        fi
    done < <(find "$TERRAFORM_ENVS_DIR" -name "terraform.tfvars.json" -type f -print0 2>/dev/null || true)
    
    if [ ${#empty_files[@]} -eq 0 ] && [ $files_with_content -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$files_with_content files contain expected content"
    else
        local details="Files with content: $files_with_content"
        if [ ${#empty_files[@]} -gt 0 ]; then
            details="$details, Issues: ${empty_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
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
    
    # Set required environment variables for the script
    export ABK_DEPLOYMENT_ENV="$TEST_ENV"
    export ABK_PRJ_NAME="test-project"
    export LOG_LEVEL="debug"
    export AWS_ACCESS_KEY_ID="test-key"
    export AWS_SECRET_ACCESS_KEY="test-secret"
    
    echo "Running deploy-001_setup-env.sh..."
    # Change to project root to run the script
    if (cd "$PROJECT_ROOT" && ./deploy-001_setup-env.sh "$TEST_ENV" "$TEST_REGION"); then
        echo "✅ deploy-001_setup-env.sh completed successfully"
    else
        echo "❌ deploy-001_setup-env.sh failed to execute"
        exit 1
    fi
    
    echo
    echo "Running tests..."
    
    # Run all tests
    test_config_file_created
    test_config_file_no_variables
    test_config_file_content
    test_terraform_vars_files_created
    test_terraform_vars_valid_json
    test_terraform_vars_content
    
    print_test_summary
}

# Run tests
main "$@"