"""Thin Python client for scripts/lib/sfx. All policy lives in sfx."""
import os
import subprocess
import sys

_LIB = os.path.dirname(os.path.abspath(__file__))


def _sfx_path():
    return os.environ.get("SF_GUARD_SFX_PATH") or os.path.join(_LIB, "sfx")


def ensure_session():
    """Re-exec the running script inside an sfx session when none is active."""
    if os.environ.get("SF_GUARD_COUNT_FILE"):
        return
    sfx = _sfx_path()
    if not os.access(sfx, os.X_OK):
        sys.stderr.write("sfx guard helper missing: refusing to run\n")
        raise SystemExit(70)
    os.execv(sfx, [sfx, "--session", "--", sys.executable] + sys.argv)


def sf(args, capture=False, **kw):
    """Run a guarded, counted sf call; returns the CompletedProcess."""
    sfx = os.environ.get("SF_GUARD_SFX")
    if not sfx:
        sys.stderr.write("cannot count sf calls: refusing to run sf\n")
        raise SystemExit(70)
    if capture:
        kw.update(capture_output=True, text=True)
    return subprocess.run([sfx] + list(args), **kw)
