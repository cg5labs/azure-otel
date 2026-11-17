import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


APP_DIR = Path(__file__).resolve().parents[1]


class StackLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        scripts = self.root / "scripts"
        scripts.mkdir()
        self.script = scripts / "otel.sh"
        shutil.copyfile(APP_DIR / "scripts/otel.sh", self.script)
        (self.root / "compose.yaml").touch()
        self.env_file = self.root / ".env"
        self.env_file.write_text("CERT_GID='1234'\n")
        self.calls = self.root / "calls"
        self.calls.touch()
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("GRAFANA_", "GF_"))
        }
        self.environment.update(
            PATH=f"{self.root}:{os.environ['PATH']}",
            CALLS_FILE=str(self.calls),
        )
        self.write_executable(
            self.root / "docker",
            '#!/usr/bin/env bash\n'
            'printf "%s\\n" "$*" >> "$CALLS_FILE"\n',
        )
        self.write_executable(
            scripts / "setenv.sh",
            '#!/usr/bin/env bash\n'
            'printf "setup\\n" >> "$CALLS_FILE"\n',
        )

    def write_executable(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def run_script(self, option):
        return subprocess.run(
            ["bash", str(self.script), option],
            cwd="/",
            env=self.environment,
            text=True,
            capture_output=True,
        )

    def test_start_manages_entire_stack(self):
        result = self.run_script("--start")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(calls[0:2], ["compose version", "setup"])
        self.assertEqual(len(calls), 3)
        self.assertTrue(calls[2].endswith(" up -d --remove-orphans"))
        self.assertIn(f"--project-directory {self.root}", calls[2])

    def test_stop_manages_entire_stack_without_setup(self):
        result = self.run_script("--stop")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls.read_text().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[1].endswith(" stop"))
        self.assertNotIn("setup", calls)

    def test_missing_environment_fails_before_setup(self):
        self.env_file.unlink()
        result = self.run_script("--start")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected a regular environment file", result.stderr)
        self.assertEqual(self.calls.read_text(), "compose version\n")

    def test_setup_failure_does_not_start_stack(self):
        self.write_executable(
            self.root / "scripts/setenv.sh",
            "#!/usr/bin/env bash\nexit 7\n",
        )
        result = self.run_script("--start")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(self.calls.read_text(), "compose version\n")

    def test_invalid_option_does_not_manage_stack(self):
        result = self.run_script("--invalid")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Usage:", result.stderr)
        self.assertEqual(self.calls.read_text(), "compose version\n")


if __name__ == "__main__":
    unittest.main()
