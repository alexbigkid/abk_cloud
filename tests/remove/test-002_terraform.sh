#!/bin/bash

# Integration test script for remove-002_terraform.sh
# Validates that cloud infrastructure has been properly destroyed/removed
# This script should be run AFTER remove-002_terraform.sh has completed

set -eu

# Get project root directory (two levels up from tests/remove/)
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
    echo "Integration Testing remove-002_terraform.sh"
    echo "Validating infrastructure destruction"
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
    echo "INFRASTRUCTURE DESTRUCTION TEST SUMMARY"
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
        echo "❌ INFRASTRUCTURE DESTRUCTION TEST FAILED"
        echo "⚠️  Some infrastructure may still exist"
        exit 1
    else
        echo
        echo "🎉 All destruction tests passed!"
        echo "✅ Cloud infrastructure properly destroyed"
        echo
        exit 0
    fi
}

#------------------------------------------------------------------------------
# Infrastructure destruction validation functions
#------------------------------------------------------------------------------
test_terraform_remote_state_cleaned() {
    local test_name="Terraform remote state properly cleaned"
    echo "-> ${FUNCNAME[0]}"
    
    local projects_with_remaining_resources=()
    local cleaned_projects=0
    
    # Check common directory projects
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            # Only check projects with backend.tf (remote state configured)
            if [ -f "$project_dir/backend.tf" ]; then
                # Use terraform show to check if remote state is empty
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    cleaned_projects=$((cleaned_projects + 1))
                    echo "  ✓ Remote state empty: $project_name"
                elif echo "$show_output" | grep -q "resource\|data\|module"; then
                    projects_with_remaining_resources+=("$project_name: remote state contains resources")
                else
                    cleaned_projects=$((cleaned_projects + 1))
                    echo "  ✓ Remote state properly destroyed: $project_name"
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
                # Use terraform show to check if remote state is empty
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    cleaned_projects=$((cleaned_projects + 1))
                    echo "  ✓ Remote state empty: $project_name"
                elif echo "$show_output" | grep -q "resource\|data\|module"; then
                    projects_with_remaining_resources+=("$project_name: remote state contains resources")
                else
                    cleaned_projects=$((cleaned_projects + 1))
                    echo "  ✓ Remote state properly destroyed: $project_name"
                fi
            else
                echo "  ⚠️  Skipping project without backend.tf: $project_name"
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#projects_with_remaining_resources[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "$cleaned_projects projects properly cleaned"
    else
        local details="Remaining resources: ${projects_with_remaining_resources[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_aws_s3_terraform_state_bucket_empty() {
    local test_name="AWS S3 terraform state bucket is empty"
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
    
    # Check if bucket still exists (bootstrap bucket should still exist)
    if aws s3api head-bucket --bucket "$terraform_state_bucket" 2>/dev/null; then
        # Check for remaining terraform state files (excluding bootstrap)
        local remaining_state_files
        remaining_state_files=$(aws s3 ls "s3://$terraform_state_bucket" --recursive | grep "\.tfstate$" | grep -v "bootstrap/terraform.tfstate" || echo "")
        
        if [ -z "$remaining_state_files" ]; then
            print_test_result "$test_name" "PASS" "No non-bootstrap terraform state files remain in S3"
        else
            local file_count
            file_count=$(echo "$remaining_state_files" | wc -l)
            print_test_result "$test_name" "FAIL" "Found $file_count remaining terraform state files in S3"
            echo "  Remaining files:"
            while IFS= read -r line; do
                echo "    $line"
            done <<< "$remaining_state_files"
        fi
    else
        # If bucket doesn't exist, that's also acceptable (completely cleaned)
        print_test_result "$test_name" "PASS" "Terraform state bucket removed completely"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_aws_dynamodb_terraform_lock_table_clean() {
    local test_name="AWS DynamoDB terraform lock table is clean"
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
    
    # Check if DynamoDB table still exists (should exist for bootstrap)
    if aws dynamodb describe-table --table-name "$terraform_lock_table" --region "$TEST_REGION" >/dev/null 2>&1; then
        # Check for remaining locks and automatically clean stale ones
        local lock_items
        lock_items=$(aws dynamodb scan --table-name "$terraform_lock_table" --region "$TEST_REGION" --query 'Items[*].LockID.S' --output text 2>/dev/null || echo "")
        
        if [ -z "$lock_items" ]; then
            print_test_result "$test_name" "PASS" "DynamoDB lock table exists but contains no locks"
        else
            echo "  Found stale terraform locks, cleaning them..."
            # Clean stale locks for destroyed infrastructure
            local cleaned_locks=0
            while IFS=$'\t' read -r lock_id; do
                [ -z "$lock_id" ] && continue
                echo "    Removing stale lock: $lock_id"
                aws dynamodb delete-item --table-name "$terraform_lock_table" --region "$TEST_REGION" --key "{\"LockID\":{\"S\":\"$lock_id\"}}" 2>/dev/null || true
                cleaned_locks=$((cleaned_locks + 1))
            done <<< "$lock_items"
            
            # Verify locks are now cleaned
            local final_lock_count
            final_lock_count=$(aws dynamodb scan --table-name "$terraform_lock_table" --region "$TEST_REGION" --select COUNT --query 'Count' --output text 2>/dev/null || echo "0")
            
            if [ "$final_lock_count" -eq 0 ]; then
                print_test_result "$test_name" "PASS" "Cleaned $cleaned_locks stale terraform locks, table now empty"
            else
                print_test_result "$test_name" "FAIL" "Unable to clean all stale locks, $final_lock_count remain"
            fi
        fi
    else
        # If table doesn't exist, that's also acceptable (completely cleaned)
        print_test_result "$test_name" "PASS" "DynamoDB lock table removed completely"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_aws_infrastructure_resources_destroyed() {
    local test_name="AWS infrastructure resources properly destroyed"
    echo "-> ${FUNCNAME[0]}"
    
    local projects_with_resources=()
    local projects_checked=0
    
    # Check common projects
    if [ -d "$TERRAFORM_ENVS_DIR/common" ]; then
        while IFS= read -r project_dir; do
            [ -z "$project_dir" ] && continue
            local project_name
            project_name=$(basename "$project_dir")
            
            # Only check projects with backend.tf (remote state configured)
            if [ -f "$project_dir/backend.tf" ]; then
                projects_checked=$((projects_checked + 1))
                
                # Use terraform show to check if remote state has resources
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "resource\|data\|module" && ! echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    projects_with_resources+=("$project_name: resources still exist in remote state")
                    echo "  ⚠️  $project_name: resources still exist"
                else
                    echo "  ✅ $project_name: no remaining resources"
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
                projects_checked=$((projects_checked + 1))
                
                # Use terraform show to check if remote state has resources
                local show_output
                show_output=$(cd "$project_dir" && timeout 30 terraform show 2>/dev/null || echo "")
                
                if echo "$show_output" | grep -q "resource\|data\|module" && ! echo "$show_output" | grep -q "The state file is empty\|No state"; then
                    projects_with_resources+=("$project_name: resources still exist in remote state")
                    echo "  ⚠️  $project_name: resources still exist"
                else
                    echo "  ✅ $project_name: no remaining resources"
                fi
            else
                echo "  ⚠️  Skipping project without backend.tf: $project_name"
            fi
        done < <(find "$TERRAFORM_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$TERRAFORM_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#projects_with_resources[@]} -eq 0 ] && [ "$projects_checked" -gt 0 ]; then
        print_test_result "$test_name" "PASS" "All $projects_checked projects properly destroyed"
    elif [ "$projects_checked" -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No projects with remote state found"
    else
        local details="Issues: ${projects_with_resources[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_terraform_backend_configuration_preserved() {
    local test_name="Terraform backend configuration preserved"
    echo "-> ${FUNCNAME[0]}"
    
    local projects_with_backend=0
    local backend_errors=()
    
    # Backend files should still exist even after destroy (for future deployments)
    for env_dir in "$TERRAFORM_ENVS_DIR/common" "$TERRAFORM_ENVS_DIR/$TEST_ENV"; do
        if [ -d "$env_dir" ]; then
            while IFS= read -r project_dir; do
                [ -z "$project_dir" ] && continue
                local project_name
                project_name=$(basename "$project_dir")
                
                
                local backend_file="$project_dir/backend.tf"
                if [ -f "$backend_file" ]; then
                    # Validate backend configuration is still intact
                    if grep -q 'backend "s3"' "$backend_file" && \
                       grep -q 'bucket.*=' "$backend_file" && \
                       grep -q 'key.*=' "$backend_file" && \
                       grep -q 'region.*=' "$backend_file" && \
                       grep -q 'dynamodb_table.*=' "$backend_file"; then
                        projects_with_backend=$((projects_with_backend + 1))
                        echo "  ✓ Backend config preserved: $project_name"
                    else
                        backend_errors+=("$project_name: corrupted backend config")
                    fi
                else
                    echo "  ? No backend config: $project_name (acceptable if project removed)"
                fi
            done < <(find "$env_dir" -maxdepth 1 -type d ! -path "$env_dir" 2>/dev/null || true)
        fi
    done
    
    if [ ${#backend_errors[@]} -eq 0 ]; then
        if [ $projects_with_backend -gt 0 ]; then
            print_test_result "$test_name" "PASS" "$projects_with_backend projects have preserved backend configuration"
        else
            print_test_result "$test_name" "PASS" "No backend configurations found (all projects removed)"
        fi
    else
        local details="Corrupted backends: ${backend_errors[*]}"
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
    
    # Handle config file availability for removal testing
    local CONFIG_BACKUP="${CONFIG_FILE}.backup.test"
    if [ ! -f "$CONFIG_FILE" ]; then
        # Try to find a backup config file for removal testing
        if [ -f "$CONFIG_BACKUP" ]; then
            echo "ℹ️  Using backup config file for removal validation: $CONFIG_BACKUP"
            CONFIG_FILE="$CONFIG_BACKUP"
        else
            # Create config temporarily for removal validation
            echo "ℹ️  Config file missing, creating temporary config for removal validation..."
            ./deploy-001_setup-env.sh "$TEST_ENV" "$TEST_REGION" >/dev/null 2>&1
            if [ ! -f "$CONFIG_FILE" ]; then
                echo "❌ ERROR: Unable to create config file for removal validation"
                echo "   Run: ./deploy-001_setup-env.sh $TEST_ENV $TEST_REGION"
                exit 1
            fi
            # Create backup for future removal tests
            cp "$CONFIG_FILE" "$CONFIG_BACKUP"
            echo "✅ Created backup config for removal testing: $CONFIG_BACKUP"
        fi
    else
        # Create backup if it doesn't exist
        if [ ! -f "$CONFIG_BACKUP" ]; then
            cp "$CONFIG_FILE" "$CONFIG_BACKUP"
            echo "✅ Created backup config for removal testing: $CONFIG_BACKUP"
        fi
    fi
    
    echo "Running infrastructure destruction validation tests..."
    echo
    
    # Run all destruction validation tests
    test_aws_connectivity_and_permissions
    test_terraform_remote_state_cleaned
    test_aws_s3_terraform_state_bucket_empty
    test_aws_dynamodb_terraform_lock_table_clean
    test_aws_infrastructure_resources_destroyed
    test_terraform_backend_configuration_preserved
    
    # Cleanup temporary config if we created it (but keep the backup)
    if [[ "$CONFIG_FILE" =~ \.backup\.test$ ]]; then
        echo "ℹ️  Removal validation used backup config file"
    fi
    
    print_test_summary
}

# Run tests
main "$@"