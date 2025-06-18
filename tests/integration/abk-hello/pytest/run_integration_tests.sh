#!/bin/bash

# Integration test runner for abk-hello service
# This script sets up the environment and runs integration tests
# against the deployed abk-hello service

set -eu

# Get project root directory (four levels up from tests/integration/abk-hello/pytest/)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB_FILE="$PROJECT_ROOT/common-lib.sh"

# Test configuration
TEST_ENV="${1:-dev}"
TEST_REGION="${2:-us-west-2}"
VERBOSE="${3:-false}"

# Source common library for utilities
if [ -f "$COMMON_LIB_FILE" ]; then
    # shellcheck source=../../../common-lib.sh
    source "$COMMON_LIB_FILE"
else
    echo "ERROR: $COMMON_LIB_FILE does not exist"
    exit 1
fi

#------------------------------------------------------------------------------
# Functions
#------------------------------------------------------------------------------
print_usage() {
    echo
    echo "Usage: $0 [ENVIRONMENT] [REGION] [VERBOSE]"
    echo
    echo "Parameters:"
    echo "  ENVIRONMENT  - Target environment (dev, qa, prod) [default: dev]"
    echo "  REGION       - AWS region [default: us-west-2]"
    echo "  VERBOSE      - Enable verbose output (true/false) [default: false]"
    echo
    echo "Environment Variables:"
    echo "  ABK_HELLO_API_URL           - Override API Gateway URL"
    echo "  ABK_DEPLOYMENT_ENV          - Override environment"
    echo "  ABK_DEPLOYMENT_REGION       - Override region"
    echo "  AWS_ACCESS_KEY_ID           - AWS credentials"
    echo "  AWS_SECRET_ACCESS_KEY       - AWS credentials"
    echo
    echo "Examples:"
    echo "  $0                          # Run tests against dev environment"
    echo "  $0 qa us-west-2            # Run tests against qa environment"
    echo "  $0 prod us-west-2 true     # Run tests against prod with verbose output"
    echo
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
            return 0
        fi
    fi
    
    PrintTrace "$TRACE_WARNING" "Could not discover API Gateway URL automatically"
    return 1
}

install_test_dependencies() {
    PrintTrace "$TRACE_INFO" "Installing test dependencies with UV..."
    
    # Check if UV is available
    if ! command -v uv >/dev/null 2>&1; then
        PrintTrace "$TRACE_ERROR" "UV not found. Please install UV first:"
        PrintTrace "$TRACE_ERROR" "  curl -LsSf https://astral.sh/uv/install.sh | sh"
        PrintTrace "$TRACE_ERROR" "  Or: pip install uv"
        return 1
    fi
    
    # Check if pyproject.toml exists
    if [ ! -f "$TEST_DIR/pyproject.toml" ]; then
        PrintTrace "$TRACE_ERROR" "pyproject.toml not found: $TEST_DIR/pyproject.toml"
        PrintTrace "$TRACE_ERROR" "Falling back to requirements.txt if available"
        
        if [ -f "$TEST_DIR/requirements.txt" ]; then
            uv pip install -r "$TEST_DIR/requirements.txt" --quiet
        else
            PrintTrace "$TRACE_ERROR" "Neither pyproject.toml nor requirements.txt found"
            return 1
        fi
    else
        # Install dependencies using UV
        (
            cd "$TEST_DIR" || exit 1
            uv sync --no-dev
        ) || {
            PrintTrace "$TRACE_ERROR" "Failed to install dependencies with UV"
            return 1
        }
    fi
    
    PrintTrace "$TRACE_INFO" "Test dependencies installed successfully with UV"
}

validate_aws_connectivity() {
    PrintTrace "$TRACE_INFO" "Validating AWS connectivity..."
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        PrintTrace "$TRACE_ERROR" "AWS CLI not configured or no connectivity"
        PrintTrace "$TRACE_ERROR" "Please configure AWS credentials:"
        PrintTrace "$TRACE_ERROR" "  export AWS_ACCESS_KEY_ID=your-key"
        PrintTrace "$TRACE_ERROR" "  export AWS_SECRET_ACCESS_KEY=your-secret"
        return 1
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
}

run_tests() {
    local api_url="$1"
    local verbose="$2"
    
    PrintTrace "$TRACE_INFO" "Running integration tests..."
    PrintTrace "$TRACE_INFO" "  API URL: $api_url"
    PrintTrace "$TRACE_INFO" "  Environment: $TEST_ENV"
    PrintTrace "$TRACE_INFO" "  Region: $TEST_REGION"
    
    # Set environment variables for tests
    export ABK_HELLO_API_URL="$api_url"
    export ABK_DEPLOYMENT_ENV="$TEST_ENV"
    export ABK_DEPLOYMENT_REGION="$TEST_REGION"
    
    # Build pytest command using UV
    local pytest_cmd=(
        "uv" "run" "pytest"
        "$TEST_DIR/test_abk_hello_integration.py"
        "--tb=short"
        "-m" "integration"
    )
    
    # Add verbose output if requested
    if [ "$verbose" = "true" ]; then
        pytest_cmd+=("-v" "-s")
    fi
    
    # Add HTML report
    pytest_cmd+=(
        "--html=$TEST_DIR/integration_test_report.html"
        "--self-contained-html"
    )
    
    # Add JSON report
    pytest_cmd+=(
        "--json-report"
        "--json-report-file=$TEST_DIR/integration_test_report.json"
    )
    
    PrintTrace "$TRACE_INFO" "Running command: ${pytest_cmd[*]}"
    
    # Change to test directory and run tests
    (
        cd "$TEST_DIR" || exit 1
        "${pytest_cmd[@]}"
    )
}

print_test_summary() {
    local exit_code="$1"
    
    echo
    echo "=================================================================="
    echo "INTEGRATION TEST SUMMARY"
    echo "=================================================================="
    
    if [ -f "$TEST_DIR/integration_test_report.json" ]; then
        local summary
        if summary=$(jq -r '.summary' "$TEST_DIR/integration_test_report.json" 2>/dev/null); then
            echo "Test Results:"
            echo "$summary" | jq -r '. | "  Passed: \(.passed // 0)", "  Failed: \(.failed // 0)", "  Skipped: \(.skipped // 0)", "  Total: \(.total // 0)"'
        fi
    fi
    
    echo "Environment: $TEST_ENV"
    echo "Region: $TEST_REGION"
    
    if [ -f "$TEST_DIR/integration_test_report.html" ]; then
        echo "HTML Report: $TEST_DIR/integration_test_report.html"
    fi
    
    if [ -f "$TEST_DIR/integration_test_report.json" ]; then
        echo "JSON Report: $TEST_DIR/integration_test_report.json"
    fi
    
    echo "=================================================================="
    
    if [ "$exit_code" -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "${GRN}✅ ALL INTEGRATION TESTS PASSED${NC}"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ INTEGRATION TESTS FAILED${NC}"
        echo "Please check the test output and reports for details."
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
        exit 0
    fi
    
    # Validate parameters
    IsPredefinedParameterValid "$TEST_ENV" "${ENV_ARRAY[@]}" || {
        PrintTrace "$TRACE_ERROR" "Invalid environment: $TEST_ENV"
        print_usage
        exit 1
    }
    
    IsPredefinedParameterValid "$TEST_REGION" "${REGION_ARRAY[@]}" || {
        PrintTrace "$TRACE_ERROR" "Invalid region: $TEST_REGION"
        print_usage
        exit 1
    }
    
    echo
    echo "🧪 ABK-HELLO INTEGRATION TESTS"
    echo "=================================================================="
    echo "Environment: $TEST_ENV"
    echo "Region: $TEST_REGION"
    echo "Test Directory: $TEST_DIR"
    echo "=================================================================="
    
    # Install test dependencies
    install_test_dependencies || exit 1
    
    # Validate AWS connectivity
    validate_aws_connectivity || exit 1
    
    # Get API URL (from environment variable or discover it)
    local api_url="$ABK_HELLO_API_URL"
    if [ -z "$api_url" ]; then
        if ! api_url=$(discover_api_url "$TEST_ENV" "$TEST_REGION"); then
            PrintTrace "$TRACE_ERROR" "Could not determine API Gateway URL"
            PrintTrace "$TRACE_ERROR" "Please set ABK_HELLO_API_URL environment variable"
            PrintTrace "$TRACE_ERROR" "Example: export ABK_HELLO_API_URL=https://your-api-id.execute-api.us-west-2.amazonaws.com/dev"
            exit 1
        fi
    fi
    
    # Run the integration tests
    local exit_code=0
    run_tests "$api_url" "$VERBOSE" || exit_code=$?
    
    # Print summary
    print_test_summary "$exit_code"
    
    PrintTrace "$TRACE_FUNCTION" "<- $0 ($exit_code)"
    echo
    exit "$exit_code"
}

# Run main function
main "$@"