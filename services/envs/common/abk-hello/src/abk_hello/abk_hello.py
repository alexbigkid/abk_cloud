"""Provides lambda functionality in ABK cloud infrastructure."""

# Standard imports
import json
import logging
import os
from enum import Enum

# 3rd party imports
from jsonschema import validate

# local imports
from abk_hello.abk_hello_io import AhLambdaRequestBody, AhLambdaResponseBody

# -----------------------------------------------------------------------------
# variables definitions, file wide access, for lambda to load only once.
# The values stay loaded in the memory, also some time after lambda execution
# This will accelerate warm start of lambda
# -----------------------------------------------------------------------------
logging.basicConfig()
abk_logger = logging.getLogger(__name__)
log_level = os.environ.get("LOG_LEVEL", "WARNING").upper()
abk_logger.setLevel(logging.getLevelName(log_level))


LAMBDA_RESP_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Credentials": True,
    "Content-Type": "application/json",
}

LAMBDA_REQ_SCHEMA = {
    "title": "ABK Lambda Request Validation",
    "description": "JSON Schema validation for ABK hello get Lambda Request.",
    "$defs": {
        "uuid": {
            "type": "string",
            "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            "minLength": 36,
            "maxLength": 36,
        }
    },
    "type": "object",
    "properties": {
        "deviceUuid": {"$ref": "#/$defs/uuid"},
        "txId": {"type": "string", "minLength": 1, "maxLength": 36},
    },
    "required": ["deviceUuid", "txId"],
    "additionalProperties": False,
}


class HttpStatusCode(Enum):
    """HTTP status codes used in this lambda."""

    OK = 200
    FORBIDDEN = 403
    CONFLICT = 409


# -----------------------------------------------------------------------------
# local functions
# -----------------------------------------------------------------------------
def validate_input(input_parameters: dict) -> AhLambdaRequestBody:
    """Validates and converts input parameters.

    Args:
        input_parameters (dict[str, str]): lambda input parameter dict
    Raises:
        ValueError: when unexpected values found
    Returns:
        LambdaRequest: converted input_parameters to LambdaRequest
    """
    validate(input_parameters, LAMBDA_REQ_SCHEMA)
    return AhLambdaRequestBody(**input_parameters)


def get_error_response_body(event_body: dict) -> AhLambdaResponseBody:
    """Constructs lambda response body in error case.

    Args:
        event_body (dict): lambda event
    Returns:
        LambdaResponseBody: body response
    """
    abk_logger.info("-> get_error_response_body()")
    resp_body = AhLambdaResponseBody(msg="error", txId=event_body.get("txId", ""))
    abk_logger.info(f"<- get_error_response_body({json.dumps(resp_body._asdict(), indent=4)})")
    return resp_body


def class_to_dict(named_tuple) -> object:
    """Converts data class or NamedTuple object to dict recursively.

    Args:
        named_tuple: named tuple
    Returns:
        dict: named tuple as dict
    """
    if isinstance(named_tuple, tuple) and hasattr(named_tuple, "_asdict"):
        return {k: class_to_dict(v) for k, v in named_tuple._asdict().items()}
    if isinstance(named_tuple, list):
        return [class_to_dict(v) for v in named_tuple]
    if isinstance(named_tuple, dict):
        return {k: class_to_dict(v) for k, v in named_tuple.items()}
    return named_tuple


# -----------------------------------------------------------------------------
# lambda handler - main function
# -----------------------------------------------------------------------------
def handler(event, context):
    """Handler for removing device from the ABK device table.

    Args:
        event (dict): event data dictionary
        context (object): lambda context object
    Returns:
        http_resp dict: lambda response dictionary, where body is a string converted from dict
    """
    status_code = HttpStatusCode.FORBIDDEN.value  # Assume error at the beginning, overwrite alter
    abk_logger.info(f"event   = {json.dumps(event, indent=2)}")
    abk_logger.debug(
        f"context = {json.dumps(context, default=lambda o: getattr(o, '__dict__', str(o)))}"
    )
    resp_body: AhLambdaResponseBody

    try:
        # Handle both GET (query parameters) and POST (body) requests
        if event.get("httpMethod") == "GET" and event.get("queryStringParameters"):
            lambda_input = event.get("queryStringParameters")
        elif event.get("body"):
            lambda_input = json.loads(event.get("body"))
        else:
            lambda_input = {}

        lambda_req = validate_input(lambda_input)
        abk_logger.debug(f"req: {json.dumps(lambda_req._asdict(), indent=4)}")

        resp_body = AhLambdaResponseBody(msg="ok", txId=lambda_req.txId)

        status_code = HttpStatusCode.OK.value
    except Exception as exc:
        abk_logger.error(f"{exc = }")
        # Try to get txId from either query params or body for error response
        try:
            if event.get("httpMethod") == "GET" and event.get("queryStringParameters"):
                error_input = event.get("queryStringParameters") or {}
            elif event.get("body"):
                error_input = json.loads(event.get("body"))
            else:
                error_input = {}
        except:
            error_input = {}
        resp_body = get_error_response_body(error_input)

    body = json.dumps(class_to_dict(resp_body))
    abk_logger.info(f"{status_code = }, {body = }")
    return {"statusCode": status_code, "headers": LAMBDA_RESP_HEADERS, "body": body}
