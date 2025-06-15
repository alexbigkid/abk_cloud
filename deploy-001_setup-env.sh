#!/bin/bash

# e: stop if any errors
# u: Treat unset variables and parameters as an error
# set -eu

EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMS=2
COMMON_LIB_FILE="common-lib.sh"
CONFIG_FILE="config.yml"
TERRAFORM_ENVS_DIR="terraform/envs"


#------------------------------------------------------------------------------
# functions
#------------------------------------------------------------------------------
PrintUsageAndExitWithCode() {
    echo
    echo "$0 setups environment configuration"
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


SetupTerraformVariables() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_PROJECT=$1
    local LCL_ENV=$2
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"
    local LCL_TF_VARS_FILE="$LCL_PROJECT/terraform.tfvars.json"
    local LCL_EXIT_CODE=0

    local LCL_PROJECT_NAME
    LCL_PROJECT_NAME=$(basename "$LCL_PROJECT")
    
    # Determine terraform project key name
    local LCL_TERRAFORM_PRJ_KEY
    if [[ "$LCL_PROJECT_NAME" =~ ^[0-9][0-9][0-9]_ ]]; then
        # Sequential project: split by '_' and get the part after the digits
        local LCL_TERRAFORM_PRJ
        IFS='_' read -ra LCL_TERRAFORM_PRJ <<< "$LCL_PROJECT_NAME"
        LCL_TERRAFORM_PRJ_KEY="${LCL_TERRAFORM_PRJ[1]}"
        PrintTrace "$TRACE_DEBUG" "Sequential project - LCL_TERRAFORM_PRJ_KEY = $LCL_TERRAFORM_PRJ_KEY"
    else
        # Parallel project: use the full project name
        LCL_TERRAFORM_PRJ_KEY="$LCL_PROJECT_NAME"
        PrintTrace "$TRACE_DEBUG" "Parallel project - LCL_TERRAFORM_PRJ_KEY = $LCL_TERRAFORM_PRJ_KEY"
    fi

    # parse config yaml file only for the project related settings
    local LCL_PROJECT_TF_VARS_JSON
    LCL_PROJECT_TF_VARS_JSON=$(yq -o=json ".terraform.$LCL_TERRAFORM_PRJ_KEY" "$LCL_ENV_CONFIG")
    PrintTrace "$TRACE_DEBUG" "LCL_PROJECT_TF_VARS_JSON = $LCL_PROJECT_TF_VARS_JSON"

    # write env configured terraform vars file to project directory
    printf "%s" "$LCL_PROJECT_TF_VARS_JSON" > "$LCL_TF_VARS_FILE"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}

SetupTerraformBackend() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_PROJECT="$1"
    local LCL_ENV="$2"
    local LCL_EXIT_CODE=0
    local LCL_PROJECT_NAME
    LCL_PROJECT_NAME=$(basename "$LCL_PROJECT")
    
    # Skip backend generation for terraformStateBootstrap modules
    if [[ "$LCL_PROJECT_NAME" =~ terraformStateBootstrap ]]; then
        PrintTrace "$TRACE_INFO" "Skipping backend.tf generation for bootstrap module: $LCL_PROJECT_NAME"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi
    
    local LCL_BACKEND_TEMPLATE="terraform/templates/backend.tf.template"
    local LCL_BACKEND_FILE="$LCL_PROJECT/backend.tf"
    
    if [ ! -f "$LCL_BACKEND_TEMPLATE" ]; then
        PrintTrace "$TRACE_ERROR" "Backend template not found: $LCL_BACKEND_TEMPLATE"
        LCL_EXIT_CODE=1
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi
    
    # Determine project name for backend key
    local LCL_TERRAFORM_PROJECT_NAME
    if [[ "$LCL_PROJECT_NAME" =~ ^[0-9][0-9][0-9]_ ]]; then
        # Sequential project: split by '_' and get the part after the digits
        local LCL_TERRAFORM_PRJ
        IFS='_' read -ra LCL_TERRAFORM_PRJ <<< "$LCL_PROJECT_NAME"
        LCL_TERRAFORM_PROJECT_NAME="${LCL_TERRAFORM_PRJ[1]}"
    else
        # Parallel project: use the full project name
        LCL_TERRAFORM_PROJECT_NAME="$LCL_PROJECT_NAME"
    fi
    
    PrintTrace "$TRACE_INFO" "Generating backend.tf for project: $LCL_PROJECT_NAME"
    PrintTrace "$TRACE_DEBUG" "Template: $LCL_BACKEND_TEMPLATE"
    PrintTrace "$TRACE_DEBUG" "Output: $LCL_BACKEND_FILE"
    PrintTrace "$TRACE_DEBUG" "Backend key project name: $LCL_TERRAFORM_PROJECT_NAME"
    
    # Set and export variables for envsubst from configuration
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"
    
    # Extract backend configuration values from the environment config
    export TERRAFORM_STATE_S3_BUCKET_NAME
    TERRAFORM_STATE_S3_BUCKET_NAME=$(yq -r ".terraform.terraformStateBootstrap.terraform_state_S3_bucket_name" "$LCL_ENV_CONFIG")
    export DYNAMODB_TERRAFORM_LOCK_NAME
    DYNAMODB_TERRAFORM_LOCK_NAME=$(yq -r ".terraform.terraformStateBootstrap.dynamodb_terraform_lock_name" "$LCL_ENV_CONFIG")
    export ABK_DEPLOYMENT_ENV="$LCL_ENV"
    export ABK_DEPLOYMENT_REGION
    export TERRAFORM_PROJECT_NAME="$LCL_TERRAFORM_PROJECT_NAME"
    
    PrintTrace "$TRACE_DEBUG" "Backend S3 bucket: $TERRAFORM_STATE_S3_BUCKET_NAME"
    PrintTrace "$TRACE_DEBUG" "Backend DynamoDB table: $DYNAMODB_TERRAFORM_LOCK_NAME"
    
    # Generate backend.tf from template
    if ! envsubst < "$LCL_BACKEND_TEMPLATE" > "$LCL_BACKEND_FILE"; then
        PrintTrace "$TRACE_ERROR" "Failed to generate backend.tf for $LCL_PROJECT_NAME"
        LCL_EXIT_CODE=1
    else
        PrintTrace "$TRACE_INFO" "Generated backend.tf for $LCL_PROJECT_NAME"
    fi
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}


SetupTerraformProjects() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_WORKING_DIR=$1
    local LCL_DIR_ENV=$2        # Directory environment (common, dev, qa, prod)
    local LCL_CONFIG_ENV=$3     # Config environment to use (dev, qa, prod)
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

    PrintTrace "$TRACE_INFO" "Terraform projects found in $LCL_DIR_ENV:"
    PrintTrace "$TRACE_INFO" "$LCL_TERRAFORM_PROJECTS"

    # Process all terraform projects
    for PROJECT in $LCL_TERRAFORM_PROJECTS; do
        SetupTerraformVariables "$PROJECT" "$LCL_CONFIG_ENV" || LCL_EXIT_CODE=$?
        SetupTerraformBackend "$PROJECT" "$LCL_CONFIG_ENV" || LCL_EXIT_CODE=$?
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
[ "$AWS_ACCESS_KEY_ID" == "" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: AWS_ACCESS_KEY_ID is not set${NC}"
[ "$AWS_SECRET_ACCESS_KEY" == "" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: AWS_SECRET_ACCESS_KEY is not set${NC}"
[ "$ABK_PRJ_NAME" == "" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: ABK_PRJ_NAME is not set${NC}"
[ "$LOG_LEVEL" == "" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: LOG_LEVEL is not set${NC}"
[ "$ABK_DEPLOYMENT_ENV" != "$1" ] && PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: $ABK_DEPLOYMENT_ENV != $1\nPlease set ${GRN}ABK_DEPLOYMENT_ENV${RED} in .envrc to ${GRN}$1${RED} to generate correct values in config.$1.yml${NC}"

ABK_DEPLOYMENT_ENV=$1
ABK_DEPLOYMENT_REGION=$2

CreateEnvConfigFile ENV_CONFIG_FILE "$ABK_DEPLOYMENT_ENV" "$CONFIG_FILE" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Failed to create config file for env: $ABK_DEPLOYMENT_ENV${NC}"
WriteValueToConfigFile "$ENV_CONFIG_FILE" ABK_DEPLOYMENT_ENV "$ABK_DEPLOYMENT_ENV" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Failed to write ABK_DEPLOYMENT_ENV: $ABK_DEPLOYMENT_ENV to config file${NC}"
WriteValueToConfigFile "$ENV_CONFIG_FILE" ABK_DEPLOYMENT_REGION "$ABK_DEPLOYMENT_REGION" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Failed to write ABK_DEPLOYMENT_ENV: $ABK_DEPLOYMENT_REGION to config file${NC}"

# GetCognitoUsersPoolArn ABK_USERS_POOL_ARN "$ABK_USERS_POOL_NAME" || PrintUsageAndExitWithCode $EXIT_CODE_GENERAL_ERROR "${RED}ERROR: Could not find ARN for $ABK_USERS_POOL_NAME ${NC}"
# WriteValueToConfigFile "$ENV_CONFIG_FILE" ABK_USERS_POOL_ARN "$ABK_USERS_POOL_ARN" || PrintUsageAndExitWithCode $EXIT_CODE_GENERAL_ERROR "${RED}ERROR: Failed to write ABK_USERS_POOL_ARN: $ABK_USERS_POOL_ARN to config file${NC}"

WriteValueToConfigFile "$ENV_CONFIG_FILE" ABK_PRJ_NAME "$ABK_PRJ_NAME" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Failed to write ABK_PRJ_NAME: $ABK_PRJ_NAME to config file${NC}"
WriteValueToConfigFile "$ENV_CONFIG_FILE" LOG_LEVEL "$LOG_LEVEL" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Failed to write LOG_LEVEL: $LOG_LEVEL to config file${NC}"


# Setup terraform projects for common and environment-specific directories
# Note: common projects use the actual deployment environment config file
SetupTerraformProjects "$TERRAFORM_ENVS_DIR" "common" "$ABK_DEPLOYMENT_ENV" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Setup Terraform Projects failed for common${NC}"
SetupTerraformProjects "$TERRAFORM_ENVS_DIR" "$ABK_DEPLOYMENT_ENV" "$ABK_DEPLOYMENT_ENV" || PrintUsageAndExitWithCode "$EXIT_CODE_GENERAL_ERROR" "${RED}ERROR: Setup Terraform Projects failed for $ABK_DEPLOYMENT_ENV${NC}"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
