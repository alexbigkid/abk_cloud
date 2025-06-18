"""
Tavern configuration and fixtures for abk-hello integration tests.

This module provides pytest configuration and fixtures specifically for Tavern-based
API testing of the abk-hello service.
"""

import os
import json
import uuid
import pytest
import subprocess
from typing import Dict, Any


@pytest.fixture(scope="session")
def tavern_global_cfg():
    """
    Global configuration for Tavern tests.
    
    This fixture provides variables that can be used in Tavern YAML tests
    using the {variable_name} syntax.
    """
    # Get environment configuration
    env = os.environ.get("ABK_DEPLOYMENT_ENV", "dev")
    region = os.environ.get("ABK_DEPLOYMENT_REGION", "us-west-2")
    
    # Get API URL from environment variable
    api_url = os.environ.get("ABK_HELLO_API_URL")
    
    if not api_url:
        # Fall back to placeholder if not set
        api_url = f"https://your-api-id.execute-api.{region}.amazonaws.com/{env}"
    
    # Generate test data
    valid_device_uuid = str(uuid.uuid4())
    valid_tx_id = "tavern-test-12345"
    
    # Create repeated string for length validation tests
    repeated_x_36_chars = "x" * 36  # This will make total length 37 when combined with the 'x' in the template
    
    return {
        "variables": {
            # API Configuration
            "api_base_url": api_url,
            "environment": env,
            "region": region,
            
            # Valid test data
            "valid_device_uuid": valid_device_uuid,
            "valid_tx_id": valid_tx_id,
            
            # Test data for concurrent requests
            "concurrent_uuid_1": str(uuid.uuid4()),
            "concurrent_uuid_2": str(uuid.uuid4()),
            
            # Test data for validation
            "repeated_x_36_chars": repeated_x_36_chars,
            
            # Additional UUIDs for various tests
            "test_uuid_1": str(uuid.uuid4()),
            "test_uuid_2": str(uuid.uuid4()),
            "test_uuid_3": str(uuid.uuid4()),
        }
    }


@pytest.fixture(scope="session", autouse=True)
def verify_api_accessibility_tavern(tavern_global_cfg):
    """
    Verify API is accessible before running Tavern tests.
    """
    import requests
    
    api_url = tavern_global_cfg["variables"]["api_base_url"]
    endpoint = f"{api_url}/abk-hello"
    
    try:
        # Make a simple request to check if endpoint is accessible
        response = requests.get(endpoint, timeout=30)
        # We expect 403 for missing parameters, which means the endpoint is working
        if response.status_code not in [200, 403, 404]:
            pytest.skip(
                f"API endpoint {endpoint} returned unexpected status code {response.status_code}. "
                "Please ensure the service is deployed."
            )
    except requests.RequestException as e:
        pytest.skip(
            f"API endpoint {endpoint} is not accessible: {e}. "
            "Please ensure the service is deployed and the API URL is correct."
        )


def pytest_configure(config):
    """Configure pytest with Tavern-specific markers."""
    config.addinivalue_line(
        "markers", "tavern: mark test as Tavern-based API test"
    )


def pytest_collection_modifyitems(config, items):
    """Automatically mark Tavern tests."""
    for item in items:
        # Mark all YAML-based tests as tavern tests
        if hasattr(item, 'fspath') and str(item.fspath).endswith('.yaml'):
            item.add_marker(pytest.mark.tavern)
        # Also mark tests in tavern directory
        elif "tavern" in str(getattr(item, 'fspath', '')):
            item.add_marker(pytest.mark.tavern)


# Additional fixtures for more complex test scenarios
@pytest.fixture(scope="session")
def api_endpoints(tavern_global_cfg):
    """Provide common API endpoints for tests."""
    base_url = tavern_global_cfg["variables"]["api_base_url"]
    
    return {
        "abk_hello": f"{base_url}/abk-hello",
        "health": f"{base_url}/health",  # If you have a health endpoint
        "base": base_url
    }


@pytest.fixture
def fresh_test_data():
    """Generate fresh test data for each test that needs it."""
    return {
        "device_uuid": str(uuid.uuid4()),
        "tx_id": f"test-{uuid.uuid4().hex[:8]}",
        "timestamp": "2024-01-01T00:00:00Z"
    }


@pytest.fixture(scope="session")
def test_data_sets():
    """Provide various test data sets for comprehensive testing."""
    return {
        "valid_requests": [
            {
                "deviceUuid": str(uuid.uuid4()),
                "txId": "valid-test-1"
            },
            {
                "deviceUuid": str(uuid.uuid4()),
                "txId": "valid-test-2"
            }
        ],
        "invalid_uuids": [
            "not-a-uuid",
            "12345678-1234-1234-1234-12345678901",  # too short
            "12345678-1234-1234-1234-1234567890123",  # too long
            "12345678-1234-1234-1234-123456789012g",  # invalid character
            "",
            None
        ],
        "invalid_tx_ids": [
            "",  # empty
            "x" * 37,  # too long
            None
        ]
    }