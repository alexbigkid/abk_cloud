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

CheckBootstrapExists() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV="$1"
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"
    local LCL_EXIT_CODE=0
    
    # Check if environment config exists
    if [ ! -f "$LCL_ENV_CONFIG" ]; then
        PrintTrace "$TRACE_INFO" "Environment config not found - this is a fresh setup"
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi
    
    # Get bootstrap bucket name from config
    local LCL_BOOTSTRAP_BUCKET
    LCL_BOOTSTRAP_BUCKET=$(yq -r ".terraform.terraformStateBootstrap.terraform_bootstrap_state_s3_bucket" "$LCL_ENV_CONFIG")
    
    if [ -z "$LCL_BOOTSTRAP_BUCKET" ] || [ "$LCL_BOOTSTRAP_BUCKET" = "null" ]; then
        PrintTrace "$TRACE_ERROR" "Could not determine bootstrap bucket name from config"
        LCL_EXIT_CODE=1
        PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
        return "$LCL_EXIT_CODE"
    fi
    
    PrintTrace "$TRACE_INFO" "Checking if bootstrap infrastructure already exists..."
    PrintTrace "$TRACE_INFO" "Bootstrap bucket: $LCL_BOOTSTRAP_BUCKET"
    
    # Check if bootstrap bucket exists using AWS CLI first, fallback to terraform check
    local bucket_exists=false
    local state_file_exists=false
    
    # Try AWS CLI first
    if AWS_PROFILE="" aws s3api head-bucket --bucket "$LCL_BOOTSTRAP_BUCKET" 2>/dev/null; then
        bucket_exists=true
        PrintTrace "$TRACE_INFO" "Bootstrap bucket exists (confirmed via AWS CLI)"
        
        # Check if bootstrap state file exists in S3
        if AWS_PROFILE="" aws s3api head-object --bucket "$LCL_BOOTSTRAP_BUCKET" --key "bootstrap/terraform.tfstate" 2>/dev/null; then
            state_file_exists=true
            PrintTrace "$TRACE_INFO" "State file found at: s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate"
        fi
    else
        PrintTrace "$TRACE_INFO" "AWS CLI check failed - trying fallback approaches..."
        
        # Fallback 1: Try to download state file directly (best effort)
        local local_state_file="$BOOTSTRAP_DIR/terraform.tfstate"
        PrintTrace "$TRACE_INFO" "Attempting to download state file as fallback check..."
        
        if timeout 10 aws s3 cp "s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate" "$local_state_file.download_test" 2>/dev/null; then
            # Successfully downloaded - infrastructure exists
            PrintTrace "$TRACE_INFO" "Successfully downloaded state file - infrastructure exists"
            rm -f "$local_state_file.download_test"  # Clean up test file
            bucket_exists=true
            state_file_exists=true
        else
            PrintTrace "$TRACE_INFO" "Could not download state file - checking local state..."
            
            # Fallback 2: Check local state file
            if [ -f "$local_state_file" ]; then
                # Check if the state file contains resources
                local resource_count
                resource_count=$(grep -c '"type":' "$local_state_file" 2>/dev/null || echo "0")
                # Ensure resource_count is a valid number
                if [[ "$resource_count" =~ ^[0-9]+$ ]] && [ "$resource_count" -gt 0 ]; then
                    PrintTrace "$TRACE_INFO" "Local state file contains $resource_count resources"
                    PrintTrace "$TRACE_INFO" "Bootstrap infrastructure appears to exist locally"
                    bucket_exists=true
                    state_file_exists=true
                    PrintTrace "$TRACE_WARNING" "Cannot verify S3 state file due to AWS CLI access issues"
                    PrintTrace "$TRACE_WARNING" "Assuming state file exists to prevent recreation"
                else
                    PrintTrace "$TRACE_INFO" "Local state file is empty or contains no resources"
                    PrintTrace "$TRACE_INFO" "Will attempt bootstrap creation"
                fi
            else
                PrintTrace "$TRACE_INFO" "No local state file found"
                PrintTrace "$TRACE_INFO" "Will attempt bootstrap creation"
            fi
        fi
    fi
    
    # Determine what to do based on findings
    if [ "$bucket_exists" = true ] && [ "$state_file_exists" = true ]; then
        PrintTrace "$TRACE_INFO" "Bootstrap infrastructure already exists!"
        LCL_EXIT_CODE=2  # Special exit code for "already exists"
    elif [ "$bucket_exists" = true ]; then
        PrintTrace "$TRACE_INFO" "Bootstrap bucket exists but state file status unclear"
        PrintTrace "$TRACE_INFO" "This may indicate a partial bootstrap - proceeding with creation"
    else
        PrintTrace "$TRACE_INFO" "Bootstrap infrastructure does not exist - proceeding with creation"
    fi
    
    PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
    return "$LCL_EXIT_CODE"
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
            if AWS_PROFILE="" aws s3 cp "$LCL_STATE_FILE" "s3://$LCL_BOOTSTRAP_BUCKET/bootstrap/terraform.tfstate" 2>/dev/null; then
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

SetupBootstrapVariables() {
    PrintTrace "$TRACE_FUNCTION" "-> ${FUNCNAME[0]} ($*)"
    local LCL_ENV="$1"
    local LCL_REGION="$2"
    local LCL_ENV_CONFIG="config.$LCL_ENV.yml"
    local LCL_TF_VARS_FILE="$BOOTSTRAP_DIR/terraform.tfvars.json"
    local LCL_EXIT_CODE=0

    # Check if environment config exists, create it if needed
    if [ ! -f "$LCL_ENV_CONFIG" ]; then
        PrintTrace "$TRACE_INFO" "Environment config file not found: $LCL_ENV_CONFIG"
        PrintTrace "$TRACE_INFO" "Running deploy-001_setup-env.sh to create it..."
        
        # Run setup script to create environment config
        if ! ./deploy-001_setup-env.sh "$LCL_ENV" "$LCL_REGION"; then
            PrintTrace "$TRACE_ERROR" "Failed to create environment config"
            LCL_EXIT_CODE=1
            PrintTrace "$TRACE_FUNCTION" "<- ${FUNCNAME[0]} ($LCL_EXIT_CODE)"
            return "$LCL_EXIT_CODE"
        fi
        
        PrintTrace "$TRACE_INFO" "Environment config created successfully"
    fi

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
        AWS_PROFILE="" terraform init -input=false || exit "$?"
        
        PrintTrace "$TRACE_INFO" "${YLW}terraform plan: terraformStateBootstrap${NC}"
        AWS_PROFILE="" terraform plan || exit "$?"
        
        PrintTrace "$TRACE_INFO" "${YLW}terraform apply: terraformStateBootstrap${NC}"
        AWS_PROFILE="" terraform apply -input=false -auto-approve || exit "$?"
        
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
    if AWS_PROFILE="" aws s3 cp "$LCL_STATE_FILE" "s3://$LCL_S3_BUCKET/$LCL_S3_KEY"; then
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
    PrintTrace "$TRACE_WARNING" "Bootstrap state will be lost when CI job completes!"
    PrintTrace "$TRACE_WARNING" "Consider running this locally instead"
fi

# Setup bootstrap variables (needed for both create and download scenarios)
if ! SetupBootstrapVariables "$ENV" "$REGION"; then
    PrintTrace "$TRACE_ERROR" "Failed to setup bootstrap variables"
    exit "$EXIT_CODE_DEPLOYMENT_FAILED"
fi

# Check if bootstrap already exists
CheckBootstrapExists "$ENV"
BOOTSTRAP_CHECK_EXIT_CODE=$?
PrintTrace "$TRACE_INFO" "Bootstrap check completed with exit code: $BOOTSTRAP_CHECK_EXIT_CODE"

if [ "$BOOTSTRAP_CHECK_EXIT_CODE" -eq 2 ]; then
    # Bootstrap already exists - download state if needed and we're ready to use existing infrastructure
    PrintTrace "$TRACE_INFO" "Bootstrap infrastructure already exists"
    
    # Download existing bootstrap state to ensure we have it locally
    DownloadExistingBootstrapState "$ENV"
    
    echo
    echo "✅ BOOTSTRAP INFRASTRUCTURE ALREADY EXISTS"
    echo "=================================================================="
    echo "The bootstrap infrastructure for environment '$ENV' already exists."
    echo "Local state file is available and ready to use."
    echo
    echo "Infrastructure is ready for:"
    echo "  - Regular terraform deployments: ./deploy-002_terraform.sh $ENV us-west-2"
    echo "  - Service deployments: ./deploy-003_services.sh $ENV us-west-2"
    echo "=================================================================="
    
    exit 0
elif [ "$BOOTSTRAP_CHECK_EXIT_CODE" -ne 0 ]; then
    # Error checking bootstrap status
    PrintTrace "$TRACE_ERROR" "Failed to check bootstrap status"
    exit "$EXIT_CODE_DEPLOYMENT_FAILED"
fi

# Create new bootstrap infrastructure
PrintTrace "$TRACE_INFO" "Creating new bootstrap infrastructure"
if ! DeployBootstrap; then
    PrintTrace "$TRACE_ERROR" "Bootstrap creation failed"
    exit "$EXIT_CODE_DEPLOYMENT_FAILED"
fi

# Upload state to S3 for backup
UploadBootstrapState "$ENV"

# Print summary
PrintBootstrapSummary "$ENV"

PrintTrace "$TRACE_FUNCTION" "<- $0 ($EXIT_CODE)"
echo
exit "$EXIT_CODE"