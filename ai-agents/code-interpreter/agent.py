"""A minimal coding agent whose tool calls run inside an Edera-isolated sandbox.

The agent exposes a single tool, ``run_python``, to the LLM. Every time the model
decides to run code, that code executes in a fresh Python sandbox managed by the
Agent Sandbox controller and running in its own Edera zone (its own kernel) — not
on the host. The model never touches the host; it can only reach the sandbox.

Run it:

    export ANTHROPIC_API_KEY=sk-...
    python agent.py

Requires a cluster set up per the workshop README (Agent Sandbox controller +
extensions, the sandbox-router, and the ``edera-python-template`` SandboxTemplate
plus the ``edera-python-pool`` SandboxWarmPool).
"""

import os

from k8s_agent_sandbox import SandboxClient
from k8s_agent_sandbox.models import SandboxLocalTunnelConnectionConfig
from langchain_anthropic import ChatAnthropic
from langchain_core.tools import tool
from langchain_core.messages import SystemMessage, HumanMessage, ToolMessage

WARMPOOL_NAME = "edera-python-pool"
MODEL = os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-6")

SYSTEM_PROMPT = (
    "You are a helpful coding assistant with access to a Python sandbox. "
    "When asked to compute something, analyze data, or run code, use the "
    "run_python tool. Always show the code you're running."
)


def make_tools(sandbox):
    @tool
    def run_python(code: str) -> str:
        """Execute Python code in an Edera-isolated sandbox and return its output."""
        # The runtime resolves the upload filename relative to its /app base,
        # so write "code.py" (not "/app/code.py") — it lands at /app/code.py.
        sandbox.files.write("code.py", code)
        result = sandbox.commands.run("python /app/code.py", timeout=30)
        if result.exit_code == 0:
            return result.stdout or "(no output)"
        return f"Error (exit code {result.exit_code}):\n{result.stderr}"

    return [run_python]


def run_turn(llm_with_tools, tools_by_name, messages):
    """Drive one user turn to completion, resolving any tool calls along the way."""
    while True:
        response = llm_with_tools.invoke(messages)
        messages.append(response)

        if not response.tool_calls:
            return response.content

        for tc in response.tool_calls:
            print(f"  [tool] {tc['name']}({tc['args']})")
            result = tools_by_name[tc["name"]].invoke(tc["args"])
            messages.append(ToolMessage(content=result, tool_call_id=tc["id"]))


def main():
    llm = ChatAnthropic(
        model_name=MODEL,
        api_key=os.environ["ANTHROPIC_API_KEY"],
        timeout=60.0,
        stop=[],
    )

    print("Starting sandbox (this may take a moment)...")
    client = SandboxClient(
        connection_config=SandboxLocalTunnelConnectionConfig(),
        cleanup=True,
    )
    sandbox = client.create_sandbox(warmpool=WARMPOOL_NAME)

    try:
        tools = make_tools(sandbox)
        llm_with_tools = llm.bind_tools(tools)
        tools_by_name = {t.name: t for t in tools}

        messages = [SystemMessage(SYSTEM_PROMPT)]

        print("Ready. Type 'exit' to quit.\n")
        while True:
            try:
                user_input = input("You: ").strip()
            except (EOFError, KeyboardInterrupt):
                break

            if not user_input or user_input.lower() in ("exit", "quit"):
                break

            messages.append(HumanMessage(user_input))
            reply = run_turn(llm_with_tools, tools_by_name, messages)
            print(f"\nAssistant: {reply}\n")
    finally:
        print("\nTerminating sandbox...")
        sandbox.terminate()


if __name__ == "__main__":
    main()
