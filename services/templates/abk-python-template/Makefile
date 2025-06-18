.PHONY:	sync install install_all install_pip install_test_pip install_all_pip export_requirements test test_v test_ff test_vff deploy settings help
.SILENT: clean deploy_dev deploy_qa deploy_prod remove_dev remove_qa remove_prod export_requirements


# -----------------------------------------------------------------------------
# Dependency installation Makefile rules
# -----------------------------------------------------------------------------
sync:
	uv sync

install:
	uv sync --no-dev

install_dev:
	uv sync --group dev

install_debug:
	uv sync --group debug

export_requirements:
	uv export --format requirements-txt --no-hashes --no-dev --no-editable > requirements.txt.tmp
	uv export --format requirements-txt --no-hashes --group dev --no-editable > requirements_dev.txt.tmp
	uv export --format requirements-txt --no-hashes --group debug --no-editable > requirements_debug.txt.tmp
	grep -v '^-e \.$$' requirements.txt.tmp | grep -v '^\.$$' > requirements.txt
	grep -v '^-e \.$$' requirements_dev.txt.tmp | grep -v '^\.$$' > requirements_dev.txt
	grep -v '^-e \.$$' requirements_debug.txt.tmp | grep -v '^\.$$' > requirements_debug.txt
	rm -f requirements*.tmp requirements*.clean


# -----------------------------------------------------------------------------
# Domain Makefile rules
# -----------------------------------------------------------------------------
create_domain:
	serverless create_domain --aws-profile ${ABK_DEPLOYMENT_ENV} --stage ${ABK_DEPLOYMENT_ENV} --region ${ABK_DEPLOYMENT_REGION}

delete_domain:
	serverless delete_domain --aws-profile ${ABK_DEPLOYMENT_ENV} --stage ${ABK_DEPLOYMENT_ENV} --region ${ABK_DEPLOYMENT_REGION}


# -----------------------------------------------------------------------------
# Deploy service Makefile rules
# -----------------------------------------------------------------------------
deploy:
	./publish.sh ${ABK_DEPLOYMENT_ENV} ${ABK_DEPLOYMENT_REGION}

deploy_env:
	serverless deploy --aws-profile ${ABK_DEPLOYMENT_ENV} --stage ${ABK_DEPLOYMENT_ENV} --region ${ABK_DEPLOYMENT_REGION}

deploy_dev:
	export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_DEV} && export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_DEV} && serverless deploy --aws-profile dev --stage dev --region ${ABK_DEPLOYMENT_REGION}

deploy_qa:
	export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_QA} && export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_QA} && serverless deploy --aws-profile qa --stage qa --region ${ABK_DEPLOYMENT_REGION}

deploy_prod:
	export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_PROD} && export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_PROD} && serverless deploy --aws-profile prod --stage prod --region ${ABK_DEPLOYMENT_REGION}


# -----------------------------------------------------------------------------
# Remove service Makefile rules
# -----------------------------------------------------------------------------
remove:
	serverless remove --stage ${ABK_DEPLOYMENT_ENV} --region ${ABK_DEPLOYMENT_REGION}

remove_env:
	serverless remove --aws-profile ${ABK_DEPLOYMENT_ENV} --stage ${ABK_DEPLOYMENT_ENV} --region ${ABK_DEPLOYMENT_REGION}

remove_dev:
	export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_DEV} && export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_DEV} && serverless remove --aws-profile dev --stage dev --region ${ABK_DEPLOYMENT_REGION}

remove_qa:
	export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_QA} && export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_QA} && serverless remove --aws-profile qa --stage qa --region ${ABK_DEPLOYMENT_REGION}

remove_prod:
	export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID_PROD} && export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY_PROD} && serverless remove --aws-profile prod --stage prod --region ${ABK_DEPLOYMENT_REGION}


# -----------------------------------------------------------------------------
# Running tests Makefile rules
# -----------------------------------------------------------------------------
test:
	uv run pytest

test_v:
	uv run pytest -v

test_ff:
	uv run pytest -x

test_vff:
	uv run pytest -v -x

%:
	@:

test_1:
	uv run pytest -k "$(filter-out $@,$(MAKECMDGOALS))"

coverage:
	uv run pytest --cov=src --cov-report=term-missing --cov-report=xml


# -----------------------------------------------------------------------------
# Clean up Makefile rules
# -----------------------------------------------------------------------------
clean:
	@echo "deleting python and test artifacts:"
	@echo "___________________"
	find . -name "__pycache__" -type d -prune -exec rm -r {} \;
	rm -rf .serverless
	rm .coverage coverage.xml


# -----------------------------------------------------------------------------
# Display info Makefile rules
# -----------------------------------------------------------------------------
settings:
	@echo "HOME             = ${HOME}"
	@echo "PWD              = ${PWD}"
	@echo "SHELL            = ${SHELL}"

help:
	@echo "Targets:"
	@echo "--------------------------------------------------------------------------------"
	@echo "  create_domain      - create custom domain"
	@echo "  delete_domain      - delete custom domain"
	@echo "--------------------------------------------------------------------------------"
	@echo "  deploy             - deploy service to account configured in .envrc"
	@echo "  deploy_dev         - deploy service to dev account"
	@echo "  deploy_qa          - deploy service to qa account"
	@echo "  deploy_prod        - deploy service to prod account"
	@echo "--------------------------------------------------------------------------------"
	@echo "  remove             - removes service from account configured in .envrc"
	@echo "  remove_dev         - removes service from dev account"
	@echo "  remove_qa          - removes service from qa account"
	@echo "  remove_prod        - removes service from prod account"
	@echo "--------------------------------------------------------------------------------"
	@echo "  sync               - sync all dependencies using uv (recommended for local dev)"
	@echo "  install            - installs required packages using uv"
	@echo "  install_dev        - installs dev required packages for testing using uv"
	@echo "  install_debug      - installs debug required packages including dev dependencies using uv"
	@echo "  export_requirements - generates requirements.txt files from uv.lock for deployment"
	@echo "--------------------------------------------------------------------------------"
	@echo "  test               - runs pytest tests"
	@echo "  test_v             - runs pytest tests with verbose output"
	@echo "  test_ff            - runs pytest tests with fail fast (stop on first failure)"
	@echo "  test_vff           - runs pytest tests with verbose output and fail fast"
	@echo "  test_1 <test_name> - runs specific pytest test(s) by name pattern"
	@echo "  coverage           - runs pytest with coverage report"
	@echo "  clean              - cleans some auto generated build files"
	@echo "--------------------------------------------------------------------------------"
	@echo "  settings           - outputs current settings"
	@echo "  help               - outputs this info"
