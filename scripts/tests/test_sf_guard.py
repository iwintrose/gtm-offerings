import os
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX = os.path.join(ROOT, "scripts", "lib", "sfx")


def stub_env(tmp):
    bindir = os.path.join(tmp, "bin")
    os.makedirs(bindir)
    log = os.path.join(tmp, "sf.log")
    stub = os.path.join(bindir, "sf")
    with open(stub, "w") as f:
        f.write('#!/bin/sh\necho "$@" >> "%s"\nexit 0\n' % log)
    os.chmod(stub, os.stat(stub).st_mode | stat.S_IXUSR)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("SF_GUARD") and k not in ("SF_TARGET_ORG", "GTM_ALLOW_PRODUCTION")}
    env["PATH"] = bindir + os.pathsep + env["PATH"]
    env["TMPDIR"] = tmp
    return env, log


def calls(log):
    if not os.path.exists(log):
        return 0
    with open(log) as f:
        return len(f.read().splitlines())


class SfGuardTests(unittest.TestCase):
    def setUp(self):
        self._t = tempfile.TemporaryDirectory()
        self.tmp = self._t.name
        self.env, self.log = stub_env(self.tmp)

    def tearDown(self):
        self._t.cleanup()

    def run_py(self, code, env=None):
        return subprocess.run([sys.executable, "-c", code], env=env or self.env,
                              capture_output=True, text=True, cwd=os.path.join(ROOT, "scripts"))

    def test_sf_without_session_fails_closed(self):
        r = self.run_py("from lib import sf_guard; sf_guard.sf(['data','query','-o','gtm-staging'])")
        self.assertEqual(r.returncode, 70)
        self.assertEqual(calls(self.log), 0)

    def test_ensure_session_missing_sfx_exits_70(self):
        env = dict(self.env, SF_GUARD_SFX_PATH=os.path.join(self.tmp, "nope"))
        r = self.run_py("from lib import sf_guard; sf_guard.ensure_session()", env)
        self.assertEqual(r.returncode, 70)

    def test_ensure_session_reexecs_and_sf_passes_args(self):
        script = os.path.join(self.tmp, "child.py")
        with open(script, "w") as f:
            f.write("import sys, os\nsys.path.insert(0, %r)\n"
                    "from lib import sf_guard\nsf_guard.ensure_session()\n"
                    "r = sf_guard.sf(['data','query','-o','gtm-staging'], capture=True)\n"
                    "print('rc', r.returncode)\n" % os.path.join(ROOT, "scripts"))
        r = subprocess.run([sys.executable, script], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("rc 0", r.stdout)
        self.assertIn("sf calls this run: 1", r.stderr)
        self.assertEqual(calls(self.log), 1)

    def test_sf_refuses_gtm_dev(self):
        script = os.path.join(self.tmp, "child.py")
        with open(script, "w") as f:
            f.write("import sys\nsys.path.insert(0, %r)\nfrom lib import sf_guard\n"
                    "sf_guard.ensure_session()\nr = sf_guard.sf(['data','query','-o','gtm-dev'], capture=True)\n"
                    "sys.exit(r.returncode)\n" % os.path.join(ROOT, "scripts"))
        r = subprocess.run([sys.executable, script], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(calls(self.log), 0)

    def drift(self, *args, extra=None):
        env = dict(self.env, **(extra or {}))
        return subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "check-org-drift.py")]
                              + list(args), env=env, capture_output=True, text=True)

    def test_drift_no_org_exits_2(self):
        r = self.drift("ApexClass:GtmSavedConfigurationController")
        self.assertEqual(r.returncode, 2)
        self.assertEqual(calls(self.log), 0)

    def test_drift_gtm_dev_refused(self):
        r = self.drift("--org", "gtm-dev", "ApexClass:GtmSavedConfigurationController")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(calls(self.log), 0)


if __name__ == "__main__":
    unittest.main()
