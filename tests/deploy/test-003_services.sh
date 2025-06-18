#!/bin/bash

# Integration test script for deploy-003_services.sh
# Validates that serverless services have been deployed successfully
# This script should be run AFTER deploy-003_services.sh has completed

set -eu

# Get project root directory (two levels up from tests/deploy/)
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
    echo "Integration Testing deploy-003_services.sh"
    echo "Validating deployed serverless services"
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
        echo "✅ Serverless services deployed successfully"
        echo
        exit 0
    fi
}

#------------------------------------------------------------------------------
# Service validation functions
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

test_deployed_lambda_functions() {
    local test_name="Lambda functions deployed"
    echo "-> ${FUNCNAME[0]}"
    
    local services_with_lambdas=0
    local services_without_lambdas=()
    
    # Check services in common directory
    if [ -d "$SERVICES_ENVS_DIR/common" ]; then
        while IFS= read -r service_dir; do
            [ -z "$service_dir" ] && continue
            local service_name
            service_name=$(basename "$service_dir")
            
            # Only check services with publish.sh
            if [ -f "$service_dir/publish.sh" ]; then
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if Lambda function exists
                local lambda_name="${clean_service_name}-${TEST_ENV}-"
                local lambda_functions
                lambda_functions=$(aws lambda list-functions --region "$TEST_REGION" --query "Functions[?starts_with(FunctionName, '$lambda_name')].FunctionName" --output text 2>/dev/null || echo "")
                
                if [ -n "$lambda_functions" ]; then
                    services_with_lambdas=$((services_with_lambdas + 1))
                    echo "  ✓ Lambda functions found for service: $service_name"
                    echo "    Functions: $lambda_functions"
                else
                    services_without_lambdas+=("$service_name: no Lambda functions found")
                fi
            else
                echo "  ⚠️  Skipping service without publish.sh: $service_name"
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
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if Lambda function exists
                local lambda_name="${clean_service_name}-${TEST_ENV}-"
                local lambda_functions
                lambda_functions=$(aws lambda list-functions --region "$TEST_REGION" --query "Functions[?starts_with(FunctionName, '$lambda_name')].FunctionName" --output text 2>/dev/null || echo "")
                
                if [ -n "$lambda_functions" ]; then
                    services_with_lambdas=$((services_with_lambdas + 1))
                    echo "  ✓ Lambda functions found for service: $service_name"
                    echo "    Functions: $lambda_functions"
                else
                    services_without_lambdas+=("$service_name: no Lambda functions found")
                fi
            else
                echo "  ⚠️  Skipping service without publish.sh: $service_name"
            fi
        done < <(find "$SERVICES_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#services_without_lambdas[@]} -eq 0 ] && [ $services_with_lambdas -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$services_with_lambdas services have deployed Lambda functions"
    elif [ $services_with_lambdas -eq 0 ] && [ ${#services_without_lambdas[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No services with publish.sh found (no deployments expected)"
    else
        local details="Deployed: $services_with_lambdas, Issues: ${services_without_lambdas[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_api_gateway_endpoints() {
    local test_name="API Gateway endpoints exist"
    echo "-> ${FUNCNAME[0]}"
    
    local services_with_apis=0
    local services_without_apis=()
    
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
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if API Gateway exists for this service
                local api_name="${TEST_ENV}-${clean_service_name}"
                local api_found
                api_found=$(echo "$rest_apis" | jq -r ".[] | select(.name == \"$api_name\") | .id" 2>/dev/null || echo "")
                
                if [ -n "$api_found" ]; then
                    services_with_apis=$((services_with_apis + 1))
                    echo "  ✓ API Gateway found for service: $service_name (API ID: $api_found)"
                else
                    services_without_apis+=("$service_name: no API Gateway found")
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
                # Get clean service name (strip leading digits)
                local clean_service_name
                clean_service_name=$(echo "$service_name" | sed 's/^[0-9_]*//g')
                
                # Check if API Gateway exists for this service
                local api_name="${TEST_ENV}-${clean_service_name}"
                local api_found
                api_found=$(echo "$rest_apis" | jq -r ".[] | select(.name == \"$api_name\") | .id" 2>/dev/null || echo "")
                
                if [ -n "$api_found" ]; then
                    services_with_apis=$((services_with_apis + 1))
                    echo "  ✓ API Gateway found for service: $service_name (API ID: $api_found)"
                else
                    services_without_apis+=("$service_name: no API Gateway found")
                fi
            fi
        done < <(find "$SERVICES_ENVS_DIR/$TEST_ENV" -maxdepth 1 -type d ! -path "$SERVICES_ENVS_DIR/$TEST_ENV" 2>/dev/null || true)
    fi
    
    if [ ${#services_without_apis[@]} -eq 0 ] && [ $services_with_apis -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$services_with_apis services have API Gateway endpoints"
    elif [ $services_with_apis -eq 0 ] && [ ${#services_without_apis[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No services with publish.sh found (no API endpoints expected)"
    else
        local details="APIs found: $services_with_apis, Issues: ${services_without_apis[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_lambda_function_health() {
    local test_name="Lambda functions are healthy"
    echo "-> ${FUNCNAME[0]}"
    
    local healthy_functions=0
    local unhealthy_functions=()
    
    # Get all Lambda functions for this environment
    local lambda_functions
    lambda_functions=$(aws lambda list-functions --region "$TEST_REGION" --query "Functions[?ends_with(FunctionName, '-$TEST_ENV-') || contains(FunctionName, '-$TEST_ENV-')].FunctionName" --output text 2>/dev/null || echo "")
    
    if [ -z "$lambda_functions" ]; then
        print_test_result "$test_name" "PASS" "No Lambda functions found for environment $TEST_ENV"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    # Check each Lambda function
    for function_name in $lambda_functions; do
        [ -z "$function_name" ] && continue
        
        echo "  Checking function: $function_name"
        
        # Get function configuration
        local function_state
        function_state=$(aws lambda get-function --function-name "$function_name" --region "$TEST_REGION" --query 'Configuration.State' --output text 2>/dev/null || echo "Unknown")
        
        local last_update_status
        last_update_status=$(aws lambda get-function --function-name "$function_name" --region "$TEST_REGION" --query 'Configuration.LastUpdateStatus' --output text 2>/dev/null || echo "Unknown")
        
        if [ "$function_state" = "Active" ] && [ "$last_update_status" = "Successful" ]; then
            healthy_functions=$((healthy_functions + 1))
            echo "    ✓ Function is healthy (State: $function_state, LastUpdate: $last_update_status)"
        else
            unhealthy_functions+=("$function_name: State=$function_state, LastUpdate=$last_update_status")
            echo "    ✗ Function has issues (State: $function_state, LastUpdate: $last_update_status)"
        fi
    done
    
    if [ ${#unhealthy_functions[@]} -eq 0 ] && [ $healthy_functions -gt 0 ]; then
        print_test_result "$test_name" "PASS" "$healthy_functions Lambda functions are healthy"
    elif [ $healthy_functions -eq 0 ] && [ ${#unhealthy_functions[@]} -eq 0 ]; then
        print_test_result "$test_name" "PASS" "No Lambda functions found (no health checks needed)"
    else
        local details="Healthy: $healthy_functions, Issues: ${unhealthy_functions[*]}"
        print_test_result "$test_name" "FAIL" "$details"
    fi
    
    echo "<- ${FUNCNAME[0]}"
}

test_serverless_deployment_bucket() {
    local test_name="Serverless deployment bucket accessible"
    echo "-> ${FUNCNAME[0]}"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        print_test_result "$test_name" "FAIL" "Config file not found: $CONFIG_FILE"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    # Get deployment bucket name from config
    local deployment_bucket
    deployment_bucket=$(yq -r '.services.abk_deployment_bucket' "$CONFIG_FILE" 2>/dev/null || echo "null")
    
    if [ -z "$deployment_bucket" ] || [ "$deployment_bucket" = "null" ]; then
        print_test_result "$test_name" "FAIL" "Could not determine deployment bucket from config"
        echo "<- ${FUNCNAME[0]}"
        return
    fi
    
    echo "  Checking bucket: $deployment_bucket"
    
    # Check if bucket exists and is accessible
    if aws s3api head-bucket --bucket "$deployment_bucket" 2>/dev/null; then
        # Check if bucket has serverless deployment files
        local deployment_files_count
        deployment_files_count=$(aws s3 ls "s3://$deployment_bucket" --recursive | grep -c "serverless\|cloudformation\|\.zip$" || echo "0")
        
        if [ "$deployment_files_count" -gt 0 ]; then
            print_test_result "$test_name" "PASS" "Bucket exists with $deployment_files_count deployment files"
        else
            print_test_result "$test_name" "PASS" "Bucket exists (ready for deployments)"
        fi
    else
        print_test_result "$test_name" "FAIL" "Deployment bucket does not exist or is not accessible: $deployment_bucket"
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
    test_serverless_deployment_bucket
    test_deployed_lambda_functions
    test_api_gateway_endpoints
    test_lambda_function_health
    
    print_test_summary
}

# Run tests
main "$@"