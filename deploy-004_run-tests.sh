#!/bin/bash

# Deploy Phase 004: Run Integration Tests
# This script discovers and executes integration tests for all deployed services
# Each service directory in tests/integration/ should contain a run_tests.sh script

# e: stop if any errors
# u: Treat unset variables and parameters as an error
set -eu

EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMS=2
COMMON_LIB_FILE="common-lib.sh"
INTEGRATION_TESTS_DIR="tests/integration"

#------------------------------------------------------------------------------
# functions
#------------------------------------------------------------------------------
PrintUsageAndExitWithCode() {
    echo
    echo "$0 runs integration tests for deployed services"
    echo "This script ($0) must be called with $EXPECTED_NUMBER_OF_PARAMS parameters."
    echo "  1st parameter Environment: dev, qa or prod"
    echo "  2nd parameter Region: us-west-2 is supported at the moment"
    echo "  The AWS_ACCESS_KEY_ID environment variable needs to be setup"
    echo "  The AWS_SECRET_ACCESS_KEY environment variable needs to be setup"
    echo
    echo "  $0 --help           - display this info"
    echo
    echo -e "$2"
    exit "$1"
}

RunIntegrationTests() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_TEST_SERVICE_DIR="$1"
    local LCL_EXIT_CODE=0
    local LCL_SERVICE_NAME
    LCL_SERVICE_NAME=$(basename "$LCL_TEST_SERVICE_DIR")

    # Only run tests if directory has a run_tests.sh script
    if [ ! -f "$LCL_TEST_SERVICE_DIR/run_tests.sh" ]; then
        PrintTrace "$TRACE_INFO" "Skipping service without run_tests.sh: $LCL_SERVICE_NAME"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "${YLW}Running integration tests for: $LCL_SERVICE_NAME${NC}"
    (
        cd "$LCL_TEST_SERVICE_DIR" || exit "$?"
        chmod +x run_tests.sh || exit "$?"
        ./run_tests.sh "$ABK_DEPLOYMENT_ENV" "$ABK_DEPLOYMENT_REGION" || exit "$?"
    ) || LCL_EXIT_CODE="$?"

    if [ "$LCL_EXIT_CODE" -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "${GRN}✅ Integration tests passed for: $LCL_SERVICE_NAME${NC}"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Integration tests failed for: $LCL_SERVICE_NAME${NC}"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

RunSequentialIntegrationTests() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_WORKING_DIR="$1"
    local LCL_EXIT_CODE=0
    local LCL_TEST_SERVICES

    if [ ! -d "$LCL_WORKING_DIR" ]; then
        PrintTrace "$TRACE_INFO" "Directory does not exist: $LCL_WORKING_DIR"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    # Find test services that start with 3 digits (sequential tests) and sort them
    LCL_TEST_SERVICES=$(find "$LCL_WORKING_DIR" -maxdepth 1 -type d -name '[0-9][0-9][0-9]_*' | sort)

    if [ -z "$LCL_TEST_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No sequential integration tests found in $LCL_WORKING_DIR"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Sequential integration tests found:"
    PrintTrace "$TRACE_INFO" "$LCL_TEST_SERVICES"

    while IFS= read -r TEST_SERVICE; do
        [ -z "$TEST_SERVICE" ] && continue
        RunIntegrationTests "$TEST_SERVICE" || LCL_EXIT_CODE="$?"
        [ "$LCL_EXIT_CODE" -ne 0 ] && break
    done <<< "$LCL_TEST_SERVICES"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

RunParallelIntegrationTests() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_WORKING_DIR="$1"
    local LCL_EXIT_CODE=0
    local LCL_TEST_SERVICES

    if [ ! -d "$LCL_WORKING_DIR" ]; then
        PrintTrace "$TRACE_INFO" "Directory does not exist: $LCL_WORKING_DIR"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    # Find test services that do NOT start with 3 digits (parallel tests)
    LCL_TEST_SERVICES=$(find "$LCL_WORKING_DIR" -maxdepth 1 -type d ! -path "$LCL_WORKING_DIR" ! -name '[0-9][0-9][0-9]_*' | sort)

    if [ -z "$LCL_TEST_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No parallel integration tests found in $LCL_WORKING_DIR"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Parallel integration tests found:"
    PrintTrace "$TRACE_INFO" "$LCL_TEST_SERVICES"

    # Check if parallel tool is available
    if ! command -v parallel > /dev/null 2>&1; then
        PrintTrace "$TRACE_WARNING" "parallel tool not found, running tests sequentially instead"
        while IFS= read -r TEST_SERVICE; do
            [ -z "$TEST_SERVICE" ] && continue
            RunIntegrationTests "$TEST_SERVICE" || LCL_EXIT_CODE="$?"
            [ "$LCL_EXIT_CODE" -ne 0 ] && break
        done <<< "$LCL_TEST_SERVICES"
    else
        PrintTrace "$TRACE_INFO" "Using parallel tool to run integration tests"
        # Export function and variables for parallel
        export -f RunIntegrationTests PrintTrace
        export TRACE_FUNCTION TRACE_INFO TRACE_ERROR TRACE_WARNING YLW NC GRN RED
        export TRACE_LEVEL TRACE_NONE TRACE_CRITICAL TRACE_ERROR TRACE_WARNING TRACE_FUNCTION TRACE_INFO TRACE_DEBUG TRACE_ALL
        export ABK_DEPLOYMENT_ENV ABK_DEPLOYMENT_REGION
        export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
        export PATH NODE_PATH
        # Export discovered API URL for tests
        export ABK_HELLO_API_URL

        if ! echo "$LCL_TEST_SERVICES" | parallel --halt now,fail=1 RunIntegrationTests; then
            LCL_EXIT_CODE="$EXIT_CODE_DEPLOYMENT_FAILED"
        fi
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

GenerateTestSummaryReport() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE="$1"
    local LCL_SUMMARY_FILE="integration_test_summary.json"
    local LCL_TOTAL_PASSED=0
    local LCL_TOTAL_FAILED=0
    local LCL_TOTAL_SKIPPED=0
    local LCL_TOTAL_TESTS=0
    local LCL_SERVICES_TESTED=0

    PrintTrace "$TRACE_INFO" "Generating integration test summary report..."

    # Create summary header
    cat > "$LCL_SUMMARY_FILE" << EOF
{
  "summary": {
    "environment": "$ABK_DEPLOYMENT_ENV",
    "region": "$ABK_DEPLOYMENT_REGION",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "overall_result": "$([ "$LCL_EXIT_CODE" -eq 0 ] && echo "PASS" || echo "FAIL")",
    "services": [
EOF

    # Find all test report files and aggregate results
    local LCL_FIRST_SERVICE=true
    while IFS= read -r REPORT_FILE; do
        [ -z "$REPORT_FILE" ] && continue
        [ ! -f "$REPORT_FILE" ] && continue
        
        local SERVICE_DIR
        SERVICE_DIR=$(dirname "$REPORT_FILE")
        local SERVICE_NAME
        SERVICE_NAME=$(basename "$SERVICE_DIR")
        
        if [ "$LCL_FIRST_SERVICE" = true ]; then
            LCL_FIRST_SERVICE=false
        else
            echo "," >> "$LCL_SUMMARY_FILE"
        fi
        
        # Extract summary from individual service report
        if command -v jq >/dev/null 2>&1 && jq -e '.summary' "$REPORT_FILE" >/dev/null 2>&1; then
            local SERVICE_SUMMARY
            SERVICE_SUMMARY=$(jq '.summary' "$REPORT_FILE")
            local PASSED
            PASSED=$(echo "$SERVICE_SUMMARY" | jq -r '.passed // 0')
            local FAILED
            FAILED=$(echo "$SERVICE_SUMMARY" | jq -r '.failed // 0')
            local SKIPPED
            SKIPPED=$(echo "$SERVICE_SUMMARY" | jq -r '.skipped // 0')
            local TOTAL
            TOTAL=$(echo "$SERVICE_SUMMARY" | jq -r '.total // 0')
            
            LCL_TOTAL_PASSED=$((LCL_TOTAL_PASSED + PASSED))
            LCL_TOTAL_FAILED=$((LCL_TOTAL_FAILED + FAILED))
            LCL_TOTAL_SKIPPED=$((LCL_TOTAL_SKIPPED + SKIPPED))
            LCL_TOTAL_TESTS=$((LCL_TOTAL_TESTS + TOTAL))
            
            cat >> "$LCL_SUMMARY_FILE" << EOF
      {
        "service": "$SERVICE_NAME",
        "passed": $PASSED,
        "failed": $FAILED,
        "skipped": $SKIPPED,
        "total": $TOTAL,
        "result": "$([ "$FAILED" -eq 0 ] && echo "PASS" || echo "FAIL")",
        "report_file": "$REPORT_FILE"
      }
EOF
        else
            # Fallback for services without detailed JSON reports
            cat >> "$LCL_SUMMARY_FILE" << EOF
      {
        "service": "$SERVICE_NAME",
        "passed": 0,
        "failed": 0,
        "skipped": 0,
        "total": 0,
        "result": "UNKNOWN",
        "report_file": "$REPORT_FILE"
      }
EOF
        fi
        
        LCL_SERVICES_TESTED=$((LCL_SERVICES_TESTED + 1))
    done < <(find "$INTEGRATION_TESTS_DIR" -name "*test_report.json" 2>/dev/null || true)

    # Close services array and add totals
    cat >> "$LCL_SUMMARY_FILE" << EOF
    ],
    "totals": {
      "services_tested": $LCL_SERVICES_TESTED,
      "total_passed": $LCL_TOTAL_PASSED,
      "total_failed": $LCL_TOTAL_FAILED,
      "total_skipped": $LCL_TOTAL_SKIPPED,
      "total_tests": $LCL_TOTAL_TESTS
    }
  }
}
EOF

    PrintTrace "$TRACE_INFO" "Integration test summary generated: $LCL_SUMMARY_FILE"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}

#------------------------------------------------------------------------------
# main
#------------------------------------------------------------------------------
# include common library, fail if does not exist
if [ -f "$COMMON_LIB_FILE" ]; then
# shellcheck disable=SC1091
# shellcheck source=./common-lib.sh
    source "$COMMON_LIB_FILE"
else
    echo "ERROR: $COMMON_LIB_FILE does not exist in the local directory."
    echo "  $COMMON_LIB_FILE contains common definitions and functions"
    exit 1
fi

echo
PrintTrace "$TRACE_FUNCTION" "-> $0 ($*)"

# ----------------------
# parameter validation
# ----------------------
IsParameterHelp "$#" "$1" && PrintUsageAndExitWithCode "$EXIT_CODE_SUCCESS" "---- Help displayed ----"
CheckNumberOfParameters "$EXPECTED_NUMBER_OF_PARAMS" "$@" || PrintUsageAndExitWithCode "$EXIT_CODE_INVALID_NUMBER_OF_PARAMETERS" "${RED}ERROR: Invalid number of parameters${NC}"
IsPredefinedParameterValid "$1" "${ENV_ARRAY[@]}" || PrintUsageAndExitWithCode "$EXIT_CODE_NOT_VALID_PARAMETER" "${RED}ERROR: Invalid ENV parameter${NC}"
IsPredefinedParameterValid "$2" "${REGION_ARRAY[@]}" || PrintUsageAndExitWithCode "$EXIT_CODE_NOT_VALID_PARAMETER" "${RED}ERROR: Invalid REGION parameter${NC}"
[ "$AWS_ACCESS_KEY_ID" == "" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: AWS_ACCESS_KEY_ID is not set${NC}"
[ "$AWS_SECRET_ACCESS_KEY" == "" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: AWS_SECRET_ACCESS_KEY is not set${NC}"
[ "$ABK_DEPLOYMENT_ENV" != "$1" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: $ABK_DEPLOYMENT_ENV != $1\\nPlease set ${GRN}ABK_DEPLOYMENT_ENV${RED} in .envrc to ${GRN}$1${RED} to generate correct values in config.$1.yml${NC}"

ABK_DEPLOYMENT_ENV="$1"
ABK_DEPLOYMENT_REGION="$2"

echo
echo "🧪 RUNNING INTEGRATION TESTS"
echo "=================================================================="
echo "Running integration tests for deployed services"
echo "Environment: $ABK_DEPLOYMENT_ENV"
echo "Region: $ABK_DEPLOYMENT_REGION"
echo "=================================================================="

# Check if integration tests directory exists
if [ ! -d "$INTEGRATION_TESTS_DIR" ]; then
    PrintTrace "$TRACE_WARNING" "Integration tests directory not found: $INTEGRATION_TESTS_DIR"
    PrintTrace "$TRACE_INFO" "Skipping integration tests - no tests to run"
    echo
    echo "=================================================================="
    PrintTrace "$TRACE_INFO" "${YLW}⚠️  NO INTEGRATION TESTS FOUND${NC}"
    echo "Create tests in $INTEGRATION_TESTS_DIR/<service-name>/ with run_tests.sh scripts"
    echo "=================================================================="
    PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
    echo
    exit "$EXIT_CODE"
fi

# Discover API URLs for all services before running tests
DiscoverServiceApiUrls() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    
    # For now, we'll focus on abk-hello service
    # TODO: Make this dynamic for multiple services
    if [ -z "${ABK_HELLO_API_URL:-}" ]; then
        local service_name="${ABK_DEPLOYMENT_ENV}-abk-hello"
        PrintTrace "$TRACE_INFO" "Discovering API Gateway URL for service: $service_name"
        
        local api_info
        if api_info=$(aws apigateway get-rest-apis \
            --region "$ABK_DEPLOYMENT_REGION" \
            --query "items[?name=='$service_name'].{id:id,name:name}" \
            --output json 2>/dev/null); then
            
            local api_id
            if api_id=$(echo "$api_info" | jq -r '.[0].id // empty' 2>/dev/null) && [ -n "$api_id" ] && [ "$api_id" != "null" ]; then
                ABK_HELLO_API_URL="https://${api_id}.execute-api.${ABK_DEPLOYMENT_REGION}.amazonaws.com/${ABK_DEPLOYMENT_ENV}"
                PrintTrace "$TRACE_INFO" "Discovered ABK_HELLO_API_URL: $ABK_HELLO_API_URL"
                export ABK_HELLO_API_URL
            else
                PrintTrace "$TRACE_WARNING" "Could not discover API Gateway URL for $service_name"
                PrintTrace "$TRACE_WARNING" "Please set ABK_HELLO_API_URL environment variable manually"
            fi
        else
            PrintTrace "$TRACE_WARNING" "Failed to query API Gateway for $service_name"
        fi
    else
        PrintTrace "$TRACE_INFO" "Using existing ABK_HELLO_API_URL: $ABK_HELLO_API_URL"
    fi
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
}

# Discover API URLs before running tests
DiscoverServiceApiUrls

# Step 1: Run sequential integration tests first
PrintTrace "$TRACE_INFO" "Step 1: Running sequential integration tests"
RunSequentialIntegrationTests "$INTEGRATION_TESTS_DIR" || EXIT_CODE="$?"

# Step 2: Run parallel integration tests
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "Step 2: Running parallel integration tests"
    RunParallelIntegrationTests "$INTEGRATION_TESTS_DIR" || EXIT_CODE="$?"
fi

# Generate summary report
GenerateTestSummaryReport "$EXIT_CODE"

echo
echo "=================================================================="
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "${GRN}✅ INTEGRATION TESTS COMPLETED SUCCESSFULLY${NC}"
    echo "All integration tests passed for environment: $ABK_DEPLOYMENT_ENV"
else
    PrintTrace "$TRACE_ERROR" "${RED}❌ INTEGRATION TESTS FAILED${NC}"
    echo "Some integration tests failed - check individual service reports"
    echo "Exit code: $EXIT_CODE"
fi
echo "=================================================================="

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit "$EXIT_CODE"