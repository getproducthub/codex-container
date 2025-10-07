# Running the Codex CLI container on Porter

This guide shows how to run the Codex CLI container as a one-off job with [Porter](https://www.porter.run). The container does not expose any ports; it just executes commands against your source tree and exits.

## Prerequisites
- Docker installed locally and access to the repo containing the `Dockerfile`.
- A container registry you can push to (examples use GitHub Container Registry at `ghcr.io`).
- A Porter project already set up with access to that registry and any secrets the Codex CLI needs.

## 1. Build and publish the image
From the repository root:

```bash
docker build -t ghcr.io/<org>/<app>/codex-cli-env:latest .

echo "$GITHUB_TOKEN" | docker login ghcr.io --username <github-username> --password-stdin

docker push ghcr.io/<org>/<app>/codex-cli-env:latest
```

- Replace `<org>/<app>` with your namespace.
- If you want to pin the Codex CLI version, add `--build-arg CODEX_CLI_VERSION=0.42.0` to the `docker build` command.

## 2. Create `porter.yaml`
Add a manifest at the root of the repo Porter will deploy:

```yaml
app:
  name: codex-cli
  platform: kubernetes

services:
  codex-task:
    type: job
    image: ghcr.io/<org>/<app>/codex-cli-env:latest
    command:
      - /usr/local/bin/codex_entry.sh
    args:
      - codex
      - <subcommand>
      - --flag=value
    env:
      - name: TZ
        value: UTC
      - name: CODEX_API_KEY
        valueFrom:
          secretKeyRef:
            name: codex-api
            key: token
    resources:
      cpu: 500m
      memory: 512Mi
```

Key points:
- `type: job` tells Porter to create a Kubernetes Job that runs to completion (no Service, no port).
- `command` defaults to the entrypoint helper; update `args` with the Codex CLI invocation you need (for example `codex summarize --json-e`).
- Inject credentials via `env`. In Porter, define the `codex-api` secret in the dashboard or CLI before running the job. The container entrypoint automatically maps `OPENAI_API_KEY`, `OPENAI_TOKEN`, or `openai_token` to `CODEX_API_KEY`, so existing `.env` files that already expose one of those names continue to work.
- Adjust the resource requests to match your workload.

If the Codex CLI needs repository files, make sure the repo connected to Porter contains them, or mount additional data using Porter volumes:

```yaml
    volumes:
      - name: workspace
        mountPath: /workspace
        persistentVolume:
          name: codex-workspace
```

Create the persistent volume in the Porter UI or with `porter volumes create` and populate it with your project files as needed.

## 3. Run the job from Porter
Use either the dashboard or the CLI:

```bash
porter jobs run codex-task
```

- Porter will build (or fetch) the image, create the Kubernetes Job, and stream logs.
- Inspect past runs with `porter jobs list` and fetch logs with `porter jobs logs codex-task`.

To run on a schedule, configure a trigger:

```bash
porter cron create codex-report \
  --service codex-task \
  --schedule "0 13 * * 1-5"
```

This example runs the job at 13:00 UTC every weekday.

## 4. Updating the command or image
- Edit `args` (or add `command`) in `porter.yaml` to change what Codex executes.
- Rebuild and push the image after modifying the container contents: `docker build ... && docker push ...`.
- Trigger a new Porter job to pick up the changes.

## 5. Troubleshooting
- **Job fails immediately**: check `porter jobs logs codex-task` for Codex CLI errors (authentication, arguments, etc.).
- **Authentication errors**: verify the Codex API key secret is present and mapped to `CODEX_API_KEY`.
- **Needs host services (e.g., Ollama)**: set `ENABLE_OSS_BRIDGE=1` and expose the target via reachable network; the helper script already understands `OSS_SERVER_URL`/`OLLAMA_HOST`.
- **Long-running tasks**: adjust the Porter job timeout or Kubernetes active deadline as needed with the `timeoutSeconds` field under the service.
