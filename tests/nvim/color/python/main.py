"""Python color stress fixture for DX semantic highlight validation."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import re
from typing import Generic, Optional, TypeVar

T = TypeVar("T")

# DX:M2 python.binding.module_binding
module_retry_limit = 3


class BindingProbe:
    # DX:M2 python.binding.class_attribute
    class_label = "binding-probe"

    def __init__(self, initial_value: int) -> None:
        # DX:M2 python.binding.instance_attribute
        self.instance_value = initial_value

    def observe(
        self,
        # DX:M2 python.binding.parameter
        parameter_value: int,
    ) -> int:
        # DX:M2 python.binding.local_binding
        local_value = parameter_value + self.instance_value
        return local_value + module_retry_limit

# Sentinel: regular expression pattern (DxString = Muted Sage)
# DX:SENTINEL python.pattern.regexp
PATTERN: re.Pattern[str] = re.compile(r"^DX42\d+$")


class NetworkError(Exception):
    """Raised when communication channel fails."""

    pass


# DX:SENTINEL python.download_summary.class
@dataclass
class DownloadSummary(Generic[T]):
    """Data model representing a verified download receipt."""

    size: int
    payload: T
    tags: list[str] = field(default_factory=list)
    _cached_hash: Optional[str] = None

    @property
    def is_empty(self) -> bool:
        """Sentinel: property definition."""
        # Sentinel: member attribute access (DxMember = Periwinkle)
        # DX:SENTINEL python.size.member
        return self.size == 0

    # DX:SENTINEL python.validate_bounds.method
    # DX:SENTINEL python.def.keyword
    def validate_bounds(self, limit: int) -> bool:
        """Sentinel: method definition (DxCallable = Muted Amber, Parameters = Muted Violet-Gray)."""
        # Local variable (Neutral body)
        margin = 100
        return self.size + margin <= limit


# DX:SENTINEL python.fetch_async.fn
async def fetch_async(endpoint: str, timeout_seconds: float = 5.0) -> DownloadSummary[dict[str, str]]:
    """Sentinel: async function (DxCallable = Muted Amber)."""
    print(f"Connecting to {endpoint} with timeout {timeout_seconds}")
    await asyncio.sleep(0.01)

    data = {"status": "ok", "version": "v1"}
    summary = DownloadSummary(size=2048, payload=data, tags=["prod", "v2"])

    if not summary.validate_bounds(4096):
        raise NetworkError("Payload exceeds configured threshold")

    return summary


def main() -> None:
    uri: str = "https://api.example.com/v1/data"
    assert PATTERN.match("DX42100") is not None
    binding_total = BindingProbe(1).observe(module_retry_limit)

    loop = asyncio.new_event_loop()
    try:
        receipt = loop.run_until_complete(fetch_async(uri))
        print(f"Received bytes: {receipt.size}, empty: {receipt.is_empty}, binding: {binding_total}")
    finally:
        loop.close()


if __name__ == "__main__":
    main()
