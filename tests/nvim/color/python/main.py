"""Python color stress fixture for DX semantic highlight validation."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Generic, Optional, TypeVar

T = TypeVar("T")


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

    # DX:SENTINEL python.is_empty.property
    @property
    def is_empty(self) -> bool:
        """Sentinel: property definition (DxMember = Lavender)."""
        return self.size == 0

    # DX:SENTINEL python.validate_bounds.method
    def validate_bounds(self, limit: int) -> bool:
        """Sentinel: method definition (DxCallable = Yellow, Parameters = Rosewater)."""
        # Local variable (Neutral text)
        margin = 100
        return self.size + margin <= limit


# DX:SENTINEL python.fetch_async.fn
async def fetch_async(endpoint: str, timeout_seconds: float = 5.0) -> DownloadSummary[dict[str, str]]:
    """Sentinel: async function (DxCallable = Yellow)."""
    print(f"Connecting to {endpoint} with timeout {timeout_seconds}")
    await asyncio.sleep(0.01)

    data = {"status": "ok", "version": "v1"}
    summary = DownloadSummary(size=2048, payload=data, tags=["prod", "v2"])

    if not summary.validate_bounds(4096):
        raise NetworkError("Payload exceeds configured threshold")

    return summary


def main() -> None:
    uri: str = "https://api.example.com/v1/data"
    loop = asyncio.new_event_loop()
    try:
        receipt = loop.run_until_complete(fetch_async(uri))
        print(f"Received bytes: {receipt.size}, empty: {receipt.is_empty}")
    finally:
        loop.close()


if __name__ == "__main__":
    main()
