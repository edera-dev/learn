# Code Interpreter agent with Edera-isolated tool calls

A minimal coding agent whose tool calls run inside Edera-isolated sandboxes. The
agent gives an LLM a single tool — `run_python` — and every time the model runs
code, that code executes in a fresh Python sandbox with its own Linux kernel, not
on the host.

This is the pattern behind "code interpreter" features: let the model execute
arbitrary code, but contain that code so it can't touch anything it shouldn't.

## Why Isolate Tool Calls?

An agent that can run code is an agent that can run *arbitrary* code — that's the
point, and the risk. A prompt injection, a hallucinated `rm -rf`, or a malicious
dependency all execute with whatever access the tool has. Running each tool call
in an Edera zone means a compromised execution is contained to a throwaway
sandbox with its own kernel — not your node, not your cluster.

See [AI Agent Sandboxing](https://docs.edera.dev/technical-overview/concepts/ai-agent-isolation/)
for the full explanation.

## How It Works

```
  agent.py (LLM)  ──run_python(code)──►  SandboxClient
                                              │  (tunnel to sandbox-router)
                                              ▼
                                    Edera zone: Python sandbox
                                    (own kernel, from edera-python-template)
```

The agent uses the [Agent Sandbox Python SDK](https://github.com/kubernetes-sigs/agent-sandbox/blob/main/clients/python/agentic-sandbox-client/README.md)
(`k8s-agent-sandbox`). For each tool call it writes the code into the sandbox
(`sandbox.files.write`) and runs it (`sandbox.commands.run`). Sandboxes are
created from the `edera-python-template` SandboxTemplate, which sets
`runtimeClassName: edera`.

## Prerequisites

- A workshop cluster set up per **[SETUP.md](./SETUP.md)** — a single-node
  Kubernetes cluster with EderaON installed, the Edera RuntimeClass, local block
  storage, and the Agent Sandbox controller + extensions + sandbox-router.
- `kubectl` configured against that cluster.
- Python 3.10+ (for the agent and SDK).
- An `ANTHROPIC_API_KEY` (only for `make run` — `make check` needs no key).

## Quick Start

```bash
# 1. Install the SandboxTemplate and verify the sandbox plumbing (no API key).
make check

# 2. Run the agent.
export ANTHROPIC_API_KEY=sk-...
make run
```

`make check` runs [`check_sandbox.py`](./check_sandbox.py): it creates a sandbox,
writes and runs code in it (exactly what the agent's tool does), and prints the
sandbox's kernel so you can confirm it differs from the host's.

`make run` starts a REPL. Try:

```
You: what's the 20th Fibonacci number?
  [tool] run_python({'code': '...'})
Assistant: The 20th Fibonacci number is 6765.
```

The `[tool]` line is the model's code running inside the Edera sandbox.

## Verify Isolation

The sandbox runs its own kernel. Compare the host node:

```bash
kubectl get node -o jsonpath='{.items[0].status.nodeInfo.kernelVersion}{"\n"}'
```

against the kernel `make check` reports from inside the sandbox — they differ,
because the sandbox is a separate Edera zone.

## Files

| File | Purpose |
|------|---------|
| `agent.py` | The LangChain agent with the `run_python` tool |
| `check_sandbox.py` | No-LLM harness that verifies the sandbox plumbing |
| `sandbox-template.yaml` | The `edera-python-template` SandboxTemplate (`runtimeClassName: edera`) |
| `requirements.txt` | Python dependencies |
| `SETUP.md` | Self-contained workshop cluster setup (GCE + EderaON + kubeadm) |

## Cleanup

```bash
make clean
```

## Troubleshooting

**`SandboxTemplateNotFoundError`**: Apply the template with `make template`, and
confirm the Agent Sandbox **extensions** are installed (the `SandboxTemplate` CRD
comes from `extensions.yaml`, not the core controller). See [SETUP.md](./SETUP.md).

**Sandbox never becomes ready / connection errors**: Confirm the sandbox-router is
running (`kubectl get pods -l app=sandbox-router`) — tunnel mode connects through
it.

**Pod stuck Pending**: Verify the Edera RuntimeClass exists: `kubectl get runtimeclass edera`.
