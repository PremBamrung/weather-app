"""Imperial -> metric conversions for Ecowitt payload fields.

Ecowitt gateways send values in Imperial units; we convert before persisting so the
database only ever holds one unit system. See docs/pipeline/payload-format.md.
"""


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
