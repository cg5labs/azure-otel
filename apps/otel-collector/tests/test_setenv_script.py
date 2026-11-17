import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


APP_DIR = Path(__file__).resolve().parents[1]
TOFU_OUTPUTS = {
    "azure_tenant_id": "tenant-from-tofu",
    "otel_service_principal_client_id": "client-from-tofu",
    "otel_service_principal_client_secret": "secret-from-tofu",
    "subscription_id": "subscription-from-tofu",
    "resource_group_name": "resource-group-from-tofu",
    "eventhub_sas_connection_string": "connection-from-tofu",
    "eventhub_consumer_group": "consumer-from-tofu",
    "otel_oidc_audience": "audience-from-tofu",
    "kubernetes_cluster_name": "cluster-from-tofu",
}


class SetenvTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app_dir = self.root / "apps/otel-collector"
        self.scripts = self.app_dir / "scripts"
        self.scripts.mkdir(parents=True)
        self.script = self.scripts / "setenv.sh"
        shutil.copyfile(APP_DIR / "scripts/setenv.sh", self.script)
        self.tofu_dir = self.root / "tf"
        self.tofu_dir.mkdir()
        (self.app_dir / "compose.yaml").touch()
        self.env_file = self.app_dir / ".env"
        self.env_file.write_text(
            "CERT_GID='1234'\n"
            "GRAFANA_ADMIN_USER='local-admin'\n"
            "GRAFANA_ADMIN_PASSWORD='local-password'\n"
            "OTEL_OIDC_AUDIENCE='stale-audience'\n"
        )
        self.checkpoint_dir = self.app_dir / "data/otel-collector-checkpoints"
        self.checkpoint_dir.mkdir(parents=True)
        (self.checkpoint_dir / "old-checkpoint").touch()
        self.calls_file = self.root / "calls"
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("AZURE_", "OTEL_"))
        }
        self.environment.update(
            PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
            CALLS_FILE=str(self.calls_file),
            TENANT_OUTPUT=TOFU_OUTPUTS["azure_tenant_id"],
        )
        (self.root / "bin").mkdir()
        self.write_executable(
            self.root / "bin/tofu",
            '#!/usr/bin/env python3\n'
            "import os, sys\n"
            "output = sys.argv[-1]\n"
            "values = " + repr(TOFU_OUTPUTS) + "\n"
            "if output not in values:\n"
            "    sys.exit(1)\n"
            "sys.stdout.write(values[output])\n",
        )
        self.write_executable(
            self.root / "bin/az",
            '#!/usr/bin/env bash\n'
            'printf "az %s\\n" "$*" >> "$CALLS_FILE"\n'
            'if [[ "$*" == *"--query tenantId"* ]]; then\n'
            '  printf "%s\\n" "$TENANT_OUTPUT"\n'
            "fi\n",
        )
        self.write_executable(
            self.root / "bin/docker",
            '#!/usr/bin/env bash\n'
            'printf "docker %s\\n" "$*" >> "$CALLS_FILE"\n'
            '[[ "$*" == "compose version" ]] && exit 0\n'
            '[[ "$*" == *"--env-file $ENV_FILE"* ]] || exit 41\n'
            'grep -q "^OTEL_OIDC_AUDIENCE=.*audience-from-tofu" "$ENV_FILE" || exit 42\n'
            'grep -q "^AZURE_TENANT_ID=.*tenant-from-tofu" "$ENV_FILE" || exit 43\n',
        )
        self.environment["ENV_FILE"] = str(self.env_file)

    def write_executable(self, path, content):
        path.write_text(content)
        path.chmod(0o755)

    def test_tofu_outputs_are_written_before_compose_teardown(self):
        result = subprocess.run(
            ["bash", str(self.script)],
            cwd="/",
            env=self.environment,
            text=True,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

        calls = self.calls_file.read_text()
        self.assertIn("docker compose", calls)
        self.assertIn("--env-file", calls)
        updated = self.env_file.read_text()
        for key, value in {
            "AZURE_TENANT_ID": "tenant-from-tofu",
            "AZURE_CLIENT_ID": "client-from-tofu",
            "AZURE_CLIENT_SECRET": "secret-from-tofu",
            "AZURE_SUBSCRIPTION_ID": "subscription-from-tofu",
            "AZURE_RESOURCE_GROUP": "resource-group-from-tofu",
            "AZURE_EVENTHUB_CONNECTION_STRING": "connection-from-tofu",
            "AZURE_EVENTHUB_CONSUMER_GROUP": "consumer-from-tofu",
            "OTEL_OIDC_AUDIENCE": "audience-from-tofu",
        }.items():
            self.assertIn(f"{key}='{value}'", updated)
        self.assertIn("CERT_GID='1234'", updated)
        self.assertIn("GRAFANA_ADMIN_USER='local-admin'", updated)
        self.assertIn("GRAFANA_ADMIN_PASSWORD='local-password'", updated)
        self.assertFalse((self.checkpoint_dir / "old-checkpoint").exists())
        self.assertTrue(self.checkpoint_dir.is_dir())
        self.assertNotIn("secret-from-tofu", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
