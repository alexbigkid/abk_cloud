"""
Python test runner for Tavern YAML tests.

This module loads and executes Tavern YAML test files using requests directly.
"""

import os
import pytest
import yaml
import requests
from pathlib import Path


class TestTavernYamlTests:
    """Test class that runs all YAML-based Tavern tests."""
    
    def test_tavern_yaml_tests(self, tavern_global_cfg):
        """Load and run all Tavern YAML tests using direct HTTP requests."""
        test_dir = Path(__file__).parent
        yaml_files = list(test_dir.glob("test_*.yaml"))
        
        assert yaml_files, "No YAML test files found"
        
        total_tests = 0
        failed_tests = 0
        
        # Get configuration variables
        variables = tavern_global_cfg.get('variables', {})
        api_base_url = variables.get('api_base_url', '')
        
        print(f"Running Tavern tests against: {api_base_url}")
        
        for yaml_file in yaml_files:
            print(f"Running tests from: {yaml_file.name}")
            
            with open(yaml_file, 'r') as f:
                test_docs = list(yaml.safe_load_all(f))
                
            for i, test_spec in enumerate(test_docs):
                if not test_spec or not test_spec.get('test_name'):
                    continue
                    
                total_tests += 1
                test_name = test_spec.get('test_name', f'Test {i+1}')
                
                try:
                    print(f"  Running: {test_name}")
                    
                    # Execute each stage in the test
                    for stage in test_spec.get('stages', []):
                        stage_name = stage.get('name', 'Unnamed stage')
                        request_spec = stage.get('request', {})
                        response_spec = stage.get('response', {})
                        
                        # Build the request URL
                        url = request_spec.get('url', '').replace('{api_base_url}', api_base_url)
                        
                        # Substitute variables in URL and other fields
                        for key, value in variables.items():
                            url = url.replace(f"{{{key}}}", str(value))
                        
                        # Prepare request parameters
                        method = request_spec.get('method', 'GET').upper()
                        headers = request_spec.get('headers', {})
                        params = request_spec.get('params', {})
                        json_data = request_spec.get('json', {})
                        
                        # Substitute variables in params and json
                        if params:
                            for key, value in params.items():
                                if isinstance(value, str):
                                    for var_key, var_value in variables.items():
                                        value = value.replace(f"{{{var_key}}}", str(var_value))
                                    params[key] = value
                        
                        if json_data:
                            for key, value in json_data.items():
                                if isinstance(value, str):
                                    for var_key, var_value in variables.items():
                                        value = value.replace(f"{{{var_key}}}", str(var_value))
                                    json_data[key] = value
                        
                        
                        # Make the HTTP request
                        response = requests.request(
                            method=method,
                            url=url,
                            headers=headers,
                            params=params,
                            json=json_data if json_data else None,
                            timeout=30
                        )
                        
                        # Validate the response
                        expected_status = response_spec.get('status_code')
                        if expected_status and response.status_code != expected_status:
                            raise AssertionError(
                                f"Expected status {expected_status}, got {response.status_code}. "
                                f"Response: {response.text}"
                            )
                        
                        # Validate response headers
                        expected_headers = response_spec.get('headers', {})
                        for header_name, expected_value in expected_headers.items():
                            actual_value = response.headers.get(header_name)
                            if actual_value != expected_value:
                                raise AssertionError(
                                    f"Expected header {header_name}={expected_value}, "
                                    f"got {actual_value}"
                                )
                        
                        # Validate response JSON
                        expected_json = response_spec.get('json', {})
                        if expected_json:
                            try:
                                actual_json = response.json()
                                
                                # First, substitute variables in the entire expected_json structure
                                substituted_json = {}
                                for key, expected_value in expected_json.items():
                                    if isinstance(expected_value, str):
                                        # Substitute variables in expected value
                                        for var_key, var_value in variables.items():
                                            expected_value = expected_value.replace(f"{{{var_key}}}", str(var_value))
                                    substituted_json[key] = expected_value
                                
                                # Now validate each key
                                for key, expected_value in substituted_json.items():
                                    if key not in actual_json:
                                        raise AssertionError(f"Missing key '{key}' in response JSON")
                                    
                                    actual_value = actual_json[key]
                                    if actual_value != expected_value:
                                        raise AssertionError(
                                            f"Expected JSON key '{key}'={expected_value}, "
                                            f"got {actual_value}"
                                        )
                            except ValueError as e:
                                raise AssertionError(f"Invalid JSON response: {e}")
                    
                    print(f"  ✅ PASSED: {test_name}")
                    
                except Exception as e:
                    failed_tests += 1
                    print(f"  ❌ FAILED: {test_name} - {str(e)}")
        
        print(f"\nTavern Test Summary:")
        print(f"  Total tests: {total_tests}")
        print(f"  Passed: {total_tests - failed_tests}")
        print(f"  Failed: {failed_tests}")
        
        # Fail the pytest if any Tavern tests failed
        if failed_tests > 0:
            pytest.fail(f"{failed_tests} out of {total_tests} Tavern tests failed")