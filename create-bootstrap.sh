#!/bin/bash

# Create terraform state bootstrap infrastructure
# This script should be run ONCE per environment to create the S3 bucket and DynamoDB table
# for storing terraform state remotely.

set -eu

EXIT_CODE=0
EXPECTED_NUMBER_OF_PARAMS=2
COMMON_LIB_FILE="common-lib.sh"
BOOTSTRAP_DIR="terraform/terraformStateBootstrap"

#------------------------------------------------------------------------------
# functions
#------------------------------------------------------------------------------
PrintUsageAndExitWithCode() {
    echo
    echo "$0 creates terraform state bootstrap infrastructure"
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


SetupBootstrapVariables() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV="$1"
    local LCL_REGION="$2"
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"
    local LCL_TF_VARS_FILE="$BOOTSTRAP_DIR/terraform.tfvars.json"
    local LCL_EXIT_CODE=0

    # Always run setup script to ensure up-to-date environment configuration
    PrintTrace "$TRACE_INFO" "Running deploy-001_setup-env.sh to ensure up-to-date environment setup..."
    # Run setup script to create/update environment config
    if ! ./deploy-001_setup-env.sh "$LCL_ENV" "$LCL_REGION"; then
        PrintTrace "$TRACE_ERROR" "Failed to setup environment config"
        LCL_EXIT_CODE=1
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi
    PrintTrace "$TRACE_INFO" "Environment config setup completed successfully"

    # Extract bootstrap configuration from environment config
    local LCL_BOOTSTRAP_TF_VARS_JSON
    LCL_BOOTSTRAP_TF_VARS_JSON=$(yq -o=json ".terraform.terraformStateBootstrap" "$LCL_ENV_CONFIG")
    PrintTrace "$TRACE_DEBUG" "Bootstrap terraform vars: $LCL_BOOTSTRAP_TF_VARS_JSON"

    # Write terraform vars file to bootstrap directory
    printf "%s" "$LCL_BOOTSTRAP_TF_VARS_JSON" > "$LCL_TF_VARS_FILE"
    PrintTrace "$TRACE_INFO" "Generated terraform vars for bootstrap: $LCL_TF_VARS_FILE"

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}


DetermineBootstrapAction() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV="$1"
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"
    local LCL_STATE_FILE="$BOOTSTRAP_DIR/terraform.tfstate"

    # Get bootstrap bucket name from config
    local LCL_BOOTSTRAP_BUCKET
    LCL_BOOTSTRAP_BUCKET=$(yq -r ".terraform.terraformStateBootstrap.terraform_bootstrap_state_s3_bucket" "$LCL_ENV_CONFIG")

    if [ -z "$LCL_BOOTSTRAP_BUCKET" ] || [ "$LCL_BOOTSTRAP_BUCKET" = "null" ]; then
        PrintTrace "$TRACE_ERROR" "Could not determine bootstrap bucket name from config"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (1)"
        return 1
    fi

    PrintTrace "$TRACE_INFO" "Analyzing bootstrap infrastructure state..."
    PrintTrace "$TRACE_INFO" "Bootstrap bucket: $LCL_BOOTSTRAP_BUCKET"

    # Check 1: S3 terraform state file exists
    local s3_tf_state_file_exists=false
    # if AWS_PROFILE="" aws s3 ls "s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate" >/dev/null 2>&1; then
    if aws s3 ls "s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate" >/dev/null 2>&1; then
        s3_tf_state_file_exists=true
        PrintTrace "$TRACE_INFO" "✓ S3 terraform state file exists"
    else
        PrintTrace "$TRACE_INFO" "✗ S3 terraform state file does not exist"
    fi

    # Check 2: Local terraform state file exists and has resources
    local local_tf_file_exists=false
    if [ -f "$LCL_STATE_FILE" ]; then
        PrintTrace "$TRACE_INFO" "Local terraform state file exist"
        local resource_count
        resource_count=$(grep -c '"type":' "$LCL_STATE_FILE" 2>/dev/null || echo "0")
        if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
            local_tf_file_exists=true
            PrintTrace "$TRACE_INFO" "✓ Local terraform state file exists with $resource_count resources"
        else
            PrintTrace "$TRACE_INFO" "✗ Local terraform state file is empty or invalid"
        fi
    else
        PrintTrace "$TRACE_INFO" "✗ Local terraform state file does not exist"
    fi

    # Simple 2x2 decision matrix
    if [ "$s3_tf_state_file_exists" = true ]; then
        PrintTrace "$TRACE_INFO" "S3 terraform state file exists"
        if [ "$local_tf_file_exists" = true ]; then
            PrintTrace "$TRACE_INFO" "Local terraform state file exists"
            PrintTrace "$TRACE_INFO" "ACTION: Infrastructure ready - everything already set up"
            echo "✅ INFRASTRUCTURE_READY"
            echo "Bootstrap infrastructure exists both remotely and locally"
        else
            PrintTrace "$TRACE_INFO" "Local terraform state file does NOT exist"
            PrintTrace "$TRACE_INFO" "ACTION: Download terraform state file from S3"
            DownloadExistingBootstrapState "$LCL_ENV"
            echo "✅ INFRASTRUCTURE_READY"
            echo "Bootstrap infrastructure downloaded from S3"
        fi
    else
        PrintTrace "$TRACE_INFO" "S3 terraform state file does NOT exist"
        if [ "$local_tf_file_exists" = true ]; then
            PrintTrace "$TRACE_INFO" "Local terraform state file exists"
            PrintTrace "$TRACE_INFO" "ACTION: Upload local state to S3 (ensure bucket exists)"
            # Ensure bucket exists before upload
            EnsureBootstrapBucket "$LCL_BOOTSTRAP_BUCKET"
            UploadBootstrapState "$LCL_ENV"
            echo "✅ INFRASTRUCTURE_READY"
            echo "Local terraform state uploaded to S3"
        else
            PrintTrace "$TRACE_INFO" "Local terraform state file does NOT exist"
            PrintTrace "$TRACE_INFO" "ACTION: Create new infrastructure (ensure bucket exists)"
            # Ensure bucket exists before creation
            EnsureBootstrapBucket "$LCL_BOOTSTRAP_BUCKET"
            # Create bootstrap infrastructure
            if ! DeployBootstrap; then
                PrintTrace "$TRACE_ERROR" "Bootstrap creation failed"
                PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (1)"
                return 1
            fi
            # Upload the newly created state
            UploadBootstrapState "$LCL_ENV"
            PrintBootstrapSummary "$LCL_ENV"
            echo "✅ INFRASTRUCTURE_READY"
            echo "Bootstrap infrastructure created and uploaded successfully"
        fi
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}

EnsureBootstrapBucket() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_BUCKET="$1"

    PrintTrace "$TRACE_INFO" "Ensuring bootstrap bucket exists: $LCL_BUCKET"

    # Check if bucket exists
    if aws s3api head-bucket --bucket "$LCL_BUCKET" 2>/dev/null; then
        PrintTrace "$TRACE_INFO" "✓ Bootstrap bucket already exists"
    else
        PrintTrace "$TRACE_INFO" "Creating bootstrap bucket: $LCL_BUCKET"
        if aws s3 mb "s3://$LCL_BUCKET" 2>/dev/null; then
            PrintTrace "$TRACE_INFO" "✓ Bootstrap bucket created successfully"
        else
            PrintTrace "$TRACE_ERROR" "Failed to create bootstrap bucket"
            PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (1)"
            return 1
        fi
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
    return 0
}


DownloadExistingBootstrapState() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV="$1"
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"
    local LCL_EXIT_CODE=0
    local LCL_STATE_FILE="$BOOTSTRAP_DIR/terraform.tfstate"

    # Get bootstrap bucket name from config
    local LCL_BOOTSTRAP_BUCKET
    LCL_BOOTSTRAP_BUCKET=$(yq -r ".terraform.terraformStateBootstrap.terraform_bootstrap_state_s3_bucket" "$LCL_ENV_CONFIG")

    echo
    echo "📥 DOWNLOADING EXISTING BOOTSTRAP STATE"
    echo "=================================================================="
    echo "Bootstrap infrastructure already exists for environment '$LCL_ENV'"
    echo "Downloading existing state file to continue working with existing infrastructure"
    echo

    PrintTrace "$TRACE_INFO" "Downloading state file from S3..."
    PrintTrace "$TRACE_INFO" "Source: s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate"
    PrintTrace "$TRACE_INFO" "Target: $LCL_STATE_FILE"

    # Check if we already have a local state file
    if [ -f "$LCL_STATE_FILE" ]; then
        local resource_count
        resource_count=$(grep -c '"type":' "$LCL_STATE_FILE" 2>/dev/null || echo "0")
        if [ "$resource_count" -gt 0 ]; then
            PrintTrace "$TRACE_INFO" "Local state file already exists with $resource_count resources"
            echo "✅ Local state file already present"
            echo "✅ Ready to work with existing bootstrap infrastructure"
            # Try to upload local state to S3 as backup
            if aws s3 cp "$LCL_STATE_FILE" "s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate" 2>/dev/null; then
                PrintTrace "$TRACE_INFO" "Local state uploaded to S3 as backup"
                echo "✅ State file backed up to S3"
            else
                PrintTrace "$TRACE_WARNING" "Could not backup state file to S3 (AWS CLI issues)"
            fi
            PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
            return "$LCL_EXIT_CODE"
        fi
    fi

    # Try to download the existing state file from S3
    PrintTrace "$TRACE_INFO" "Attempting to download state file from S3..."
    if timeout 10 aws s3 cp "s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate" "$LCL_STATE_FILE" 2>/dev/null; then
        PrintTrace "$TRACE_INFO" "Bootstrap state downloaded successfully"
        echo "✅ State file downloaded successfully"
        echo "✅ Ready to work with existing bootstrap infrastructure"
    else
        PrintTrace "$TRACE_WARNING" "Failed to download bootstrap state file"
        echo "⚠️  Could not download state file from S3"
        echo "   This could be due to:"
        echo "   - AWS credentials not configured for CLI access"
        echo "   - Network connectivity issues"
        echo "   - S3 bucket permissions"
        echo "   - State file may not exist in S3 yet"
        echo
        echo "   Continuing without remote state file..."
        echo "   Note: Infrastructure will be managed from local state only"
        # Don't fail if download fails - continue without remote state
    fi

    echo "=================================================================="

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}


DeployBootstrap() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]}"
    local LCL_EXIT_CODE=0

    PrintTrace "$TRACE_INFO" "Creating terraform state bootstrap infrastructure"
    PrintTrace "$TRACE_INFO" "Bootstrap directory: $BOOTSTRAP_DIR"

    # Check if bootstrap directory exists
    if [ ! -d "$BOOTSTRAP_DIR" ]; then
        PrintTrace "$TRACE_ERROR" "Bootstrap directory not found: $BOOTSTRAP_DIR"
        LCL_EXIT_CODE=1
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    # Deploy bootstrap terraform
    (
        cd "$BOOTSTRAP_DIR" || exit "$?"

        PrintTrace "$TRACE_INFO" "${YLW}terraform init: terraformStateBootstrap${NC}"
        terraform init -input=false || exit "$?"

        PrintTrace "$TRACE_INFO" "${YLW}terraform plan: terraformStateBootstrap${NC}"
        terraform plan || exit "$?"

        PrintTrace "$TRACE_INFO" "${YLW}terraform apply: terraformStateBootstrap${NC}"
        terraform apply -input=false -auto-approve || exit "$?"

    ) || LCL_EXIT_CODE="$?"

    if [ "$LCL_EXIT_CODE" -eq 0 ]; then
        PrintTrace "$TRACE_INFO" "Bootstrap infrastructure created successfully"
    else
        PrintTrace "$TRACE_ERROR" "Bootstrap creation failed"
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}


UploadBootstrapState() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV="$1"
    local LCL_EXIT_CODE=0
    local LCL_STATE_FILE="$BOOTSTRAP_DIR/terraform.tfstate"
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"

    # Check if state file exists
    if [ ! -f "$LCL_STATE_FILE" ]; then
        PrintTrace "$TRACE_WARNING" "No terraform state file found: $LCL_STATE_FILE"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    # Get S3 bucket name from config (bootstrap-specific bucket)
    local LCL_S3_BUCKET
    LCL_S3_BUCKET=$(yq -r ".terraform.terraformStateBootstrap.terraform_bootstrap_state_s3_bucket" "$LCL_ENV_CONFIG")

    if [ -z "$LCL_S3_BUCKET" ] || [ "$LCL_S3_BUCKET" = "null" ]; then
        PrintTrace "$TRACE_ERROR" "Could not determine S3 bucket name from config"
        LCL_EXIT_CODE=1
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi

    PrintTrace "$TRACE_INFO" "Uploading bootstrap state to S3: $LCL_S3_BUCKET"

    # Upload state file to S3 bucket
    local LCL_S3_KEY="bootstrap/terraform.tfstate"
    if aws s3 cp "$LCL_STATE_FILE" "s3://$LCL_S3_BUCKET/$LCL_S3_KEY"; then
        PrintTrace "$TRACE_INFO" "Bootstrap state uploaded successfully to s3://$LCL_S3_BUCKET/$LCL_S3_KEY"
        PrintTrace "$TRACE_INFO" "State backup available at: s3://$LCL_S3_BUCKET/$LCL_S3_KEY"
    else
        PrintTrace "$TRACE_WARNING" "Failed to upload bootstrap state to S3"
        PrintTrace "$TRACE_WARNING" "Local state file preserved at: $LCL_STATE_FILE"
        # Don't fail the entire process if S3 upload fails
    fi

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
}


PrintBootstrapSummary() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV="$1"
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"

    echo
    echo "=================================================================="
    echo "                    BOOTSTRAP CREATION COMPLETE"
    echo "=================================================================="

    # Extract values from config
    local LCL_TERRAFORM_STATE_BUCKET
    local LCL_BOOTSTRAP_STATE_BUCKET
    local LCL_DYNAMODB_TABLE
    LCL_TERRAFORM_STATE_BUCKET=$(yq -r ".terraform.terraformStateBootstrap.terraform_state_S3_bucket_name" "$LCL_ENV_CONFIG")
    LCL_BOOTSTRAP_STATE_BUCKET=$(yq -r ".terraform.terraformStateBootstrap.terraform_bootstrap_state_s3_bucket" "$LCL_ENV_CONFIG")
    LCL_DYNAMODB_TABLE=$(yq -r ".terraform.terraformStateBootstrap.dynamodb_terraform_lock_name" "$LCL_ENV_CONFIG")

    echo "Environment: $LCL_ENV"
    echo "Terraform State S3 Bucket: $LCL_TERRAFORM_STATE_BUCKET"
    echo "Bootstrap State S3 Bucket: $LCL_BOOTSTRAP_STATE_BUCKET"
    echo "DynamoDB Lock Table: $LCL_DYNAMODB_TABLE"
    echo
    echo "✅ Remote state infrastructure is ready!"
    echo "✅ Other terraform modules can now use remote state"
    echo "✅ Local state preserved at: $BOOTSTRAP_DIR/terraform.tfstate"
    echo
    echo "Next steps:"
    echo "  1. Deploy other infrastructure: ./deploy-002_terraform.sh $LCL_ENV us-west-2"
    echo "  2. Deploy services: ./deploy-003_services.sh $LCL_ENV us-west-2"
    echo
    echo "=================================================================="

    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} (0)"
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

ENV="$1"
REGION="$2"

PrintTrace "$TRACE_INFO" "Environment: ${ENV}"
PrintTrace "$TRACE_INFO" "Region: ${REGION}"

# Check if we're in CI/CD and warn
if [ "${CI:-false}" = "true" ]; then
    PrintTrace "$TRACE_WARNING" "Running in CI/CD environment"
    PrintTrace "$TRACE_WARNING" "Bootstrap state might be lost when CI job completes!"
    PrintTrace "$TRACE_WARNING" "Consider running this locally instead"
fi

# Setup bootstrap variables (needed for both create and download scenarios)
if ! SetupBootstrapVariables "$ENV" "$REGION"; then
    PrintTrace "$TRACE_ERROR" "Failed to setup bootstrap variables"
    exit "$EXIT_CODE_DEPLOYMENT_FAILED"
fi

# Determine and execute bootstrap infrastructure action
echo
echo "🔍 ANALYZING BOOTSTRAP INFRASTRUCTURE STATE"
echo "=================================================================="
DetermineBootstrapAction "$ENV"
BOOTSTRAP_ACTION_EXIT_CODE=$?

if [ "$BOOTSTRAP_ACTION_EXIT_CODE" -ne 0 ]; then
    # Error during bootstrap analysis or execution
    PrintTrace "$TRACE_ERROR" "Bootstrap infrastructure action failed"
    exit "$EXIT_CODE_DEPLOYMENT_FAILED"
fi

echo "=================================================================="
echo "Infrastructure is ready for:"
echo "  - Regular terraform deployments: ./deploy-002_terraform.sh $ENV us-west-2"
echo "  - Service deployments: ./deploy-003_services.sh $ENV us-west-2"
echo "=================================================================="

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit "$EXIT_CODE"
