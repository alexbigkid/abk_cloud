#!/bin/bash

# e: stop if any errors
# u: Treat unset variables and parameters as an error
# set -eu

EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMS=2
COMMON_LIB_FILE="common-lib.sh"
# shellcheck disable=SC2034
CONFIG_FILE="config.yml"  # Keep for future use/reference
TERRAFORM_ENVS_DIR="terraform/envs"


#------------------------------------------------------------------------------
# functions
#------------------------------------------------------------------------------
PrintUsageAndExitWithCode() {
    echo
    echo "$0 removes environment configuration"
    echo "This script ($0) must be called with $EXPECTED_NUMBER_OF_PARAMS parameters."
    echo "  1st parameter Environment: dev, qa or prod"
    echo "  2nd parameter Region: us-west-2 is supported at the moment"
    echo
    echo "  $0 --help           - display this info"
    echo
    echo -e "$2"
    exit "$1"
}


RemoveTerraformVariables() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_PROJECT=$1
    local LCL_TF_VARS_FILE="$LCL_PROJECT/terraform.tfvars.json"
    local LCL_EXIT_CODE=0

    if [ -f "$LCL_TF_VARS_FILE" ]; then
        PrintTrace "$TRACE_INFO" "Removing terraform vars file: $LCL_TF_VARS_FILE"
        rm -f "$LCL_TF_VARS_FILE" || LCL_EXIT_CODE=$?
    else
        PrintTrace "$TRACE_DEBUG" "Terraform vars file does not exist: $LCL_TF_VARS_FILE"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

RemoveTerraformBackend() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_PROJECT="$1"
    local LCL_BACKEND_FILE="$LCL_PROJECT/backend.tf"
    local LCL_EXIT_CODE=0
    local LCL_PROJECT_NAME
    LCL_PROJECT_NAME=$(basename "$LCL_PROJECT")

    # Skip backend removal for terraformStateBootstrap modules (they don't have backend.tf)
    if [[ "$LCL_PROJECT_NAME" =~ terraformStateBootstrap ]]; then
        PrintTrace "$TRACE_DEBUG" "Skipping backend.tf removal for bootstrap module: $LCL_PROJECT_NAME"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    if [ -f "$LCL_BACKEND_FILE" ]; then
        PrintTrace "$TRACE_INFO" "Removing terraform backend file: $LCL_BACKEND_FILE"
        rm -f "$LCL_BACKEND_FILE" || LCL_EXIT_CODE=$?
    else
        PrintTrace "$TRACE_DEBUG" "Terraform backend file does not exist: $LCL_BACKEND_FILE"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}


RemoveTerraformProjects() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_WORKING_DIR=$1
    local LCL_DIR_ENV=$2        # Directory environment (common, dev, qa, prod)
    local LCL_EXIT_CODE=0
    local LCL_TERRAFORM_PROJECTS
    
    # Skip if directory doesn't exist
    if [ ! -d "$LCL_WORKING_DIR/$LCL_DIR_ENV" ]; then
        PrintTrace "$TRACE_INFO" "Directory does not exist: $LCL_WORKING_DIR/$LCL_DIR_ENV"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi
    
    # Find all terraform project directories (excluding parent directory)
    LCL_TERRAFORM_PROJECTS=$(find "$LCL_WORKING_DIR/$LCL_DIR_ENV" -maxdepth 1 -type d ! -path "$LCL_WORKING_DIR/$LCL_DIR_ENV" | sort)

    PrintTrace "$TRACE_INFO" "Removing terraform vars from projects in $LCL_DIR_ENV:"
    PrintTrace "$TRACE_INFO" "$LCL_TERRAFORM_PROJECTS"

    # Remove terraform vars and backend files from all projects
    for PROJECT in $LCL_TERRAFORM_PROJECTS; do
        RemoveTerraformVariables "$PROJECT" || LCL_EXIT_CODE=$?
        RemoveTerraformBackend "$PROJECT" || LCL_EXIT_CODE=$?
    done

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

#------------------------------------------------------------------------------
# main
#------------------------------------------------------------------------------
# include common library, fail if does not exist
if [ -f "$COMMON_LIB_FILE" ]; then
# shellcheck disable=SC1091
# shellcheck source=../common-lib.sh
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
IsParameterHelp $# "$1" && PrintUsageAndExitWithCode "$EXIT_CODE_SUCCESS" "---- Help displayed ----"
# shellcheck disable=SC2068
CheckNumberOfParameters "$EXPECTED_NUMBER_OF_PARAMS" $@ || PrintUsageAndExitWithCode "$EXIT_CODE_INVALID_NUMBER_OF_PARAMETERS" "${RED}ERROR: Invalid number of parameters${NC}"
IsPredefinedParameterValid "$1" "${ENV_ARRAY[@]}" || PrintUsageAndExitWithCode "$EXIT_CODE_NOT_VALID_PARAMETER" "${RED}ERROR: Invalid ENV parameter${NC}"
IsPredefinedParameterValid "$2" "${REGION_ARRAY[@]}" || PrintUsageAndExitWithCode "$EXIT_CODE_NOT_VALID_PARAMETER" "${RED}ERROR: Invalid REGION parameter${NC}"

ABK_DEPLOYMENT_ENV=$1
# shellcheck disable=SC2034
ABK_DEPLOYMENT_REGION=$2  # Keep for consistency with other scripts

# Remove generated environment config file
ENV_CONFIG_FILE="config.$ABK_DEPLOYMENT_ENV.yml"
if [ -f "$ENV_CONFIG_FILE" ]; then
    PrintTrace "$TRACE_INFO" "Removing environment config file: $ENV_CONFIG_FILE"
    rm -f "$ENV_CONFIG_FILE" || EXIT_CODE=$?
else
    PrintTrace "$TRACE_DEBUG" "Environment config file does not exist: $ENV_CONFIG_FILE"
fi

# Remove terraform variable files from common and environment-specific directories
RemoveTerraformProjects "$TERRAFORM_ENVS_DIR" "common" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Remove Terraform Projects failed for common${NC}"
RemoveTerraformProjects "$TERRAFORM_ENVS_DIR" "$ABK_DEPLOYMENT_ENV" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Remove Terraform Projects failed for $ABK_DEPLOYMENT_ENV${NC}"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE