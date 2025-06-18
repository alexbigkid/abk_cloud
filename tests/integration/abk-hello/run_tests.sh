#!/bin/bash

# Unified integration test runner for abk-hello service
# This script orchestrates both pytest and Tavern test suites
# and provides a single entry point for all integration testing

set -eu

# Get project root directory (three levels up from tests/integration/abk-hello/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TEST_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTEST_DIR="$TEST_ROOT_DIR/pytest"
TAVERN_DIR="$TEST_ROOT_DIR/tavern"
COMMON_LIB_FILE="$PROJECT_ROOT/common-lib.sh"

# Test configuration
TEST_ENV="${1:-dev}"
TEST_REGION="${2:-us-west-2}"
VERBOSE="${3:-false}"
TEST_SUITE="${4:-all}"  # all, pytest, tavern

# Exit codes
EXIT_CODE_SUCCESS=0
EXIT_CODE_GENERAL_ERROR=1
EXIT_CODE_INVALID_PARAMETERS=2

# Source common library for utilities
if [ -f "$COMMON_LIB_FILE" ]; then
    # shellcheck source=../../../common-lib.sh
    source "$COMMON_LIB_FILE"
else
    echo "ERROR: $COMMON_LIB_FILE does not exist"
    exit $EXIT_CODE_GENERAL_ERROR
fi

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------
print_usage() {
    echo
    echo "Usage: $0 [ENVIRONMENT] [REGION] [VERBOSE] [TEST_SUITE]"
    echo
    echo "Parameters:"
    echo "  ENVIRONMENT  - Target environment (dev, qa, prod) [default: dev]"
    echo "  REGION       - AWS region [default: us-west-2]"
    echo "  VERBOSE      - Enable verbose output (true/false) [default: false]"
    echo "  TEST_SUITE   - Test suite to run (all/pytest/tavern) [default: all]"
    echo
    echo "Environment Variables:"
    echo "  ABK_HELLO_API_URL           - Override API Gateway URL"
    echo "  ABK_DEPLOYMENT_ENV          - Override environment"
    echo "  ABK_DEPLOYMENT_REGION       - Override region"
    echo "  AWS_ACCESS_KEY_ID           - AWS credentials"
    echo "  AWS_SECRET_ACCESS_KEY       - AWS credentials"
    echo
    echo "Examples:"
    echo "  $0                          # Run all tests against dev environment"
    echo "  $0 qa us-west-2            # Run all tests against qa environment"
    echo "  $0 dev us-west-2 true      # Run all tests with verbose output"
    echo "  $0 dev us-west-2 false pytest  # Run only pytest tests"
    echo "  $0 dev us-west-2 false tavern  # Run only Tavern tests"
    echo
    echo "Test Suites:"
    echo "  pytest/  - Python-based integration tests"
    echo "  tavern/  - YAML-based API tests using Tavern framework"
    echo
}

validate_parameters() {
    PrintTrace "$TRACE_INFO" "Validating parameters..."
    
    # Validate environment
    if ! IsPredefinedParameterValid "$TEST_ENV" "${ENV_ARRAY[@]}"; then
        PrintTrace "$TRACE_ERROR" "Invalid environment: $TEST_ENV"
        print_usage
        return $EXIT_CODE_INVALID_PARAMETERS
    fi
    
    # Validate region
    if ! IsPredefinedParameterValid "$TEST_REGION" "${REGION_ARRAY[@]}"; then
        PrintTrace "$TRACE_ERROR" "Invalid region: $TEST_REGION"
        print_usage
        return $EXIT_CODE_INVALID_PARAMETERS
    fi
    
    # Validate test suite
    local valid_suites=("all" "pytest" "tavern")
    if ! IsPredefinedParameterValid "$TEST_SUITE" "${valid_suites[@]}"; then
        PrintTrace "$TRACE_ERROR" "Invalid test suite: $TEST_SUITE"
        print_usage
        return $EXIT_CODE_INVALID_PARAMETERS
    fi
    
    PrintTrace "$TRACE_INFO" "Parameters validated successfully"
    return $EXIT_CODE_SUCCESS
}

discover_api_url() {
    local env="$1"
    local region="$2"
    local service_name="${env}-abk-hello"
    
    PrintTrace "$TRACE_INFO" "Discovering API Gateway URL for service: $service_name"
    
    # Try to get API Gateway info using AWS CLI
    local api_info
    if api_info=$(aws apigateway get-rest-apis \
        --region "$region" \
        --query "items[?name=='$service_name'].{id:id,name:name}" \
        --output json 2>/dev/null); then
        
        local api_id
        if api_id=$(echo "$api_info" | jq -r '.[0].id // empty' 2>/dev/null) && [ -n "$api_id" ] && [ "$api_id" != "null" ]; then
            local api_url="https://${api_id}.execute-api.${region}.amazonaws.com/${env}"
            PrintTrace "$TRACE_INFO" "Discovered API URL: $api_url"
            echo "$api_url"
            return $EXIT_CODE_SUCCESS
        fi
    fi
    
    PrintTrace "$TRACE_WARNING" "Could not discover API Gateway URL automatically"
    return $EXIT_CODE_GENERAL_ERROR
}

validate_aws_connectivity() {
    PrintTrace "$TRACE_INFO" "Validating AWS connectivity..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        PrintTrace "$TRACE_ERROR" "AWS CLI not configured or no connectivity"
        PrintTrace "$TRACE_ERROR" "Please configure AWS credentials:"
        PrintTrace "$TRACE_ERROR" "  export AWS_ACCESS_KEY_ID=your-key"
        PrintTrace "$TRACE_ERROR" "  export AWS_SECRET_ACCESS_KEY=your-secret"
        return $EXIT_CODE_GENERAL_ERROR
    fi
    
    local caller_identity
    caller_identity=$(aws sts get-caller-identity 2>/dev/null)
    local account_id
    account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null || echo "unknown")
    local user_arn
    user_arn=$(echo "$caller_identity" | jq -r '.Arn' 2>/dev/null || echo "unknown")
    
    PrintTrace "$TRACE_INFO" "AWS connectivity validated"
    PrintTrace "$TRACE_INFO" "  Account ID: $account_id"
    PrintTrace "$TRACE_INFO" "  User/Role: $user_arn"
    PrintTrace "$TRACE_INFO" "  Region: $TEST_REGION"
    
    return $EXIT_CODE_SUCCESS
}

run_pytest_tests() {
    local api_url="$1"
    local verbose="$2"
    
    PrintTrace "$TRACE_INFO" "${YLW}🧪 Running pytest integration tests...${NC}"
    
    if [ ! -d "$PYTEST_DIR" ]; then
        PrintTrace "$TRACE_ERROR" "Pytest directory not found: $PYTEST_DIR"
        return $EXIT_CODE_GENERAL_ERROR
    fi
    
    if [ ! -f "$PYTEST_DIR/run_integration_tests.sh" ]; then
        PrintTrace "$TRACE_ERROR" "Pytest runner not found: $PYTEST_DIR/run_integration_tests.sh"
        return $EXIT_CODE_GENERAL_ERROR
    fi
    
    # Set environment variables for pytest tests
    export ABK_HELLO_API_URL="$api_url"
    export ABK_DEPLOYMENT_ENV="$TEST_ENV"
    export ABK_DEPLOYMENT_REGION="$TEST_REGION"
    
    # Run pytest tests
    (
        cd "$PYTEST_DIR" || exit $EXIT_CODE_GENERAL_ERROR
        ./run_integration_tests.sh "$TEST_ENV" "$TEST_REGION" "$verbose"
    )
}

run_tavern_tests() {
    local api_url="$1"
    local verbose="$2"
    
    PrintTrace "$TRACE_INFO" "${YLW}🏛️  Running Tavern integration tests...${NC}"
    
    if [ ! -d "$TAVERN_DIR" ]; then
        PrintTrace "$TRACE_ERROR" "Tavern directory not found: $TAVERN_DIR"
        return $EXIT_CODE_GENERAL_ERROR
    fi
    
    if [ ! -f "$TAVERN_DIR/run_tavern_tests.sh" ]; then
        PrintTrace "$TRACE_ERROR" "Tavern runner not found: $TAVERN_DIR/run_tavern_tests.sh"
        return $EXIT_CODE_GENERAL_ERROR
    fi
    
    # Set environment variables for Tavern tests
    export ABK_HELLO_API_URL="$api_url"
    export ABK_DEPLOYMENT_ENV="$TEST_ENV"
    export ABK_DEPLOYMENT_REGION="$TEST_REGION"
    
    # Run Tavern tests
    (
        cd "$TAVERN_DIR" || exit $EXIT_CODE_GENERAL_ERROR
        ./run_tavern_tests.sh "$TEST_ENV" "$TEST_REGION" "$verbose"
    )
}

generate_combined_report() {
    local overall_exit_code="$1"
    
    echo
    echo "=================================================================="
    echo "COMBINED INTEGRATION TEST SUMMARY"
    echo "=================================================================="
    
    # Count results from both test suites
    local pytest_results=""
    local tavern_results=""
    local total_passed=0
    local total_failed=0
    local total_skipped=0
    local total_tests=0
    
    # Parse pytest results if available
    if [ -f "$PYTEST_DIR/integration_test_report.json" ]; then
        if pytest_results=$(jq -r '.summary' "$PYTEST_DIR/integration_test_report.json" 2>/dev/null); then
            local pytest_passed
            pytest_passed=$(echo "$pytest_results" | jq -r '.passed // 0')
            local pytest_failed
            pytest_failed=$(echo "$pytest_results" | jq -r '.failed // 0')
            local pytest_skipped
            pytest_skipped=$(echo "$pytest_results" | jq -r '.skipped // 0')
            local pytest_total
            pytest_total=$(echo "$pytest_results" | jq -r '.total // 0')
            
            echo "Pytest Results:"
            echo "  Passed: $pytest_passed"
            echo "  Failed: $pytest_failed"
            echo "  Skipped: $pytest_skipped"
            echo "  Total: $pytest_total"
            
            total_passed=$((total_passed + pytest_passed))
            total_failed=$((total_failed + pytest_failed))
            total_skipped=$((total_skipped + pytest_skipped))
            total_tests=$((total_tests + pytest_total))
        fi
    fi
    
    # Parse Tavern results if available
    if [ -f "$TAVERN_DIR/tavern_test_report.json" ]; then
        if tavern_results=$(jq -r '.summary' "$TAVERN_DIR/tavern_test_report.json" 2>/dev/null); then
            local tavern_passed
            tavern_passed=$(echo "$tavern_results" | jq -r '.passed // 0')
            local tavern_failed
            tavern_failed=$(echo "$tavern_results" | jq -r '.failed // 0')
            local tavern_skipped
            tavern_skipped=$(echo "$tavern_results" | jq -r '.skipped // 0')
            local tavern_total
            tavern_total=$(echo "$tavern_results" | jq -r '.total // 0')
            
            echo "Tavern Results:"
            echo "  Passed: $tavern_passed"
            echo "  Failed: $tavern_failed"
            echo "  Skipped: $tavern_skipped"
            echo "  Total: $tavern_total"
            
            total_passed=$((total_passed + tavern_passed))
            total_failed=$((total_failed + tavern_failed))
            total_skipped=$((total_skipped + tavern_skipped))
            total_tests=$((total_tests + tavern_total))
        fi
    fi
    
    echo
    echo "Combined Results:"
    echo "  Total Passed: $total_passed"
    echo "  Total Failed: $total_failed"
    echo "  Total Skipped: $total_skipped"
    echo "  Total Tests: $total_tests"
    echo
    echo "Environment: $TEST_ENV"
    echo "Region: $TEST_REGION"
    echo "Test Suite: $TEST_SUITE"
    
    # Show report locations
    if [ -f "$PYTEST_DIR/integration_test_report.html" ]; then
        echo "Pytest HTML Report: $PYTEST_DIR/integration_test_report.html"
    fi
    if [ -f "$TAVERN_DIR/tavern_test_report.html" ]; then
        echo "Tavern HTML Report: $TAVERN_DIR/tavern_test_report.html"
    fi
    
    echo "=================================================================="
    
    if [ "$overall_exit_code" -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "${GRN}✅ ALL INTEGRATION TESTS PASSED${NC}"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ INTEGRATION TESTS FAILED${NC}"
        echo "Please check the individual test reports for details."
    fi
}

#------------------------------------------------------------------------------
# Main execution
#------------------------------------------------------------------------------
main() {
    echo
    PrintTrace "$TRACE_FUNCTION" "-> $0 ($*)"
    
    # Handle help request
    if [ $# -gt 0 ] && [ "$1" = "--help" ]; then
        print_usage
        exit $EXIT_CODE_SUCCESS
    fi
    
    # Validate parameters
    if ! validate_parameters; then
        exit $EXIT_CODE_INVALID_PARAMETERS
    fi
    
    echo
    echo "🧪 ABK-HELLO INTEGRATION TEST SUITE"
    echo "=================================================================="
    echo "Environment: $TEST_ENV"
    echo "Region: $TEST_REGION"
    echo "Test Suite: $TEST_SUITE"
    echo "Verbose: $VERBOSE"
    echo "Test Directory: $TEST_ROOT_DIR"
    echo "=================================================================="
    
    # Validate AWS connectivity
    if ! validate_aws_connectivity; then
        exit $EXIT_CODE_GENERAL_ERROR
    fi
    
    # Get API URL (from environment variable or discover it)
    local api_url="$ABK_HELLO_API_URL"
    if [ -z "$api_url" ]; then
        if ! api_url=$(discover_api_url "$TEST_ENV" "$TEST_REGION"); then
            PrintTrace "$TRACE_ERROR" "Could not determine API Gateway URL"
            PrintTrace "$TRACE_ERROR" "Please set ABK_HELLO_API_URL environment variable"
            PrintTrace "$TRACE_ERROR" "Example: export ABK_HELLO_API_URL=https://your-api-id.execute-api.us-west-2.amazonaws.com/dev"
            exit $EXIT_CODE_GENERAL_ERROR
        fi
    fi
    
    # Track overall exit code
    local overall_exit_code=$EXIT_CODE_SUCCESS
    
    # Run test suites based on selection
    case "$TEST_SUITE" in
        "pytest")
            if ! run_pytest_tests "$api_url" "$VERBOSE"; then
                overall_exit_code=$EXIT_CODE_GENERAL_ERROR
            fi
            ;;
        "tavern")
            if ! run_tavern_tests "$api_url" "$VERBOSE"; then
                overall_exit_code=$EXIT_CODE_GENERAL_ERROR
            fi
            ;;
        "all")
            # Run pytest first, then Tavern
            if ! run_pytest_tests "$api_url" "$VERBOSE"; then
                overall_exit_code=$EXIT_CODE_GENERAL_ERROR
            fi
            
            echo
            PrintTrace "$TRACE_INFO" "Proceeding to Tavern tests..."
            echo
            
            if ! run_tavern_tests "$api_url" "$VERBOSE"; then
                overall_exit_code=$EXIT_CODE_GENERAL_ERROR
            fi
            ;;
        *)
            PrintTrace "$TRACE_ERROR" "Invalid test suite: $TEST_SUITE"
            exit $EXIT_CODE_INVALID_PARAMETERS
            ;;
    esac
    
    # Generate combined report
    generate_combined_report "$overall_exit_code"
    
    PrintTrace "$TRACE_FUNCTION" "<- $0 ($overall_exit_code)"
    echo
    exit "$overall_exit_code"
}

# Run main function
main "$@"