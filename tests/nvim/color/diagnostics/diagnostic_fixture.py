"""Isolated fixture for testing Python diagnostic underline and state interaction."""

from typing import List


def process_items(items: List[str]) -> int:
    # Warning: unused local
    unused_var = "diagnostic_probe"

    total = 0
    for it in items:
        total += len(it)
    return total
