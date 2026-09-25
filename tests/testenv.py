"""Shared test-environment isolation & hard guard, imported first by every
Python test file that can reach the filesystem (test_bridge.py and friends),
and mirrored in shell form at the top of tests/run-all.sh for the QML scene
tests that spawn qmlscene rather than the bridge.

Why this exists: a test run once deleted the owner's LIVE Solfa data dir
(the Chromium profile with the sign-in) because a test process inherited the
real HOME/XDG_DATA_HOME - none of them were overridden - and a bridge code
path (the orphan-lease wipe) computed its delete target from those, in the
same process tree as the real engine.

Two independent things happen here, in order:

1. ISOLATION: point HOME/XDG_DATA_HOME/XDG_CACHE_HOME/XDG_CONFIG_HOME/
   XDG_STATE_HOME, and SOLFA_RUNTIME_DIR/SOLFA_PROFILE_DIR/SOLFA_CACHE_DIR,
   at a fresh temp dir, and set SOLFA_TEST=1 (the marker bin/solfa-bridge's
   delete/rename helpers refuse to touch a real dir under - see
   refuse_if_real_path there). XDG_RUNTIME_DIR/WAYLAND_DISPLAY are left
   alone: the QML scene tests need the real Wayland/Hyprland session.

   If SOLFA_TEST_ENV_ROOT is already set (tests/run-all.sh sets it once for
   the whole suite), that root is reused and this module does not clean it
   up on exit - run-all.sh's own trap does that. Run standalone (a single
   test file, or a probe), this module creates its own root and registers
   the cleanup itself.

2. HARD VERIFY: after isolating, resolve every one of those vars again and
   refuse to proceed (exit non-zero, before any test runs or any file is
   touched) if any of them still lands inside the owner's REAL per-user
   dirs - computed from pwd.getpwuid, never from $HOME, so this cannot be
   fooled by a test that only overrides $HOME and leaves XDG_DATA_HOME (or
   vice versa). This is the check that would have caught the incident.
"""
import atexit
import os
import pathlib
import pwd
import shutil
import sys
import tempfile

PLUGIN_ID = "io.github.sirallap.solfa"
OLD_PLUGIN_ID = "serallap.solfa"

CHECKED_VARS = ("HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME",
                "XDG_STATE_HOME", "SOLFA_PROFILE_DIR", "SOLFA_CACHE_DIR", "SOLFA_RUNTIME_DIR")


def real_home():
    """The OS's real home for this uid (pwd, never $HOME - $HOME is exactly
    the thing a test might have gotten wrong)."""
    try:
        return pathlib.Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()
    except (KeyError, OSError):
        return pathlib.Path(os.path.expanduser("~")).resolve()


def real_forbidden_dirs():
    """Every real, live location Solfa's data can be in, current and old
    plugin id, for this real user - independent of any env var a test (or a
    bug in this module) controls."""
    home = real_home()
    uid = os.getuid()
    dirs = []
    for plugin_id in (PLUGIN_ID, OLD_PLUGIN_ID):
        dirs.append(home / ".local" / "share" / plugin_id)
        dirs.append(home / ".cache" / plugin_id)
        dirs.append(pathlib.Path(f"/run/user/{uid}") / plugin_id)
    dirs.append(home / ".config" / "omarchy")
    return dirs


def is_inside(candidate, forbidden):
    """True if candidate is forbidden, is under it, or is one of its
    ancestors (an ancestor is just as dangerous: deleting/renaming it takes
    forbidden with it)."""
    candidate = pathlib.Path(os.path.normpath(str(candidate)))
    forbidden = pathlib.Path(os.path.normpath(str(forbidden)))
    return candidate == forbidden or forbidden in candidate.parents or candidate in forbidden.parents


def verify_env_is_safe(env=None):
    """Refuse (exit 1) if any of CHECKED_VARS, as currently set, resolves
    anywhere near a real dir. Returns quietly when everything is clear."""
    env = env if env is not None else os.environ
    forbidden_dirs = real_forbidden_dirs()
    for name in CHECKED_VARS:
        value = env.get(name)
        if not value:
            continue
        candidate = pathlib.Path(value)
        for forbidden in forbidden_dirs:
            if is_inside(candidate, forbidden):
                sys.exit(
                    "testenv: REFUSED - {0}={1} resolves against the real {2}. "
                    "A test run must never be able to reach the owner's live Solfa "
                    "data; aborting before any test ran.".format(name, value, forbidden)
                )


def isolate():
    """Point every test-relevant path at a fresh temp dir, set SOLFA_TEST=1,
    then hard-verify the result. Safe to call more than once (every test
    file imports this module): a second call sees SOLFA_TEST_ENV_ROOT
    already set and reuses it instead of making a new one."""
    root = os.environ.get("SOLFA_TEST_ENV_ROOT")
    owns_root = False
    if not root:
        base = os.environ.get("CLAUDE_SCRATCHPAD_DIR") or os.environ.get("TMPDIR") or tempfile.gettempdir()
        root = tempfile.mkdtemp(prefix="solfa-testenv-", dir=base)
        owns_root = True

    root_path = pathlib.Path(root)
    dirs = {
        "HOME": root_path / "home",
        "XDG_DATA_HOME": root_path / "data",
        "XDG_CACHE_HOME": root_path / "cache",
        "XDG_CONFIG_HOME": root_path / "config",
        "XDG_STATE_HOME": root_path / "state",
        "SOLFA_RUNTIME_DIR": root_path / "runtime" / PLUGIN_ID,
        "SOLFA_PROFILE_DIR": root_path / "profile" / "engine",
    }
    for name, path in dirs.items():
        path.mkdir(parents=True, exist_ok=True)
        os.environ[name] = str(path)
    os.environ["SOLFA_TEST"] = "1"
    os.environ["SOLFA_TEST_ENV_ROOT"] = root

    verify_env_is_safe()

    if owns_root:
        atexit.register(shutil.rmtree, root, ignore_errors=True)

    return root_path


ROOT = isolate()
