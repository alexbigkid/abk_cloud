"""
Python test runner for Tavern YAML tests.

This module loads and executes Tavern YAML test files using pytest.
"""

import os
import pytest
import yaml
from pathlib import Path
from tavern.core import run


def get_tavern_config():
    """Get Tavern configuration from conftest.py."""
    # Import conftest to get the configuration
    import conftest
    config_fixture = conftest.tavern_global_cfg()
    return config_fixture


class TestTavernYamlTests:
    """Test class that runs all YAML-based Tavern tests."""
    
    def test_tavern_yaml_tests(self, tavern_global_cfg):
        """Load and run all Tavern YAML tests."""
        test_dir = Path(__file__).parent
        yaml_files = list(test_dir.glob("test_*.yaml"))
        
        assert yaml_files, "No YAML test files found"
        
        total_tests = 0
        failed_tests = 0
        
        for yaml_file in yaml_files:
            print(f"Running tests from: {yaml_file.name}")
            
            with open(yaml_file, 'r') as f:
                # Load all documents from the YAML file
                test_docs = list(yaml.safe_load_all(f))
                
            for i, test_spec in enumerate(test_docs):
                if not test_spec:  # Skip empty documents
                    continue
                    
                total_tests += 1
                test_name = test_spec.get('test_name', f'Test {i+1}')
                
                try:
                    print(f"  Running: {test_name}")
                    
                    # Merge the global config with the test spec
                    test_spec_with_config = {
                        **test_spec,
                        'includes': [tavern_global_cfg]
                    }
                    
                    # Run the individual test
                    run(test_spec_with_config, tavern_global_cfg)
                    print(f"  ✅ PASSED: {test_name}")
                    
                except Exception as e:
                    failed_tests += 1
                    print(f"  ❌ FAILED: {test_name} - {str(e)}")
                    # Don't fail immediately, collect all failures
        
        print(f"\nTavern Test Summary:")
        print(f"  Total tests: {total_tests}")
        print(f"  Passed: {total_tests - failed_tests}")
        print(f"  Failed: {failed_tests}")
        
        # Fail the pytest if any Tavern tests failed
        if failed_tests > 0:
            pytest.fail(f"{failed_tests} out of {total_tests} Tavern tests failed")


if __name__ == "__main__":
    # Allow running this file directly for debugging
    config = get_tavern_config()
    test_instance = TestTavernYamlTests()
    test_instance.test_tavern_yaml_tests(config)