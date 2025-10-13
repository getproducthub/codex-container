"""Stream Codex CLI output using experimental JSON events.

Usage:
    python examples/run_codex_stream.py "list python files"

Requires the Codex CLI (`codex`) to be installed and on PATH.
"""

import json
import subprocess
import sys
from typing import Iterator, Dict, Any


def stream_codex(prompt: str) -> Iterator[Dict[str, Any]]:
    """Yield Codex JSON events for the given prompt."""
    proc = subprocess.Popen(
        ["codex", "exec", "--experimental-json", "--skip-git-repo-check", "-"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )

    assert proc.stdin is not None
    proc.stdin.write(prompt)
    proc.stdin.close()

    assert proc.stdout is not None
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except json.JSONDecodeError:
            yield {"type": "raw", "content": line}

    proc.wait()


def main() -> None:
    prompt = sys.argv[1] if len(sys.argv) > 1 else "list python files"

    for event in stream_codex(prompt):
        msg = event.get("msg", {})
        event_type = msg.get("type")

        if event_type == "agent_message_delta":
            print(msg.get("delta", ""), end="", flush=True)
        elif event_type == "agent_message":
            print(msg.get("message", ""))
        elif event_type == "agent_reasoning":
            print(f"[reasoning] {msg.get('text', '')}")
        else:
            # Surface everything else for visibility (token counts, etc.)
            print(f"[{event_type}] {event}")


if __name__ == "__main__":
    main()
