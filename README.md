# Agent Observe Skill

Agent Observe Skill is a local scanner for AI-agent codebases. It looks for Vercel AI SDK, OpenAI SDK, and broader agent patterns, then writes an observability report into the repo it scans. Your code never leaves your machine.

## UI Example

![Agent Observe Skill UI example](assets/ui-example.png)

## Add To A Codex Repo

From the root of the repo you want to scan:

```bash
curl -fsSL https://raw.githubusercontent.com/scottschindler/agent-observe-skill/main/public/downloads/install-codex-skill.sh | bash
```

Restart Codex from that repo, start a new thread, then invoke:

```text
Use $agent-observe-skill to scan this repo for prompts, tools, model calls, entry points, routes, eval gaps, and trace risks.
```

If you prefer not to pipe into `bash`, download and run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/scottschindler/agent-observe-skill/main/public/downloads/install-codex-skill.sh -o install-agent-observe.sh
bash install-agent-observe.sh
rm install-agent-observe.sh
```

Commit the skill folder if you want everyone on the project to have it:

```bash
git add .agents/skills/agent-observe-skill
git commit -m "Add agent observe Codex skill"
```

## Install As A Codex Plugin

Add the Agent Observe plugin marketplace:

```bash
codex plugin marketplace add scottschindler/agent-observe-skill --sparse .agents/plugins
```

This only adds the marketplace catalog. To make `$agent-observe-skill` appear in Codex, restart Codex, open the Plugin Directory, choose **Agent Observe**, install **Agent Observe Skill**, then start a new thread. Resumed threads keep the skill list they had when they were created.

After installing the plugin, invoke:

```text
Use $agent-observe-skill to scan this repo for prompts, tools, model calls, entry points, routes, eval gaps, and trace risks.
```

To update later:

```bash
codex plugin marketplace upgrade agent-observe-marketplace
```

## Install With skills.sh For Claude Code

For Claude Code, install the skill with the skills.sh CLI:

```bash
npx skills add scottschindler/agent-observe-skill
```

Then invoke it from Claude Code:

```text
Use $agent-observe-skill to scan this repo for prompts, tools, chains, routes, eval gaps, and trace risks.
```

## What It Generates

The scanner creates a local output folder in the target repo:

```text
.agent-observe-skill/
├── agent-report.html
├── agent-report.json
├── agent-map.md
└── agent-report.previous.json
```

Open `agent-report.html` in your browser. It includes agent selection, flow timeline, full prompt text, prompt-to-model links, model-to-tool links, mermaid diagram, severity filters, search, copy-paste fix snippets, and per-agent context export. Use `agent-report.json` for CI and tooling. Use `agent-map.md` as paste-ready context for Cursor, Codex, or Claude. Generated files are added to `.git/info/exclude` so they stay out of ordinary commits.

## CI Guardrail

Fail the build when high-severity risks exceed a threshold:

```bash
bash agent-observe-skill/scripts/skill.sh . --ci --max-high 0
```

GitHub Actions example:

```yaml
- name: Agent Observe scan
  run: |
    bash agent-observe-skill/scripts/skill.sh . --ci --max-high 0
```

## What Gets Installed

The installed skill is limited to `SKILL.md`, `agents/openai.yaml`, `scripts/skill.sh`, and `scripts/_report-ui-script.js`. Demo files and README images stay outside the skill folder.

## What It Detects

The scanner prioritizes Vercel AI SDK 5/6, OpenAI SDK, and agent patterns:

- `streamText(...)`, `generateText(...)`, `streamObject(...)`, `generateObject(...)`
- `new ToolLoopAgent(...)`, `Experimental_Agent`, `dynamicTool(...)`
- `openai.chat.completions.create(...)`, `openai.responses.create(...)`
- `tool(...)` with `inputSchema`, `execute`, `needsApproval`
- Loop control: `stopWhen`, `stepCountIs`, `maxSteps`, `prepareStep`, `toolChoice`
- Telemetry: `experimental_telemetry`, `functionId`, `recordInputs`, `recordOutputs`
- MCP clients, structured output, message persistence helpers
- `system`, `prompt`, `messages`, and `instructions`
- API routes under `app/api/**` and `pages/api/**`
- Client chat hooks like `useChat(...)`, `useCompletion(...)`, and `useAssistant(...)`
- `package.json` `ai` dependency version

It also flags AI SDK-specific risks with copy-paste fix snippets:

- Unbounded agent loops and `toolChoice: 'required'` without a `done` tool
- Side-effecting tools without `needsApproval`
- Per-call missing telemetry or `functionId`
- Telemetry recording user PII in prompts
- Scattered hardcoded models across files
- Inline prompts, missing evals, missing trace coverage

## Report Questions

The generated report answers:

- Where are prompts defined?
- What is the full text of each prompt?
- Which model calls use which prompts and models?
- Which tools can each chain call?
- Which model calls can invoke each tool?
- What schemas do tools expose?
- Which tools have side effects or lack approval gates?
- Which agent loops have bounds?
- Is telemetry configured per call?
- Which routes expose AI behavior?
- Which chains lack evals?
- Which chains lack trace IDs or logging?
- Which prompts are inline and hard to audit?
- What changed since the last scan?

## How It Works

`scripts/skill.sh` is portable Bash. When Node is available, it runs an embedded Node scanner for richer static analysis and the visual HTML report. When Node is not available, it falls back to Bash and grep-based detection while still producing `agent-report.html`.

The scanner ignores common generated or dependency folders such as `.git`, `node_modules`, `.next`, `dist`, `build`, `coverage`, and `.agent-observe-skill`.

## Privacy

The scanner reads local files and writes a local HTML report. It does not upload source code, call a remote API, or require credentials.

## Demo Page

The static product demo is available at:

```text
demo/
```

Its source is `demo/index.html`, baked from a scan of `agent-observe-skill/fixtures/sample-agent`. It includes:

- 4 sample agents (chat, checkout, unbounded loop)
- AI SDK version header (`ai@6.0.0`)
- Flow timeline, mermaid diagram, severity filters, and search
- Copy-paste fix snippets and per-agent context export
- Report/Risks toggle with 12 sample risks

To preview locally, serve the repo with any static file server and open `demo/`.

To refresh the demo after fixture changes, scan the fixture then rebake:

```bash
bash agent-observe-skill/scripts/skill.sh agent-observe-skill/fixtures/sample-agent
node agent-observe-skill/scripts/bake-demo.js
```
