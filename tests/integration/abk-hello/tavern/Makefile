.PHONY: sync install install_dev test test_v validate_yaml clean help
.SILENT: clean

# -----------------------------------------------------------------------------
# UV-based dependency management
# -----------------------------------------------------------------------------
sync:
	uv sync

install:
	uv sync --no-dev

install_dev:
	uv sync --group dev

# -----------------------------------------------------------------------------
# Testing
# -----------------------------------------------------------------------------
test:
	uv run pytest

test_v:
	uv run pytest -v

test_tavern:
	uv run pytest -m tavern

test_integration:
	uv run pytest -m integration

test_performance:
	uv run pytest -m performance

test_html:
	uv run pytest --html=tavern_test_report.html --self-contained-html

test_json:
	uv run pytest --json-report --json-report-file=tavern_test_report.json

test_specific:
	uv run pytest test_abk_hello_tavern.yaml -v

test_advanced:
	uv run pytest advanced_scenarios.yaml -v

# -----------------------------------------------------------------------------
# YAML validation
# -----------------------------------------------------------------------------
validate_yaml:
	uv run yamllint *.yaml

check_yaml_syntax:
	@echo "Checking YAML syntax..."
	@for file in *.yaml; do \
		echo "Validating $$file..."; \
		python -c "import yaml; yaml.safe_load(open('$$file'))" || exit 1; \
	done
	@echo "All YAML files are valid!"

# -----------------------------------------------------------------------------
# Code quality
# -----------------------------------------------------------------------------
format:
	uv run black .

lint:
	uv run ruff check .

lint_fix:
	uv run ruff check --fix .

# -----------------------------------------------------------------------------
# Clean up
# -----------------------------------------------------------------------------
clean:
	@echo "Cleaning test artifacts..."
	find . -name "__pycache__" -type d -prune -exec rm -r {} \;
	rm -rf .pytest_cache
	rm -f .coverage
	rm -rf htmlcov
	rm -f tavern_test_report.html
	rm -f tavern_test_report.json

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
help:
	@echo "Available targets:"
	@echo "  sync               - Install all dependencies including dev"
	@echo "  install            - Install production dependencies only"
	@echo "  install_dev        - Install dev dependencies"
	@echo "  test               - Run all tests"
	@echo "  test_v             - Run tests with verbose output"
	@echo "  test_tavern        - Run only Tavern tests"
	@echo "  test_integration   - Run only integration tests"
	@echo "  test_performance   - Run only performance tests"
	@echo "  test_html          - Run tests and generate HTML report"
	@echo "  test_json          - Run tests and generate JSON report"
	@echo "  test_specific      - Run main Tavern test file"
	@echo "  test_advanced      - Run advanced scenario tests"
	@echo "  validate_yaml      - Validate YAML syntax with yamllint"
	@echo "  check_yaml_syntax  - Check YAML files for syntax errors"
	@echo "  format             - Format code with black"
	@echo "  lint               - Lint code with ruff"
	@echo "  lint_fix           - Lint and fix code with ruff"
	@echo "  clean              - Clean test artifacts"
	@echo "  help               - Show this help message"