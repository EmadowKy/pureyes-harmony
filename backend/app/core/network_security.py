import ipaddress
import socket
from urllib.parse import urlparse

from flask import current_app


def _is_public_address(raw_address):
    try:
        address = ipaddress.ip_address(raw_address)
    except ValueError:
        return False
    return address.is_global


def validate_llm_base_url(raw_url, resolve_dns=False):
    value = (raw_url or "").strip().rstrip("/")
    if not value:
        return ""

    parsed = urlparse(value)
    if parsed.scheme not in {"https", "http"} or not parsed.hostname:
        raise ValueError("BASE URL 必须是有效的 HTTP(S) 地址")
    if parsed.username or parsed.password:
        raise ValueError("BASE URL 不能包含用户名或密码")
    if parsed.scheme != "https" and not current_app.config.get("ALLOW_INSECURE_LLM_HTTP"):
        raise ValueError("BASE URL 必须使用 HTTPS")

    hostname = parsed.hostname.lower().rstrip(".")
    allowed_hosts = current_app.config.get("LLM_ALLOWED_HOSTS") or set()
    if allowed_hosts and hostname not in allowed_hosts:
        raise ValueError("该大模型服务域名不在服务器允许列表中")

    allow_private = current_app.config.get("ALLOW_PRIVATE_LLM_NETWORK") is True
    try:
        literal_address = ipaddress.ip_address(hostname)
        if not allow_private and not literal_address.is_global:
            raise ValueError("BASE URL 不能指向本机或内网地址")
    except ValueError as exc:
        if "不能指向" in str(exc):
            raise

    if resolve_dns and not allow_private:
        try:
            addresses = {
                item[4][0]
                for item in socket.getaddrinfo(hostname, parsed.port or 443, type=socket.SOCK_STREAM)
            }
        except socket.gaierror as exc:
            raise ValueError("无法解析大模型服务域名") from exc
        if not addresses or any(not _is_public_address(address) for address in addresses):
            raise ValueError("大模型服务域名解析到了本机或内网地址")

    return value
