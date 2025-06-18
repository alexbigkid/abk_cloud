# ABK-Hello Tavern Integration Tests

This directory contains [Tavern](https://github.com/taverntesting/tavern) integration tests for the `abk-hello` serverless service. Tavern is a pytest plugin that allows you to write API tests in YAML format, making them more readable and maintainable than traditional code-based tests.

## Why Tavern?

### Advantages of Tavern over Pure Pytest:

1. **YAML-Based**: Tests are written in human-readable YAML format
2. **Declarative**: Focus on what you want to test, not how to implement it
3. **Less Code**: Significantly fewer lines than equivalent Python tests
4. **Schema Validation**: Built-in JSON schema validation
5. **Reusable Components**: Common patterns can be defined once and reused
6. **Response Chaining**: Easy to pass data between test stages
7. **Non-Technical Friendly**: QA team members can write/modify tests without deep Python knowledge

### When to Use Tavern vs Pytest:

- **Use Tavern for**: API contract testing, happy path validation, standard REST API workflows
- **Use Pytest for**: Complex logic, custom validation, performance testing, advanced mocking

## Test Structure

```
tavern/
├── test_abk_hello_tavern.yaml    # Main API functionality tests
├── advanced_scenarios.yaml       # Complex validation scenarios  
├── common.yaml                   # Reusable YAML components
└── conftest.py                   # Tavern-specific pytest configuration
```

## Test Files

### 1. `test_abk_hello_tavern.yaml`
Main test suite covering:
- Valid GET/POST requests
- Input validation (UUID format, parameter requirements)
- Error handling and status codes
- CORS headers validation
- Basic performance testing

### 2. `advanced_scenarios.yaml`
Complex scenarios including:
- Boundary value testing
- UUID format variations (upper/lower/mixed case)
- HTTP method validation
- Error response consistency
- Load simulation
- Special character handling

### 3. `common.yaml`
Reusable YAML anchors and references:
- Common headers (`&common_headers`)
- Response structures (`&success_response`, `&error_response`)
- Request templates (`&valid_get_request`, `&valid_post_request`)

## Running Tavern Tests

### Using the Tavern Test Runner (Recommended)

```bash
# Run all Tavern tests against dev environment
./run_tavern_tests.sh

# Run tests against specific environment
./run_tavern_tests.sh qa us-west-2

# Run with verbose output
./run_tavern_tests.sh dev us-west-2 true

# Run specific test files
./run_tavern_tests.sh dev us-west-2 false "test_*tavern*"
./run_tavern_tests.sh dev us-west-2 false "*advanced*"

# Show help
./run_tavern_tests.sh --help
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

# Run Tavern tests using UV (recommended)
uv run pytest . -v --tb=short

# Or using legacy python method
python -m pytest . -v --tb=short
```

## Tavern Test Configuration

### Global Variables (`conftest.py`)

Tavern tests use variables defined in `tavern_global_cfg` fixture:

```yaml
# In YAML tests, use curly braces to reference variables
url: "{api_base_url}/abk-hello"
params:
  deviceUuid: "{valid_device_uuid}"
  txId: "{valid_tx_id}"
```

Available variables:
- `api_base_url` - Discovered or configured API Gateway URL
- `valid_device_uuid` - Generated UUID for testing
- `valid_tx_id` - Valid transaction ID
- `environment` - Target environment (dev/qa/prod)
- `region` - AWS region

### YAML Anchors and References

Using `common.yaml` for reusable components:

```yaml
# Define reusable component
common_headers: &common_headers
  content-type: application/json
  user-agent: "ABK-Hello-Tavern-Tests/1.0"

# Use the component
stages:
  - name: Test with common headers
    request:
      headers:
        <<: *common_headers  # Include all common headers
```

## Example Tavern Test

```yaml
---
test_name: Simple GET Request Test

stages:
  - name: Test valid API call
    request:
      url: "{api_base_url}/abk-hello"
      method: GET
      params:
        deviceUuid: "{valid_device_uuid}"
        txId: "simple-test"
    response:
      status_code: 200
      headers:
        content-type: application/json
        access-control-allow-origin: "*"
      json:
        msg: "ok"
        txId: "simple-test"
```

## Advanced Tavern Features

### Response Data Chaining

```yaml
stages:
  - name: Get data from first request
    request:
      url: "{api_base_url}/abk-hello"
      method: GET
      params:
        deviceUuid: "{valid_device_uuid}"
        txId: "chain-test"
    response:
      status_code: 200
      save:
        json:
          saved_msg: msg  # Save response field

  - name: Use saved data in second request
    request:
      url: "{api_base_url}/abk-hello"
      method: POST
      json:
        deviceUuid: "{valid_device_uuid}"
        txId: "using-{saved_msg}"  # Use saved data
    response:
      status_code: 200
```

### Multiple Test Documents

Separate test scenarios with `---`:

```yaml
---
test_name: First Test Scenario
stages:
  - name: Test case 1
    # ... test definition

---
test_name: Second Test Scenario  
stages:
  - name: Test case 2
    # ... test definition
```

## Reports and Output

Tavern tests generate the same reports as pytest tests:

- **HTML Report**: `tavern_test_report.html`
- **JSON Report**: `tavern_test_report.json`
- **Console Output**: Detailed test execution logs

## Troubleshooting Tavern Tests

### Common Issues

1. **YAML Syntax Errors**
   ```bash
   # Validate YAML syntax
   python -c "import yaml; yaml.safe_load(open('tavern/test_file.yaml'))"
   ```

2. **Variable Not Found**
   - Check `conftest.py` for variable definitions
   - Ensure variable names match exactly (case-sensitive)

3. **API URL Discovery Fails**
   - Manually set `ABK_HELLO_API_URL` environment variable
   - Check AWS credentials and permissions

4. **Test Flakiness**
   - Use unique UUIDs for each test run
   - Add appropriate delays between requests if needed

### Debug Mode

```bash
# Run with maximum verbosity
./run_tavern_tests.sh dev us-west-2 true

# Or with pytest directly
python -m pytest tavern/ -v -s --tb=long
```

## Comparison: Tavern vs Pytest

### Same Test in Both Formats

**Tavern (YAML):**
```yaml
---
test_name: Valid GET Request
stages:
  - name: Test valid parameters
    request:
      url: "{api_base_url}/abk-hello"
      method: GET
      params:
        deviceUuid: "{valid_device_uuid}"
        txId: "test-123"
    response:
      status_code: 200
      json:
        msg: "ok"
        txId: "test-123"
```

**Pytest (Python):**
```python
def test_valid_get_request(api_client, valid_test_data):
    response = api_client.get(params={
        "deviceUuid": valid_test_data["deviceUuid"],
        "txId": "test-123"
    })
    
    assert response.status_code == 200
    response_data = response.json()
    assert response_data["msg"] == "ok"
    assert response_data["txId"] == "test-123"
```

### Lines of Code Comparison

- **Tavern**: ~15 lines for comprehensive test
- **Pytest**: ~25-30 lines for equivalent test
- **Readability**: Tavern YAML is more declarative and readable
- **Maintenance**: Tavern requires less code maintenance

## Integration with CI/CD

Tavern tests integrate seamlessly with existing pytest infrastructure:

```yaml
# GitHub Actions example
- name: Run Tavern Integration Tests
  run: |
    cd tests/integration/abk-hello
    ./run_tavern_tests.sh ${{ env.ENVIRONMENT }} ${{ env.REGION }}
  env:
    AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
    AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## Best Practices

1. **Use Descriptive Test Names**: Make test intentions clear
2. **Leverage YAML Anchors**: Reduce duplication with reusable components
3. **Validate Response Schema**: Use Tavern's built-in JSON validation
4. **Group Related Tests**: Use multiple documents in single YAML file
5. **Generate Dynamic Data**: Use fixtures for UUIDs and timestamps
6. **Document Complex Tests**: Add comments for complex validation logic

## Adding New Tavern Tests

1. Create new YAML file or add to existing file:
   ```yaml
   ---
   test_name: Your New Test
   stages:
     - name: Your test stage
       request:
         # Request definition
       response:
         # Expected response
   ```

2. Use existing variables from `conftest.py`
3. Follow naming convention: `test_*.yaml`
4. Add to appropriate test runner patterns if needed