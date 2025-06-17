#!/bin/bash

# e: stop if any errors
# u: Treat unset variables and parameters as an error
set -eu

EXIT_CODE=0
MIN_NUMBER_OF_PARAMS=2
MAX_NUMBER_OF_PARAMS=3
COMMON_LIB_FILE="../common-lib.sh"
TEMPLATE_NAME_FOR_TYPESCRIPT="templates/abk-typescript-template"
TEMPLATE_NAME_FOR_PYTHON="templates/abk-python-template"
# declare -a SUPPORTED_TYPES_ARRAY=("py" "ts")
declare -a SUPPORTED_TYPES_ARRAY=("py")
declare -a SUPPORTED_ENV_ARRAY=("common" "dev" "qa" "prod")
DEFAULT_ENV="common"

TS_NODE_DEPENDENCIES=(
)
TS_NODE_DEV_DEPENDENCIES=(
    '@jest/globals'
    '@types/aws-lambda'
    '@types/jest'
    '@types/jsonwebtoken'
    '@types/node'
    '@types/pg'
    'esbuild'
    'jest'
    'serverless@^3.0.0'
    'serverless-deployment-bucket'
    'serverless-domain-manager'
    'serverless-esbuild'
    'serverless-latest-layer-version'
    'serverless-prune-plugin'
    'ts-jest'
    'ts-mock-imports'
    'typescript@~5.1.0'
)



#------------------------------------------------------------------------------
# functions
#------------------------------------------------------------------------------
PrintUsageAndExitWithCode() {
    echo
    echo "$0 creates service from a template"
    echo "This script ($0) must be called with 2 or 3 parameters."
    echo "  1st parameter type: py (python)"
    # echo "  1st parameter type: py (python) or ts (TypeScript)"
    echo "  2nd parameter service name: should be kebab-case-name and not taken by previously created service"
    echo "  3rd parameter environment (optional): common, dev, qa, or prod (default: common)"
    echo
    echo "Examples:"
    echo "  $0 py my-service              # Creates service in envs/common/"
    echo "  $0 py my-service dev          # Creates service in envs/dev/"
    echo
    echo "  $0 --help           - display this info"
    echo -e "$2"
    exit "$1"
}

InstallNodeDependencies() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_SERVICE_TYPE="$1"
    local LCL_SERVICE_PATH="$2"
    local LCL_EXIT_CODE=0

    if [ ! -d "$LCL_SERVICE_PATH" ]; then
        PrintTrace "$TRACE_ERROR" "Directory does not exist: $LCL_SERVICE_PATH"
        return 1
    fi

    (
        cd "$LCL_SERVICE_PATH" || { PrintTrace "$TRACE_INFO" "Failed to change directory to $LCL_SERVICE_PATH"; exit $?; }
        PrintTrace "$TRACE_INFO" "PWD = $PWD"
        if [ "$LCL_SERVICE_TYPE" == "ts" ]; then
            PrintTrace "$TRACE_INFO" "installing node dependencies"
            npm install --save "${TS_NODE_DEPENDENCIES[@]}"

            PrintTrace "$TRACE_INFO" "installing node devDependencies"
            npm install --save --save-dev "${TS_NODE_DEV_DEPENDENCIES[@]}"
        fi
    ) || LCL_EXIT_CODE=$?
    PrintTrace "$TRACE_INFO" "PWD = $PWD"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return $LCL_EXIT_CODE
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
    echo "ERROR: cannot find $COMMON_LIB_FILE"
    echo "  $COMMON_LIB_FILE contains common definitions and functions"
    exit 1
fi

echo
PrintTrace "$TRACE_FUNCTION" "-> $0 ($*)"
[ $# -eq 0 ] && PrintUsageAndExitWithCode "$EXIT_CODE_SUCCESS" "${GRN}Did that help?${NC}"
IsParameterHelp $# "$1" && PrintUsageAndExitWithCode "$EXIT_CODE_SUCCESS" "${GRN}Did that help?${NC}"

# Check parameter count (2 or 3 parameters allowed)
if [ $# -lt $MIN_NUMBER_OF_PARAMS ] || [ $# -gt $MAX_NUMBER_OF_PARAMS ]; then
    PrintUsageAndExitWithCode "$EXIT_CODE_INVALID_NUMBER_OF_PARAMETERS" "${RED}ERROR: Invalid number of parameters. Expected 2 or 3 parameters.${NC}"
fi

IsPredefinedParameterValid "$1" "${SUPPORTED_TYPES_ARRAY[@]}" || PrintUsageAndExitWithCode "$EXIT_CODE_NOT_VALID_PARAMETER" "${RED}ERROR: Service type have to be 'py' or 'ts'.${NC}"

SERVICE_TYPE=$1
SERVICE_NAME=$2
SERVICE_ENV=${3:-$DEFAULT_ENV}  # Use 3rd parameter or default to 'common'

# Validate environment parameter if provided
if [ $# -eq 3 ]; then
    IsPredefinedParameterValid "$SERVICE_ENV" "${SUPPORTED_ENV_ARRAY[@]}" || PrintUsageAndExitWithCode "$EXIT_CODE_NOT_VALID_PARAMETER" "${RED}ERROR: Environment must be 'common', 'dev', 'qa', or 'prod'.${NC}"
fi

# Create the full service path
SERVICE_PATH="envs/$SERVICE_ENV/$SERVICE_NAME"

# Check if service already exists
[ -d "$SERVICE_PATH" ] && PrintUsageAndExitWithCode "$EXIT_CODE_NOT_VALID_PARAMETER" "${RED}ERROR: Service '$SERVICE_NAME' already exists in environment '$SERVICE_ENV'. Please choose another name.${NC}"

# Ensure the environment directory exists
mkdir -p "envs/$SERVICE_ENV"

PrintTrace "$TRACE_INFO" "Creating service '$SERVICE_NAME' of type '$SERVICE_TYPE' in environment '$SERVICE_ENV'"

[ "$SERVICE_TYPE" = "py" ] && TEMPLATE_NAME=$TEMPLATE_NAME_FOR_PYTHON || TEMPLATE_NAME=$TEMPLATE_NAME_FOR_TYPESCRIPT
serverless create --template-path "$TEMPLATE_NAME" --name "$SERVICE_NAME" --path "$SERVICE_PATH"

# Replace placeholders in Python service files
if [ "$SERVICE_TYPE" = "py" ]; then
    PrintTrace "$TRACE_INFO" "Updating service configuration for $SERVICE_NAME"

    # Update pyproject.toml
    if [ -f "$SERVICE_PATH/pyproject.toml" ]; then
        sed -i.bak "s/{{SERVICE_NAME}}/$SERVICE_NAME/g" "$SERVICE_PATH/pyproject.toml"
        sed -i.bak "s/{{SERVICE_DESCRIPTION}}/$SERVICE_NAME Service/g" "$SERVICE_PATH/pyproject.toml"
        rm "$SERVICE_PATH/pyproject.toml.bak"
    fi
fi

InstallNodeDependencies "$SERVICE_TYPE" "$SERVICE_PATH" || EXIT_CODE=$?

# Install serverless plugins from serverless.yml
PrintTrace "$TRACE_INFO" "Installing serverless plugins for $SERVICE_NAME"
(
    cd "$SERVICE_PATH" || { PrintTrace "$TRACE_ERROR" "Failed to change directory to $SERVICE_PATH"; exit 1; }
    InstallRequiredServerlessPlugins
) || EXIT_CODE=$?

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit $EXIT_CODE
