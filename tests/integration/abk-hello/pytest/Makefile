.PHONY: sync install install_dev test test_v clean help
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

test_integration:
	uv run pytest -m integration

test_performance:
	uv run pytest -m performance

test_html:
	uv run pytest --html=integration_test_report.html --self-contained-html

test_json:
	uv run pytest --json-report --json-report-file=integration_test_report.json

coverage:
	uv run pytest --cov=. --cov-report=term-missing --cov-report=html

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
	rm -f integration_test_report.html
	rm -f integration_test_report.json

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
	@echo "  test_integration   - Run only integration tests"
	@echo "  test_performance   - Run only performance tests"
	@echo "  test_html          - Run tests and generate HTML report"
	@echo "  test_json          - Run tests and generate JSON report"
	@echo "  coverage           - Run tests with coverage reporting"
	@echo "  format             - Format code with black"
	@echo "  lint               - Lint code with ruff"
	@echo "  lint_fix           - Lint and fix code with ruff"
	@echo "  clean              - Clean test artifacts"
	@echo "  help               - Show this help message"