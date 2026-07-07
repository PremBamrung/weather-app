"""Imperial -> metric conversions for Ecowitt payload fields.

Ecowitt gateways send values in Imperial units; we convert before persisting so the
database only ever holds one unit system. See docs/pipeline/payload-format.md.
"""

from datetime import datetime, timezone


def f_to_c(f: float) -> float:
    """Fahrenheit -> Celsius."""
    return (f - 32.0) * 5.0 / 9.0


def inhg_to_hpa(v: float) -> float:
    """Inches of mercury -> hectopascals."""
    return v * 33.8639


def mph_to_ms(v: float) -> float:
    """Miles per hour -> metres per second."""
    return v * 0.44704


def in_to_mm(v: float) -> float:
    """Inches -> millimetres."""
    return v * 25.4


def to_float(value):
    """Best-effort float parse; returns None on missing/blank/garbage."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def to_int(value):
    """Best-effort int parse; returns None on missing/blank/garbage.

    Parses via float first so "0", "0.0" and " 1 " all work — Ecowitt sends flags as
    plain strings. Used for the battery flag, stored as SMALLINT.
    """
    v = to_float(value)
    return int(v) if v is not None else None


def parse_dateutc(value):
    """Parse the gateway's `dateutc` field ("YYYY-MM-DD HH:MM:SS", UTC) to a tz-aware
    datetime, or None if missing/unparseable. The gateway sends this in UTC despite the
    lack of an explicit offset, so we attach UTC. See docs/schema-enrichment.md.
    """
    if not value:
        return None
    try:
        return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None
