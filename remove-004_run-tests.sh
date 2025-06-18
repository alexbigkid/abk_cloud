#!/bin/bash

# Remove Phase 004: Clean up Integration Test Reports
# This script cleans up integration test reports and artifacts
# It's the counterpart to deploy-004_run-tests.sh but focuses on cleanup

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
    echo "$0 cleans up integration test reports and artifacts"
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

CleanupTestArtifacts() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_TEST_SERVICE_DIR="$1"
    local LCL_EXIT_CODE=0
    local LCL_SERVICE_NAME
    LCL_SERVICE_NAME=$(basename "$LCL_TEST_SERVICE_DIR")

    # Skip if directory doesn't exist
    if [ ! -d "$LCL_TEST_SERVICE_DIR" ]; then
        PrintTrace "$TRACE_INFO" "Directory does not exist: $LCL_SERVICE_NAME"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "${YLW}Cleaning test artifacts for: $LCL_SERVICE_NAME${NC}"
    
    # Clean up test reports and artifacts
    (
        cd "$LCL_TEST_SERVICE_DIR" || exit "$?"
        
        # Remove HTML test reports
        find . -name "*test_report.html" -type f -delete 2>/dev/null || true
        find . -name "integration_test_report.html" -type f -delete 2>/dev/null || true
        find . -name "tavern_test_report.html" -type f -delete 2>/dev/null || true
        
        # Remove JSON test reports
        find . -name "*test_report.json" -type f -delete 2>/dev/null || true
        find . -name "integration_test_report.json" -type f -delete 2>/dev/null || true
        find . -name "tavern_test_report.json" -type f -delete 2>/dev/null || true
        
        # Remove pytest cache
        find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        find . -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
        
        # Remove coverage reports
        find . -name ".coverage" -type f -delete 2>/dev/null || true
        find . -name "htmlcov" -type d -exec rm -rf {} + 2>/dev/null || true
        find . -name "coverage.xml" -type f -delete 2>/dev/null || true
        
        # Remove UV cache and lock files (optional cleanup)
        # Note: Keeping uv.lock as it's version controlled, but cleaning up any temporary files
        find . -name ".uv_cache" -type d -exec rm -rf {} + 2>/dev/null || true
        
        # Remove any temporary test files
        find . -name "*.tmp" -type f -delete 2>/dev/null || true
        find . -name "temp_*" -type f -delete 2>/dev/null || true
        
        PrintTrace "$TRACE_INFO" "✅ Cleaned test artifacts for: $LCL_SERVICE_NAME"
    ) || LCL_EXIT_CODE="$?"

    if [ "$LCL_EXIT_CODE" -ne 0 ]; then
        PrintTrace "$TRACE_WARNING" "${YLW}⚠️  Some cleanup operations failed for: $LCL_SERVICE_NAME${NC}"
        # Don't fail the overall process for cleanup issues
        LCL_EXIT_CODE=0
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

CleanupSequentialTestArtifacts() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_WORKING_DIR="$1"
    local LCL_EXIT_CODE=0
    local LCL_TEST_SERVICES

    if [ ! -d "$LCL_WORKING_DIR" ]; then
        PrintTrace "$TRACE_INFO" "Directory does not exist: $LCL_WORKING_DIR"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    # Find test services that start with 3 digits (sequential tests) and sort them in reverse order
    LCL_TEST_SERVICES=$(find "$LCL_WORKING_DIR" -maxdepth 1 -type d -name '[0-9][0-9][0-9]_*' | sort -r)

    if [ -z "$LCL_TEST_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No sequential integration test artifacts found in $LCL_WORKING_DIR"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Sequential integration test cleanup (reverse order):"
    PrintTrace "$TRACE_INFO" "$LCL_TEST_SERVICES"

    while IFS= read -r TEST_SERVICE; do
        [ -z "$TEST_SERVICE" ] && continue
        CleanupTestArtifacts "$TEST_SERVICE" || LCL_EXIT_CODE="$?"
        # Continue cleanup even if one service fails
    done <<< "$LCL_TEST_SERVICES"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

CleanupParallelTestArtifacts() {
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
    LCL_TEST_SERVICES=$(find "$LCL_WORKING_DIR" -maxdepth 1 -type d ! -path "$LCL_WORKING_DIR" ! -name '[0-9][0-9][0-9]_*' | sort -r)

    if [ -z "$LCL_TEST_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No parallel integration test artifacts found in $LCL_WORKING_DIR"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Parallel integration test cleanup:"
    PrintTrace "$TRACE_INFO" "$LCL_TEST_SERVICES"

    # Check if parallel tool is available
    if ! command -v parallel > /dev/null 2>&1; then
        PrintTrace "$TRACE_WARNING" "parallel tool not found, cleaning artifacts sequentially instead"
        while IFS= read -r TEST_SERVICE; do
            [ -z "$TEST_SERVICE" ] && continue
            CleanupTestArtifacts "$TEST_SERVICE" || LCL_EXIT_CODE="$?"
            # Continue cleanup even if one service fails
        done <<< "$LCL_TEST_SERVICES"
    else
        PrintTrace "$TRACE_INFO" "Using parallel tool to clean test artifacts"
        # Export function and variables for parallel
        export -f CleanupTestArtifacts PrintTrace
        export TRACE_FUNCTION TRACE_INFO TRACE_ERROR TRACE_WARNING YLW NC GRN RED
        export TRACE_LEVEL TRACE_NONE TRACE_CRITICAL TRACE_ERROR TRACE_WARNING TRACE_FUNCTION TRACE_INFO TRACE_DEBUG TRACE_ALL
        export ABK_DEPLOYMENT_ENV ABK_DEPLOYMENT_REGION

        # Use parallel without halt-on-fail for cleanup (we want to clean everything possible)
        echo "$LCL_TEST_SERVICES" | parallel CleanupTestArtifacts || true
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

CleanupGlobalTestArtifacts() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_EXIT_CODE=0

    PrintTrace "$TRACE_INFO" "Cleaning up global integration test artifacts..."

    # Remove global summary report
    if [ -f "integration_test_summary.json" ]; then
        rm -f "integration_test_summary.json" || true
        PrintTrace "$TRACE_INFO" "Removed global test summary report"
    fi

    # Remove any global test artifacts in the project root
    find . -maxdepth 1 -name "*test_report*.html" -type f -delete 2>/dev/null || true
    find . -maxdepth 1 -name "*test_report*.json" -type f -delete 2>/dev/null || true
    find . -maxdepth 1 -name "integration_test_*" -type f -delete 2>/dev/null || true

    PrintTrace "$TRACE_INFO" "Global test artifacts cleanup completed"
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
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
echo "🧹 CLEANING INTEGRATION TEST ARTIFACTS"
echo "=================================================================="
echo "Cleaning up integration test reports and artifacts"
echo "Environment: $ABK_DEPLOYMENT_ENV"
echo "Region: $ABK_DEPLOYMENT_REGION"
echo "=================================================================="

# Check if integration tests directory exists
if [ ! -d "$INTEGRATION_TESTS_DIR" ]; then
    PrintTrace "$TRACE_WARNING" "Integration tests directory not found: $INTEGRATION_TESTS_DIR"
    PrintTrace "$TRACE_INFO" "No test artifacts to clean up"
    echo
    echo "=================================================================="
    PrintTrace "$TRACE_INFO" "${YLW}⚠️  NO INTEGRATION TEST DIRECTORY FOUND${NC}"
    echo "Nothing to clean up in $INTEGRATION_TESTS_DIR"
    echo "=================================================================="
else
    # Step 1: Clean parallel integration test artifacts first
    PrintTrace "$TRACE_INFO" "Step 1: Cleaning parallel integration test artifacts"
    CleanupParallelTestArtifacts "$INTEGRATION_TESTS_DIR" || EXIT_CODE="$?"

    # Step 2: Clean sequential integration test artifacts (reverse order)
    PrintTrace "$TRACE_INFO" "Step 2: Cleaning sequential integration test artifacts (reverse order)"
    CleanupSequentialTestArtifacts "$INTEGRATION_TESTS_DIR" || EXIT_CODE="$?"
fi

# Step 3: Clean global test artifacts
PrintTrace "$TRACE_INFO" "Step 3: Cleaning global test artifacts"
CleanupGlobalTestArtifacts || EXIT_CODE="$?"

echo
echo "=================================================================="
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "${GRN}✅ INTEGRATION TEST CLEANUP COMPLETED${NC}"
    echo "All integration test artifacts have been cleaned up"
else
    PrintTrace "$TRACE_WARNING" "${YLW}⚠️  INTEGRATION TEST CLEANUP COMPLETED WITH WARNINGS${NC}"
    echo "Some cleanup operations encountered issues but the process completed"
    echo "Exit code: $EXIT_CODE"
fi
echo "=================================================================="

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit "$EXIT_CODE"