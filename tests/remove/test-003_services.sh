#!/bin/bash

# Integration test script for remove-003_services.sh
# Validates that serverless services have been properly destroyed/removed
# This script should be run AFTER remove-003_services.sh has completed

set -eu

# Get project root directory (two levels up from tests/remove/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test configuration
TEST_ENV="${1:-dev}"
TEST_REGION="${2:-us-west-2}"
SERVICES_ENVS_DIR="$PROJECT_ROOT/services/envs"
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
    echo "Integration Testing remove-003_services.sh"
    echo "Validating service destruction"
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
        echo "✅ Serverless services removed successfully"
        echo
        exit 0
    fi
}

#------------------------------------------------------------------------------
# Service removal validation functions
#------------------------------------------------------------------------------
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
    
    # Test Lambda list permissions
    local lambda_test=false
    if aws lambda list-functions --region "$TEST_REGION" >/dev/null 2>&1; then
        lambda_test=true
        echo "  ✓ Lambda list permissions: OK"
    else
        echo "  ✗ Lambda list permissions: FAILED"
    fi
    
    # Test API Gateway list permissions
    local apigateway_test=false
    if aws apigateway get-rest-apis --region "$TEST_REGION" >/dev/null 2>&1; then
        apigateway_test=true
        echo "  ✓ API Gateway list permissions: OK"
    else
        echo "  ✗ API Gateway list permissions: FAILED"
    fi
    
    if [ "$lambda_test" = true ] && [ "$apigateway_test" = true ]; then
        print_test_result "$test_name" "PASS" "AWS connectivity and basic permissions verified"
    else
        print_test_result "$test_name" "FAIL" "AWS permissions insufficient for service validation"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_lambda_functions_removed() {
    local test_name="Lambda functions properly removed"
    echo "-> ${FUNCNAME[0]}"
    
    local services_with_remaining_lambdas=()
    local total_services_checked=0
    
    # Check services in common directory
    if [ -d "$SERVICES_ENVS_DIR/common" ]; then
        while IFS= read -r service_dir; do
            [ -z "$service_dir" ] && continue
            local service_name
            service_name=$(basename "$service_dir")
            
            # Only check services with publish.sh
            if [ -f "$service_dir/publish.sh" ]; then
                total_services_checked=$((total_services_checked + 1))
                
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if Lambda functions still exist
                local lambda_name="${clean_service_name}-${TEST_ENV}-"
                local lambda_functions
                lambda_functions=$(aws lambda list-functions --region "$TEST_REGION" --query "Functions[?starts_with(FunctionName, '$lambda_name')].FunctionName" --output text 2>/dev/null || echo "")
                
                if [ -n "$lambda_functions" ]; then
                    services_with_remaining_lambdas+=("$service_name: still has Lambda functions: $lambda_functions")
                    echo "  ❌ Lambda functions still exist for service: $service_name"
                    echo "    Functions: $lambda_functions"
                else
                    echo "  ✓ No Lambda functions found for service: $service_name (properly removed)"
                fi
            fi
        done < <(find "$SERVICES_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/common" 2>/dev/null || true)
    fi
    
    # Check services in environment-specific directory
    if [ -d "$SERVICES_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r service_dir; do
            [ -z "$service_dir" ] && continue
            local service_name
            service_name=$(basename "$service_dir")
            
            # Only check services with publish.sh
            if [ -f "$service_dir/publish.sh" ]; then
                total_services_checked=$((total_services_checked + 1))
                
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if Lambda functions still exist
                local lambda_name="${clean_service_name}-${TEST_ENV}-"
                local lambda_functions
                lambda_functions=$(aws lambda list-functions --region "$TEST_REGION" --query "Functions[?starts_with(FunctionName, '$lambda_name')].FunctionName" --output text 2>/dev/null || echo "")
                
                if [ -n "$lambda_functions" ]; then
                    services_with_remaining_lambdas+=("$service_name: still has Lambda functions: $lambda_functions")
                    echo "  ❌ Lambda functions still exist for service: $service_name"
                    echo "    Functions: $lambda_functions"
                else
                    echo "  ✓ No Lambda functions found for service: $service_name (properly removed)"
                fi
            fi
        done < <(find "$SERVICES_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#services_with_remaining_lambdas[@]} -eq 0 ]; then
        if [ $total_services_checked -gt 0 ]; then
            print_test_result "$test_name" "PASS" "All $total_services_checked services have Lambda functions properly removed"
        else
            print_test_result "$test_name" "PASS" "No services with publish.sh found (no Lambda functions to remove)"
        fi
    else
        local details="Services with remaining Lambdas: ${services_with_remaining_lambdas[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_api_gateway_endpoints_removed() {
    local test_name="API Gateway endpoints properly removed"
    echo "-> ${FUNCNAME[0]}"
    
    local services_with_remaining_apis=()
    local total_services_checked=0
    
    # Get all REST APIs
    local rest_apis
    rest_apis=$(aws apigateway get-rest-apis --region "$TEST_REGION" --query 'items[].{id:id,name:name}' --output json 2>/dev/null || echo "[]")
    
    # Check services in common directory
    if [ -d "$SERVICES_ENVS_DIR/common" ]; then
        while IFS= read -r service_dir; do
            [ -z "$service_dir" ] && continue
            local service_name
            service_name=$(basename "$service_dir")
            
            # Only check services with publish.sh
            if [ -f "$service_dir/publish.sh" ]; then
                total_services_checked=$((total_services_checked + 1))
                
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if API Gateway still exists for this service
                local api_name="${TEST_ENV}-${clean_service_name}"
                local api_found
                api_found=$(echo "$rest_apis" | jq -r ".[] | select(.name == \"$api_name\") | .id" 2>/dev/null || echo "")
                
                if [ -n "$api_found" ]; then
                    services_with_remaining_apis+=("$service_name: still has API Gateway: $api_found")
                    echo "  ❌ API Gateway still exists for service: $service_name (API ID: $api_found)"
                else
                    echo "  ✓ No API Gateway found for service: $service_name (properly removed)"
                fi
            fi
        done < <(find "$SERVICES_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/common" 2>/dev/null || true)
    fi
    
    # Check services in environment-specific directory
    if [ -d "$SERVICES_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r service_dir; do
            [ -z "$service_dir" ] && continue
            local service_name
            service_name=$(basename "$service_dir")
            
            # Only check services with publish.sh
            if [ -f "$service_dir/publish.sh" ]; then
                total_services_checked=$((total_services_checked + 1))
                
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if API Gateway still exists for this service
                local api_name="${TEST_ENV}-${clean_service_name}"
                local api_found
                api_found=$(echo "$rest_apis" | jq -r ".[] | select(.name == \"$api_name\") | .id" 2>/dev/null || echo "")
                
                if [ -n "$api_found" ]; then
                    services_with_remaining_apis+=("$service_name: still has API Gateway: $api_found")
                    echo "  ❌ API Gateway still exists for service: $service_name (API ID: $api_found)"
                else
                    echo "  ✓ No API Gateway found for service: $service_name (properly removed)"
                fi
            fi
        done < <(find "$SERVICES_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#services_with_remaining_apis[@]} -eq 0 ]; then
        if [ $total_services_checked -gt 0 ]; then
            print_test_result "$test_name" "PASS" "All $total_services_checked services have API Gateway endpoints properly removed"
        else
            print_test_result "$test_name" "PASS" "No services with publish.sh found (no API endpoints to remove)"
        fi
    else
        local details="Services with remaining APIs: ${services_with_remaining_apis[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_cloudformation_stacks_removed() {
    local test_name="CloudFormation stacks properly removed"
    echo "-> ${FUNCNAME[0]}"
    
    local services_with_remaining_stacks=()
    local total_services_checked=0
    
    # Get all CloudFormation stacks
    local cf_stacks
    cf_stacks=$(aws cloudformation list-stacks --region "$TEST_REGION" --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].StackName' --output text 2>/dev/null || echo "")
    
    # Check services in common directory
    if [ -d "$SERVICES_ENVS_DIR/common" ]; then
        while IFS= read -r service_dir; do
            [ -z "$service_dir" ] && continue
            local service_name
            service_name=$(basename "$service_dir")
            
            # Only check services with publish.sh
            if [ -f "$service_dir/publish.sh" ]; then
                total_services_checked=$((total_services_checked + 1))
                
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if CloudFormation stack still exists for this service
                local stack_name="${clean_service_name}-${TEST_ENV}"
                local stack_found=""
                
                if echo "$cf_stacks" | grep -q "$stack_name"; then
                    stack_found=$(echo "$cf_stacks" | tr '\t' '\n' | grep "$stack_name" || echo "")
                fi
                
                if [ -n "$stack_found" ]; then
                    services_with_remaining_stacks+=("$service_name: still has CloudFormation stack: $stack_found")
                    echo "  ❌ CloudFormation stack still exists for service: $service_name"
                    echo "    Stack: $stack_found"
                else
                    echo "  ✓ No CloudFormation stack found for service: $service_name (properly removed)"
                fi
            fi
        done < <(find "$SERVICES_ENVS_DIR/common" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/common" 2>/dev/null || true)
    fi
    
    # Check services in environment-specific directory
    if [ -d "$SERVICES_ENVS_DIR/$TEST_ENV" ]; then
        while IFS= read -r service_dir; do
            [ -z "$service_dir" ] && continue
            local service_name
            service_name=$(basename "$service_dir")
            
            # Only check services with publish.sh
            if [ -f "$service_dir/publish.sh" ]; then
                total_services_checked=$((total_services_checked + 1))
                
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if CloudFormation stack still exists for this service
                local stack_name="${clean_service_name}-${TEST_ENV}"
                local stack_found=""
                
                if echo "$cf_stacks" | grep -q "$stack_name"; then
                    stack_found=$(echo "$cf_stacks" | tr '\t' '\n' | grep "$stack_name" || echo "")
                fi
                
                if [ -n "$stack_found" ]; then
                    services_with_remaining_stacks+=("$service_name: still has CloudFormation stack: $stack_found")
                    echo "  ❌ CloudFormation stack still exists for service: $service_name"
                    echo "    Stack: $stack_found"
                else
                    echo "  ✓ No CloudFormation stack found for service: $service_name (properly removed)"
                fi
            fi
        done < <(find "$SERVICES_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#services_with_remaining_stacks[@]} -eq 0 ]; then
        if [ $total_services_checked -gt 0 ]; then
            print_test_result "$test_name" "PASS" "All $total_services_checked services have CloudFormation stacks properly removed"
        else
            print_test_result "$test_name" "PASS" "No services with publish.sh found (no CloudFormation stacks to remove)"
        fi
    else
        local details="Services with remaining stacks: ${services_with_remaining_stacks[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_no_orphaned_resources() {
    local test_name="No orphaned AWS resources remain"
    echo "-> ${FUNCNAME[0]}"
    
    local orphaned_resources=()
    
    # Check for any Lambda functions with the environment pattern that shouldn't exist
    local unexpected_lambdas
    unexpected_lambdas=$(aws lambda list-functions --region "$TEST_REGION" --query "Functions[?ends_with(FunctionName, '-$TEST_ENV-') || contains(FunctionName, '-$TEST_ENV-')].FunctionName" --output text 2>/dev/null || echo "")
    
    if [ -n "$unexpected_lambdas" ]; then
        for lambda_name in $unexpected_lambdas; do
            [ -z "$lambda_name" ] && continue
            orphaned_resources+=("Lambda function: $lambda_name")
            echo "  ⚠️  Unexpected Lambda function found: $lambda_name"
        done
    fi
    
    # Check for API Gateways with the environment pattern
    local unexpected_apis
    unexpected_apis=$(aws apigateway get-rest-apis --region "$TEST_REGION" --query "items[?starts_with(name, '$TEST_ENV-')].{id:id,name:name}" --output text 2>/dev/null || echo "")
    
    if [ -n "$unexpected_apis" ]; then
        while read -r api_info; do
            [ -z "$api_info" ] && continue
            orphaned_resources+=("API Gateway: $api_info")
            echo "  ⚠️  Unexpected API Gateway found: $api_info"
        done <<< "$unexpected_apis"
    fi
    
    # Check for CloudFormation stacks with the environment pattern
    local unexpected_stacks
    unexpected_stacks=$(aws cloudformation list-stacks --region "$TEST_REGION" --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?ends_with(StackName, '-$TEST_ENV')].StackName" --output text 2>/dev/null || echo "")
    
    if [ -n "$unexpected_stacks" ]; then
        for stack_name in $unexpected_stacks; do
            [ -z "$stack_name" ] && continue
            orphaned_resources+=("CloudFormation stack: $stack_name")
            echo "  ⚠️  Unexpected CloudFormation stack found: $stack_name"
        done
    fi
    
    if [ ${#orphaned_resources[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No orphaned AWS resources found for environment $TEST_ENV"
    else
        local details="Orphaned resources: ${orphaned_resources[*]}"
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
    test_lambda_functions_removed
    test_api_gateway_endpoints_removed
    test_cloudformation_stacks_removed
    test_no_orphaned_resources
    
    print_test_summary
}

# Run tests
main "$@"