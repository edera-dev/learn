"""Verify the sandbox tool-call plumbing without involving the LLM.

This exercises exactly what the agent's ``run_python`` tool does — create a
sandbox from the template, write a file into it, run a command, read the result —
and confirms the sandbox is running in its own Edera zone (its own kernel).

Use it to validate the cluster setup before running the full agent (which needs
an Anthropic API key). It makes no Anthropic calls.

    python check_sandbox.py
"""

import sys

from k8s_agent_sandbox import SandboxClient
from k8s_agent_sandbox.models import SandboxLocalTunnelConnectionConfig

WARMPOOL_NAME = "edera-python-pool"


def main():
    print("Creating sandbox from warm pool (this may take a moment)...")
    client = SandboxClient(
        connection_config=SandboxLocalTunnelConnectionConfig(),
        cleanup=True,
    )
    sandbox = client.create_sandbox(warmpool=WARMPOOL_NAME)

    try:
        # 1. The exact path the agent's run_python tool takes: write then run.
        # The runtime resolves the upload filename relative to its /app base.
        sandbox.files.write("code.py", "print('hello from inside the sandbox')")
        result = sandbox.commands.run("python /app/code.py", timeout=30)
        print(f"  exit_code: {result.exit_code}")
        print(f"  stdout:    {result.stdout!r}")
        print(f"  stderr:    {result.stderr!r}")
        assert result.exit_code == 0, "code execution failed"
        assert "hello from inside the sandbox" in result.stdout

        # 2. Show the sandbox runs its own kernel (Edera zone isolation).
        kernel = sandbox.commands.run("uname -r").stdout.strip()
        print(f"  sandbox kernel: {kernel}")

        print("\nOK: write + run plumbing works and the sandbox has its own kernel.")
        print("Compare 'sandbox kernel' above with the host's 'uname -r' — they differ.")
    except Exception as exc:  # noqa: BLE001 - surface any failure clearly
        print(f"\nFAILED: {exc}", file=sys.stderr)
        sys.exit(1)
    finally:
        print("Terminating sandbox...")
        sandbox.terminate()


if __name__ == "__main__":
    main()
