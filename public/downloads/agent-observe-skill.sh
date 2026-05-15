#!/usr/bin/env bash
set -u

ROOT=""
AGENT_FILTER="${AGENT_OBSERVE_AGENT:-}"
LIST_AGENTS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)
      AGENT_FILTER="${2:-}"
      shift 2
      ;;
    --agent=*)
      AGENT_FILTER="${1#--agent=}"
      shift
      ;;
    --list-agents)
      LIST_AGENTS=1
      shift
      ;;
    --help|-h)
      cat <<'HELP'
Usage: bash skill.sh [repo-path] [--agent <agent-name-or-id[,agent-name-or-id...]>] [--list-agents]

Options:
  --agent <value>   Scan one or more detected agents. Accepts shown ids, names, comma-separated values, or "all".
  --list-agents     Print detected agents and exit without writing reports.
  --help            Show this help.
HELP
      exit 0
      ;;
    *)
      if [ -z "$ROOT" ]; then
        ROOT="$1"
        shift
      else
        say "Unknown argument: $1" >&2
        exit 1
      fi
      ;;
  esac
done

ROOT="${ROOT:-$(pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)"
OUT_DIR="$ROOT/.agent-observe-skill"
SELF_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
GIT_EXCLUDE=""
if command -v git >/dev/null 2>&1; then
  GIT_EXCLUDE="$(git -C "$ROOT" rev-parse --git-path info/exclude 2>/dev/null || true)"
  if [ -n "$GIT_EXCLUDE" ] && [ "${GIT_EXCLUDE#/}" = "$GIT_EXCLUDE" ]; then
    GIT_EXCLUDE="$ROOT/$GIT_EXCLUDE"
  fi
fi

mkdir -p "$OUT_DIR"

say() {
  printf '%s\n' "$*"
}

add_local_git_exclude() {
  [ -n "$GIT_EXCLUDE" ] || return 0
  mkdir -p "$(dirname "$GIT_EXCLUDE")"
  touch "$GIT_EXCLUDE"
  if ! grep -qxF "# Agent Observe generated artifacts" "$GIT_EXCLUDE"; then
    printf '\n# Agent Observe generated artifacts\n' >> "$GIT_EXCLUDE"
  fi
  for pattern in "$@"; do
    if ! grep -qxF "$pattern" "$GIT_EXCLUDE"; then
      printf '%s\n' "$pattern" >> "$GIT_EXCLUDE"
    fi
  done
}

INTERACTIVE=0
if [ -t 0 ] && [ -t 1 ]; then
  INTERACTIVE=1
fi

if command -v node >/dev/null 2>&1; then
  SKILL_SELF="$SELF_PATH" AGENT_OBSERVE_AGENT="$AGENT_FILTER" AGENT_OBSERVE_LIST="$LIST_AGENTS" AGENT_OBSERVE_INTERACTIVE="$INTERACTIVE" node - "$ROOT" "$OUT_DIR" <<'NODE'
const fs = require("fs");
const path = require("path");
const childProcess = require("child_process");

const root = process.argv[2];
const outDir = process.argv[3];
const selfPath = path.resolve(process.env.SKILL_SELF || "");
const requestedAgent = clean(process.env.AGENT_OBSERVE_AGENT || "");
const listAgentsOnly = process.env.AGENT_OBSERVE_LIST === "1";
const interactive = process.env.AGENT_OBSERVE_INTERACTIVE === "1";

const ignoreDirs = new Set([
  ".git",
  ".hg",
  ".svn",
  "node_modules",
  ".next",
  ".nuxt",
  ".svelte-kit",
  "dist",
  "build",
  "coverage",
  ".turbo",
  ".vercel",
  ".agent-observe-skill",
]);
const scanExts = new Set([
  ".js",
  ".jsx",
  ".ts",
  ".tsx",
  ".mjs",
  ".cjs",
  ".mts",
  ".cts",
  ".mdx",
]);

const records = {
  agents: [],
  prompts: [],
  tools: [],
  chains: [],
  routes: [],
  uiEntrypoints: [],
  modelCalls: [],
  risks: [],
};

function rel(file) {
  return path.relative(root, file).split(path.sep).join("/");
}

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ignoreDirs.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, files);
      continue;
    }
    if (!entry.isFile()) continue;
    if (path.resolve(full) === selfPath) continue;
    if (scanExts.has(path.extname(entry.name))) files.push(full);
  }
  return files;
}

function lineOf(text, index) {
  return text.slice(0, index).split(/\r?\n/).length;
}

function clean(value) {
  return String(value || "")
    .replace(/\s+/g, " ")
    .replace(/`/g, "'")
    .trim();
}

function preview(value, max = 140) {
  const text = clean(value);
  return text.length > max ? `${text.slice(0, max - 1)}...` : text;
}

function id(prefix, file, line, extra = "") {
  return `${prefix}:${rel(file)}:${line}${extra ? `:${extra}` : ""}`;
}

function slug(value) {
  const text = clean(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return text || "agent";
}

function titleCaseSlug(value) {
  return clean(value)
    .split(/[-_/.\s]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ") || "Agent";
}

function inferAgent(file, text, index = 0, fallback = "agent") {
  const relative = rel(file);
  const appRoute = relative.match(/^app\/api\/(.+)\/route\.[cm]?[jt]sx?$/);
  if (appRoute) {
    const name = appRoute[1].replace(/\[[^\]]+\]/g, "").replace(/\/+/g, "-") || "api-agent";
    return { id: `route:${slug(name)}`, name: titleCaseSlug(name), source: "api-route" };
  }
  const pagesRoute = relative.match(/^pages\/api\/(.+)\.[cm]?[jt]sx?$/);
  if (pagesRoute) {
    const name = pagesRoute[1].replace(/\[[^\]]+\]/g, "").replace(/\/+/g, "-") || "api-agent";
    return { id: `route:${slug(name)}`, name: titleCaseSlug(name), source: "api-route" };
  }
  const before = text.slice(Math.max(0, index - 260), index);
  const named = before.match(/(?:export\s+)?(?:async\s+function|function|const|let|var)\s+([A-Za-z_$][\w$]*(?:Agent|Chat|Assistant|Chain|Workflow)[A-Za-z_$\w]*)/i);
  if (named) {
    return { id: `code:${slug(named[1])}`, name: named[1], source: "code-symbol" };
  }
  const base = path.basename(relative).replace(/\.[cm]?[jt]sx?$/, "").replace(/\.mdx$/, "");
  const dir = path.basename(path.dirname(relative));
  const name = /^(index|route|page)$/.test(base) ? dir : base;
  return { id: `file:${slug(name || fallback)}`, name: titleCaseSlug(name || fallback), source: "file" };
}

const agentMap = new Map();

function registerAgent(agent, file, line, kind) {
  if (!agent || !agent.id) return "";
  const current = agentMap.get(agent.id) || {
    id: agent.id,
    name: agent.name || agent.id,
    source: agent.source || "detected",
    files: new Set(),
    evidence: [],
    counts: { prompts: 0, tools: 0, chains: 0, routes: 0, uiEntrypoints: 0, risks: 0 },
  };
  current.files.add(rel(file));
  current.evidence.push({ file: rel(file), line, kind });
  agentMap.set(agent.id, current);
  return agent.id;
}

function read(file) {
  try {
    return fs.readFileSync(file, "utf8");
  } catch {
    return "";
  }
}

function eachMatch(text, regex, fn) {
  regex.lastIndex = 0;
  let match;
  while ((match = regex.exec(text))) {
    fn(match);
    if (match.index === regex.lastIndex) regex.lastIndex += 1;
  }
}

function extractBalancedCall(text, start) {
  const open = text.indexOf("(", start);
  if (open === -1) return text.slice(start, start + 900);
  let depth = 0;
  let quote = "";
  let escaped = false;
  for (let i = open; i < text.length; i += 1) {
    const ch = text[i];
    if (quote) {
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === quote) {
        quote = "";
      }
      continue;
    }
    if (ch === "'" || ch === '"' || ch === "`") {
      quote = ch;
      continue;
    }
    if (ch === "(") depth += 1;
    if (ch === ")") depth -= 1;
    if (depth === 0) return text.slice(start, i + 1);
  }
  return text.slice(start, start + 1200);
}

function inferAssignedName(text, index, fallback) {
  const before = text.slice(Math.max(0, index - 180), index);
  const assigned = before.match(/(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*$/);
  if (assigned) return assigned[1];
  const property = before.match(/([A-Za-z_$][\w$]*)\s*:\s*$/);
  if (property) return property[1];
  return fallback;
}

function extractProperty(snippet, key) {
  const pattern = new RegExp(`\\b${key}\\s*:\\s*([\\s\\S]{1,700})`);
  const match = snippet.match(pattern);
  if (!match) return "";
  const raw = match[1].trim();
  if (raw[0] === "`" || raw[0] === '"' || raw[0] === "'") {
    const quote = raw[0];
    let escaped = false;
    for (let i = 1; i < raw.length; i += 1) {
      const ch = raw[i];
      if (escaped) {
        escaped = false;
      } else if (ch === "\\") {
        escaped = true;
      } else if (ch === quote) {
        return raw.slice(0, i + 1);
      }
    }
  }
  if (raw[0] === "{") return raw.slice(0, findMatching(raw, "{", "}") + 1);
  if (raw[0] === "[") return raw.slice(0, findMatching(raw, "[", "]") + 1);
  return (raw.match(/^[^,\n)]+/) || [""])[0].trim();
}

function findMatching(text, open, close) {
  let depth = 0;
  let quote = "";
  let escaped = false;
  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (quote) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === quote) quote = "";
      continue;
    }
    if (ch === "'" || ch === '"' || ch === "`") {
      quote = ch;
      continue;
    }
    if (ch === open) depth += 1;
    if (ch === close) depth -= 1;
    if (depth === 0) return i;
  }
  return Math.min(text.length - 1, 600);
}

function hasEvalEvidence(text, file) {
  return /\b(eval|evaluate|judg(e|ment)|grade|benchmark)\b/i.test(text) ||
    /(__tests__|\.test\.|\.spec\.|evals?\/|tests?\/)/i.test(rel(file)) ||
    /\b(expect|assert|describe|it|test)\s*\(/.test(text);
}

function hasTraceEvidence(text) {
  return /\b(traceId|trace_id|span|telemetry|experimental_telemetry|logger|log\.|console\.(log|info|warn|error)|observability|otel|sentry)\b/i.test(text);
}

function hasSideEffect(snippet) {
  return /\b(fetch|axios|request|prisma|db\.|sql`|insert|update|delete|upsert|create|writeFile|appendFile|unlink|rm\(|send|email|stripe|charge|refund|queue|publish|POST|PUT|PATCH|DELETE)\b/i.test(snippet);
}

function schemaSummary(snippet) {
  const schema = extractProperty(snippet, "inputSchema") || extractProperty(snippet, "schema") || "";
  if (!schema) return "No inputSchema detected";
  const keys = new Set();
  eachMatch(schema, /\b([A-Za-z_$][\w$]*)\s*:\s*(?:z\.|Schema\.|Type\.|yup\.|v\.)/g, (m) => keys.add(m[1]));
  return keys.size ? [...keys].slice(0, 12).join(", ") : preview(schema, 180);
}

function pushRisk(kind, severity, file, line, message, evidence, targetId = "", agentId = "") {
  const risk = {
    id: id("risk", file, line, `${kind}:${records.risks.length + 1}`),
    kind,
    severity,
    file: rel(file),
    line,
    message,
    evidence: preview(evidence, 220),
    targetId,
    agentId,
  };
  records.risks.push(risk);
  return risk;
}

const files = walk(root);

for (const file of files) {
  const text = read(file);
  const relative = rel(file);
  const fileAgent = inferAgent(file, text, 0);

  const isAppRoute = /^app\/api\/.*\/route\.[cm]?[jt]sx?$/.test(relative);
  const isPagesRoute = /^pages\/api\/.*\.[cm]?[jt]sx?$/.test(relative);
  if (isAppRoute || isPagesRoute) {
    const routeAgent = inferAgent(file, text, 0);
    const agentId = registerAgent(routeAgent, file, 1, "route");
    const methods = new Set();
    eachMatch(text, /\bexport\s+(?:async\s+)?function\s+(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\b/g, (m) => methods.add(m[1]));
    eachMatch(text, /\bexport\s+const\s+(GET|POST|PUT|PATCH|DELETE|OPTIONS|HEAD)\b/g, (m) => methods.add(m[1]));
    if (isPagesRoute && methods.size === 0) methods.add("handler");
    const aiPatterns = [];
    for (const pattern of ["streamText", "generateText", "streamObject", "generateObject", "ToolLoopAgent"]) {
      if (text.includes(pattern)) aiPatterns.push(pattern);
    }
    records.routes.push({
      id: id("route", file, 1),
      file: relative,
      line: 1,
      kind: isAppRoute ? "app-router" : "pages-api",
      methods: [...methods],
      aiPatterns,
      hasTrace: hasTraceEvidence(text),
      agentId,
    });
  }

  eachMatch(text, /\b(useChat|useCompletion|useAssistant)\s*\(/g, (m) => {
    const snippet = extractBalancedCall(text, m.index);
    const apiValue = preview(extractProperty(snippet, "api") || "Default or indirect API route", 100);
    const apiMatch = apiValue.match(/\/api\/([A-Za-z0-9_/-]+)/);
    const uiAgent = apiMatch
      ? { id: `route:${slug(apiMatch[1])}`, name: titleCaseSlug(apiMatch[1]), source: "client-api" }
      : inferAgent(file, text, m.index, m[1]);
    const agentId = registerAgent(uiAgent, file, lineOf(text, m.index), "ui");
    records.uiEntrypoints.push({
      id: id("ui", file, lineOf(text, m.index), m[1]),
      file: relative,
      line: lineOf(text, m.index),
      hook: m[1],
      api: apiValue,
      evidence: preview(snippet, 220),
      agentId,
    });
  });

  eachMatch(text, /\b(system|prompt|messages)\s*:\s*(`(?:\\.|[^`])*`|"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|\[[\s\S]{0,700}?\]|[A-Za-z_$][\w$.[\]]*)/g, (m) => {
    const value = m[2] || "";
    const inline = /^[`"']/.test(value) || (m[1] === "messages" && value.trim().startsWith("["));
    const prompt = {
      id: id("prompt", file, lineOf(text, m.index), `${m[1]}:${records.prompts.length + 1}`),
      file: relative,
      line: lineOf(text, m.index),
      agentId: registerAgent(fileAgent, file, lineOf(text, m.index), "prompt"),
      kind: m[1],
      inline,
      valueType: inline ? "inline literal" : "reference",
      preview: preview(value, 180),
    };
    records.prompts.push(prompt);
    if (inline) {
      pushRisk(
        "inline-prompt",
        "medium",
        file,
        prompt.line,
        "Prompt is inline and harder to audit, diff, reuse, or cover with evals.",
        prompt.preview,
        prompt.id,
        prompt.agentId,
      );
    }
  });

  eachMatch(text, /(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*(?:Prompt|System|Messages|Instruction|Instructions)[A-Za-z_$\w]*)\s*=\s*(`(?:\\.|[^`])*`|"(?:\\.|[^"])*"|'(?:\\.|[^'])*')/gi, (m) => {
    records.prompts.push({
      id: id("prompt", file, lineOf(text, m.index), m[1]),
      file: relative,
      line: lineOf(text, m.index),
      agentId: registerAgent(fileAgent, file, lineOf(text, m.index), "prompt"),
      kind: "constant",
      name: m[1],
      inline: false,
      valueType: "named constant",
      preview: preview(m[2], 180),
    });
  });

  eachMatch(text, /\btool\s*\(\s*\{/g, (m) => {
    const snippet = extractBalancedCall(text, m.index);
    const line = lineOf(text, m.index);
    const name = inferAssignedName(text, m.index, `tool_${records.tools.length + 1}`);
    const sideEffect = hasSideEffect(extractProperty(snippet, "execute") || snippet);
    const tool = {
      id: id("tool", file, line, name),
      file: relative,
      line,
      agentId: registerAgent(fileAgent, file, line, "tool"),
      name,
      description: preview(extractProperty(snippet, "description") || "No description detected", 160),
      schema: schemaSummary(snippet),
      hasInputSchema: /\binputSchema\s*:/.test(snippet),
      hasExecute: /\bexecute\s*:/.test(snippet),
      sideEffect,
      evidence: preview(snippet, 240),
    };
    records.tools.push(tool);
    if (sideEffect) {
      pushRisk(
        "side-effect-tool",
        "high",
        file,
        line,
        `Tool ${name} appears to perform side effects and should have trace IDs, authorization checks, and tests.`,
        tool.evidence,
        tool.id,
        tool.agentId,
      );
    }
  });

  eachMatch(text, /\b(streamText|generateText|streamObject|generateObject)\s*\(/g, (m) => {
    const snippet = extractBalancedCall(text, m.index);
    const line = lineOf(text, m.index);
    const model = extractProperty(snippet, "model") || "No model property detected";
    const promptRefs = [];
    for (const key of ["system", "prompt", "messages"]) {
      const value = extractProperty(snippet, key);
      if (value) promptRefs.push(`${key}: ${preview(value, 90)}`);
    }
    const toolBlock = extractProperty(snippet, "tools");
    const tools = [];
    if (toolBlock) {
      eachMatch(toolBlock, /\b([A-Za-z_$][\w$]*)\s*[:,]/g, (tm) => {
        if (!["description", "parameters", "inputSchema", "execute"].includes(tm[1])) tools.push(tm[1]);
      });
    }
    const chain = {
      id: id("chain", file, line, m[1]),
      file: relative,
      line,
      agentId: registerAgent(inferAgent(file, text, m.index, m[1]), file, line, "chain"),
      type: m[1],
      model: preview(model, 120),
      prompts: promptRefs,
      tools: [...new Set(tools)],
      hasEval: hasEvalEvidence(text, file),
      hasTrace: hasTraceEvidence(snippet) || hasTraceEvidence(text),
      evidence: preview(snippet, 260),
    };
    records.modelCalls.push(chain);
    records.chains.push(chain);
    if (!chain.hasEval) {
      pushRisk("missing-eval", "medium", file, line, `${m[1]} chain lacks nearby eval or test evidence.`, snippet, chain.id, chain.agentId);
    }
    if (!chain.hasTrace) {
      pushRisk("missing-trace", "high", file, line, `${m[1]} chain lacks trace ID, structured logging, or AI SDK telemetry evidence.`, snippet, chain.id, chain.agentId);
    }
  });

  eachMatch(text, /\bToolLoopAgent\b/g, (m) => {
    const line = lineOf(text, m.index);
    const snippet = text.slice(Math.max(0, m.index - 220), Math.min(text.length, m.index + 700));
    const chain = {
      id: id("chain", file, line, "ToolLoopAgent"),
      file: relative,
      line,
      agentId: registerAgent(inferAgent(file, text, m.index, "ToolLoopAgent"), file, line, "chain"),
      type: "ToolLoopAgent",
      model: "Agent loop",
      prompts: [],
      tools: records.tools.filter((tool) => tool.file === relative).map((tool) => tool.name),
      hasEval: hasEvalEvidence(text, file),
      hasTrace: hasTraceEvidence(text),
      evidence: preview(snippet, 260),
    };
    records.chains.push(chain);
    if (!chain.hasEval) pushRisk("missing-eval", "medium", file, line, "ToolLoopAgent chain lacks nearby eval or test evidence.", snippet, chain.id, chain.agentId);
    if (!chain.hasTrace) pushRisk("missing-trace", "high", file, line, "ToolLoopAgent chain lacks trace ID, structured logging, or telemetry evidence.", snippet, chain.id, chain.agentId);
  });
}

for (const route of records.routes) {
  if (route.aiPatterns.length && !route.hasTrace) {
    pushRisk(
      "route-without-trace",
      "high",
      path.join(root, route.file),
      route.line,
      `AI route ${route.file} exposes ${route.aiPatterns.join(", ")} without trace evidence.`,
      route.aiPatterns.join(", "),
      route.id,
      route.agentId,
    );
  }
}

function computeAgents() {
  const agents = [...agentMap.values()].map((agent) => {
    const counts = {
      prompts: records.prompts.filter((item) => item.agentId === agent.id).length,
      tools: records.tools.filter((item) => item.agentId === agent.id).length,
      chains: records.chains.filter((item) => item.agentId === agent.id).length,
      routes: records.routes.filter((item) => item.agentId === agent.id).length,
      uiEntrypoints: records.uiEntrypoints.filter((item) => item.agentId === agent.id).length,
      risks: records.risks.filter((item) => item.agentId === agent.id).length,
    };
    return {
      ...agent,
      files: [...agent.files].sort(),
      evidence: agent.evidence.slice(0, 12),
      counts,
      score: counts.chains * 5 + counts.routes * 4 + counts.uiEntrypoints * 3 + counts.tools * 2 + counts.prompts + counts.risks,
    };
  });
  return agents
    .filter((agent) => agent.score > 0)
    .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name));
}

function readTtyLine(prompt) {
  try {
    const fd = fs.openSync("/dev/tty", "r+");
    fs.writeSync(fd, prompt);
    const chunks = [];
    const buffer = Buffer.alloc(1);
    while (fs.readSync(fd, buffer, 0, 1, null) === 1) {
      const ch = buffer.toString("utf8");
      if (ch === "\n" || ch === "\r") break;
      chunks.push(ch);
    }
    fs.closeSync(fd);
    return chunks.join("").trim();
  } catch {
    return "";
  }
}

function parseAgentSelection(value, agents) {
  const tokens = clean(value).split(",").map(clean).filter(Boolean);
  if (!tokens.length) return { all: true, selected: [], missing: [] };
  if (tokens.some((token) => token === "0" || token === "*" || slug(token) === "all" || slug(token) === "all-agents")) {
    return { all: true, selected: [], missing: [] };
  }

  const selected = [];
  const seen = new Set();
  const missing = [];
  for (const token of tokens) {
    const asIndex = Number(token);
    const requested = slug(token);
    const found = Number.isInteger(asIndex) && asIndex >= 1 && asIndex <= agents.length
      ? agents[asIndex - 1]
      : agents.find((agent) => agent.id === token || slug(agent.id) === requested || slug(agent.name) === requested);
    if (!found) {
      missing.push(token);
      continue;
    }
    if (!seen.has(found.id)) {
      selected.push(found);
      seen.add(found.id);
    }
  }
  return { all: false, selected, missing };
}

function describeSelection(agents) {
  if (!agents || !agents.length) return "All detected agents";
  return agents.map((agent) => `${agent.name} (${agent.id})`).join(", ");
}

function chooseAgents(agents) {
  if (listAgentsOnly) {
    if (!agents.length) {
      console.log("No agent candidates detected.");
    } else {
      console.log("Detected agents:");
      agents.forEach((agent, index) => {
        console.log(`${index + 1}. ${agent.name} (${agent.id}) - chains:${agent.counts.chains} routes:${agent.counts.routes} tools:${agent.counts.tools} prompts:${agent.counts.prompts} risks:${agent.counts.risks}`);
      });
    }
    process.exit(0);
  }

  if (requestedAgent) {
    const selection = parseAgentSelection(requestedAgent, agents);
    if (selection.all) return null;
    if (selection.missing.length) {
      console.error(`Agent not found: ${selection.missing.join(", ")}`);
      if (agents.length) {
        console.error("Available agents:");
        agents.forEach((agent) => console.error(`- ${agent.name} (${agent.id})`));
      }
      process.exit(1);
    }
    return selection.selected;
  }

  if (agents.length > 1 && interactive) {
    console.log("Multiple agent candidates detected:");
    console.log("0. All agents");
    agents.forEach((agent, index) => {
      console.log(`${index + 1}. ${agent.name} (${agent.id}) - chains:${agent.counts.chains} routes:${agent.counts.routes} tools:${agent.counts.tools} prompts:${agent.counts.prompts} risks:${agent.counts.risks}`);
    });
    const answer = readTtyLine("Choose agents to analyze. Use comma-separated numbers, ids, names, or 0 for all [0]: ");
    if (!answer) return null;
    const selection = parseAgentSelection(answer, agents);
    if (selection.all) return null;
    if (!selection.missing.length && selection.selected.length) return selection.selected;
    console.log("Selection not recognized. Scanning all agents.");
  }

  return null;
}

function applyAgentFilter(selectedAgents) {
  records.agents = computeAgents();
  const allAgents = records.agents;
  const selectedList = selectedAgents || [];
  if (!selectedList.length) {
    return {
      selectedAgent: null,
      selectedAgents: [],
      label: "All detected agents",
      mode: records.agents.length > 1 ? "all-agents" : "single-or-none",
    };
  }

  const selectedIds = new Set(selectedList.map((agent) => agent.id));
  const selectedChains = records.chains.filter((item) => selectedIds.has(item.agentId));
  const selectedRoutes = records.routes.filter((item) => selectedIds.has(item.agentId));
  const selectedUi = records.uiEntrypoints.filter((item) => selectedIds.has(item.agentId));
  const selectedFiles = new Set([...selectedChains, ...selectedRoutes, ...selectedUi].map((item) => item.file));
  const selectedToolNames = new Set(selectedChains.flatMap((chain) => chain.tools || []));
  const selectedTargetIds = new Set([...selectedChains, ...selectedRoutes, ...selectedUi].map((item) => item.id));

  records.chains = selectedChains;
  records.routes = selectedRoutes;
  records.uiEntrypoints = selectedUi;
  records.prompts = records.prompts.filter((item) => selectedIds.has(item.agentId) || selectedFiles.has(item.file));
  records.tools = records.tools.filter((item) => selectedIds.has(item.agentId) || selectedFiles.has(item.file) || selectedToolNames.has(item.name));
  for (const item of [...records.prompts, ...records.tools]) selectedTargetIds.add(item.id);
  records.modelCalls = records.modelCalls.filter((item) => selectedIds.has(item.agentId));
  records.risks = records.risks.filter((item) => selectedIds.has(item.agentId) || selectedFiles.has(item.file) || selectedTargetIds.has(item.targetId));
  records.agents = allAgents.filter((agent) => selectedIds.has(agent.id));
  return {
    selectedAgent: records.agents.length === 1 ? records.agents[0] : null,
    selectedAgents: records.agents,
    label: describeSelection(records.agents),
    mode: records.agents.length === 1 ? "selected-agent" : "selected-agents",
  };
}

records.agents = computeAgents();
const selection = applyAgentFilter(chooseAgents(records.agents));

function rows(items, empty, render) {
  if (!items.length) return `- ${empty}\n`;
  return items.map(render).join("\n") + "\n";
}

function write(name, body) {
  fs.writeFileSync(path.join(outDir, name), body);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function summaryCards(summary) {
  return [
    ["Agents", summary.agents],
    ["Prompts", summary.prompts],
    ["Tools", summary.tools],
    ["Chains", summary.chains],
    ["Routes", summary.routes],
    ["UI Entries", summary.uiEntrypoints],
    ["Risks", summary.risks],
  ];
}

function renderList(items, empty, render) {
  if (!items.length) return `<p class="empty">${escapeHtml(empty)}</p>`;
  return `<div class="list">${items.map(render).join("")}</div>`;
}

function tracePayload(generatedAt) {
  return {
    generatedAt,
    root,
    scanner: "agent-observe-skill.sh",
    selection,
    summary: {
      agents: records.agents.length,
      prompts: records.prompts.length,
      tools: records.tools.length,
      chains: records.chains.length,
      routes: records.routes.length,
      uiEntrypoints: records.uiEntrypoints.length,
      risks: records.risks.length,
    },
    ...records,
  };
}

function renderSimpleHtmlReport(trace, report) {
  const json = JSON.stringify({ ...trace, markdownReport: report }).replace(/</g, "\\u003c");
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Agent Observe Report</title>
    <style>
      :root { color-scheme: light; --bg: #f7f8f5; --panel: #fff; --ink: #171a16; --muted: #637063; --line: #d7ddd2; --blue: #2f80ed; --red: #b4372f; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      * { box-sizing: border-box; }
      body { margin: 0; background: var(--bg); color: var(--ink); }
      main { width: min(1040px, calc(100vw - 32px)); margin: 0 auto; padding: 28px 0 40px; display: grid; gap: 22px; }
      header { display: flex; justify-content: space-between; gap: 18px; align-items: end; border-bottom: 1px solid var(--line); padding-bottom: 18px; }
      h1 { margin: 0; font-size: clamp(34px, 6vw, 64px); line-height: .96; letter-spacing: 0; }
      h2 { margin: 0 0 12px; font-size: 18px; letter-spacing: 0; }
      p { margin: 0; color: var(--muted); line-height: 1.45; }
      code { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
      section, .panel { border: 1px solid var(--line); border-radius: 8px; background: var(--panel); padding: 18px; box-shadow: 0 14px 40px rgba(35, 44, 30, .07); }
      .trust { max-width: 330px; border-left: 3px solid #1b7c55; padding-left: 12px; }
      .summary { display: grid; grid-template-columns: repeat(6, minmax(110px, 1fr)); gap: 10px; }
      .metric { border: 1px solid var(--line); border-radius: 7px; padding: 14px; background: #fbfcf9; text-align: center; }
      .metric strong { display: block; font-size: 28px; }
      .metric span { color: var(--muted); font-size: 12px; }
      .agents { display: flex; flex-wrap: wrap; gap: 12px; justify-content: center; }
      .agent-button { min-width: 150px; border: 2px solid #1f271d; border-radius: 8px; background: #fff; color: var(--ink); padding: 16px 18px; cursor: pointer; font: inherit; font-weight: 760; }
      .agent-button.active { border-color: var(--blue); color: var(--blue); box-shadow: inset 0 0 0 1px var(--blue); }
      .workspace { display: grid; grid-template-columns: minmax(260px, .95fr) minmax(300px, 1.05fr); gap: 28px; align-items: start; }
      .agent-title { color: var(--blue); text-align: center; font-size: 30px; margin: 0 0 22px; }
      .evidence-list { display: grid; gap: 12px; }
      .evidence-button { width: 100%; border: 2px solid #1f271d; border-radius: 7px; background: #fff; color: var(--ink); padding: 18px; text-align: center; cursor: pointer; font: inherit; font-weight: 760; }
      .evidence-button.active { border-color: var(--blue); color: var(--blue); }
      .evidence-button small { display: block; margin-top: 4px; color: var(--muted); font-weight: 500; }
      .detail-title { text-align: center; margin-bottom: 12px; font-weight: 760; }
      .detail-box { min-height: 260px; border: 2px solid var(--blue); border-radius: 7px; background: #fff; padding: 18px; display: grid; gap: 12px; align-content: start; }
      .row { border-top: 1px solid var(--line); padding-top: 10px; }
      .row:first-child { border-top: 0; padding-top: 0; }
      .row span { display: block; color: var(--muted); font-size: 11px; letter-spacing: .08em; text-transform: uppercase; }
      .row strong { display: block; margin-top: 5px; }
      .row code { display: block; margin-top: 6px; color: var(--muted); font-size: 12px; overflow-wrap: anywhere; }
      .empty { color: var(--muted); background: #f1f4ef; border-radius: 7px; padding: 12px; }
      @media (max-width: 860px) { header, .workspace { grid-template-columns: 1fr; display: grid; } .summary { grid-template-columns: repeat(2, minmax(0, 1fr)); } .trust { max-width: none; } }
    </style>
  </head>
  <body>
    <main>
      <header>
        <div>
          <h1>Agent Observe Report</h1>
          <p>Initial scan scope: <strong>${escapeHtml(trace.selection.label || "All detected agents")}</strong></p>
        </div>
        <p class="trust">Your code stayed local. Generated from static analysis at <code>${escapeHtml(trace.generatedAt)}</code>.</p>
      </header>

      <section>
        <h2>Overall</h2>
        <div class="summary" id="summary"></div>
      </section>

      <section>
        <h2>Agents</h2>
        <div class="agents" id="agents"></div>
      </section>

      <section class="workspace">
        <div>
          <h2 class="agent-title" id="agent-title">Agent</h2>
          <div class="evidence-list" id="evidence-list"></div>
        </div>
        <div>
          <div class="detail-title" id="detail-title">Details</div>
          <div class="detail-box" id="detail-box"></div>
        </div>
      </section>
    </main>
    <script>
      const trace = ${json};
      const state = { agentId: (trace.agents || [])[0]?.id || "", kind: "tools" };
      const kinds = [
        ["tools", "Tool calls"],
        ["prompts", "Prompts"],
        ["chains", "Model calls"],
        ["routes", "Routes"],
        ["risks", "Risks"],
      ];
      const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
      const byAgent = (items) => (items || []).filter((item) => item.agentId === state.agentId);
      const currentAgent = () => (trace.agents || []).find((agent) => agent.id === state.agentId) || null;
      function rows(kind) {
        if (kind === "tools") return byAgent(trace.tools).map((tool) => ({ meta: tool.sideEffect ? "side-effect tool" : "tool", title: tool.name, code: tool.schema + " · " + tool.file + ":" + tool.line }));
        if (kind === "prompts") return byAgent(trace.prompts).map((prompt) => ({ meta: prompt.kind, title: prompt.preview, code: prompt.file + ":" + prompt.line }));
        if (kind === "chains") return byAgent(trace.chains).map((chain) => ({ meta: chain.type, title: chain.model, code: chain.file + ":" + chain.line + " · tools: " + ((chain.tools || []).join(", ") || "none") }));
        if (kind === "routes") return [...byAgent(trace.routes).map((route) => ({ meta: route.kind, title: route.file, code: "methods: " + ((route.methods || []).join(", ") || "unknown") + " · AI: " + ((route.aiPatterns || []).join(", ") || "none") })), ...byAgent(trace.uiEntrypoints).map((entry) => ({ meta: "UI entry", title: entry.hook, code: entry.file + ":" + entry.line + " · API: " + entry.api }))];
        return byAgent(trace.risks).map((risk) => ({ meta: risk.severity + " / " + risk.kind, title: risk.message, code: risk.file + ":" + risk.line }));
      }
      function count(kind) {
        if (kind === "routes") return byAgent(trace.routes).length + byAgent(trace.uiEntrypoints).length;
        return rows(kind).length;
      }
      function render() {
        const agent = currentAgent();
        const summary = [
          ["Agents", trace.summary?.agents || 0],
          ["Prompts", trace.summary?.prompts || 0],
          ["Tool calls", trace.summary?.tools || 0],
          ["Model calls", trace.summary?.chains || 0],
          ["Routes", (trace.summary?.routes || 0) + (trace.summary?.uiEntrypoints || 0)],
          ["Risks", trace.summary?.risks || 0],
        ];
        document.querySelector("#summary").innerHTML = summary.map(([label, value]) => '<div class="metric"><strong>' + escapeHtml(value) + '</strong><span>' + escapeHtml(label) + '</span></div>').join("");
        document.querySelector("#agents").innerHTML = (trace.agents || []).map((item) => '<button type="button" class="agent-button ' + (item.id === state.agentId ? "active" : "") + '" data-agent="' + escapeHtml(item.id) + '">' + escapeHtml(item.name) + '</button>').join("") || '<p class="empty">No agent candidates detected.</p>';
        document.querySelectorAll("[data-agent]").forEach((button) => button.addEventListener("click", () => { state.agentId = button.dataset.agent; render(); }));
        document.querySelector("#agent-title").textContent = agent ? agent.name : "No agent selected";
        document.querySelector("#evidence-list").innerHTML = kinds.map(([kind, label]) => '<button type="button" class="evidence-button ' + (kind === state.kind ? "active" : "") + '" data-kind="' + kind + '">' + label + '<small>' + count(kind) + ' detected</small></button>').join("");
        document.querySelectorAll("[data-kind]").forEach((button) => button.addEventListener("click", () => { state.kind = button.dataset.kind; render(); }));
        const label = kinds.find(([kind]) => kind === state.kind)?.[1] || "Details";
        document.querySelector("#detail-title").textContent = label + " info";
        const detailRows = rows(state.kind);
        document.querySelector("#detail-box").innerHTML = detailRows.map((row) => '<div class="row"><span>' + escapeHtml(row.meta) + '</span><strong>' + escapeHtml(row.title) + '</strong><code>' + escapeHtml(row.code) + '</code></div>').join("") || '<p class="empty">No ' + escapeHtml(label.toLowerCase()) + ' detected for this agent.</p>';
      }
      render();
    </script>
  </body>
</html>
`;
}

function renderSimpleNextPage(trace) {
  const data = {
    generatedAt: trace.generatedAt,
    selected: trace.selection.label || "All detected agents",
    summary: trace.summary,
    agents: trace.agents,
    prompts: trace.prompts,
    tools: trace.tools,
    chains: trace.chains,
    routes: trace.routes,
    uiEntrypoints: trace.uiEntrypoints,
    risks: trace.risks,
  };
  return `"use client";

/* Generated by agent-observe-skill. Re-run skill.sh to refresh. */
import { useMemo, useState } from "react";

const data = ${JSON.stringify(data, null, 2)} as any;

const colors = { bg: "#f7f8f5", panel: "#fff", ink: "#171a16", muted: "#637063", line: "#d7ddd2", blue: "#2f80ed" };
const kinds = [["tools", "Tool calls"], ["prompts", "Prompts"], ["chains", "Model calls"], ["routes", "Routes"], ["risks", "Risks"]] as const;

function Metric({ label, value }: { label: string; value: number }) {
  return <div style={{ border: "1px solid " + colors.line, borderRadius: 7, padding: 14, background: "#fbfcf9", textAlign: "center" }}><strong style={{ display: "block", fontSize: 28 }}>{value}</strong><span style={{ color: colors.muted, fontSize: 12 }}>{label}</span></div>;
}

export default function AgentObserveSkillPage() {
  const [agentId, setAgentId] = useState<string>(data.agents[0]?.id || "");
  const [kind, setKind] = useState<string>("tools");
  const agent = data.agents.find((item: any) => item.id === agentId);
  const byAgent = (items: any[]) => (items || []).filter((item: any) => item.agentId === agentId);
  const rows = useMemo(() => {
    if (kind === "tools") return byAgent(data.tools).map((tool: any) => ({ meta: tool.sideEffect ? "side-effect tool" : "tool", title: tool.name, code: tool.schema + " · " + tool.file + ":" + tool.line }));
    if (kind === "prompts") return byAgent(data.prompts).map((prompt: any) => ({ meta: prompt.kind, title: prompt.preview, code: prompt.file + ":" + prompt.line }));
    if (kind === "chains") return byAgent(data.chains).map((chain: any) => ({ meta: chain.type, title: chain.model, code: chain.file + ":" + chain.line + " · tools: " + ((chain.tools || []).join(", ") || "none") }));
    if (kind === "routes") return [...byAgent(data.routes).map((route: any) => ({ meta: route.kind, title: route.file, code: "methods: " + ((route.methods || []).join(", ") || "unknown") + " · AI: " + ((route.aiPatterns || []).join(", ") || "none") })), ...byAgent(data.uiEntrypoints).map((entry: any) => ({ meta: "UI entry", title: entry.hook, code: entry.file + ":" + entry.line + " · API: " + entry.api }))];
    return byAgent(data.risks).map((risk: any) => ({ meta: risk.severity + " / " + risk.kind, title: risk.message, code: risk.file + ":" + risk.line }));
  }, [agentId, kind]);
  const count = (item: string) => item === "routes" ? byAgent(data.routes).length + byAgent(data.uiEntrypoints).length : (item === "tools" ? byAgent(data.tools).length : item === "prompts" ? byAgent(data.prompts).length : item === "chains" ? byAgent(data.chains).length : byAgent(data.risks).length);
  const activeLabel = kinds.find(([item]) => item === kind)?.[1] || "Details";
  const summary = [["Agents", data.summary.agents], ["Prompts", data.summary.prompts], ["Tool calls", data.summary.tools], ["Model calls", data.summary.chains], ["Routes", data.summary.routes + data.summary.uiEntrypoints], ["Risks", data.summary.risks]] as const;
  return (
    <main style={{ minHeight: "100vh", background: colors.bg, color: colors.ink, padding: 28 }}>
      <div style={{ maxWidth: 1040, margin: "0 auto", display: "grid", gap: 22 }}>
        <header style={{ display: "flex", justifyContent: "space-between", gap: 18, alignItems: "end", borderBottom: "1px solid " + colors.line, paddingBottom: 18 }}>
          <div><h1 style={{ margin: 0, fontSize: "clamp(34px, 6vw, 64px)", lineHeight: .96 }}>Agent Observe Report</h1><p style={{ margin: "8px 0 0", color: colors.muted }}>Initial scan scope: <strong>{data.selected}</strong></p></div>
          <p style={{ maxWidth: 330, margin: 0, color: colors.muted, borderLeft: "3px solid #1b7c55", paddingLeft: 12 }}>Your code stayed local. Generated at <code>{data.generatedAt}</code>.</p>
        </header>
        <section style={{ border: "1px solid " + colors.line, borderRadius: 8, background: colors.panel, padding: 18 }}>
          <h2 style={{ margin: "0 0 12px" }}>Overall</h2>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(110px, 1fr))", gap: 10 }}>{summary.map(([label, value]) => <Metric key={label} label={label} value={value} />)}</div>
        </section>
        <section style={{ border: "1px solid " + colors.line, borderRadius: 8, background: colors.panel, padding: 18 }}>
          <h2 style={{ margin: "0 0 12px" }}>Agents</h2>
          <div style={{ display: "flex", flexWrap: "wrap", gap: 12, justifyContent: "center" }}>{data.agents.map((item: any) => <button key={item.id} type="button" onClick={() => setAgentId(item.id)} style={{ minWidth: 150, border: "2px solid " + (item.id === agentId ? colors.blue : "#1f271d"), borderRadius: 8, background: "#fff", color: item.id === agentId ? colors.blue : colors.ink, padding: "16px 18px", cursor: "pointer", font: "inherit", fontWeight: 760 }}>{item.name}</button>)}</div>
        </section>
        <section style={{ border: "1px solid " + colors.line, borderRadius: 8, background: colors.panel, padding: 18, display: "grid", gridTemplateColumns: "minmax(260px, .95fr) minmax(300px, 1.05fr)", gap: 28 }}>
          <div><h2 style={{ color: colors.blue, textAlign: "center", fontSize: 30, margin: "0 0 22px" }}>{agent?.name || "No agent selected"}</h2><div style={{ display: "grid", gap: 12 }}>{kinds.map(([item, label]) => <button key={item} type="button" onClick={() => setKind(item)} style={{ width: "100%", border: "2px solid " + (item === kind ? colors.blue : "#1f271d"), borderRadius: 7, background: "#fff", color: item === kind ? colors.blue : colors.ink, padding: 18, cursor: "pointer", font: "inherit", fontWeight: 760 }}>{label}<small style={{ display: "block", marginTop: 4, color: colors.muted, fontWeight: 500 }}>{count(item)} detected</small></button>)}</div></div>
          <div><div style={{ textAlign: "center", marginBottom: 12, fontWeight: 760 }}>{activeLabel} info</div><div style={{ minHeight: 260, border: "2px solid " + colors.blue, borderRadius: 7, background: "#fff", padding: 18, display: "grid", gap: 12, alignContent: "start" }}>{rows.length ? rows.map((row: any, index: number) => <div key={index} style={{ borderTop: index ? "1px solid " + colors.line : 0, paddingTop: index ? 10 : 0 }}><span style={{ display: "block", color: colors.muted, fontSize: 11, letterSpacing: ".08em", textTransform: "uppercase" }}>{row.meta}</span><strong style={{ display: "block", marginTop: 5 }}>{row.title}</strong><code style={{ display: "block", marginTop: 6, color: colors.muted, fontSize: 12, overflowWrap: "anywhere" }}>{row.code}</code></div>) : <p style={{ color: colors.muted }}>No {activeLabel.toLowerCase()} detected for this agent.</p>}</div></div>
        </section>
      </div>
    </main>
  );
}
`;
}

function gitRelative(filePath) {
  return path.relative(root, filePath).split(path.sep).join("/");
}

function gitPath(args) {
  try {
    const value = childProcess.execFileSync("git", ["-C", root, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    if (!value) return "";
    return path.isAbsolute(value) ? value : path.join(root, value);
  } catch {
    return "";
  }
}

function isGitTracked(relativePath) {
  try {
    childProcess.execFileSync("git", ["-C", root, "ls-files", "--error-unmatch", "--", relativePath], {
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

function addLocalGitExcludes(patterns) {
  const excludePath = gitPath(["rev-parse", "--git-path", "info/exclude"]);
  if (!excludePath) return "";
  fs.mkdirSync(path.dirname(excludePath), { recursive: true });
  const existing = fs.existsSync(excludePath) ? fs.readFileSync(excludePath, "utf8") : "";
  const lines = new Set(existing.split(/\r?\n/).map((line) => line.trim()).filter(Boolean));
  const missing = patterns.filter((pattern) => !lines.has(pattern));
  if (!missing.length) return excludePath;
  const prefix = existing.endsWith("\n") || existing.length === 0 ? "" : "\n";
  const header = lines.has("# Agent Observe generated artifacts") ? "" : "# Agent Observe generated artifacts\n";
  fs.appendFileSync(excludePath, `${prefix}${header}${missing.join("\n")}\n`);
  return excludePath;
}

function maybeWriteNextPage(trace) {
  const appDir = path.join(root, "app");
  if (!fs.existsSync(appDir) || !fs.statSync(appDir).isDirectory()) return "";
  const routeDir = path.join(appDir, "agent-observe-skill");
  const pagePath = path.join(routeDir, "page.tsx");
  if (isGitTracked(gitRelative(pagePath))) return "";
  if (fs.existsSync(pagePath)) {
    const existing = fs.readFileSync(pagePath, "utf8");
    if (!existing.includes("Generated by agent-observe-skill")) return "";
  }
  fs.mkdirSync(routeDir, { recursive: true });
  fs.writeFileSync(pagePath, renderSimpleNextPage(trace));
  return pagePath;
}

const generatedAt = new Date().toISOString();
const header = (title) => `# ${title}\n\nGenerated ${generatedAt} from \`${root}\`.\n\n`;

write(
  "prompts.md",
  header("Prompts") +
    rows(records.prompts, "No system, prompt, messages, or named prompt constants detected.", (p) =>
      `- \`${p.file}:${p.line}\` ${p.kind}${p.name ? ` \`${p.name}\`` : ""} (${p.valueType}): ${p.preview}`,
    ),
);

write(
  "tools.md",
  header("Tools") +
    rows(records.tools, "No Vercel AI SDK tool(...) definitions detected.", (t) =>
      [
        `- \`${t.file}:${t.line}\` \`${t.name}\``,
        `  - Schema: ${t.schema}`,
        `  - Execute handler: ${t.hasExecute ? "yes" : "no"}`,
        `  - Side effects: ${t.sideEffect ? "yes" : "no"}`,
        `  - Description: ${t.description}`,
      ].join("\n"),
    ),
);

write(
  "chains.md",
  header("Chains And Model Calls") +
    rows(records.chains, "No streamText, generateText, streamObject, generateObject, or ToolLoopAgent usage detected.", (c) =>
      [
        `- \`${c.file}:${c.line}\` ${c.type}`,
        `  - Model: ${c.model}`,
        `  - Prompts: ${c.prompts.length ? c.prompts.join("; ") : "No prompt property detected in call"}`,
        `  - Tools: ${c.tools.length ? c.tools.join(", ") : "No direct tools object detected"}`,
        `  - Eval coverage evidence: ${c.hasEval ? "yes" : "no"}`,
        `  - Trace/logging evidence: ${c.hasTrace ? "yes" : "no"}`,
      ].join("\n"),
    ),
);

write(
  "routes.md",
  header("Routes And UI Entrypoints") +
    "## API Routes\n\n" +
    rows(records.routes, "No app/api/** route or pages/api/** files detected.", (r) =>
      `- \`${r.file}\` (${r.kind}) methods: ${r.methods.length ? r.methods.join(", ") : "not detected"}; AI patterns: ${
        r.aiPatterns.length ? r.aiPatterns.join(", ") : "none"
      }`,
    ) +
    "\n## Client Entrypoints\n\n" +
    rows(records.uiEntrypoints, "No useChat, useCompletion, or useAssistant calls detected.", (u) =>
      `- \`${u.file}:${u.line}\` ${u.hook}; API: ${u.api}`,
    ),
);

write(
  "risks.md",
  header("Risks") +
    rows(records.risks, "No obvious observability risks detected by this static scan.", (r) =>
      `- [${r.severity}] \`${r.file}:${r.line}\` ${r.message} Evidence: ${r.evidence}`,
    ),
);

const report = `${header("Agent Observe Report")}## Summary

- Agent selection: ${selection.label}
- Agent candidates detected: ${records.agents.length}
- Prompts detected: ${records.prompts.length}
- Tools detected: ${records.tools.length}
- Chains/model calls detected: ${records.chains.length}
- API routes detected: ${records.routes.length}
- UI entrypoints detected: ${records.uiEntrypoints.length}
- Risks detected: ${records.risks.length}

## Agent Candidates

${rows(records.agents, "No agent candidates detected.", (agent) => `- ${agent.name} (${agent.id}) files: ${agent.files.join(", ") || "none"}.`)}
## Where are prompts defined?

${rows(records.prompts, "No prompt definitions detected.", (p) => `- \`${p.file}:${p.line}\` ${p.kind} (${p.valueType}): ${p.preview}`)}
## Which model calls use which prompts?

${rows(records.chains, "No model calls detected.", (c) => `- \`${c.file}:${c.line}\` ${c.type} uses ${c.prompts.length ? c.prompts.join("; ") : "no directly detected prompt property"}.`)}
## Which tools can each chain call?

${rows(records.chains, "No chains detected.", (c) => `- \`${c.file}:${c.line}\` ${c.type}: ${c.tools.length ? c.tools.join(", ") : "no direct tools object detected"}.`)}
## What schemas do tools expose?

${rows(records.tools, "No tools detected.", (t) => `- \`${t.name}\` at \`${t.file}:${t.line}\`: ${t.schema}.`)}
## Which tools have side effects?

${rows(records.tools.filter((t) => t.sideEffect), "No side-effecting tools detected.", (t) => `- \`${t.name}\` at \`${t.file}:${t.line}\`.`)}
## Which routes expose AI behavior?

${rows(records.routes.filter((r) => r.aiPatterns.length), "No AI route exposure detected.", (r) => `- \`${r.file}\`: ${r.aiPatterns.join(", ")}.`)}
## Which chains lack evals?

${rows(records.chains.filter((c) => !c.hasEval), "No chains missing eval evidence.", (c) => `- \`${c.file}:${c.line}\` ${c.type}.`)}
## Which chains lack trace IDs or logging?

${rows(records.chains.filter((c) => !c.hasTrace), "No chains missing trace/logging evidence.", (c) => `- \`${c.file}:${c.line}\` ${c.type}.`)}
## Which prompts are inline and hard to audit?

${rows(records.prompts.filter((p) => p.inline), "No inline prompts detected.", (p) => `- \`${p.file}:${p.line}\` ${p.kind}: ${p.preview}`)}
`;

write("report.md", report);
const trace = tracePayload(generatedAt);
write("index.html", renderSimpleHtmlReport(trace, report));
write(
  "trace-map.json",
  JSON.stringify(trace, null, 2) + "\n",
);
const nextPagePath = maybeWriteNextPage(trace);
const excludePatterns = [".agent-observe-skill/"];
if (nextPagePath) excludePatterns.push("app/agent-observe-skill/");
const excludePath = addLocalGitExcludes(excludePatterns);

console.log(`Agent Observe report written to ${outDir}`);
console.log(`Open ${path.join(outDir, "report.md")}`);
console.log(`Open ${path.join(outDir, "index.html")} for the visual report`);
if (nextPagePath) console.log(`Next.js page written to ${nextPagePath}`);
if (excludePath) console.log(`Generated artifacts are locally ignored via ${excludePath}`);
NODE
  exit $?
fi

REPORT="$OUT_DIR/report.md"
PROMPTS="$OUT_DIR/prompts.md"
TOOLS="$OUT_DIR/tools.md"
CHAINS="$OUT_DIR/chains.md"
ROUTES="$OUT_DIR/routes.md"
RISKS="$OUT_DIR/risks.md"
TRACE="$OUT_DIR/trace-map.json"
INDEX="$OUT_DIR/index.html"

if [ "$LIST_AGENTS" = "1" ]; then
  say "Detected agent candidates:"
  find "$ROOT" \
    \( -name .git -o -name node_modules -o -name .next -o -name dist -o -name build -o -name coverage -o -name .agent-observe-skill \) -prune \
    -o \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.mdx" \) -type f -print |
  while IFS= read -r file; do
    rel_file="${file#$ROOT/}"
    if grep -Eq '\b(streamText|generateText|streamObject|generateObject|ToolLoopAgent|useChat|useCompletion|useAssistant)\b' "$file" ||
      printf '%s\n' "$rel_file" | grep -Eq '^(app/api/.*/route|pages/api/).*\.[cm]?[jt]sx?$'; then
      printf -- '- %s\n' "$rel_file"
    fi
  done
  exit 0
fi

say "# Agent Observe Report" > "$REPORT"
say "" >> "$REPORT"
say "Generated locally from \`$ROOT\`." >> "$REPORT"
say "" >> "$REPORT"
say "Node was not available, so this Bash fallback used grep-based detection." >> "$REPORT"
if [ -n "$AGENT_FILTER" ]; then
  say "Agent filter requested: \`$AGENT_FILTER\`. Bash fallback applies this as a path/name substring filter." >> "$REPORT"
fi
say "" >> "$REPORT"

say "# Prompts" > "$PROMPTS"
say "# Tools" > "$TOOLS"
say "# Chains And Model Calls" > "$CHAINS"
say "# Routes And UI Entrypoints" > "$ROUTES"
say "# Risks" > "$RISKS"

prompt_count=0
tool_count=0
chain_count=0
route_count=0
risk_count=0

find "$ROOT" \
  \( -name .git -o -name node_modules -o -name .next -o -name dist -o -name build -o -name coverage -o -name .agent-observe-skill \) -prune \
  -o \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.mdx" \) -type f -print |
while IFS= read -r file; do
  [ "$(cd "$(dirname "$file")" 2>/dev/null && pwd)/$(basename "$file")" = "$SELF_PATH" ] && continue
  rel_file="${file#$ROOT/}"
  if [ -n "$AGENT_FILTER" ] && ! printf '%s\n' "$rel_file" | grep -Eiq "$(printf '%s' "$AGENT_FILTER" | sed 's/[][\.^$*+?{}|()]/\\&/g')"; then
    continue
  fi

  if printf '%s\n' "$rel_file" | grep -Eq '^(app/api/.*/route|pages/api/).*\.[cm]?[jt]sx?$'; then
    route_count=$((route_count + 1))
    printf -- '- `%s` route file\n' "$rel_file" >> "$ROUTES"
  fi

  if grep -Eq '\b(useChat|useCompletion|useAssistant)\s*\(' "$file"; then
    printf -- '- `%s` client chat entrypoint\n' "$rel_file" >> "$ROUTES"
  fi

  if grep -Eq '\b(system|prompt|messages)\s*:' "$file"; then
    prompt_count=$((prompt_count + 1))
    grep -nE '\b(system|prompt|messages)\s*:' "$file" | head -20 |
      sed "s#^#- \`$rel_file:#; s#:#\` #" >> "$PROMPTS"
  fi

  if grep -Eq '\btool\s*\(' "$file"; then
    tool_count=$((tool_count + 1))
    grep -nE '\btool\s*\(' "$file" | head -20 |
      sed "s#^#- \`$rel_file:#; s#:#\` tool(...) #" >> "$TOOLS"
    if grep -Eq '\b(execute|fetch|prisma|db\.|insert|update|delete|writeFile|send|email|stripe|POST|PUT|PATCH|DELETE)\b' "$file"; then
      risk_count=$((risk_count + 1))
      printf -- '- [high] `%s` contains tool-like side-effect evidence. Review execute handlers.\n' "$rel_file" >> "$RISKS"
    fi
  fi

  if grep -Eq '\b(streamText|generateText|streamObject|generateObject|ToolLoopAgent)\b' "$file"; then
    chain_count=$((chain_count + 1))
    grep -nE '\b(streamText|generateText|streamObject|generateObject|ToolLoopAgent)\b' "$file" | head -20 |
      sed "s#^#- \`$rel_file:#; s#:#\` #" >> "$CHAINS"
    if ! grep -Eqi '\b(eval|evaluate|test|expect|assert|judge|grade)\b' "$file"; then
      risk_count=$((risk_count + 1))
      printf -- '- [medium] `%s` contains AI chain evidence without nearby eval/test terms.\n' "$rel_file" >> "$RISKS"
    fi
    if ! grep -Eqi '\b(traceId|trace_id|telemetry|experimental_telemetry|logger|console\.|span|otel|sentry)\b' "$file"; then
      risk_count=$((risk_count + 1))
      printf -- '- [high] `%s` contains AI chain evidence without trace/logging terms.\n' "$rel_file" >> "$RISKS"
    fi
  fi
done

{
  say "## Where are prompts defined?"
  cat "$PROMPTS"
  say ""
  say "## Which model calls use which prompts?"
  cat "$CHAINS"
  say ""
  say "## Which tools can each chain call?"
  cat "$TOOLS"
  say ""
  say "## What schemas do tools expose?"
  say "See tools.md for grep-detected tool definitions. Install Node for schema summaries."
  say ""
  say "## Which tools have side effects?"
  cat "$RISKS"
  say ""
  say "## Which routes expose AI behavior?"
  cat "$ROUTES"
  say ""
  say "## Which chains lack evals?"
  cat "$RISKS"
  say ""
  say "## Which chains lack trace IDs or logging?"
  cat "$RISKS"
  say ""
  say "## Which prompts are inline and hard to audit?"
  cat "$PROMPTS"
} >> "$REPORT"

cat > "$TRACE" <<JSON
{
  "scanner": "agent-observe-skill.sh",
  "mode": "bash-fallback",
  "root": "$(printf '%s' "$ROOT" | sed 's/"/\\"/g')",
  "note": "Install Node for rich trace-map records."
}
JSON

cat > "$INDEX" <<HTML
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Agent Observe Report</title>
    <style>
      body { margin: 0; padding: 28px; background: #f6f7f3; color: #171a16; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      main { display: grid; gap: 18px; }
      section { border: 1px solid #d7ddd2; border-radius: 8px; background: #fff; padding: 18px; }
      h1 { margin: 0; font-size: clamp(34px, 6vw, 72px); line-height: .95; }
      pre { margin: 0; white-space: pre-wrap; overflow-x: auto; color: #edf3ea; background: #101410; border-radius: 8px; padding: 16px; }
    </style>
  </head>
  <body>
    <main>
      <h1>Agent Observe Report</h1>
      <section>
        <p>Node was not available, so this visual report uses the Bash fallback output.</p>
        <p>Open <code>report.md</code>, <code>prompts.md</code>, <code>tools.md</code>, <code>chains.md</code>, <code>routes.md</code>, and <code>risks.md</code> for details.</p>
      </section>
      <section>
        <h2>Generated Report</h2>
        <pre>$(sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' "$REPORT")</pre>
      </section>
    </main>
  </body>
</html>
HTML

add_local_git_exclude ".agent-observe-skill/"

say "Agent Observe report written to $OUT_DIR"
say "Open $REPORT"
say "Open $INDEX for the visual report"
[ -n "$GIT_EXCLUDE" ] && say "Generated artifacts are locally ignored via $GIT_EXCLUDE"
