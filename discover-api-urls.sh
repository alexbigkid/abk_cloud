#!/bin/bash

# Discover API Gateway URLs for integration testing
# This script helps you find and set API Gateway URLs for local testing

set -eu

COMMON_LIB_FILE="common-lib.sh"

#------------------------------------------------------------------------------
# functions
#------------------------------------------------------------------------------
PrintUsage() {
    echo
    echo "Usage: $0 [ENVIRONMENT] [REGION]"
    echo
    echo "This script discovers API Gateway URLs for integration testing"
    echo
    echo "Parameters:"
    echo "  ENVIRONMENT  - Target environment (dev, qa, prod) [default: dev]"
    echo "  REGION       - AWS region [default: us-west-2]"
    echo
    echo "Examples:"
    echo "  $0                    # Discover URLs for dev environment"
    echo "  $0 qa us-west-2      # Discover URLs for qa environment"
    echo "  $0 prod us-west-2    # Discover URLs for prod environment"
    echo
    echo "Output:"
    echo "  - Displays discovered URLs"
    echo "  - Provides export commands for your shell"
    echo
}

DiscoverApiUrl() {
    local env="$1"
    local region="$2" 
    local service_base_name="$3"
    local service_name="${env}-${service_base_name}"
    
    echo "🔍 Discovering API Gateway for: $service_name"
    
    # Try to get API Gateway info using AWS CLI
    local api_info
    if api_info=$(aws apigateway get-rest-apis \
        --region "$region" \
        --query "items[?name=='$service_name'].{id:id,name:name}" \
        --output json 2>/dev/null); then
        
        local api_id
        if api_id=$(echo "$api_info" | jq -r '.[0].id // empty' 2>/dev/null) && [ -n "$api_id" ] && [ "$api_id" != "null" ]; then
            local api_url="https://${api_id}.execute-api.${region}.amazonaws.com/${env}"
            echo "✅ Found: $api_url"
            return 0
        fi
    fi
    
    echo "❌ Not found: $service_name"
    return 1
}

#------------------------------------------------------------------------------
# main
#------------------------------------------------------------------------------
# include common library for color support (optional)
if [ -f "$COMMON_LIB_FILE" ]; then
    # shellcheck source=./common-lib.sh
    source "$COMMON_LIB_FILE" 2>/dev/null || true
else
    # Define basic colors if common lib not available
    GRN='\033[1;32m'
    YLW='\033[1;33m'
    NC='\033[0m'
fi

# Handle help
if [ $# -gt 0 ] && [ "$1" = "--help" ]; then
    PrintUsage
    exit 0
fi

# Set defaults
ENVIRONMENT="${1:-dev}"
REGION="${2:-us-west-2}"

echo
echo "🌐 API Gateway URL Discovery"
echo "=================================================================="
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo "=================================================================="
echo

# Check AWS connectivity
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "❌ ERROR: AWS CLI not configured or no connectivity"
    echo "Please configure AWS credentials:"
    echo "  export AWS_ACCESS_KEY_ID=your-key"
    echo "  export AWS_SECRET_ACCESS_KEY=your-secret"
    echo
    exit 1
fi

# Get caller identity
caller_identity=$(aws sts get-caller-identity 2>/dev/null)
account_id=$(echo "$caller_identity" | jq -r '.Account' 2>/dev/null || echo "unknown")
user_arn=$(echo "$caller_identity" | jq -r '.Arn' 2>/dev/null || echo "unknown")

echo "📋 AWS Account Info:"
echo "  Account ID: $account_id"
echo "  User/Role: $user_arn"
echo "  Region: $REGION"
echo

# Discover known services
DISCOVERED_URLS=()
EXPORT_COMMANDS=()

echo "🔍 Discovering API Gateway URLs..."
echo

# ABK Hello Service
if DiscoverApiUrl "$ENVIRONMENT" "$REGION" "abk-hello"; then
    api_url="https://$(aws apigateway get-rest-apis --region "$REGION" --query "items[?name=='${ENVIRONMENT}-abk-hello'].id" --output text).execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}"
    DISCOVERED_URLS+=("ABK_HELLO_API_URL=$api_url")
    EXPORT_COMMANDS+=("export ABK_HELLO_API_URL=\"$api_url\"")
fi

# Add more services here as needed
# if DiscoverApiUrl "$ENVIRONMENT" "$REGION" "user-service"; then
#     api_url="https://$(aws apigateway get-rest-apis --region "$REGION" --query "items[?name=='${ENVIRONMENT}-user-service'].id" --output text).execute-api.${REGION}.amazonaws.com/${ENVIRONMENT}"
#     DISCOVERED_URLS+=("USER_SERVICE_API_URL=$api_url")
#     EXPORT_COMMANDS+=("export USER_SERVICE_API_URL=\"$api_url\"")
# fi

echo
echo "=================================================================="
echo "📋 DISCOVERY SUMMARY"
echo "=================================================================="

if [ ${#DISCOVERED_URLS[@]} -eq 0 ]; then
    echo "❌ No API Gateway URLs found for environment: $ENVIRONMENT"
    echo
    echo "Possible reasons:"
    echo "  - Services not deployed to $ENVIRONMENT environment"
    echo "  - Different naming convention used"
    echo "  - Insufficient AWS permissions"
    echo
    echo "💡 Manual Discovery:"
    echo "  aws apigateway get-rest-apis --region $REGION --output table"
    echo
else
    echo "✅ Found ${#DISCOVERED_URLS[@]} API Gateway URL(s):"
    echo
    for url in "${DISCOVERED_URLS[@]}"; do
        echo "  $url"
    done
    echo
    echo "🔧 Export Commands (copy and paste):"
    echo
    for cmd in "${EXPORT_COMMANDS[@]}"; do
        echo -e "  ${GRN}$cmd${NC}"
    done
    echo
    echo "💾 Save to .envrc (for direnv users):"
    echo
    for cmd in "${EXPORT_COMMANDS[@]}"; do
        echo "  $cmd"
    done
    echo
    echo "🧪 Test Integration (after setting URLs):"
    echo -e "  ${YLW}cd tests/integration/abk-hello${NC}"
    echo -e "  ${YLW}./run_tests.sh $ENVIRONMENT $REGION${NC}"
fi
echo "=================================================================="
echo