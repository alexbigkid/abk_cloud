# ABK-Hello Integration Tests

This directory contains integration tests for the `abk-hello` serverless service. These tests verify that the deployed service is working correctly by making actual HTTP requests to the API Gateway endpoints.

## Test Structure

- `test_abk_hello_integration.py` - Main integration test suite
- `conftest.py` - Pytest configuration and fixtures
- `run_integration_tests.sh` - Test runner script
- `pyproject.toml` - UV-based dependency configuration
- `requirements.txt` - Legacy pip dependencies (kept for compatibility)
- `README.md` - This documentation

## Prerequisites

1. **AWS Credentials**: Ensure AWS credentials are configured
   ```bash
   export AWS_ACCESS_KEY_ID=your-access-key
   export AWS_SECRET_ACCESS_KEY=your-secret-key
   ```

2. **Service Deployment**: The `abk-hello` service must be deployed to the target environment

3. **UV Package Manager**: Ensure UV is installed for modern dependency management
   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   # Or: pip install uv
   ```

## Running Tests

### Using the Test Runner Script (Recommended)

```bash
# Run tests against dev environment (default)
./run_integration_tests.sh

# Run tests against specific environment
./run_integration_tests.sh qa us-west-2

# Run with verbose output
./run_integration_tests.sh dev us-west-2 true

# Show help
./run_integration_tests.sh --help
```

### Direct pytest Execution

```bash
# Install dependencies using UV (recommended)
uv sync --no-dev

# Or using legacy pip method
pip install -r requirements.txt

# Set environment variables
export ABK_HELLO_API_URL="https://your-api-id.execute-api.us-west-2.amazonaws.com/dev"
export ABK_DEPLOYMENT_ENV="dev"
export ABK_DEPLOYMENT_REGION="us-west-2"

# Run tests using UV (recommended)
uv run pytest test_abk_hello_integration.py -v

# Or using legacy python method
python -m pytest test_abk_hello_integration.py -v
```

## Test Configuration

### Environment Variables

- `ABK_HELLO_API_URL` - API Gateway URL (auto-discovered if not set)
- `ABK_DEPLOYMENT_ENV` - Target environment (dev, qa, prod)
- `ABK_DEPLOYMENT_REGION` - AWS region
- `AWS_ACCESS_KEY_ID` - AWS access key
- `AWS_SECRET_ACCESS_KEY` - AWS secret key

### Auto-Discovery

The test runner will attempt to automatically discover the API Gateway URL if `ABK_HELLO_API_URL` is not set. This uses the AWS CLI to query for API Gateways with the expected naming pattern.

## Test Categories

### Functional Tests (`TestAbkHelloIntegration`)

- **Valid GET Requests**: Tests with proper query parameters
- **Valid POST Requests**: Tests with proper JSON body
- **Input Validation**: Tests for various invalid inputs
- **Error Handling**: Verifies proper error responses
- **CORS Headers**: Validates Cross-Origin Resource Sharing setup
- **Concurrency**: Tests multiple simultaneous requests

### Performance Tests (`TestAbkHelloPerformance`)

- **Response Time**: Measures API response times
- **Cold vs Warm Lambda**: Compares cold start vs warm execution times

## Test Data

Tests use dynamically generated UUIDs and transaction IDs to avoid conflicts. The test fixtures in `conftest.py` provide:

- `valid_test_data` - Properly formatted test data
- `invalid_test_data` - Various invalid inputs for negative testing
- `api_client` - HTTP client with proper configuration

## Expected Test Results

### Successful Responses (200 OK)
```json
{
  "msg": "ok",
  "txId": "your-transaction-id"
}
```

### Error Responses (403 Forbidden)
```json
{
  "msg": "error",
  "txId": "your-transaction-id-or-empty"
}
```

## Test Reports

The test runner generates two types of reports:

1. **HTML Report**: `integration_test_report.html` - Human-readable test results
2. **JSON Report**: `integration_test_report.json` - Machine-readable test data

## Troubleshooting

### Common Issues

1. **API URL Not Found**
   - Ensure the service is deployed
   - Check that AWS credentials have API Gateway permissions
   - Manually set `ABK_HELLO_API_URL` if auto-discovery fails

2. **AWS Connectivity Issues**
   - Verify AWS credentials are correctly set
   - Check network connectivity to AWS
   - Ensure correct region is specified

3. **Test Failures**
   - Check service logs in CloudWatch
   - Verify service deployment status
   - Review API Gateway configuration

### Debug Mode

Run tests with verbose output for debugging:

```bash
./run_integration_tests.sh dev us-west-2 true
```

Or with pytest directly:

```bash
python -m pytest test_abk_hello_integration.py -v -s
```

## Integration with CI/CD

These tests can be integrated into your CI/CD pipeline after deployment:

```yaml
# Example GitHub Actions step
- name: Run Integration Tests
  run: |
    cd tests/integration/abk-hello
    ./run_integration_tests.sh ${{ env.ENVIRONMENT }} ${{ env.REGION }}
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Adding New Tests

To add new integration tests:

1. Add test methods to `TestAbkHelloIntegration` class
2. Use the provided fixtures for consistent test data
3. Follow the naming convention: `test_<scenario>_<expected_outcome>`
4. Add appropriate markers for test categorization

Example:
```python
def test_new_endpoint_with_valid_data(self, api_client, valid_test_data):
    """Test description."""
    response = api_client.get(params=valid_test_data)
    assert response.status_code == 200
```