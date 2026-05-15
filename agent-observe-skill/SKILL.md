---
name: agent-observe-skill
description: Scan a local codebase for Agent Observe evidence and gaps. Use when a user asks to map or audit AI agent prompts, Vercel AI SDK calls, tool definitions, tool schemas, chain steps, API routes, client chat entrypoints, eval coverage, trace IDs, logging, or side-effect risks in a repository.
---

# Agent Observe Skill

## Overview

Use this skill to generate a local observability report for an AI-agent codebase. It is optimized for Vercel AI SDK patterns first, then falls back to broader static evidence.

The scanner writes all output into `.agent-observe-skill/` in the target repo. The user's code stays local.

## Quick Start

Run the bundled scanner from the repository root:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh
```

If running from outside the target repo, pass the repo path:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo
```

If multiple agents are detected and the script is running in an interactive terminal, choose one from the prompt or choose all agents.

For non-interactive use, list candidates first:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo --list-agents
```

Then scan one candidate by id or name:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo --agent checkout
```

After it runs, read `.agent-observe-skill/report.md` first, then inspect the focused files as needed.

## Output Files

The scanner creates:

```text
.agent-observe-skill/
├── report.md
├── prompts.md
├── tools.md
├── chains.md
├── routes.md
├── risks.md
└── trace-map.json
```

Use `report.md` for the user-facing summary. Use `trace-map.json` when a structured map is needed for follow-up analysis or visualization.

## Detection Priorities

Prioritize these Vercel AI SDK signals:

- `streamText(...)`
- `generateText(...)`
- `streamObject(...)`
- `generateObject(...)`
- `tool(...)`
- `ToolLoopAgent`
- `system`, `prompt`, and `messages`
- `inputSchema`
- `execute`
- API routes under `app/api/**` and `pages/api/**`
- Client hooks such as `useChat(...)`, `useCompletion(...)`, and `useAssistant(...)`

## Report Questions

Make sure the final answer reflects the report's answers to:

- Where are prompts defined?
- Which model calls use which prompts?
- Which tools can each chain call?
- What schemas do tools expose?
- Which tools have side effects?
- Which routes expose AI behavior?
- Which chains lack evals?
- Which chains lack trace IDs or logging?
- Which prompts are inline and hard to audit?

## Workflow

1. Run `scripts/skill.sh` against the target repo.
2. Confirm `.agent-observe-skill/report.md` and `.agent-observe-skill/trace-map.json` exist.
3. Read the summary counts from `trace-map.json`.
4. Read `report.md`, `risks.md`, and any focused file the user asks about.
5. Summarize findings with file references and separate detected evidence from static-analysis limitations.

## Limitations

This is static analysis. Treat findings as evidence for review, not as proof of runtime behavior.

When Node is available, the scanner uses richer local parsing heuristics. Without Node, it uses a Bash and grep fallback that still writes the same output files but provides less detail.
