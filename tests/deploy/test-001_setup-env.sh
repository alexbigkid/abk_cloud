#!/bin/bash

# Test script for deploy-001_setup-env.sh
# Validates that the script creates proper config files and terraform.tfvars.json files

set -eu

# Get project root directory (two levels up from tests/deploy/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test configuration
TEST_ENV="${1:-dev}"
TEST_REGION="${2:-us-west-2}"
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
        echo "❌ FAILED TESTS:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo
        echo "❌ TEST SUITE FAILED"
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
    echo "-> ${FUNCNAME[0]}"

    if [ -f "$EXPECTED_CONFIG_FILE" ]; then
        print_test_result "$test_name" "PASS"
    else
        print_test_result "$test_name" "FAIL" "File $EXPECTED_CONFIG_FILE does not exist"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_config_file_no_variables() {
    local test_name="Config file has no unresolved variables"
    echo "-> ${FUNCNAME[0]}"

    if [ ! -f "$EXPECTED_CONFIG_FILE" ]; then
        print_test_result "$test_name" "FAIL" "Config file does not exist"
        return
    fi

    # Check for any remaining $ variables (should be resolved)
    local unresolved_vars=0
    if grep -q '\$[A-Z_][A-Z0-9_]*' "$EXPECTED_CONFIG_FILE" 2>/dev/null; then
        unresolved_vars=$(grep -c '\$[A-Z_][A-Z0-9_]*' "$EXPECTED_CONFIG_FILE" 2>/dev/null || echo "0")
    fi

    if [ "$unresolved_vars" -eq 0 ]; then
        print_test_result "$test_name" "PASS"
    else
        local vars_found
        vars_found=$(grep '\$[A-Z_][A-Z0-9_]*' "$EXPECTED_CONFIG_FILE" 2>/dev/null || echo "none")
        print_test_result "$test_name" "FAIL" "Found $unresolved_vars unresolved variables: $vars_found"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_config_file_content() {
    local test_name="Config file contains expected values"
    echo "-> ${FUNCNAME[0]}"

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
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_vars_files_created() {
    local test_name="Terraform tfvars files created"
    local missing_files=()
    local found_files=0
    local expected_projects=0
    echo "-> ${FUNCNAME[0]}"

    # Check common directory
    echo "  Checking common directory: $TERRAFORM_ENVS_DIR/common"
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        echo "  Common directory exists"
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            echo "  Processing project: $project_dir"
            expected_projects=$((expected_projects + 1))
            local tfvars_file="$project_dir/terraform.tfvars.json"
            if [ -f "$tfvars_file" ]; then
                echo "  Found tfvars: $tfvars_file"
                found_files=$((found_files + 1))
            else
                echo "  Missing tfvars: $tfvars_file"
                missing_files+=("$tfvars_file")
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/common")
    else
        echo "  Common directory does not exist"
    fi

    # Check environment-specific directory (only if it contains projects)
    if [ -d "$TERRAFORM_ENVS_DIR/$TEST_ENV" ]; then
        local env_projects
        env_projects=$(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" | wc -l)
        if [ "$env_projects" -gt 0 ]; then
            while IFS= read -r project_dir; do
                [ -z "$project_dir" ] && continue
                expected_projects=$((expected_projects + 1))
                local tfvars_file="$project_dir/terraform.tfvars.json"
                if [ -f "$tfvars_file" ]; then
                    found_files=$((found_files + 1))
                else
                    missing_files+=("$tfvars_file")
                fi
            done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV")
        fi
    fi

    echo "  Summary: expected=$expected_projects, found=$found_files, missing=${#missing_files[@]}"

    if [ ${#missing_files[@]} -eq 0 ] && [ $found_files -gt 0 ]; then
        print_test_result "$test_name" "PASS" "Found $found_files terraform.tfvars.json files"
    elif [ $expected_projects -eq 0 ]; then
        print_test_result "$test_name" "FAIL" "No terraform projects found in common or $TEST_ENV directories"
    else
        local details="Found $found_files files, expected $expected_projects"
        if [ ${#missing_files[@]} -gt 0 ]; then
            details="$details, Missing: ${missing_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_vars_valid_json() {
    local test_name="Terraform tfvars files contain valid JSON"
    local invalid_files=()
    local valid_files=0
    echo "-> ${FUNCNAME[0]}"

    # Find all terraform.tfvars.json files
    while IFS= read -r tfvars_file; do
        [ -z "$tfvars_file" ] && continue
        if jq empty "$tfvars_file" 2>/dev/null; then
            valid_files=$((valid_files + 1))
        else
            invalid_files+=("$tfvars_file")
        fi
    done < <(find "$TERRAFORM_ENVS_DIR" -name "terraform.tfvars.json" -type f 2>/dev/null || true)

    if [ ${#invalid_files[@]} -eq 0 ] && [ $valid_files -gt 0 ]; then
        print_test_result "$test_name" "PASS" "All $valid_files tfvars files contain valid JSON"
    else
        local details="Valid: $valid_files"
        if [ ${#invalid_files[@]} -gt 0 ]; then
            details="$details, Invalid JSON: ${invalid_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_vars_content() {
    local test_name="Terraform tfvars files contain expected content"
    local files_with_content=0
    local empty_files=()
    echo "-> ${FUNCNAME[0]}"

    # Find all terraform.tfvars.json files and check content
    while IFS= read -r tfvars_file; do
        [ -z "$tfvars_file" ] && continue
        if [ -s "$tfvars_file" ]; then
            # Check if file contains expected environment values
            if grep -q "\"$TEST_ENV\"" "$tfvars_file" 2>/dev/null; then
                files_with_content=$((files_with_content + 1))
            else
                empty_files+=("$tfvars_file (no env values)")
            fi
        else
            empty_files+=("$tfvars_file (empty)")
        fi
    done < <(find "$TERRAFORM_ENVS_DIR" -name "terraform.tfvars.json" -type f 2>/dev/null || true)

    if [ ${#empty_files[@]} -eq 0 ] && [ $files_with_content -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$files_with_content files contain expected content"
    else
        local details="Files with content: $files_with_content"
        if [ ${#empty_files[@]} -gt 0 ]; then
            details="$details, Issues: ${empty_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_backend_files_created() {
    local test_name="Terraform backend.tf files created"
    local missing_files=()
    local found_files=0
    local expected_projects=0
    echo "-> ${FUNCNAME[0]}"

    # Check common directory
    echo "  Checking common directory: $TERRAFORM_ENVS_DIR/common"
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        echo "  Common directory exists"
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            echo "  Processing project: $project_dir"
            
            # Skip terraformStateBootstrap (should NOT have backend.tf)
            if [[ "$project_name" =~ terraformStateBootstrap ]]; then
                echo "  Skipping bootstrap project: $project_name"
                continue
            fi
            
            expected_projects=$((expected_projects + 1))
            local backend_file="$project_dir/backend.tf"
            if [ -f "$backend_file" ]; then
                echo "  Found backend.tf: $backend_file"
                found_files=$((found_files + 1))
            else
                echo "  Missing backend.tf: $backend_file"
                missing_files+=("$backend_file")
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/common")
    else
        echo "  Common directory does not exist"
    fi

    # Check environment-specific directory (only if it contains projects)
    if [ -d "$TERRAFORM_ENVS_DIR/$TEST_ENV" ]; then
        local env_projects
        env_projects=$(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" | wc -l)
        if [ "$env_projects" -gt 0 ]; then
            while IFS= read -r project_dir; do
                [ -z "$project_dir" ] && continue
                local project_name
                project_name=$(basename "$project_dir")
                
                # Skip terraformStateBootstrap (should NOT have backend.tf)
                if [[ "$project_name" =~ terraformStateBootstrap ]]; then
                    echo "  Skipping bootstrap project: $project_name"
                    continue
                fi
                
                expected_projects=$((expected_projects + 1))
                local backend_file="$project_dir/backend.tf"
                if [ -f "$backend_file" ]; then
                    found_files=$((found_files + 1))
                else
                    missing_files+=("$backend_file")
                fi
            done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV")
        fi
    fi

    echo "  Summary: expected=$expected_projects, found=$found_files, missing=${#missing_files[@]}"

    if [ ${#missing_files[@]} -eq 0 ] && [ $found_files -gt 0 ]; then
        print_test_result "$test_name" "PASS" "Found $found_files backend.tf files"
    elif [ $expected_projects -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No non-bootstrap terraform projects found (expected)"
    else
        local details="Found $found_files files, expected $expected_projects"
        if [ ${#missing_files[@]} -gt 0 ]; then
            details="$details, Missing: ${missing_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_backend_content() {
    local test_name="Terraform backend.tf files contain valid content"
    local invalid_files=()
    local valid_files=0
    echo "-> ${FUNCNAME[0]}"

    # Find all backend.tf files
    while IFS= read -r backend_file; do
        [ -z "$backend_file" ] && continue
        
        local project_dir
        project_dir=$(dirname "$backend_file")
        local project_name
        project_name=$(basename "$project_dir")
        
        # Check if file contains expected backend configuration
        if grep -q "backend \"s3\"" "$backend_file" 2>/dev/null && \
           grep -q "bucket.*=" "$backend_file" 2>/dev/null && \
           grep -q "key.*=" "$backend_file" 2>/dev/null && \
           grep -q "region.*=" "$backend_file" 2>/dev/null && \
           grep -q "dynamodb_table.*=" "$backend_file" 2>/dev/null; then
            valid_files=$((valid_files + 1))
            echo "  Valid backend.tf: $backend_file"
        else
            invalid_files+=("$backend_file")
            echo "  Invalid backend.tf: $backend_file"
        fi
    done < <(find "$TERRAFORM_ENVS_DIR" -name "backend.tf" -type f 2>/dev/null || true)

    if [ ${#invalid_files[@]} -eq 0 ] && [ $valid_files -gt 0 ]; then
        print_test_result "$test_name" "PASS" "All $valid_files backend.tf files contain valid content"
    elif [ $valid_files -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No backend.tf files found (expected for bootstrap-only setup)"
    else
        local details="Valid: $valid_files"
        if [ ${#invalid_files[@]} -gt 0 ]; then
            details="$details, Invalid: ${invalid_files[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_backend_no_bootstrap() {
    local test_name="Bootstrap projects do NOT have backend.tf files"
    local bootstrap_with_backend=()
    local bootstrap_projects=0
    echo "-> ${FUNCNAME[0]}"

    # Find all terraformStateBootstrap projects
    while IFS= read -r project_dir; do
        [ -z "$project_dir" ] && continue
        local project_name
        project_name=$(basename "$project_dir")
        
        if [[ "$project_name" =~ terraformStateBootstrap ]]; then
            bootstrap_projects=$((bootstrap_projects + 1))
            local backend_file="$project_dir/backend.tf"
            if [ -f "$backend_file" ]; then
                bootstrap_with_backend+=("$project_dir")
                echo "  ERROR: Bootstrap project has backend.tf: $project_dir"
            else
                echo "  OK: Bootstrap project has no backend.tf: $project_dir"
            fi
        fi
    done < <(find "$TERRAFORM_ENVS_DIR" -maxdepth 2 -type d -name "*terraformStateBootstrap*" 2>/dev/null || true)

    if [ ${#bootstrap_with_backend[@]} -eq 0 ]; then
        if [ $bootstrap_projects -gt 0 ]; then
            print_test_result "$test_name" "PASS" "All $bootstrap_projects bootstrap projects correctly have no backend.tf"
        else
            print_test_result "$test_name" "PASS" "No bootstrap projects found"
        fi
    else
        local details="Bootstrap projects with backend.tf: ${bootstrap_with_backend[*]}"
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

    # Set required environment variables for the script (only if not already set)
    export ABK_DEPLOYMENT_ENV="$TEST_ENV"
    export ABK_PRJ_NAME="${ABK_PRJ_NAME:-test-project}"
    export LOG_LEVEL="${LOG_LEVEL:-debug}"
    export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test-key}"
    export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test-secret}"

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
    test_config_file_created || echo "❌ test_config_file_created"
    test_config_file_no_variables || echo "❌ test_config_file_no_variables"
    test_config_file_content || echo "❌ test_config_file_content"
    test_terraform_vars_files_created || echo "❌ test_terraform_vars_files_created"
    test_terraform_vars_valid_json || echo "❌ test_terraform_vars_valid_json"
    test_terraform_vars_content || echo "❌ test_terraform_vars_content"
    test_terraform_backend_files_created || echo "❌ test_terraform_backend_files_created"
    test_terraform_backend_content || echo "❌ test_terraform_backend_content"
    test_terraform_backend_no_bootstrap || echo "❌ test_terraform_backend_no_bootstrap"

    print_test_summary
}

# Run tests
main "$@"
