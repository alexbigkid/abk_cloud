#!/usr/bin/env python3
"""
Integration tests for abk-hello service.

This module contains integration tests that verify the abk-hello service
is working correctly when deployed to AWS Lambda and accessible via API Gateway.
"""

import json
import uuid
import requests
import pytest
import os
from typing import Dict, Any, Optional
from urllib.parse import urlencode


class TestAbkHelloIntegration:
    """Integration tests for the abk-hello service."""

    @classmethod
    def setup_class(cls):
        """Set up test class with API configuration."""
        # Get API Gateway URL from environment or config
        cls.api_base_url = os.environ.get(
            "ABK_HELLO_API_URL", 
            "https://your-api-id.execute-api.us-west-2.amazonaws.com/dev"
        )
        cls.api_endpoint = f"{cls.api_base_url}/abk-hello"
        
        # Test data
        cls.valid_device_uuid = str(uuid.uuid4())
        cls.valid_tx_id = "test-tx-12345"
        
        print(f"Testing API endpoint: {cls.api_endpoint}")

    def test_get_with_valid_query_parameters(self):
        """Test GET request with valid query parameters."""
        params = {
            "deviceUuid": self.valid_device_uuid,
            "txId": self.valid_tx_id
        }
        
        response = requests.get(self.api_endpoint, params=params)
        
        assert response.status_code == 200
        assert response.headers.get("Content-Type") == "application/json"
        
        response_data = response.json()
        assert response_data["msg"] == "ok"
        assert response_data["txId"] == self.valid_tx_id

    def test_get_with_missing_required_parameters(self):
        """Test GET request with missing required parameters."""
        # Missing deviceUuid
        params = {"txId": self.valid_tx_id}
        response = requests.get(self.api_endpoint, params=params)
        assert response.status_code == 403
        
        response_data = response.json()
        assert response_data["msg"] == "error"

    def test_get_with_invalid_device_uuid_format(self):
        """Test GET request with invalid UUID format."""
        params = {
            "deviceUuid": "invalid-uuid-format",
            "txId": self.valid_tx_id
        }
        
        response = requests.get(self.api_endpoint, params=params)
        assert response.status_code == 403
        
        response_data = response.json()
        assert response_data["msg"] == "error"

    def test_get_with_empty_tx_id(self):
        """Test GET request with empty txId."""
        params = {
            "deviceUuid": self.valid_device_uuid,
            "txId": ""
        }
        
        response = requests.get(self.api_endpoint, params=params)
        assert response.status_code == 403
        
        response_data = response.json()
        assert response_data["msg"] == "error"

    def test_get_with_tx_id_too_long(self):
        """Test GET request with txId exceeding maximum length."""
        long_tx_id = "x" * 37  # Exceeds 36 character limit
        params = {
            "deviceUuid": self.valid_device_uuid,
            "txId": long_tx_id
        }
        
        response = requests.get(self.api_endpoint, params=params)
        assert response.status_code == 403
        
        response_data = response.json()
        assert response_data["msg"] == "error"

    def test_post_with_valid_json_body(self):
        """Test POST request with valid JSON body."""
        payload = {
            "deviceUuid": self.valid_device_uuid,
            "txId": self.valid_tx_id
        }
        
        response = requests.post(
            self.api_endpoint,
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        
        assert response.status_code == 200
        assert response.headers.get("Content-Type") == "application/json"
        
        response_data = response.json()
        assert response_data["msg"] == "ok"
        assert response_data["txId"] == self.valid_tx_id

    def test_post_with_invalid_json_body(self):
        """Test POST request with invalid JSON body."""
        payload = {
            "deviceUuid": "invalid-uuid",
            "txId": self.valid_tx_id
        }
        
        response = requests.post(
            self.api_endpoint,
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        
        assert response.status_code == 403
        
        response_data = response.json()
        assert response_data["msg"] == "error"

    def test_post_with_extra_properties(self):
        """Test POST request with additional properties (should be rejected)."""
        payload = {
            "deviceUuid": self.valid_device_uuid,
            "txId": self.valid_tx_id,
            "extraField": "should be rejected"
        }
        
        response = requests.post(
            self.api_endpoint,
            json=payload,
            headers={"Content-Type": "application/json"}
        )
        
        assert response.status_code == 403
        
        response_data = response.json()
        assert response_data["msg"] == "error"

    def test_response_headers_cors(self):
        """Test that CORS headers are properly set."""
        params = {
            "deviceUuid": self.valid_device_uuid,
            "txId": self.valid_tx_id
        }
        
        response = requests.get(self.api_endpoint, params=params)
        
        assert response.headers.get("Access-Control-Allow-Origin") == "*"
        assert response.headers.get("Access-Control-Allow-Credentials") == "true"

    def test_multiple_concurrent_requests(self):
        """Test multiple concurrent requests to ensure Lambda handles concurrency."""
        import concurrent.futures
        import threading
        
        def make_request(request_id: int) -> Dict[str, Any]:
            params = {
                "deviceUuid": str(uuid.uuid4()),
                "txId": f"concurrent-test-{request_id}"
            }
            response = requests.get(self.api_endpoint, params=params)
            return {
                "request_id": request_id,
                "status_code": response.status_code,
                "response_data": response.json()
            }
        
        # Make 5 concurrent requests
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(make_request, i) for i in range(5)]
            results = [future.result() for future in concurrent.futures.as_completed(futures)]
        
        # All requests should succeed
        for result in results:
            assert result["status_code"] == 200
            assert result["response_data"]["msg"] == "ok"
            assert result["response_data"]["txId"].startswith("concurrent-test-")

    def test_api_endpoint_accessibility(self):
        """Test that the API endpoint is accessible and returns proper error for no params."""
        response = requests.get(self.api_endpoint)
        
        # Should return 403 for missing parameters, but endpoint should be reachable
        assert response.status_code == 403
        assert response.headers.get("Content-Type") == "application/json"
        
        response_data = response.json()
        assert response_data["msg"] == "error"


class TestAbkHelloPerformance:
    """Performance tests for the abk-hello service."""

    @classmethod
    def setup_class(cls):
        """Set up test class with API configuration."""
        cls.api_base_url = os.environ.get(
            "ABK_HELLO_API_URL",
            "https://your-api-id.execute-api.us-west-2.amazonaws.com/dev"
        )
        cls.api_endpoint = f"{cls.api_base_url}/abk-hello"

    def test_response_time(self):
        """Test that API response time is within acceptable limits."""
        import time
        
        params = {
            "deviceUuid": str(uuid.uuid4()),
            "txId": "performance-test"
        }
        
        start_time = time.time()
        response = requests.get(self.api_endpoint, params=params)
        end_time = time.time()
        
        response_time = end_time - start_time
        
        assert response.status_code == 200
        # Response should be under 5 seconds (generous for cold start)
        assert response_time < 5.0, f"Response time {response_time:.2f}s exceeds 5s limit"
        print(f"Response time: {response_time:.2f}s")

    def test_warm_lambda_response_time(self):
        """Test response time for warm Lambda (after initial call)."""
        import time
        
        params = {
            "deviceUuid": str(uuid.uuid4()),
            "txId": "warm-up-call"
        }
        
        # Warm up the Lambda
        requests.get(self.api_endpoint, params=params)
        
        # Now test the warm Lambda response time
        params["txId"] = "warm-lambda-test"
        start_time = time.time()
        response = requests.get(self.api_endpoint, params=params)
        end_time = time.time()
        
        response_time = end_time - start_time
        
        assert response.status_code == 200
        # Warm Lambda should respond much faster
        assert response_time < 1.0, f"Warm Lambda response time {response_time:.2f}s exceeds 1s"
        print(f"Warm Lambda response time: {response_time:.2f}s")


if __name__ == "__main__":
    # Allow running tests directly
    pytest.main([__file__, "-v"])