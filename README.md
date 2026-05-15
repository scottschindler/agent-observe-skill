# Agent Observe Skill

Drop one file into your repo. See every prompt, tool, and chain.

Agent Observe Skill is a local scanner for AI-agent codebases. It looks for Vercel AI SDK patterns first, then writes an observability report into the repo it scans. Your code never leaves your machine.

## Install With skills.sh

After this repo is published to GitHub, install it into your agent environment:

```bash
npx skills add scottschindler/agent-observe-skill
```

Then invoke it from your agent:

```text
Use $agent-observe-skill to scan this repo for prompts, tools, chains, routes, eval gaps, and trace risks.
```

## Run The Scanner Directly

You can also run the bundled scanner without installing the skill:

```bash
bash agent-observe-skill/scripts/skill.sh
```

Or scan another repo:

```bash
bash agent-observe-skill/scripts/skill.sh /path/to/repo
```

The downloadable single-file version is here:

```text
public/downloads/agent-observe-skill.sh
```

Users can download it as `skill.sh`, place it at the root of their own repo, and run:

```bash
bash skill.sh
```

## What It Generates

The scanner creates a local output folder in the target repo:

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

Start with `report.md`. Use `trace-map.json` for structured follow-up analysis or visualizations.

## What It Detects

The scanner prioritizes Vercel AI SDK and agent patterns:

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
- Client chat hooks like `useChat(...)`, `useCompletion(...)`, and `useAssistant(...)`

It also flags common observability risks:

- Inline prompts that are hard to audit
- Side-effecting tools
- Chains without nearby eval evidence
- Chains without trace IDs, logging, or telemetry evidence
- AI routes without trace coverage

## Report Questions

The generated report answers:

- Where are prompts defined?
- Which model calls use which prompts?
- Which tools can each chain call?
- What schemas do tools expose?
- Which tools have side effects?
- Which routes expose AI behavior?
- Which chains lack evals?
- Which chains lack trace IDs or logging?
- Which prompts are inline and hard to audit?

## How It Works

`scripts/skill.sh` is portable Bash. When Node is available, it runs an embedded Node scanner for richer static analysis and JSON output. When Node is not available, it falls back to Bash and grep-based detection while still producing the same output files.

The scanner ignores common generated or dependency folders such as `.git`, `node_modules`, `.next`, `dist`, `build`, `coverage`, and `.agent-observe-skill`.

## Privacy

The scanner reads local files and writes local Markdown and JSON. It does not upload source code, call a remote API, or require credentials.

## Demo Page

The static product demo is available at:

```text
/agent-observe-skill/
```

Its source is `agent-observe-skill/index.html`. It includes:

- A download button for `skill.sh`
- A visual chain map
- An inspector panel
- A sample generated report

To preview it locally, serve the repo with any static file server and open `/agent-observe-skill/`.
