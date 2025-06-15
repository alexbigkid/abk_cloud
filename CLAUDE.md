# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a cloud infrastructure deployment template for AWS-based projects. It uses Terraform for infrastructure-as-code, Serverless Framework for Lambda services, and Bash scripts for orchestration. Supports multi-environment deployments (dev, qa, prod) with sequential and parallel deployment strategies.

## Common Commands

### Setup and Installation
```bash
# Install required tools (AWS CLI, Terraform, jq, yq, parallel, serverless)
./install-tools.sh

# Setup environment variables in .envrc (direnv recommended)
export ABK_DEPLOYMENT_ENV=dev
export ABK_DEPLOYMENT_REGION=us-west-2
export ABK_PRJ_NAME=your-project-name
export LOG_LEVEL=info
export AWS_ACCESS_KEY_ID=your-key
export AWS_SECRET_ACCESS_KEY=your-secret
```

### Full Deployment
```bash
# Deploy entire infrastructure (runs all deploy-xxx phases)
./deploy.sh dev us-west-2

# Remove entire infrastructure (runs all remove-xxx phases in reverse)
./remove.sh dev us-west-2
```

### Manual Terraform Deployment
```bash
# 1. Setup environment configuration
./deploy-001_setup-env.sh dev us-west-2

# 2. Navigate to specific terraform project
cd terraform/envs/common/serviceDeploymentBucket

# 3. Deploy terraform
terraform init
terraform plan
terraform apply
```

### Manual Service Deployment
```bash
# 1. Ensure ABK_DEPLOYMENT_ENV is set in .envrc
export ABK_DEPLOYMENT_ENV=dev

# 2. Setup environment
./deploy-001_setup-env.sh dev us-west-2

# 3. Deploy infrastructure dependencies if needed
./deploy-002_terraform.sh dev us-west-2

# 4. Deploy individual service (if it has publish.sh)
cd services/envs/dev/your-service
./publish.sh dev us-west-2
```

### Service Management
```bash
# Create new service from template (defaults to 'common' environment)
cd services
./createNewService.sh py my-service           # Creates in envs/common/
./createNewService.sh py my-service dev       # Creates in envs/dev/
./createNewService.sh py my-service prod      # Creates in envs/prod/

# Disable service deployment temporarily
mv services/envs/dev/your-service/publish.sh services/envs/dev/your-service/do_not_publish.sh
```

### Linting
```bash
# Run shellcheck on all bash scripts
shellcheck deploy*.sh remove*.sh common-lib.sh install-tools.sh
```

## Architecture Overview

### Directory Structure
- **`.github/`**: GitHub Actions pipeline and scripts
- **`.vscode/`**: VSCode settings and shortcuts for unit tests
- **`docs/`**: Documentation files
- **`services/`**: Lambda services and deployments
- **`terraform/`**: Cloud infrastructure code
- **`tests/`**: Integration tests

### Sequential Deployment Phases
1. **Setup Environment** (`deploy-001_setup-env.sh`): Generate config files and Terraform variables
2. **Terraform** (`deploy-002_terraform.sh`): Deploy cloud infrastructure
3. **Services** (`deploy-003_services.sh`): Deploy Lambda services
4. **Tests** (`deploy-004_run-tests.sh`): Execute integration tests

### Terraform Organization
- **`terraform/envs/common/`**: Resources deployed to all environments (deploy first)
- **`terraform/envs/dev|qa|prod/`**: Environment-specific resources
- **`terraform/templates/`**: Reusable Terraform modules

**Sequential vs Parallel Deployment:**
- Folders starting with digits (e.g., `000_terraformStateBootstrap`) deploy sequentially
- Other folders can deploy in parallel

### Services Organization
- **`services/envs/common/`**: Services deployed to all environments (deploy first)
- **`services/envs/dev|qa|prod/`**: Environment-specific services
- **`services/templates/`**: Service boilerplate templates
- **`services/createNewService.sh`**: Script to generate new services from templates

**Service Deployment Pattern:**
- Services deploy via `publish.sh` script in each service directory
- Supports multiple languages (TypeScript, Python, Java, C#)
- Uses Serverless Framework with dynamically generated config files

### Configuration System
- **`config.yml`**: Master template with environment variable placeholders
- **`config.$ENV.yml`**: Generated environment-specific configurations
- **`terraform.tfvars.json`**: Auto-generated per Terraform project
- **`serverless.yml`**: Service configurations that reference config files

### Shared Library (`common-lib.sh`)
Provides standardized functions for:
- Environment validation (`ENV_ARRAY=("dev" "qa" "prod")`, `REGION_ARRAY=("us-west-2")`)
- Exit codes and error handling
- Color-coded logging with trace levels
- Configuration file management
- AWS resource discovery utilities

## Development Guidelines

### Adding New Terraform Infrastructure
1. **For shared resources**: Create in `terraform/envs/common/`
2. **For environment-specific**: Create in `terraform/envs/$ENV/`
3. **For reusable modules**: Create in `terraform/templates/`
4. **For sequential deployment**: Prefix with digits `000_`, `001_`, etc.
5. Update `config.yml` with module-specific variables

### Adding New Services
1. Use `./services/createNewService.sh <type> <name> [env]` to generate from template
   - Type: `py` (Python) or `ts` (TypeScript) 
   - Environment: `common` (default), `dev`, `qa`, or `prod`
2. Service is automatically created in `services/envs/$ENV/` directory
3. Ensure service has `publish.sh` script for deployment (auto-generated)
4. For sequential deployment, prefix service name with 3 digits
5. Services use Serverless Framework with generated config files

### Script Conventions
- All scripts source `common-lib.sh` for shared functionality
- Use `PrintTrace` with appropriate trace levels (`TRACE_ERROR`, `TRACE_INFO`, etc.)
- Follow established parameter validation pattern
- Quote all variables to prevent word splitting
- Use standardized exit codes from `common-lib.sh`
- **Parameter Consistency**: All deployment scripts must accept both environment and region parameters for consistency, even if the region parameter is not actively used

### Environment Management
- Set `ABK_DEPLOYMENT_ENV` in `.envrc` file
- Run `deploy-001_setup-env.sh` after environment variable changes
- Common resources deployed before environment-specific ones
- Configuration files generated dynamically to avoid hardcoded secrets

## Key Environment Variables
Required variables that must be set:
- `ABK_DEPLOYMENT_ENV`: Target environment (dev/qa/prod)
- `ABK_DEPLOYMENT_REGION`: AWS region (currently us-west-2)
- `ABK_PRJ_NAME`: Project name prefix for resource naming
- `LOG_LEVEL`: Logging level for deployment scripts
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`: AWS credentials

## Deployment Strategy for Terraform and Services

### Deployment Process
The deployment of Terraform modules and services follows a specific sequential strategy:

1. Deploy Terraform modules sequentially in `envs/common` directory, starting with modules prefixed with triple digits (e.g., `000_`, `001_`)
2. Move to the sequential deployment of the target environment (dev, qa, or prod)
3. Deploy Terraform modules without triple-digit prefixes from the common folder in parallel using the `parallel` tool
4. Finally, deploy Terraform modules from the current environment directory (dev, qa, or prod)

This strategy will also be applied to the services directory when deploying services, ensuring a controlled and predictable infrastructure and service deployment process.

### Deployment Script Requirements (`@deploy-002_terraform.sh`)
- Include clear entry and exit statements for each function
- Handle sequential and parallel deployment of Terraform modules
- Pay special attention to modules prefixed with triple digits to ensure correct order of deployment
- Support deployment across different environments (dev, qa, prod)