"""
Configuration and fixtures for abk-hello integration tests.

This module provides pytest configuration, fixtures, and utility functions
for integration testing of the abk-hello service.
"""

import os
import json
import pytest
import requests
from typing import Dict, Optional, Any
from urllib.parse import urljoin


@pytest.fixture(scope="session")
def api_config():
    """Provide API configuration for tests."""
    # Get environment from environment variable or default to 'dev'
    env = os.environ.get("ABK_DEPLOYMENT_ENV", "dev")
    region = os.environ.get("ABK_DEPLOYMENT_REGION", "us-west-2")
    
    # Try to get API URL from environment variable first
    api_url = os.environ.get("ABK_HELLO_API_URL")
    
    if not api_url:
        # Try to discover API Gateway URL from AWS CLI if available
        try:
            import subprocess
            
            # Get service name from serverless.yml or use default
            service_name = f"{env}-abk-hello"
            
            # Try to get API Gateway info
            result = subprocess.run(
                [
                    "aws", "apigateway", "get-rest-apis", 
                    "--region", region,
                    "--query", f"items[?name=='{service_name}'].{{id:id,name:name}}",
                    "--output", "json"
                ],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                apis = json.loads(result.stdout)
                if apis:
                    api_id = apis[0]["id"]
                    api_url = f"https://{api_id}.execute-api.{region}.amazonaws.com/{env}"
                    print(f"Discovered API URL: {api_url}")
        except (subprocess.SubprocessError, json.JSONDecodeError, ImportError, FileNotFoundError):
            # Fall back to placeholder if discovery fails
            print("Warning: Could not discover API Gateway URL, using placeholder")
            api_url = f"https://your-api-id.execute-api.{region}.amazonaws.com/{env}"
    
    return {
        "base_url": api_url,
        "endpoint_url": urljoin(api_url, "/abk-hello"),
        "environment": env,
        "region": region,
        "timeout": 30  # Default timeout for requests
    }


@pytest.fixture(scope="session")
def api_client(api_config):
    """Provide an API client for making requests."""
    
    class APIClient:
        """Simple API client for testing."""
        
        def __init__(self, config: Dict[str, str]):
            self.config = config
            self.session = requests.Session()
            self.session.timeout = config["timeout"]
        
        def get(self, params: Optional[Dict[str, str]] = None, **kwargs) -> requests.Response:
            """Make GET request to abk-hello endpoint."""
            return self.session.get(self.config["endpoint_url"], params=params, **kwargs)
        
        def post(self, json_data: Optional[Dict[str, Any]] = None, **kwargs) -> requests.Response:
            """Make POST request to abk-hello endpoint."""
            headers = kwargs.get("headers", {})
            headers.setdefault("Content-Type", "application/json")
            kwargs["headers"] = headers
            
            return self.session.post(
                self.config["endpoint_url"], 
                json=json_data, 
                **kwargs
            )
        
        def is_accessible(self) -> bool:
            """Check if the API endpoint is accessible."""
            try:
                # Make a simple request (expect 403 for missing params)
                response = self.get()
                return response.status_code in [200, 403, 404]  # Any valid HTTP response
            except requests.RequestException:
                return False
    
    return APIClient(api_config)


@pytest.fixture
def valid_test_data():
    """Provide valid test data for requests."""
    import uuid
    return {
        "deviceUuid": str(uuid.uuid4()),
        "txId": "test-transaction-12345"
    }


@pytest.fixture
def invalid_test_data():
    """Provide various invalid test data for negative testing."""
    import uuid
    
    return {
        "invalid_uuid": {
            "deviceUuid": "not-a-valid-uuid",
            "txId": "test-tx-123"
        },
        "missing_device_uuid": {
            "txId": "test-tx-123"
        },
        "missing_tx_id": {
            "deviceUuid": str(uuid.uuid4())
        },
        "empty_tx_id": {
            "deviceUuid": str(uuid.uuid4()),
            "txId": ""
        },
        "tx_id_too_long": {
            "deviceUuid": str(uuid.uuid4()),
            "txId": "x" * 37  # Exceeds 36 character limit
        },
        "extra_properties": {
            "deviceUuid": str(uuid.uuid4()),
            "txId": "test-tx-123",
            "extraField": "should-be-rejected"
        }
    }


@pytest.fixture(scope="session", autouse=True)
def verify_api_accessibility(api_client):
    """Verify API is accessible before running tests."""
    if not api_client.is_accessible():
        pytest.skip(
            f"API endpoint {api_client.config['endpoint_url']} is not accessible. "
            "Please ensure the service is deployed and the API URL is correct."
        )


def pytest_configure(config):
    """Configure pytest with custom markers."""
    config.addinivalue_line(
        "markers", "integration: mark test as integration test"
    )
    config.addinivalue_line(
        "markers", "performance: mark test as performance test"
    )
    config.addinivalue_line(
        "markers", "slow: mark test as slow running"
    )


def pytest_collection_modifyitems(config, items):
    """Automatically mark integration tests."""
    for item in items:
        # Mark all tests in this directory as integration tests
        if "integration" in str(item.fspath):
            item.add_marker(pytest.mark.integration)