---
name: agent-observe-skill
description: Scan a local codebase for Agent Observe evidence and gaps. Use when a user asks to map or audit AI agent prompts, Vercel AI SDK calls, OpenAI SDK calls, tool definitions, tool schemas, chain steps, API routes, client chat entrypoints, eval coverage, trace IDs, logging, loop bounds, needsApproval gates, experimental_telemetry, or side-effect risks in a repository.
---

# Agent Observe Skill

## Overview

Use this skill to generate a local observability report for an AI-agent codebase. It is optimized for Vercel AI SDK 5/6 and OpenAI SDK patterns first, then falls back to broader static evidence.

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

For CI guardrails:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo --ci --max-high 0
```

For machine-readable output only:

```bash
bash /path/to/agent-observe-skill/scripts/skill.sh /path/to/repo --format json
```

When using this skill inside Codex, run `--list-agents` before the full scan unless the user already specified an agent scope. If more than one candidate is listed, ask the user whether to analyze all agents, one agent, or multiple agents. Then run the scan with no `--agent` flag for all agents or with `--agent id1,id2` for a selected subset.

After it runs, direct the user to open `.agent-observe-skill/agent-report.html` in their browser. In Next.js App Router repos, the scanner also creates `app/agent-observe-skill/page.tsx` so the report is available at `/agent-observe-skill`.

The visual report includes agent selection, flow timeline, mermaid diagram, severity filters, search, copy-paste fix snippets, and per-agent context export. Users can inspect entry points, full prompt text, which model call each prompt feeds, which prompts each model call reads, which tools each model call can invoke, loop config, telemetry, routes, and risks locally.

Generated report artifacts are local-only by default. The scanner adds `.agent-observe-skill/` and, when generated, `app/agent-observe-skill/` to the target repo's `.git/info/exclude` file instead of `.gitignore`, so normal `git add .` will not commit them.

## Output Files

The scanner creates:

```text
.agent-observe-skill/
├── agent-report.html   # visual report (default)
├── agent-report.json   # stable machine-readable trace
├── agent-map.md        # LLM-ready agent map with mermaid flows
└── agent-report.previous.json  # previous scan (for diffing)
```

Use `agent-report.html` for the visual preview. Use `agent-report.json` for CI and tooling. Use `agent-map.md` as paste-ready context for Cursor, Codex, or Claude.

## Detection Priorities

Prioritize these Vercel AI SDK and OpenAI SDK signals:

- `streamText(...)`, `generateText(...)`, `streamObject(...)`, `generateObject(...)`
- `new ToolLoopAgent(...)`, `Experimental_Agent`, `dynamicTool(...)`
- `openai.chat.completions.create(...)`, `openai.responses.create(...)`
- `tool(...)` with `inputSchema`, `execute`, `needsApproval`
- Loop control: `stopWhen`, `stepCountIs`, `maxSteps`, `prepareStep`, `onStepFinish`, `toolChoice`, `activeTools`
- Telemetry: `experimental_telemetry`, `functionId`, `recordInputs`, `recordOutputs`
- MCP: `experimental_createMCPClient`
- Structured output: `output`, `experimental_output`
- Message persistence: `convertToModelMessages`
- `system`, `prompt`, `messages`, and `instructions`
- API routes under `app/api/**` and `pages/api/**`
- Client hooks: `useChat(...)`, `useCompletion(...)`, `useAssistant(...)`
- `package.json` `ai` dependency version

## Risk Checks (AI SDK focused)

- Unbounded agent loops (`isLoopFinished()` without bounds)
- `toolChoice: 'required'` without a terminating `done` tool
- Side-effecting tools without `needsApproval`
- Per-call missing `experimental_telemetry` or `functionId`
- Telemetry recording user PII (`recordInputs`/`recordOutputs` with dynamic prompts)
- Scattered hardcoded models across files
- Inline prompts, missing evals, missing trace coverage

Each risk includes a copy-pasteable fix snippet in the report.

## Report Questions

Make sure the final answer reflects the report's answers to:

- Where are prompts defined?
- What is the full text of each prompt?
- Which model calls use which prompts and models?
- Which prompts feed each model call step?
- Which tools can each chain call?
- Which model calls can invoke each tool?
- What schemas do tools expose?
- Which tools have side effects or lack `needsApproval`?
- Which agent loops have bounds (`stopWhen` / `maxSteps`)?
- Is `experimental_telemetry` enabled per call with a `functionId`?
- Which routes expose AI behavior?
- Which chains lack evals?
- Which chains lack trace IDs or logging?
- Which prompts are inline and hard to audit?
- What changed since the last scan?

## Workflow

1. Unless the user already specified all agents or specific agents, run `scripts/skill.sh --list-agents` against the target repo.
2. If more than one candidate is listed, ask the user to choose all agents, one agent, or multiple agents.
3. Run `scripts/skill.sh` against the target repo, using `--agent id1,id2` only when the user selected a subset.
4. Confirm `.agent-observe-skill/agent-report.html` exists and tell the user to open it in their browser.
5. Read summary counts from the scan output or from `.agent-observe-skill/agent-report.json`.
6. Mention `agent-map.md` if the user wants paste-ready agent context for another LLM session.
7. If `app/agent-observe-skill/page.tsx` was generated, tell the user the app route is available at `/agent-observe-skill`.
8. Summarize findings with file references, full prompt text when relevant, prompt-to-model relationships, model-to-tool relationships, fix snippets for high-severity risks, and separate detected evidence from static-analysis limitations.

## Limitations

This is static analysis. Treat findings as evidence for review, not as proof of runtime behavior.

When Node is available, the scanner uses richer local parsing heuristics. Without Node, it uses a Bash and grep fallback that still writes `agent-report.html` but provides less detail.

Git can still commit generated files if a user force-adds them with `git add -f`. Treat the generated UI page and `.agent-observe-skill/` folder as disposable scan output.
