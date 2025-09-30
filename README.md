# Codex Service Container Helper

These scripts launch the OpenAI Codex CLI inside a reproducible Docker container. Drop either script somewhere on your `PATH`, change into any project, and the helper mounts the current working directory alongside a persistent Codex home so credentials survive between runs.

## Codex Home Directory

By default the container mounts a user-scoped directory as its `$HOME`:

- Windows PowerShell: `%USERPROFILE%\.codex-service`
- macOS / Linux / WSL: `$HOME/.codex-service`

This folder holds Codex authentication (`.codex/`), CLI configuration, and any scratch files produced inside the container. You can override the location in two ways:

1. Set `CODEX_CONTAINER_HOME` before invoking the script.
2. Pass an explicit flag (`-CodexHome <path>` or `--codex-home <path>`).

Relative paths are resolved the same way your shell would (e.g. `./state`, `~/state`).

Both scripts expand `~`, accept absolute paths, and create the directory if it does not exist. If you previously used the repo-local `codex-home/` folder, move or copy its contents into the new location and delete the old directory when you’re done.

## Windows (PowerShell)

`scripts\codex_container.ps1` (once on `PATH`, invoke it as `codex-container.ps1` or similar):

- **Install / rebuild the image**
  ```powershell
  ./scripts/codex_container.ps1 -Install
  ```
  Builds the `gnosis/codex-service:dev` image and refreshes the bundled Codex CLI.
  The script always mounts the workspace you specify with `-Workspace` (or, by default, the directory you were in when you invoked the command) so Codex sees the same files regardless of the action.

- **Authenticate Codex** *(normally triggered automatically)*
  ```powershell
  ./scripts/codex_container.ps1 -Login
  ```

- **Run the interactive CLI in the current repo**
  ```powershell
  ./scripts/codex_container.ps1 -- "summarize the repo"
  ```

- **Non-interactive execution**
  ```powershell
  ./scripts/codex_container.ps1 -Exec "hello"
  ./scripts/codex_container.ps1 -Exec -JsonE "status report"
  ```
  `-Json` enables the legacy `--json` stream; `-JsonE` selects the new `--experimental-json` format.

- **Custom Codex home**
  ```powershell
  ./scripts/codex_container.ps1 -Exec "hello" -CodexHome "C:\\Users\\kordl\\.codex-service-test"
  ```

- **Other useful switches**
  - `-Shell` opens an interactive `/bin/bash` session inside the container.
  - `-Workspace <path>` mounts a different project directory at `/workspace`.
  - `-Tag <image>` and `-Push` let you build or push under a custom image name.
  - `-SkipUpdate` skips the npm refresh (useful when you know the CLI is up to date).
  - `-NoAutoLogin` disables the implicit login check; Codex must already be authenticated.
  - `-Oss` tells Codex to target a locally hosted provider via `--oss` (e.g., Ollama). The helper automatically bridges `127.0.0.1:11434` inside the container to your host service—just keep Ollama running as you normally would.
  - `-OssModel <name>` (maps to Codex `-m/--model` and implies `-Oss`) selects the model Codex should request when using the OSS provider.
  - `-CodexArgs <value>` and `-Exec` both accept multiple values (repeat the flag or pass positionals after `--`) to forward raw arguments to the CLI.

## macOS / Linux / WSL (Bash)

`scripts/codex_container.sh` provides matching functionality:

- Primary actions: `--install`, `--login`, `--run` (default), `--exec`, `--shell`
- JSON output switches: `--json`, `--json-e` (alias `--json-experimental`)
- Override Codex home: `--codex-home /path/to/state`
- Other useful flags:
  - `--workspace <path>` mounts an alternate directory as `/workspace`.
  - `--tag <image>` / `--push` match the Docker image controls in the PowerShell script.
  - `--skip-update` skips the npm refresh; `--no-auto-login` avoids implicit login attempts.
  - `--oss` forwards the `--oss` flag and the helper bridge takes care of sending container traffic to your host Ollama service automatically.
  - `--model <name>` (maps to Codex `-m/--model` and implies `--oss`) mirrors the PowerShell `-OssModel` flag.
  - `--codex-arg <value>` and `--exec-arg <value>` forward additional parameters to Codex (repeat the flag as needed).

Typical example:

```bash
./scripts/codex_container.sh --exec --json-e "hello"
```
The directory passed via `--workspace`—or, if omitted, the directory you were in when you invoked the script—is what gets mounted into `/workspace` for *all* actions (install, login, run, etc.).

## Cleanup Helpers

To wipe Codex state quickly:

- PowerShell: `./scripts/cleanup_codex.ps1 [-CodexHome C:\path\to\state] [-RemoveDockerImage]`
- Bash: `./scripts/cleanup_codex.sh [--codex-home ~/path/to/state] [--remove-image] [--tag image:tag]`

## Requirements

- Docker Desktop / Docker Engine accessible from your shell. On Windows + WSL, enable Docker Desktop’s WSL integration **and** add your user to the `docker` group (`sudo usermod -aG docker $USER`).
- No local Node.js install is required; the CLI lives inside the container.
- Building the image (or running the update step) requires internet access to fetch `@openai/codex` from npm. You can pin a version at build time via `--build-arg CODEX_CLI_VERSION=0.42.0` if desired.
- When using `--oss/-Oss`, the helper bridge tunnels `127.0.0.1:11434` inside the container to your host; just keep your Ollama daemon running as usual.

## Troubleshooting

- **`permission denied` talking to Docker** – ensure your user is in the `docker` group and restart the shell; verify `docker ps` works before rerunning the scripts.
- **Codex keeps asking for login** – run `-Login`/`--login` to refresh credentials. The persisted files live under the configured Codex home (not the repo).
- **`… does not support tools` from Ollama** – switch to a model that advertises tool support or disable tool usage when invoking Codex; the OSS bridge assumes the provider can execute tool calls.
- **Reset everything** – delete the Codex home folder you configured (e.g. `%USERPROFILE%\.codex-service`) and reinstall/login.
