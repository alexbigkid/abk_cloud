#!/bin/bash

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
    echo "$0 deploys serverless services"
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

DeployService() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_SERVICE="$1"
    local LCL_EXIT_CODE=0
    local LCL_SERVICE_NAME
    LCL_SERVICE_NAME=$(basename "$LCL_SERVICE")

    # Only deploy if service has a publish.sh script
    if [ ! -f "$LCL_SERVICE/publish.sh" ]; then
        PrintTrace "$TRACE_INFO" "Skipping service without publish.sh: $LCL_SERVICE_NAME"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "${YLW}Deploying service: $LCL_SERVICE_NAME${NC}"
    (
        cd "$LCL_SERVICE" || exit "$?"
        chmod +x publish.sh || exit "$?"
        ./publish.sh "$ABK_DEPLOYMENT_ENV" "$ABK_DEPLOYMENT_REGION" || exit "$?"
    ) || LCL_EXIT_CODE="$?"

    if [ "$LCL_EXIT_CODE" -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "${GRN}✅ Service deployed successfully: $LCL_SERVICE_NAME${NC}"
    else
        PrintTrace "$TRACE_ERROR" "${RED}❌ Service deployment failed: $LCL_SERVICE_NAME${NC}"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

DeploySequentialServices() {
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

    # Find services that start with 3 digits (sequential services)
    LCL_SERVICES=$(find "$LCL_WORKING_DIR/$LCL_ENV" -maxdepth 1 -type d -name '[0-9][0-9][0-9]_*' | sort)

    if [ -z "$LCL_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No sequential services found in $LCL_WORKING_DIR/$LCL_ENV"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Sequential services found:"
    PrintTrace "$TRACE_INFO" "$LCL_SERVICES"

    while IFS= read -r SERVICE; do
        [ -z "$SERVICE" ] && continue
        DeployService "$SERVICE" || LCL_EXIT_CODE="$?"
        [ "$LCL_EXIT_CODE" -ne 0 ] && break
    done <<< "$LCL_SERVICES"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

DeployParallelServices() {
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

    # Find services that do NOT start with 3 digits (parallel services)
    LCL_SERVICES=$(find "$LCL_WORKING_DIR/$LCL_ENV" -maxdepth 1 -type d ! -path "$LCL_WORKING_DIR/$LCL_ENV" ! -name '[0-9][0-9][0-9]_*' | sort)

    if [ -z "$LCL_SERVICES" ]; then
        PrintTrace "$TRACE_INFO" "No parallel services found in $LCL_WORKING_DIR/$LCL_ENV"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Parallel services found:"
    PrintTrace "$TRACE_INFO" "$LCL_SERVICES"

    # Check if parallel tool is available
    if ! command -v parallel > /dev/null 2>&1; then
        PrintTrace "$TRACE_WARNING" "parallel tool not found, deploying services sequentially instead"
        while IFS= read -r SERVICE; do
            [ -z "$SERVICE" ] && continue
            DeployService "$SERVICE" || LCL_EXIT_CODE="$?"
            [ "$LCL_EXIT_CODE" -ne 0 ] && break
        done <<< "$LCL_SERVICES"
    else
        PrintTrace "$TRACE_INFO" "Using parallel tool to deploy services"
        # Export function and variables for parallel
        export -f DeployService PrintTrace
        export TRACE_FUNCTION TRACE_INFO TRACE_ERROR TRACE_WARNING YLW NC GRN RED
        export ABK_DEPLOYMENT_ENV ABK_DEPLOYMENT_REGION

        if ! echo "$LCL_SERVICES" | parallel --halt now,fail=1 DeployService; then
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

# Step 1: Deploy sequential services from common directory
PrintTrace "$TRACE_INFO" "Step 1: Deploying sequential services from common directory"
DeploySequentialServices "$SERVICES_ENVS_DIR" "common" || EXIT_CODE="$?"

# Step 2: Deploy sequential services from environment directory
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "Step 2: Deploying sequential services from $ABK_DEPLOYMENT_ENV directory"
    DeploySequentialServices "$SERVICES_ENVS_DIR" "$ABK_DEPLOYMENT_ENV" || EXIT_CODE="$?"
fi

# Step 3: Deploy parallel services from common directory
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "Step 3: Deploying parallel services from common directory"
    DeployParallelServices "$SERVICES_ENVS_DIR" "common" || EXIT_CODE="$?"
fi

# Step 4: Deploy parallel services from environment directory
if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "Step 4: Deploying parallel services from $ABK_DEPLOYMENT_ENV directory"
    DeployParallelServices "$SERVICES_ENVS_DIR" "$ABK_DEPLOYMENT_ENV" || EXIT_CODE="$?"
fi

if [ "$EXIT_CODE" -eq 0 ]; then
    PrintTrace "$TRACE_INFO" "${GRN}🎉 All services deployed successfully!${NC}"
else
    PrintTrace "$TRACE_ERROR" "${RED}❌ Service deployment failed with exit code: $EXIT_CODE${NC}"
fi

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit "$EXIT_CODE"