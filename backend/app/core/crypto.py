from cryptography.fernet import Fernet, InvalidToken
from flask import current_app, has_app_context
from sqlalchemy.types import Text, TypeDecorator


ENCRYPTED_PREFIX = "enc:v1:"


class EncryptedText(TypeDecorator):
    impl = Text
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None or value == "":
            return value
        value = str(value)
        if value.startswith(ENCRYPTED_PREFIX):
            return value
        if not has_app_context():
            raise RuntimeError("encrypted values require an application context")
        token = Fernet(current_app.config["DATA_ENCRYPTION_KEY"].encode("ascii")).encrypt(
            value.encode("utf-8")
        )
        return ENCRYPTED_PREFIX + token.decode("ascii")

    def process_result_value(self, value, dialect):
        if not value or not str(value).startswith(ENCRYPTED_PREFIX):
            return value
        if not has_app_context():
            raise RuntimeError("encrypted values require an application context")
        token = str(value)[len(ENCRYPTED_PREFIX):]
        try:
            return Fernet(current_app.config["DATA_ENCRYPTION_KEY"].encode("ascii")).decrypt(
                token.encode("ascii")
            ).decode("utf-8")
        except InvalidToken as exc:
            raise RuntimeError("failed to decrypt stored API key") from exc
