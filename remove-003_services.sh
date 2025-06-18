#!/bin/bash

# Remove serverless services - exact reverse of deploy-003_services.sh
# This script removes serverless services in reverse order:
# 1. Environment-specific parallel services
# 2. Environment-specific sequential services (reverse order)
# 3. Common parallel services
# 4. Common sequential services (reverse order)

# e: stop if any errors
# u: Treat unset variables and parameters as an error
set -eu

EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMS=2
COMMON_LIB_FILE="common-lib.sh"
SERVICES_ENVS_DIR="services/envs"

#------------------------------------------------------------------------------
# functions
#------------------------------------------------------------------------------
PrintUsageAndExitWithCode() {
    echo
    echo "$0 removes serverless services"
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

RemoveService() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_SERVICE="$1"
    local LCL_EXIT_CODE=0
    local LCL_SERVICE_NAME
    LCL_SERVICE_NAME=$(basename "$LCL_SERVICE")

    # Only remove if service has a publish.sh script
    if [ ! -f "$LCL_SERVICE/publish.sh" ]; then
        PrintTrace "$TRACE_INFO" "Skipping service without publish.sh: $LCL_SERVICE_NAME"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "${YLW}Removing service: $LCL_SERVICE_NAME${NC}"
    (
        cd "$LCL_SERVICE" || exit "$?"
        # Use serverless remove command to delete the service
        serverless remove --stage "$ABK_DEPLOYMENT_ENV" --region "$ABK_DEPLOYMENT_REGION" || exit "$?"
    ) || LCL_EXIT_CODE="$?"

    if [ "$LCL_EXIT_CODE" -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "${GRN}✅ Service removed successfully: $LCL_SERVICE_NAME${NC}"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Service removal failed: $LCL_SERVICE_NAME${NC}"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

RemoveSequentialServices() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_WORKING_DIR="$1"
    local LCL_ENV="$2"
    local LCL_EXIT_CODE=0
    local LCL_SERVICES

    if [ ! -d "$LCL_WORKING_DIR/$LCL_ENV" ]; then
        PrintTrace "$TRACE_INFO" "Directory does not exist: $LCL_WORKING_DIR/$LCL_ENV"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    # Find services that start with 3 digits (sequential services) and sort in REVERSE order for removal
    LCL_SERVICES=$(find "$LCL_WORKING_DIR/$LCL_ENV" -maxdepth 1 -type d -name '[0-9][0-9][0-9]_*' | sort -r)

    if [ -z "$LCL_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No sequential services found in $LCL_WORKING_DIR/$LCL_ENV"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Sequential services found (removing in reverse order):"
    PrintTrace "$TRACE_INFO" "$LCL_SERVICES"

    while IFS= read -r SERVICE; do
        [ -z "$SERVICE" ] && continue
        RemoveService "$SERVICE" || LCL_EXIT_CODE="$?"
        [ "$LCL_EXIT_CODE" -ne 0 ] && break
    done <<< "$LCL_SERVICES"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

RemoveParallelServices() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_WORKING_DIR="$1"
    local LCL_ENV="$2"
    local LCL_EXIT_CODE=0
    local LCL_SERVICES

    if [ ! -d "$LCL_WORKING_DIR/$LCL_ENV" ]; then
        PrintTrace "$TRACE_INFO" "Directory does not exist: $LCL_WORKING_DIR/$LCL_ENV"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    # Find services that do NOT start with 3 digits (parallel services) and reverse sort for removal
    LCL_SERVICES=$(find "$LCL_WORKING_DIR/$LCL_ENV" -maxdepth 1 -type d ! -path "$LCL_WORKING_DIR/$LCL_ENV" ! -name '[0-9][0-9][0-9]_*' | sort -r)

    if [ -z "$LCL_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No parallel services found in $LCL_WORKING_DIR/$LCL_ENV"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Parallel services found (removing in reverse order):"
    PrintTrace "$TRACE_INFO" "$LCL_SERVICES"

    # Check if parallel tool is available
    if ! command -v parallel > /dev/null 2>&1; then
        PrintTrace "$TRACE_WARNING" "parallel tool not found, removing services sequentially instead"
        while IFS= read -r SERVICE; do
            [ -z "$SERVICE" ] && continue
            RemoveService "$SERVICE" || LCL_EXIT_CODE="$?"
            [ "$LCL_EXIT_CODE" -ne 0 ] && break
        done <<< "$LCL_SERVICES"
    else
        PrintTrace "$TRACE_INFO" "Using parallel tool to remove services"
        # Export function and variables for parallel
        export -f RemoveService PrintTrace
        export TRACE_FUNCTION TRACE_INFO TRACE_ERROR TRACE_WARNING YLW NC GRN RED
        export ABK_DEPLOYMENT_ENV ABK_DEPLOYMENT_REGION

        if ! echo "$LCL_SERVICES" | parallel --halt now,fail=1 RemoveService; then
            LCL_EXIT_CODE="$EXIT_CODE_DEPLOYMENT_FAILED"
        fi
    fi

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
echo "🗑️  REMOVING SERVERLESS SERVICES"
echo "=================================================================="
echo "Removing services in reverse order of deployment"
echo "Environment: $ABK_DEPLOYMENT_ENV"
echo "Region: $ABK_DEPLOYMENT_REGION"
echo "=================================================================="

# Step 1: Remove parallel services from environment directory (reverse of deploy step 4)
PrintTrace "$TRACE_INFO" "Step 1: Removing parallel services from $ABK_DEPLOYMENT_ENV directory"
RemoveParallelServices "$SERVICES_ENVS_DIR" "$ABK_DEPLOYMENT_ENV" || EXIT_CODE="$?"

# Step 2: Remove parallel services from common directory (reverse of deploy step 3)
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "Step 2: Removing parallel services from common directory"
    RemoveParallelServices "$SERVICES_ENVS_DIR" "common" || EXIT_CODE="$?"
fi

# Step 3: Remove sequential services from environment directory (reverse of deploy step 2)
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "Step 3: Removing sequential services from $ABK_DEPLOYMENT_ENV directory (reverse order)"
    RemoveSequentialServices "$SERVICES_ENVS_DIR" "$ABK_DEPLOYMENT_ENV" || EXIT_CODE="$?"
fi

# Step 4: Remove sequential services from common directory (reverse of deploy step 1)
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "Step 4: Removing sequential services from common directory (reverse order)"
    RemoveSequentialServices "$SERVICES_ENVS_DIR" "common" || EXIT_CODE="$?"
fi

echo
echo "=================================================================="
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "${GRN}✅ SERVERLESS SERVICES REMOVAL COMPLETE${NC}"
    echo "All serverless services have been successfully removed"
else
    PrintTrace "$TRACE_ERROR" "${RED}❌ SERVERLESS SERVICES REMOVAL FAILED${NC}"
    echo "Some services may still exist - check logs above"
    echo "Exit code: $EXIT_CODE"
fi
echo "=================================================================="

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit "$EXIT_CODE"