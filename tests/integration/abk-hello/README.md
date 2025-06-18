# ABK-Hello Integration Tests

This directory contains comprehensive integration tests for the `abk-hello` serverless service. The tests are organized into two frameworks to provide flexibility in testing approaches:

- **`pytest/`** - Python-based integration tests with programmatic control
- **`tavern/`** - YAML-based API tests using the Tavern framework

## Quick Start

```bash
# Run all tests (both pytest and Tavern)
./run_tests.sh

# Run against specific environment
./run_tests.sh qa us-west-2

# Run only pytest tests
./run_tests.sh dev us-west-2 false pytest

# Run only Tavern tests
./run_tests.sh dev us-west-2 false tavern

# Run with verbose output
./run_tests.sh dev us-west-2 true
```

## Directory Structure

```
tests/integration/abk-hello/
├── run_tests.sh              # 🎯 Main test runner (USE THIS)
├── README.md                 # This documentation
├── pytest/                  # Python-based tests
│   ├── test_abk_hello_integration.py
│   ├── conftest.py
│   ├── requirements.txt
│   ├── run_integration_tests.sh
│   └── README.md
└── tavern/                   # YAML-based tests
    ├── test_abk_hello_tavern.yaml
    ├── advanced_scenarios.yaml
    ├── common.yaml
    ├── conftest.py
    ├── requirements.txt
    ├── run_tavern_tests.sh
    └── README.md
```

## Unified Test Runner

### `run_tests.sh` - Main Entry Point

The unified test runner provides a single interface for all integration testing:

```bash
Usage: ./run_tests.sh [ENVIRONMENT] [REGION] [VERBOSE] [TEST_SUITE]

Parameters:
  ENVIRONMENT  - Target environment (dev, qa, prod) [default: dev]
  REGION       - AWS region [default: us-west-2]
  VERBOSE      - Enable verbose output (true/false) [default: false]
  TEST_SUITE   - Test suite to run (all/pytest/tavern) [default: all]
```

### Key Features:

- ✅ **Single Entry Point** - One script runs both test frameworks
- ✅ **Framework Selection** - Choose pytest, Tavern, or both
- ✅ **AWS Integration** - Automatic API discovery and credential validation
- ✅ **Combined Reporting** - Aggregated results from both test suites
- ✅ **Environment Aware** - Supports dev/qa/prod environments
- ✅ **CI/CD Ready** - Proper exit codes and report generation

## Test Framework Comparison

| Feature | Pytest | Tavern |
|---------|--------|--------|
| **Format** | Python code | YAML declarative |
| **Learning Curve** | Moderate | Low |
| **Flexibility** | High | Medium |
| **Readability** | Good | Excellent |
| **Maintenance** | Medium | Low |
| **Custom Logic** | Excellent | Limited |
| **QA Friendly** | No | Yes |

### When to Use Each Framework:

**Use Pytest for:**
- Complex validation logic
- Performance testing with custom metrics
- Advanced mocking and fixtures
- Custom test data generation
- Integration with other Python libraries

**Use Tavern for:**
- API contract validation
- Happy path testing
- Standard REST API workflows
- Tests that non-developers need to modify
- Quick prototyping of API tests

## Prerequisites

1. **AWS Credentials**: Configure AWS access
   ```bash
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   ```

2. **Service Deployment**: The `abk-hello` service must be deployed

3. **UV Package Manager**: Modern Python dependency management
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   # Or: pip install uv
   ```

4. **Dependencies**: Automatically installed by test runners using UV

## Environment Variables

- `ABK_HELLO_API_URL` - Override API Gateway URL (auto-discovered if not set)
- `ABK_DEPLOYMENT_ENV` - Target environment (dev, qa, prod)
- `ABK_DEPLOYMENT_REGION` - AWS region
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key

## Test Reports

Both frameworks generate detailed reports:

### Pytest Reports:
- `pytest/integration_test_report.html` - Interactive HTML report
- `pytest/integration_test_report.json` - Machine-readable results

### Tavern Reports:
- `tavern/tavern_test_report.html` - Interactive HTML report
- `tavern/tavern_test_report.json` - Machine-readable results

### Combined Summary:
The unified runner provides aggregated statistics from both test suites.

## Examples

### Run All Tests
```bash
# Default: all tests against dev environment
./run_tests.sh

# All tests against qa environment
./run_tests.sh qa us-west-2

# All tests with verbose output
./run_tests.sh dev us-west-2 true
```

### Framework-Specific Testing
```bash
# Only Python pytest tests
./run_tests.sh dev us-west-2 false pytest

# Only Tavern YAML tests
./run_tests.sh dev us-west-2 false tavern
```

### CI/CD Integration
```bash
# Example GitHub Actions usage
- name: Run Integration Tests
  run: |
    cd tests/integration/abk-hello
    ./run_tests.sh ${{ env.ENVIRONMENT }} ${{ env.REGION }}
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Test Coverage

Both test frameworks cover:

### Functional Testing:
- ✅ Valid GET/POST requests
- ✅ Input validation (UUID format, parameter requirements)
- ✅ Error handling and proper status codes
- ✅ CORS headers validation
- ✅ Response schema validation

### Performance Testing:
- ✅ Response time measurements
- ✅ Cold start vs warm Lambda performance
- ✅ Concurrent request handling

### Edge Cases:
- ✅ Boundary value testing
- ✅ Invalid input handling
- ✅ HTTP method validation
- ✅ Special character handling

## Troubleshooting

### Common Issues:

1. **API URL Not Found**
   ```bash
   # Manually set API URL if auto-discovery fails
   export ABK_HELLO_API_URL="https://your-api-id.execute-api.us-west-2.amazonaws.com/dev"
   ```

2. **AWS Connectivity Issues**
   ```bash
   # Verify AWS credentials
   aws sts get-caller-identity
   ```

3. **Test Failures**
   - Check service deployment status
   - Review CloudWatch logs for Lambda errors
   - Verify API Gateway configuration

### Debug Mode:
```bash
# Run with verbose output for troubleshooting
./run_tests.sh dev us-west-2 true

# Or run individual frameworks directly
cd pytest && ./run_integration_tests.sh dev us-west-2 true
cd tavern && ./run_tavern_tests.sh dev us-west-2 true
```

## Adding New Tests

### For Pytest Tests:
1. Add test methods to `pytest/test_abk_hello_integration.py`
2. Use existing fixtures from `pytest/conftest.py`
3. Follow naming convention: `test_<scenario>_<expected_outcome>`

### For Tavern Tests:
1. Add test scenarios to existing YAML files or create new ones
2. Use variables from `tavern/conftest.py`
3. Leverage reusable components from `tavern/common.yaml`

### Example New Test:

**Pytest:**
```python
def test_new_feature(api_client, valid_test_data):
    """Test new feature functionality."""
    response = api_client.get(params=valid_test_data)
    assert response.status_code == 200
```

**Tavern:**
```yaml
---
test_name: New Feature Test
stages:
  - name: Test new feature
    request:
      url: "{api_base_url}/abk-hello"
      method: GET
      params:
        deviceUuid: "{valid_device_uuid}"
        txId: "new-feature-test"
    response:
      status_code: 200
      json:
        msg: "ok"
```

## Best Practices

1. **Use the Unified Runner** - Always use `./run_tests.sh` as the main entry point
2. **Framework Selection** - Choose the right tool for the job (pytest for complex logic, Tavern for API contracts)
3. **Environment Testing** - Test against multiple environments before production deployment
4. **Report Review** - Always check both HTML and JSON reports for detailed results
5. **Parallel Development** - Both frameworks can be developed simultaneously by different team members
6. **Documentation** - Keep framework-specific README files updated for detailed usage

## Support

For detailed information about each testing framework:
- **Pytest**: See `pytest/README.md`
- **Tavern**: See `tavern/README.md`

For issues or questions, check the individual framework documentation or contact the development team.