# AI Agent Isolation

Examples for running AI agents securely with Edera's per-workload kernel isolation.

## Why Isolate AI Agents?

AI coding agents need broad permissions to be useful—executing code, writing files, installing packages, making network calls. This creates risk: you're giving an AI system the ability to run arbitrary code in your environment.

Edera solves this with virtualization-based isolation. Each AI agent runs in its own Linux kernel. If something goes wrong, it's contained to that workload—not your cluster.

See [AI Agent Sandboxing](https://docs.edera.dev/technical-overview/concepts/ai-agent-isolation/) for the full technical explanation.

## Examples

| Example | Description |
|---------|-------------|
| [Claude Code](./claude-code/) | Run Anthropic's Claude Code CLI in an Edera-protected pod |

## Quick Start

```bash
cd claude-code
make build push deploy exec
```
