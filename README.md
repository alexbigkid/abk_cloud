# ABK Cloud

[![CI/CD Pipeline](https://github.com/alexbigkid/abk_cloud/actions/workflows/cloud.yml/badge.svg?branch=main)](https://github.com/alexbigkid/abk_cloud/actions/workflows/cloud.yml)
[![Latest Release](https://img.shields.io/github/v/release/alexbigkid/abk_cloud?include_prereleases&label=release)](https://github.com/alexbigkid/abk_cloud/releases)
[![License](https://img.shields.io/github/license/alexbigkid/abk_cloud)](LICENSE)

ABK Cloud template - for cloud infrastructure projects

[TOC]

## Directories

| directory | description                                        |
| :-------- | :------------------------------------------------- |
| .github   | GitHub Actions pipeline and scripts                |
| .vscode   | vscode settings and shortcuts to create unit tests |
| docs      | some documentation files                           |
| services  | services/lambdas                                   |
| terraform | cloud infrastructure terraform code                |
| tests     | tests, mostly integration tests                    |

### Terraform folders

| directory   | description                                                         |
| :---------- | :------------------------------------------------------------------ |
| envs        | environment to deploy terraform to                                  |
| envs/common | terraform deployments to all environments, should be deployed first |
| envs/dev    | terraform deployments for dev environment only                      |
| envs/prod   | terraform deployments for prod environment only                     |
| envs/qa     | terraform deployments for qa environment only                       |
| templates   | own terraform modules                                               |

Notes:
1. if terraform deployment for dev, qa and prod are the same, place them into common directory.
2. there are some cloud infrastructure which needs to be deployed first before anything else, those need to be deployed sequentially. Those terraform folder should start with digits. eg. 000_terraformStateBootstrap all other terraform folders can be deployed in parallel.


### Terraform deployments
The pipeline will deploy all terraform and service automatically. However if there is a need to deploy terraform change manually during development time, here are the steps:
- execute the script deploy-001_setup-env.sh: <code>./deploy-001_setup-env.sh dev us-west-2</code>
  - it creates or updates config.<env>.yml with new values
  - it creates also terraform.tfvars.json, where the terraform variables are getting their values from
- after changing terraform, change into terraform project e.g.: <code>cd terraform/env/common/serviceDeploymentBucket</code>
- execute: <code>terraform init</code> - to initialize terraform project
- execute: <code>terraform plan</code> to show terraform changes
- execute: <code>terraform apply</code> to apply terraform changes


### Services

| directory / files   | description                                                       |
| :------------------ | :---------------------------------------------------------------- |
| envs                | environment to deploy services to                                 |
| envs/common         | service deployments to all environments, should be deployed first |
| envs/dev            | service deployments for dev environment only                      |
| envs/prod           | service deployments for prod environment only                     |
| envs/qa             | service deployments for qa environment only                       |
| templates           | service boilerplates templates to generate new services from      |
| createNewService.sh | script to create a new service from templates                     |

Notes:
1. if service deployment for dev, qa and prod are the same, place them into common directory,
2. there are some services which needs to be deployed first before any other service, in that case name the service starting with 3 digits. Those will be deployed first sequentially.


### Services deployments
Services projects from <code>services</code> directory are deployed with <code>publish.sh</code> script, if it can be found in the service project directory. Since lambda services could be written in different languages (TypeScript, Python, Java, C#) every service is deployed with different command. Placing <code>publish.sh</code> script in the service project directory make it deployable. <code>publish.sh</code> should be called with 2 parameters.
Deployment environment: <code>dev</code>, <code>qa</code> or <code>prod</code>.
Deployment Region: <code>us-west-2</code> is currently accepted


### Single Service deployment
Services are deployed using serverless framework. A lot of services configuration is done in the serverless.yml file. To avoid secrets and hard coded values in the serverless.yml files, the sensitive information has been moved to dynamically generated files: <code> config.dev.yml, config.qa.yml, config.prod.yml</code> So in order to deploy a service following steps are required:
1. make sure the <code>ABK_DEPLOYMENT_ENV</code> is set to dev in the <code>./.envrc</code> file
2. execute: <code>./deploy-001_setup-env.sh dev us-west-2</code> to create config.dev.yml file
3. if your service depends on AWS resource, you have to make sure that AWS resource does already exist. Execute:<code>./deploy-002_terraform.sh dev us-west-2</code> if needed
4. if a service deployment needs to be disabled temporarily simply rename publish.sh to something else. E.g.: do_not_publish.sh


## Files

| file                    | description                                                              |
| :---------------------- | :----------------------------------------------------------------------- |
| common-lib.sh           | common shell functions used in other shell scripts                       |
| config.yml              | Main configuration template for terraform and services.                  |
| deploy-001_setup-env.sh | sets up environment variables for each terraform and services projects   |
| deploy-002_terraform.sh | deploys cloud infrastructure from terraform directory                    |
| deploy-003_services.sh  | deploys lambda services from services directory lambdas                  |
| deploy-004_run-tests.sh | executes integration tests                                               |
| deploy.sh               | main deployment script. It will execute deploy scripts in order          |
| install-tools.sh        | installs needed for deployment tools, used on the pipeline               |
| remove-001_setup-env.sh | reverts all of the setup done in deploy-001_setup-env.sh                 |
| remove-002_terraform.sh | reverts all of the terraform deployments done in deploy-002_terraform.sh |
| remove-003_services.sh  | reverts all of the service deployments done in deploy-003_services.sh    |
| remove-004_run-tests.sh | reverts all changes done in if any deploy-004_run-tests.sh               |
| remove.sh               | main remove script. It will execute remove scripts in reverse order      |
