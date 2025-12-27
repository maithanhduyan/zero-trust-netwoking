# agent/client.py
"""
Control Plane API Client
Handles communication with the Zero Trust Control Plane
"""

import os
import json
import socket
import logging
from typing import Optional, Dict, Any
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin

logger = logging.getLogger('zt-agent.client')


def has_interface(interface: str) -> bool:
    """Check if a network interface exists and has an IP"""
    try:
        import subprocess
        result = subprocess.run(
            ["ip", "addr", "show", interface],
            capture_output=True,
            text=True
        )
        return result.returncode == 0 and "inet " in result.stdout
    except Exception:
        return False


def get_base_url() -> str:
    """
    Determine the best URL to reach Control Plane
    - If wg0 is up: Use overlay network (most secure)
    - Otherwise: Use public endpoint (HTTPS)
    """
    if has_interface("wg0"):
        return "http://10.0.0.1:8000"  # Via WireGuard tunnel
    else:
        # Fall back to public endpoint
        return os.getenv("CONTROL_PLANE_URL", "https://hub.example.com")


class ControlPlaneClient:
    """
    HTTP Client for Control Plane API

    Features:
    - Automatic URL selection (overlay vs public)
    - Retry logic
    - Error handling
    """

    def __init__(self, base_url: Optional[str] = None, timeout: int = 30):
        self.base_url = base_url or get_base_url()
        self.timeout = timeout
        self.api_prefix = "/api/v1/agent"
        logger.info(f"Control Plane client initialized: {self.base_url}")

    def _make_request(
        self,
        method: str,
        endpoint: str,
        data: Optional[Dict] = None,
        headers: Optional[Dict] = None
    ) -> Dict[str, Any]:
        """Make HTTP request to Control Plane"""
        url = urljoin(self.base_url, f"{self.api_prefix}{endpoint}")

        default_headers = {
            "Content-Type": "application/json",
            "User-Agent": "ZT-Agent/1.0"
        }
        if headers:
            default_headers.update(headers)

        body = None
        if data:
            body = json.dumps(data).encode('utf-8')

        request = Request(
            url=url,
            data=body,
            headers=default_headers,
            method=method
        )

        try:
            logger.debug(f"{method} {url}")
            with urlopen(request, timeout=self.timeout) as response:
                response_data = response.read().decode('utf-8')
                return json.loads(response_data) if response_data else {}

        except HTTPError as e:
            error_body = e.read().decode('utf-8') if e.fp else ""
            logger.error(f"HTTP {e.code}: {error_body}")
            raise APIError(e.code, error_body)

        except URLError as e:
            logger.error(f"Connection error: {e.reason}")
            raise ConnectionError(f"Cannot reach Control Plane: {e.reason}")

        except socket.timeout:
            logger.error("Request timed out")
            raise TimeoutError("Request to Control Plane timed out")

    def register(
        self,
        hostname: str,
        role: str,
        public_key: str,
        description: Optional[str] = None,
        agent_version: Optional[str] = None,
        os_info: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Register node with Control Plane

        Returns:
            Registration response with overlay_ip, hub_public_key, etc.
        """
        data = {
            "hostname": hostname,
            "role": role,
            "public_key": public_key,
        }

        if description:
            data["description"] = description
        if agent_version:
            data["agent_version"] = agent_version
        if os_info:
            data["os_info"] = os_info

        return self._make_request("POST", "/register", data)

    def get_config(self, hostname: str) -> Dict[str, Any]:
        """
        Get configuration for this node

        Returns:
            Config with peers, acl_rules, config_version
        """
        return self._make_request("GET", f"/config/{hostname}")

    def get_config_by_key(self, public_key: str) -> Dict[str, Any]:
        """
        Get configuration using public key

        Returns:
            Config with peers, acl_rules, config_version
        """
        # URL encode the public key
        from urllib.parse import quote
        encoded_key = quote(public_key, safe='')
        return self._make_request("GET", f"/config?public_key={encoded_key}")

    def heartbeat(
        self,
        hostname: str,
        public_key: str,
        agent_version: Optional[str] = None,
        uptime_seconds: Optional[int] = None,
        cpu_percent: Optional[float] = None,
        memory_percent: Optional[float] = None,
        disk_percent: Optional[float] = None,
        security_events: Optional[Dict[str, Any]] = None,
        network_stats: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Send heartbeat to Control Plane with security metrics

        Returns:
            Heartbeat response with config_changed flag and trust_score
        """
        data = {
            "hostname": hostname,
            "public_key": public_key,
        }

        if agent_version:
            data["agent_version"] = agent_version
        if uptime_seconds is not None:
            data["uptime_seconds"] = uptime_seconds
        if cpu_percent is not None:
            data["cpu_percent"] = cpu_percent
        if memory_percent is not None:
            data["memory_percent"] = memory_percent
        if disk_percent is not None:
            data["disk_percent"] = disk_percent
        if security_events is not None:
            data["security_events"] = security_events
        if network_stats is not None:
            data["network_stats"] = network_stats

        return self._make_request("POST", "/heartbeat", data)

    def get_status(self, hostname: str) -> Dict[str, Any]:
        """Get node status"""
        return self._make_request("GET", f"/status/{hostname}")


class APIError(Exception):
    """API error with status code"""

    def __init__(self, status_code: int, message: str):
        self.status_code = status_code
        self.message = message
        super().__init__(f"API Error {status_code}: {message}")
