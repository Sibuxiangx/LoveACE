from pydantic import BaseModel


class ECLoginStatus(BaseModel):
    success: bool = False
    fail_not_found_twfid: bool = False
    fail_not_found_rsa_key: bool = False
    fail_not_found_rsa_exp: bool = False
    fail_not_found_csrf_code: bool = False
    fail_invalid_credentials: bool = False
    fail_maybe_attacked: bool = False
    fail_network_error: bool = False
    fail_unknown_error: bool = False


class ECCheckStatus(BaseModel):
    logged_in: bool = False
    fail_network_error: bool = False
    fail_unknown_error: bool = False


class UAAPLoginStatus(BaseModel):
    success: bool = False
    fail_not_found_lt: bool = False
    fail_not_found_execution: bool = False
    fail_invalid_credentials: bool = False
    fail_network_error: bool = False
    fail_unknown_error: bool = False
