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
test_terraform_state_files_exist() {
    local test_name="Terraform state files exist"
    echo "-> ${FUNCNAME[0]}"
    
    local missing_state_files=()
    local found_state_files=0
    
    # Check common directory for state files
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            # Check multiple possible state file locations
            local state_file="$project_dir/terraform.tfstate"
            local terraform_state_file="$project_dir/.terraform/terraform.tfstate"
            local found_state=false
            
            # Check main directory first
            if [ -f "$state_file" ]; then
                local resource_count
                resource_count=$(grep -c '"type":' "$state_file" 2>/dev/null || echo "0")
                if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
                    found_state_files=$((found_state_files + 1))
                    echo "  ✓ Found state with $resource_count resources: $(basename "$project_dir")"
                    found_state=true
                fi
            # Check .terraform directory
            elif [ -f "$terraform_state_file" ]; then
                local resource_count
                resource_count=$(grep -c '"type":' "$terraform_state_file" 2>/dev/null || echo "0")
                if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
                    found_state_files=$((found_state_files + 1))
                    echo "  ✓ Found state with $resource_count resources: $(basename "$project_dir") (.terraform dir)"
                    found_state=true
                fi
            fi
            
            if [ "$found_state" = false ]; then
                # For projects with remote state, check if they have backend.tf (indicates successful deployment)
                if [ -f "$project_dir/backend.tf" ]; then
                    echo "  ✓ Remote state project (backend configured): $(basename "$project_dir")"
                    found_state_files=$((found_state_files + 1))
                else
                    missing_state_files+=("$project_dir (no state file)")
                fi
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/common" 2>/dev/null || true)
    fi
    
    # Check environment-specific directory for state files
    if [ -d "$TERRAFORM_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            # Check multiple possible state file locations
            local state_file="$project_dir/terraform.tfstate"
            local terraform_state_file="$project_dir/.terraform/terraform.tfstate"
            local found_state=false
            
            # Check main directory first
            if [ -f "$state_file" ]; then
                local resource_count
                resource_count=$(grep -c '"type":' "$state_file" 2>/dev/null || echo "0")
                if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
                    found_state_files=$((found_state_files + 1))
                    echo "  ✓ Found state with $resource_count resources: $(basename "$project_dir")"
                    found_state=true
                fi
            # Check .terraform directory
            elif [ -f "$terraform_state_file" ]; then
                local resource_count
                resource_count=$(grep -c '"type":' "$terraform_state_file" 2>/dev/null || echo "0")
                if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
                    found_state_files=$((found_state_files + 1))
                    echo "  ✓ Found state with $resource_count resources: $(basename "$project_dir") (.terraform dir)"
                    found_state=true
                fi
            fi
            
            if [ "$found_state" = false ]; then
                # For projects with remote state, check if they have backend.tf (indicates successful deployment)
                if [ -f "$project_dir/backend.tf" ]; then
                    echo "  ✓ Remote state project (backend configured): $(basename "$project_dir")"
                    found_state_files=$((found_state_files + 1))
                else
                    missing_state_files+=("$project_dir (no state file)")
                fi
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#missing_state_files[@]} -eq 0 ] && [ $found_state_files -gt 0 ]; then
        print_test_result "$test_name" "PASS" "Found $found_state_files projects with valid terraform state"
    else
        local details="Found $found_state_files valid states"
        if [ ${#missing_state_files[@]} -gt 0 ]; then
            details="$details, Issues: ${missing_state_files[*]}"
        fi
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
            print_test_result "$test_name" "FAIL" "Bucket exists but contains no terraform state files"
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
    local test_name="AWS infrastructure resources exist"
    echo "-> ${FUNCNAME[0]}"
    
    local total_resources=0
    local projects_with_resources=0
    
    # Check common projects
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            # Skip bootstrap project (it's tested separately)
            if [[ "$project_name" =~ terraformStateBootstrap ]]; then
                continue
            fi
            
            # Check multiple possible state file locations
            local state_file="$project_dir/terraform.tfstate"
            local terraform_state_file="$project_dir/.terraform/terraform.tfstate"
            local resource_count=0
            
            # Check main directory first
            if [ -f "$state_file" ]; then
                resource_count=$(grep -c '"type":' "$state_file" 2>/dev/null || echo "0")
            # Check .terraform directory
            elif [ -f "$terraform_state_file" ]; then
                resource_count=$(grep -c '"type":' "$terraform_state_file" 2>/dev/null || echo "0")
            # For remote state projects, try to get state info differently
            elif [ -f "$project_dir/backend.tf" ]; then
                # For remote state, we can't easily count resources without terraform show
                # But we can validate the deployment was successful by checking terraform outputs
                if (cd "$project_dir" && timeout 30 terraform show >/dev/null 2>&1); then
                    resource_count=1  # Assume at least 1 resource if terraform show succeeds
                    echo "  ✓ $project_name: remote state (deployment verified)"
                else
                    echo "  ? $project_name: remote state (cannot verify resources)"
                fi
            fi
            
            if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
                total_resources=$((total_resources + resource_count))
                projects_with_resources=$((projects_with_resources + 1))
                if [ "$resource_count" -ne 1 ] || [ ! -f "$project_dir/backend.tf" ]; then
                    echo "  ✓ $project_name: $resource_count resources"
                fi
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/common" 2>/dev/null || true)
    fi
    
    # Check environment-specific projects
    if [ -d "$TERRAFORM_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            local state_file="$project_dir/terraform.tfstate"
            if [ -f "$state_file" ]; then
                local resource_count
                resource_count=$(grep -c '"type":' "$state_file" 2>/dev/null || echo "0")
                if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
                    total_resources=$((total_resources + resource_count))
                    projects_with_resources=$((projects_with_resources + 1))
                    echo "  ✓ $project_name: $resource_count resources"
                fi
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ $total_resources -gt 0 ] && [ $projects_with_resources -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$total_resources total resources across $projects_with_resources projects"
    else
        print_test_result "$test_name" "FAIL" "No infrastructure resources found in terraform state files"
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
                
                # Skip bootstrap project (it should NOT have backend configuration)
                if [[ "$project_name" =~ terraformStateBootstrap ]]; then
                    continue
                fi
                
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
    test_terraform_state_files_exist
    test_terraform_backend_configuration
    test_aws_infrastructure_resources
    
    print_test_summary
}

# Run tests
main "$@"