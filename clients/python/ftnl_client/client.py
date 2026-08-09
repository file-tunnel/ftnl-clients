from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen


@dataclass(slots=True)
class ApiError(RuntimeError):
    status: int
    body: str

    def __str__(self) -> str:
        return f"File Tunnel API returned HTTP {self.status}: {self.body}"


class Client:
    def __init__(self, base_url: str, token: str | None = None, timeout: float = 30.0) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def request(self, method: str, path: str, body: Any | None = None) -> Any:
        payload = None if body is None else json.dumps(body).encode("utf-8")
        headers = {"Accept": "application/json"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = Request(f"{self.base_url}/{path.lstrip('/')}", data=payload, headers=headers, method=method.upper())
        try:
            with urlopen(request, timeout=self.timeout) as response:
                data = response.read()
                return None if not data else json.loads(data)
        except HTTPError as error:
            raise ApiError(error.code, error.read(65536).decode("utf-8", errors="replace")) from error

    def health(self) -> Any:
        return self.request("GET", "/health")
