#!/bin/bash

# Integration test script for deploy-002_terraform.sh
# Validates that actual cloud infrastructure has been deployed successfully
# This script should be run AFTER deploy-002_terraform.sh has completed

set -eu

# Get project root directory (two levels up from tests/deploy/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test configuration
TEST_ENV="${1:-dev}"
TEST_REGION="${2:-us-west-2}"
TERRAFORM_ENVS_DIR="$PROJECT_ROOT/terraform/envs"
COMMON_LIB_FILE="$PROJECT_ROOT/common-lib.sh"
CONFIG_FILE="$PROJECT_ROOT/config.$TEST_ENV.yml"

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
    echo "Integration Testing deploy-002_terraform.sh"
    echo "Validating actual cloud infrastructure"
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
    echo "INTEGRATION TEST SUMMARY"
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
        echo "❌ INTEGRATION TEST SUITE FAILED"
        exit 1
    else
        echo
        echo "🎉 All integration tests passed!"
        echo "✅ Cloud infrastructure deployed successfully"
        echo
        exit 0
    fi
}

#------------------------------------------------------------------------------
# Infrastructure validation functions
#------------------------------------------------------------------------------
test_terraform_remote_state_exists() {
    local test_name="Terraform remote state exists"
    echo "-> ${FUNCNAME[0]}"
    
    local projects_without_state=()
    local projects_with_state=0
    
    # Check common directory projects
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            # Only check projects with backend.tf (remote state configured)
            if [ -f "$project_dir/backend.tf" ]; then
                # Use terraform show to check remote state
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "resource\|data\|module" && ! echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    projects_with_state=$((projects_with_state + 1))
                    echo "  ✓ Remote state contains resources: $project_name"
                else
                    projects_without_state+=("$project_name: remote state empty or inaccessible")
                fi
            else
                echo "  ⚠️  Skipping project without backend.tf: $project_name"
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/common" 2>/dev/null || true)
    fi
    
    # Check environment-specific directory projects
    if [ -d "$TERRAFORM_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            # Only check projects with backend.tf (remote state configured)
            if [ -f "$project_dir/backend.tf" ]; then
                # Use terraform show to check remote state
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "resource\|data\|module" && ! echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    projects_with_state=$((projects_with_state + 1))
                    echo "  ✓ Remote state contains resources: $project_name"
                else
                    projects_without_state+=("$project_name: remote state empty or inaccessible")
                fi
            else
                echo "  ⚠️  Skipping project without backend.tf: $project_name"
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#projects_without_state[@]} -eq 0 ] && [ $projects_with_state -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$projects_with_state projects have valid remote state"
    elif [ $projects_with_state -eq 0 ] && [ ${#projects_without_state[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No terraform projects found (serverless-only deployment)"
    else
        local details="Valid: $projects_with_state, Issues: ${projects_without_state[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_aws_s3_terraform_state_bucket() {
    local test_name="AWS S3 terraform state bucket exists"
    echo "-> ${FUNCNAME[0]}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_test_result "$test_name" "FAIL" "Config file not found: $CONFIG_FILE"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    # Get terraform state bucket name from config
    local terraform_state_bucket
    terraform_state_bucket=$(yq -r '.terraform.terraformStateBootstrap.terraform_bootstrap_state_s3_bucket' "$CONFIG_FILE" 2>/dev/null || echo "null")
    
    if [ -z "$terraform_state_bucket" ] || [ "$terraform_state_bucket" = "null" ]; then
        print_test_result "$test_name" "FAIL" "Could not determine terraform state bucket from config"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    echo "  Checking bucket: $terraform_state_bucket"
    
    # Check if bucket exists and is accessible
    if aws s3api head-bucket --bucket "$terraform_state_bucket" 2>/dev/null; then
        # Check if bucket has terraform state files
        local state_files_count
        state_files_count=$(aws s3 ls "s3://$terraform_state_bucket" --recursive | grep -c "\.tfstate$" || echo "0")
        
        if [ "$state_files_count" -gt 0 ]; then
            print_test_result "$test_name" "PASS" "Bucket exists with $state_files_count terraform state files"
        else
            print_test_result "$test_name" "PASS" "Bucket exists (ready for terraform state files)"
        fi
    else
        print_test_result "$test_name" "FAIL" "S3 bucket does not exist or is not accessible: $terraform_state_bucket"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_aws_dynamodb_terraform_lock_table() {
    local test_name="AWS DynamoDB terraform lock table exists"
    echo "-> ${FUNCNAME[0]}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_test_result "$test_name" "FAIL" "Config file not found: $CONFIG_FILE"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    # Get terraform lock table name from config
    local terraform_lock_table
    terraform_lock_table=$(yq -r '.terraform.terraformStateBootstrap.dynamodb_terraform_lock_name' "$CONFIG_FILE" 2>/dev/null || echo "null")
    
    if [ -z "$terraform_lock_table" ] || [ "$terraform_lock_table" = "null" ]; then
        print_test_result "$test_name" "FAIL" "Could not determine terraform lock table from config"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    echo "  Checking table: $terraform_lock_table"
    
    # Check if DynamoDB table exists
    if aws dynamodb describe-table --table-name "$terraform_lock_table" --region "$TEST_REGION" >/dev/null 2>&1; then
        # Get table status
        local table_status
        table_status=$(aws dynamodb describe-table --table-name "$terraform_lock_table" --region "$TEST_REGION" --query 'Table.TableStatus' --output text 2>/dev/null || echo "UNKNOWN")
        
        if [ "$table_status" = "ACTIVE" ]; then
            print_test_result "$test_name" "PASS" "DynamoDB table is active: $terraform_lock_table"
        else
            print_test_result "$test_name" "FAIL" "DynamoDB table exists but status is: $table_status"
        fi
    else
        print_test_result "$test_name" "FAIL" "DynamoDB table does not exist: $terraform_lock_table"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_aws_infrastructure_resources() {
    local test_name="AWS infrastructure resources deployed"
    echo "-> ${FUNCNAME[0]}"
    
    local projects_with_resources=0
    local projects_without_resources=()
    
    # Check common projects
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            # Only check projects with backend.tf (remote state configured)
            if [ -f "$project_dir/backend.tf" ]; then
                # Use terraform show to verify resources exist in remote state
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "resource\|data\|module" && ! echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    projects_with_resources=$((projects_with_resources + 1))
                    echo "  ✓ Resources deployed: $project_name"
                else
                    projects_without_resources+=("$project_name: no resources in remote state")
                fi
            else
                echo "  ⚠️  Skipping project without backend.tf: $project_name"
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/common" 2>/dev/null || true)
    fi
    
    # Check environment-specific projects
    if [ -d "$TERRAFORM_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            # Only check projects with backend.tf (remote state configured)
            if [ -f "$project_dir/backend.tf" ]; then
                # Use terraform show to verify resources exist in remote state
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "resource\|data\|module" && ! echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    projects_with_resources=$((projects_with_resources + 1))
                    echo "  ✓ Resources deployed: $project_name"
                else
                    projects_without_resources+=("$project_name: no resources in remote state")
                fi
            else
                echo "  ⚠️  Skipping project without backend.tf: $project_name"
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#projects_without_resources[@]} -eq 0 ] && [ $projects_with_resources -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$projects_with_resources projects have deployed resources"
    elif [ $projects_with_resources -eq 0 ] && [ ${#projects_without_resources[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No terraform projects found (serverless-only deployment)"
    else
        local details="Deployed: $projects_with_resources, Issues: ${projects_without_resources[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_backend_configuration() {
    local test_name="Terraform backend configuration is valid"
    echo "-> ${FUNCNAME[0]}"
    
    local projects_with_backend=0
    local projects_without_backend=0
    local backend_errors=()
    
    # Check all terraform projects for valid backend configuration
    for env_dir in "$TERRAFORM_ENVS_DIR/common" "$TERRAFORM_ENVS_DIR/$TEST_ENV"; do
        if [ -d "$env_dir" ]; then
            while IFS= read -r project_dir; do
                [ -z "$project_dir" ] && continue
                local project_name
                project_name=$(basename "$project_dir")
                
                # Only check projects in terraform/envs (bootstrap is separate)
                
                local backend_file="$project_dir/backend.tf"
                if [ -f "$backend_file" ]; then
                    # Validate backend configuration
                    if grep -q 'backend "s3"' "$backend_file" && \
                       grep -q 'bucket.*=' "$backend_file" && \
                       grep -q 'key.*=' "$backend_file" && \
                       grep -q 'region.*=' "$backend_file" && \
                       grep -q 'dynamodb_table.*=' "$backend_file"; then
                        projects_with_backend=$((projects_with_backend + 1))
                        echo "  ✓ Valid backend config: $project_name"
                    else
                        backend_errors+=("$project_name: incomplete backend config")
                    fi
                else
                    projects_without_backend=$((projects_without_backend + 1))
                    backend_errors+=("$project_name: no backend.tf file")
                fi
            done < <(find "$env_dir" -maxdepth 1 -type d ! -path "$env_dir" 2>/dev/null || true)
        fi
    done
    
    if [ ${#backend_errors[@]} -eq 0 ] && [ $projects_with_backend -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$projects_with_backend projects have valid backend configuration"
    elif [ $projects_with_backend -eq 0 ] && [ ${#backend_errors[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No terraform projects found (serverless-only deployment)"
    else
        local details="Valid backends: $projects_with_backend"
        if [ ${#backend_errors[@]} -gt 0 ]; then
            details="$details, Errors: ${backend_errors[*]}"
        fi
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_aws_connectivity_and_permissions() {
    local test_name="AWS connectivity and permissions"
    echo "-> ${FUNCNAME[0]}"
    
    # Test basic AWS CLI connectivity
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_test_result "$test_name" "FAIL" "AWS CLI not configured or no connectivity"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    # Get caller identity info
    local caller_identity
    caller_identity=$(aws sts get-caller-identity 2>/dev/null || echo "unknown")
    local account_id
    account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null || echo "unknown")
    local user_arn
    user_arn=$(echo "$caller_identity" | jq -r '.Arn' 2>/dev/null || echo "unknown")
    
    echo "  Account ID: $account_id"
    echo "  User/Role: $user_arn"
    echo "  Region: $TEST_REGION"
    
    # Test S3 list permissions
    local s3_test=false
    if aws s3 ls >/dev/null 2>&1; then
        s3_test=true
        echo "  ✓ S3 list permissions: OK"
    else
        echo "  ✗ S3 list permissions: FAILED"
    fi
    
    # Test DynamoDB list permissions
    local dynamodb_test=false
    if aws dynamodb list-tables --region "$TEST_REGION" >/dev/null 2>&1; then
        dynamodb_test=true
        echo "  ✓ DynamoDB list permissions: OK"
    else
        echo "  ✗ DynamoDB list permissions: FAILED"
    fi
    
    if [ "$s3_test" = true ] && [ "$dynamodb_test" = true ]; then
        print_test_result "$test_name" "PASS" "AWS connectivity and basic permissions verified"
    else
        print_test_result "$test_name" "FAIL" "AWS permissions insufficient for infrastructure validation"
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
        echo "❌ ERROR: $COMMON_LIB_FILE not found"
        exit 1
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "❌ ERROR: Environment config not found: $CONFIG_FILE"
        echo "   Run: ./deploy-001_setup-env.sh $TEST_ENV $TEST_REGION"
        exit 1
    fi
    
    echo "Running integration tests..."
    echo
    
    # Run all integration tests
    test_aws_connectivity_and_permissions
    test_aws_s3_terraform_state_bucket
    test_aws_dynamodb_terraform_lock_table
    test_terraform_remote_state_exists
    test_terraform_backend_configuration
    test_aws_infrastructure_resources
    
    print_test_summary
}

# Run tests
main "$@"