"""Unit tests for abk_hello.py."""

# Standard library imports
import logging
import os

# Own modules imports
from abk_hello.abk_hello_io import AhLambdaRequestBody, AhLambdaResponseBody
from abk_hello import abk_hello

# Third party imports
import pytest

logging.basicConfig(format="[%(funcName)s]:[%(levelname)s]: %(message)s")
tst_logger = logging.getLogger(__name__)
log_level = os.environ.get("LOG_LEVEL", "WARNING").upper()
tst_logger.setLevel(logging.getLevelName(log_level))


# -----------------------------------------------------------------------------
# help classes
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# local constants
# -----------------------------------------------------------------------------
# Common test definitions
# -----------------------------------------------------------------------------
TEST_ST_THING_NAME = "abeabeab-eabe-abea-beab-abeabeabeabe"
VALID_REQ = AhLambdaRequestBody(
    deviceUuid=TEST_ST_THING_NAME, txId="test_txId_from_valid_lambda_req"
)

INVALID_RESP_BODY = AhLambdaResponseBody(msg="error", txId=VALID_REQ.txId)


class LambdaResponseHelper:
    """Holds test data for LambdaResponse."""

    def __init__(self, status_code: int, body_str: str):
        """TestLambdaResponse class init."""
        self._resp = {
            "statusCode": status_code,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Credentials": True,
                "Content-Type": "application/json",
            },
            "body": body_str,
        }

    @property
    def resp(self):
        """Returns lambda response."""
        return self._resp


# -----------------------------------------------------------------------------
# pytest fixtures and setup
# -----------------------------------------------------------------------------
@pytest.fixture(scope="session", autouse=True)
def setup_logging():
    """Setup logging for tests."""
    logging.disable(logging.CRITICAL)  # disables logging
    yield
    logging.disable(logging.NOTSET)


@pytest.fixture
def valid_input():
    """Provide valid input for tests."""
    return VALID_REQ._asdict()


# -----------------------------------------------------------------------------
# Tests for LambdaRequest conversion
# -----------------------------------------------------------------------------
def test_abk_hello__converting_lambda_input_parameters(valid_input) -> None:
    """Validates that the lambda input parameters are converted correctly."""
    actual_req = AhLambdaRequestBody(**valid_input)
    # tst_logger.debug(f'actual_req: {json.dumps(actual_req._asdict(), indent=4)}')
    # tst_logger.debug(f'expected_req: {json.dumps(VALID_REQ._asdict(), indent=4)}')
    assert actual_req == VALID_REQ


# -----------------------------------------------------------------------------
# Tests for validate_input
# -----------------------------------------------------------------------------
@pytest.mark.parametrize("key_to_delete", ["deviceUuid", "txId"])
def test_convert_and_validate_input__throws_given_required_input_key_missing(
    valid_input, key_to_delete
) -> None:
    """Validates that exception is thrown when one of the required keys is missing."""
    lcl_actual_input = valid_input.copy()
    del lcl_actual_input[key_to_delete]
    lcl_exception_msg = f"'{key_to_delete}' is a required property"
    
    with pytest.raises(Exception) as exception_message:
        abk_hello.validate_input(lcl_actual_input)
    # tst_logger.info(f"{exception_message.exception = }")
    assert lcl_exception_msg in str(exception_message.value)


def test_convert_and_validate_input__throws_given_additional_input_key_is_present(
    valid_input,
) -> None:
    """Validates exception is thrown when additional keys is present in the lambda request."""
    lcl_actual_input = valid_input.copy()
    lcl_extra_param = "additional_parameter_value"
    lcl_actual_input[lcl_extra_param] = "notAllowed"
    lcl_exception_msg = f"Additional properties are not allowed ('{lcl_extra_param}' was unexpected)"  # noqa: E501
    
    with pytest.raises(Exception) as exception_message:
        abk_hello.validate_input(lcl_actual_input)
    assert lcl_exception_msg in str(exception_message.value)


@pytest.mark.parametrize(
    "p_key,p_value,ex_msg",
    [
        # key,          value       exception message
        (
            "deviceUuid",
            "aec4f817-0729-442e-bf6b-588b2a2011b60",
            "'aec4f817-0729-442e-bf6b-588b2a2011b60' does not match",
        ),
        ("deviceUuid", "NotValid", "'NotValid' does not match"),
        ("deviceUuid", "", "'' does not match"),
        ("deviceUuid", True, "True is not of type 'string'"),
        ("deviceUuid", 89, "89 is not of type 'string'"),
        ("deviceUuid", 3.14, "3.14 is not of type 'string"),
        ("deviceUuid", {}, "{} is not of type 'string'"),
        ("deviceUuid", [], "[] is not of type 'string'"),
        ("txId", "", "'' should be non-empty"),
        ("txId", "X" * 37, f"'{'X' * 37}' is too long"),
        ("txId", True, "True is not of type 'string'"),
        ("txId", 89, "89 is not of type 'string'"),
        ("txId", 3.14, "3.14 is not of type 'string"),
        ("txId", {}, "{} is not of type 'string'"),
        ("txId", [], "[] is not of type 'string'"),
    ]
)
def test_convert_and_validate_input__throws_given_invalid_input(
    valid_input, p_key: str, p_value, ex_msg: str
) -> None:
    """Validates exception is thrown when unexpected value is seen."""
    lcl_actual_input = valid_input.copy()
    lcl_actual_input[p_key] = p_value
    
    with pytest.raises(Exception) as exception_message:
        abk_hello.validate_input(lcl_actual_input)
    # tst_logger.info(f"{exception_message.exception = }")
    assert ex_msg in str(exception_message.value)


# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------