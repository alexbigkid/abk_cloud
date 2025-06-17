.PHONY:	sync install install_all install_pip install_test_pip install_all_pip export_requirements test test_v test_ff test_vff deploy settings help
.SILENT: clean deploy_dev deploy_qa deploy_prod remove_dev remove_qa remove_prod


# -----------------------------------------------------------------------------
# Dependency installation Makefile rules
# -----------------------------------------------------------------------------
sync:
	uv sync

install:
	uv pip install --requirement requirements.txt

install_test:
	uv pip install --requirement requirements_test.txt

install_all:
	uv pip install --requirement requirements_all.txt

# Legacy pip commands (for compatibility)
install_pip:
	pip install --requirement requirements.txt

install_test_pip:
	pip install --requirement requirements_test.txt

install_all_pip:
	pip install --requirement requirements_all.txt


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
	uv run python -m unittest discover --start-directory tests

test_v:
	uv run python -m unittest discover --start-directory tests --verbose

test_ff:
	uv run python -m unittest discover --start-directory tests --failfast

test_vff:
	uv run python -m unittest discover --start-directory tests --verbose --failfast

%:
	@:

test_1:
	uv run python -m unittest "tests.$(filter-out $@,$(MAKECMDGOALS))"

coverage:
	uv run coverage run --source ./src --omit ./tests/*  -m unittest discover --start-directory tests
	@echo
	uv run coverage report
	uv run coverage xml


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
	@echo "  install_test       - installs required packages for testing using uv"
	@echo "  install_all        - installs all packages including dev dependencies using uv"
	@echo "  install_pip        - installs required packages using legacy pip"
	@echo "  install_test_pip   - installs required packages for testing using legacy pip"
	@echo "  install_all_pip    - installs all packages using legacy pip"
	@echo "  export_requirements - generates requirements.txt files from uv.lock for deployment"
	@echo "--------------------------------------------------------------------------------"
	@echo "  test               - runs test"
	@echo "  test_v             - runs test with verbose messaging"
	@echo "  test_ff            - runs test fast fail"
	@echo "  test_vff           - runs test fast fail with verbose messaging"
	@echo "  test_1 <file.class.test> - runs a single test"
	@echo "  coverage           - runs test, produces coverage and displays it"
	@echo "  clean              - cleans some auto generated build files"
	@echo "--------------------------------------------------------------------------------"
	@echo "  settings           - outputs current settings"
	@echo "  help               - outputs this info"
