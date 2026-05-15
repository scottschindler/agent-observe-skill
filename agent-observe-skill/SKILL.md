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

If multiple agents are detected and the script is running in an interactive terminal, choose one, multiple comma-separated agents, or all agents from the prompt.

For non-interactive use, list candidates first:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo --list-agents
```

Then scan one or more candidates by id or name:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo --agent checkout
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo --agent checkout,billing
```

When using this skill inside Codex, run `--list-agents` before the full scan unless the user already specified an agent scope. If more than one candidate is listed, ask the user whether to analyze all agents, one agent, or multiple agents. Then run the scan with no `--agent` flag for all agents or with `--agent id1,id2` for a selected subset.

After it runs, read `.agent-observe-skill/report.md` first and open `.agent-observe-skill/index.html` for the visual report. In Next.js App Router repos, the scanner also creates `app/agent-observe-skill/page.tsx` so the report is available at `/agent-observe-skill`.

The visual report is intentionally simple: overall counts, agent buttons, evidence buttons, and one detail panel. Users can select an agent, then inspect tool calls, prompts, model calls, routes, and risks locally.

Generated report artifacts are local-only by default. The scanner adds `.agent-observe-skill/` and, when generated, `app/agent-observe-skill/` to the target repo's `.git/info/exclude` file instead of `.gitignore`, so normal `git add .` will not commit them.

## Output Files

The scanner creates:

```text
.agent-observe-skill/
├── index.html
├── report.md
├── prompts.md
├── tools.md
├── chains.md
├── routes.md
├── risks.md
└── trace-map.json
```

Use `index.html` for the visual preview and `report.md` for the user-facing summary. Use `trace-map.json` when a structured map is needed for follow-up analysis or visualization.

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

1. Unless the user already specified all agents or specific agents, run `scripts/skill.sh --list-agents` against the target repo.
2. If more than one candidate is listed, ask the user to choose all agents, one agent, or multiple agents.
3. Run `scripts/skill.sh` against the target repo, using `--agent id1,id2` only when the user selected a subset.
4. Confirm `.agent-observe-skill/index.html`, `.agent-observe-skill/report.md`, and `.agent-observe-skill/trace-map.json` exist.
5. Read the summary counts from `trace-map.json`.
6. If `app/agent-observe-skill/page.tsx` was generated, tell the user the app route is available at `/agent-observe-skill` after their dev server reloads and includes the simplified per-agent evidence UI.
7. Read `report.md`, `risks.md`, and any focused file the user asks about.
8. Summarize findings with file references and separate detected evidence from static-analysis limitations.

## Limitations

This is static analysis. Treat findings as evidence for review, not as proof of runtime behavior.

When Node is available, the scanner uses richer local parsing heuristics. Without Node, it uses a Bash and grep fallback that still writes the same output files but provides less detail.

Git can still commit generated files if a user force-adds them with `git add -f`. Treat the generated UI page and `.agent-observe-skill/` folder as disposable scan output.
