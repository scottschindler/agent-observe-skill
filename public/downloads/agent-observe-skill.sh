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
Usage: bash skill.sh [repo-path] [--agent <agent-name-or-id>] [--list-agents]

Options:
  --agent <value>   Scan one detected agent. Accepts the shown agent id or name.
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

function chooseAgent(agents) {
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
    const requested = slug(requestedAgent);
    const found = agents.find((agent) => agent.id === requestedAgent || slug(agent.id) === requested || slug(agent.name) === requested);
    if (!found) {
      console.error(`Agent not found: ${requestedAgent}`);
      if (agents.length) {
        console.error("Available agents:");
        agents.forEach((agent) => console.error(`- ${agent.name} (${agent.id})`));
      }
      process.exit(1);
    }
    return found;
  }

  if (agents.length > 1 && interactive) {
    console.log("Multiple agent candidates detected:");
    console.log("0. All agents");
    agents.forEach((agent, index) => {
      console.log(`${index + 1}. ${agent.name} (${agent.id}) - chains:${agent.counts.chains} routes:${agent.counts.routes} tools:${agent.counts.tools} prompts:${agent.counts.prompts} risks:${agent.counts.risks}`);
    });
    const answer = readTtyLine("Choose an agent to analyze [0]: ");
    if (!answer || answer === "0") return null;
    const index = Number(answer);
    if (Number.isInteger(index) && index >= 1 && index <= agents.length) return agents[index - 1];
    const requested = slug(answer);
    const found = agents.find((agent) => agent.id === answer || slug(agent.id) === requested || slug(agent.name) === requested);
    if (found) return found;
    console.log("Selection not recognized. Scanning all agents.");
  }

  return null;
}

function applyAgentFilter(agent) {
  records.agents = computeAgents();
  const selectedAgent = agent || null;
  if (!selectedAgent) return { selectedAgent: null, mode: records.agents.length > 1 ? "all-agents" : "single-or-none" };

  const selectedId = selectedAgent.id;
  const selectedChains = records.chains.filter((item) => item.agentId === selectedId);
  const selectedRoutes = records.routes.filter((item) => item.agentId === selectedId);
  const selectedUi = records.uiEntrypoints.filter((item) => item.agentId === selectedId);
  const selectedFiles = new Set([...selectedChains, ...selectedRoutes, ...selectedUi].map((item) => item.file));
  const selectedToolNames = new Set(selectedChains.flatMap((chain) => chain.tools || []));
  const selectedTargetIds = new Set([...selectedChains, ...selectedRoutes, ...selectedUi].map((item) => item.id));

  records.chains = selectedChains;
  records.routes = selectedRoutes;
  records.uiEntrypoints = selectedUi;
  records.prompts = records.prompts.filter((item) => item.agentId === selectedId || selectedFiles.has(item.file));
  records.tools = records.tools.filter((item) => item.agentId === selectedId || selectedFiles.has(item.file) || selectedToolNames.has(item.name));
  for (const item of [...records.prompts, ...records.tools]) selectedTargetIds.add(item.id);
  records.modelCalls = records.modelCalls.filter((item) => item.agentId === selectedId);
  records.risks = records.risks.filter((item) => item.agentId === selectedId || selectedFiles.has(item.file) || selectedTargetIds.has(item.targetId));
  records.agents = [selectedAgent];
  return { selectedAgent, mode: "selected-agent" };
}

records.agents = computeAgents();
const selection = applyAgentFilter(chooseAgent(records.agents));

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

function renderHtmlReport(trace, report) {
  const selected = trace.selection.selectedAgent
    ? `${trace.selection.selectedAgent.name} (${trace.selection.selectedAgent.id})`
    : "All detected agents";
  const topRisks = trace.risks.slice(0, 8);
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Agent Observe Report</title>
    <style>
      :root { color-scheme: light; --bg: #f6f7f3; --panel: #fff; --ink: #171a16; --muted: #5d675c; --line: #d7ddd2; --green: #1b7c55; --blue: #2359a6; --amber: #a96d11; --red: #b4372f; --violet: #6a4cad; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      * { box-sizing: border-box; }
      body { margin: 0; background: var(--bg); color: var(--ink); }
      main { display: grid; gap: 18px; padding: 28px; }
      header { display: flex; justify-content: space-between; gap: 18px; align-items: flex-end; border-bottom: 1px solid var(--line); padding-bottom: 18px; }
      h1 { margin: 0; max-width: 780px; font-size: clamp(34px, 6vw, 72px); line-height: .95; letter-spacing: 0; }
      h2 { margin: 0 0 10px; font-size: 18px; letter-spacing: 0; }
      p { margin: 0; color: var(--muted); line-height: 1.5; }
      code { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
      .trust { max-width: 320px; border-left: 3px solid var(--green); padding-left: 12px; }
      .grid { display: grid; grid-template-columns: repeat(7, minmax(120px, 1fr)); gap: 10px; }
      .card, section { border: 1px solid var(--line); border-radius: 8px; background: var(--panel); box-shadow: 0 14px 40px rgba(35, 44, 30, .08); }
      .card { padding: 14px; }
      .card strong { display: block; font-size: 28px; }
      .card span { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .08em; }
      .columns { display: grid; grid-template-columns: minmax(0, 1.2fr) minmax(320px, .8fr); gap: 18px; }
      section { padding: 18px; }
      .map { min-height: 420px; background: linear-gradient(90deg, rgba(23,26,22,.045) 1px, transparent 1px), linear-gradient(0deg, rgba(23,26,22,.045) 1px, transparent 1px), var(--panel); background-size: 34px 34px; }
      .nodes { display: grid; grid-template-columns: repeat(3, minmax(180px, 1fr)); gap: 12px; margin-top: 16px; }
      .node { border: 1px solid var(--line); border-left: 5px solid var(--blue); border-radius: 8px; background: rgba(255,255,255,.94); padding: 12px; }
      .node.tool { border-left-color: var(--green); }
      .node.chain { border-left-color: var(--violet); }
      .node.route { border-left-color: var(--amber); }
      .node.risk { border-left-color: var(--red); }
      .node .type, .item .meta { color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: .08em; }
      .node strong, .item strong { display: block; margin-top: 6px; }
      .node code, .item code { display: block; margin-top: 8px; color: var(--muted); overflow-wrap: anywhere; font-size: 12px; }
      .list { display: grid; gap: 10px; }
      .item { border-top: 1px solid var(--line); padding-top: 10px; }
      .empty { padding: 12px; background: #f0f3ee; border-radius: 8px; }
      pre { margin: 0; white-space: pre-wrap; overflow-x: auto; font-size: 12px; line-height: 1.5; color: #edf3ea; background: #101410; border-radius: 8px; padding: 16px; }
      @media (max-width: 1000px) { .grid, .columns, .nodes { grid-template-columns: 1fr; } header { display: grid; } }
    </style>
  </head>
  <body>
    <main>
      <header>
        <div>
          <h1>Agent Observe Report</h1>
          <p>Selected agent: <strong>${escapeHtml(selected)}</strong></p>
        </div>
        <p class="trust">Your code stayed local. This report was generated from static analysis at <code>${escapeHtml(trace.generatedAt)}</code>.</p>
      </header>
      <div class="grid">
        ${summaryCards(trace.summary).map(([label, value]) => `<div class="card"><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join("")}
      </div>
      <div class="columns">
        <section class="map">
          <h2>Chain Map</h2>
          <p>Detected routes, model calls, tools, prompts, and risks.</p>
          <div class="nodes">
            ${trace.routes.slice(0, 6).map((route) => `<div class="node route"><span class="type">Route</span><strong>${escapeHtml(route.file)}</strong><code>${escapeHtml((route.aiPatterns || []).join(", ") || "No AI pattern")}</code></div>`).join("")}
            ${trace.chains.slice(0, 6).map((chain) => `<div class="node chain"><span class="type">${escapeHtml(chain.type)}</span><strong>${escapeHtml(chain.model)}</strong><code>${escapeHtml(chain.file)}:${escapeHtml(chain.line)}</code></div>`).join("")}
            ${trace.tools.slice(0, 6).map((tool) => `<div class="node tool"><span class="type">Tool</span><strong>${escapeHtml(tool.name)}</strong><code>${escapeHtml(tool.schema)}</code></div>`).join("")}
            ${topRisks.map((risk) => `<div class="node risk"><span class="type">${escapeHtml(risk.severity)} risk</span><strong>${escapeHtml(risk.kind)}</strong><code>${escapeHtml(risk.file)}:${escapeHtml(risk.line)}</code></div>`).join("")}
          </div>
        </section>
        <section>
          <h2>Top Risks</h2>
          ${renderList(topRisks, "No risks detected.", (risk) => `<div class="item"><span class="meta">${escapeHtml(risk.severity)} / ${escapeHtml(risk.kind)}</span><strong>${escapeHtml(risk.message)}</strong><code>${escapeHtml(risk.file)}:${escapeHtml(risk.line)}</code></div>`)}
        </section>
      </div>
      <section>
        <h2>Agents</h2>
        ${renderList(trace.agents, "No agent candidates detected.", (agent) => `<div class="item"><span class="meta">${escapeHtml(agent.id)}</span><strong>${escapeHtml(agent.name)}</strong><code>${escapeHtml((agent.files || []).join(", "))}</code></div>`)}
      </section>
      <section>
        <h2>Generated Markdown Report</h2>
        <pre>${escapeHtml(report)}</pre>
      </section>
    </main>
  </body>
</html>
`;
}

function renderNextPage(trace) {
  const selected = trace.selection.selectedAgent
    ? `${trace.selection.selectedAgent.name} (${trace.selection.selectedAgent.id})`
    : "All detected agents";
  const data = {
    generatedAt: trace.generatedAt,
    selected,
    summary: trace.summary,
    agents: trace.agents.slice(0, 10),
    routes: trace.routes.slice(0, 8),
    chains: trace.chains.slice(0, 8),
    tools: trace.tools.slice(0, 8),
    risks: trace.risks.slice(0, 10),
  };
  return `/* Generated by agent-observe-skill. Re-run skill.sh to refresh. */
const data = ${JSON.stringify(data, null, 2)} as const;

const colors = {
  bg: "#f6f7f3",
  panel: "#ffffff",
  ink: "#171a16",
  muted: "#5d675c",
  line: "#d7ddd2",
  green: "#1b7c55",
  blue: "#2359a6",
  amber: "#a96d11",
  red: "#b4372f",
  violet: "#6a4cad",
};

function Card({ label, value }: { label: string; value: number }) {
  return (
    <div style={{ border: \`1px solid \${colors.line}\`, borderRadius: 8, background: colors.panel, padding: 14 }}>
      <span style={{ color: colors.muted, fontSize: 12, textTransform: "uppercase", letterSpacing: ".08em" }}>{label}</span>
      <strong style={{ display: "block", fontSize: 28 }}>{value}</strong>
    </div>
  );
}

function Node({ type, title, meta, color }: { type: string; title: string; meta: string; color: string }) {
  return (
    <div style={{ border: \`1px solid \${colors.line}\`, borderLeft: \`5px solid \${color}\`, borderRadius: 8, background: colors.panel, padding: 12 }}>
      <span style={{ color: colors.muted, fontSize: 11, textTransform: "uppercase", letterSpacing: ".08em" }}>{type}</span>
      <strong style={{ display: "block", marginTop: 6 }}>{title}</strong>
      <code style={{ display: "block", marginTop: 8, color: colors.muted, overflowWrap: "anywhere", fontSize: 12 }}>{meta}</code>
    </div>
  );
}

export default function AgentObserveSkillPage() {
  const cards = [
    ["Agents", data.summary.agents],
    ["Prompts", data.summary.prompts],
    ["Tools", data.summary.tools],
    ["Chains", data.summary.chains],
    ["Routes", data.summary.routes],
    ["UI Entries", data.summary.uiEntrypoints],
    ["Risks", data.summary.risks],
  ] as const;

  return (
    <main style={{ minHeight: "100vh", background: colors.bg, color: colors.ink, padding: 28, display: "grid", gap: 18 }}>
      <header style={{ display: "flex", justifyContent: "space-between", gap: 18, alignItems: "flex-end", borderBottom: \`1px solid \${colors.line}\`, paddingBottom: 18 }}>
        <div>
          <h1 style={{ margin: 0, maxWidth: 780, fontSize: "clamp(34px, 6vw, 72px)", lineHeight: ".95", letterSpacing: 0 }}>Agent Observe Report</h1>
          <p style={{ margin: "10px 0 0", color: colors.muted }}>Selected agent: <strong>{data.selected}</strong></p>
        </div>
        <p style={{ maxWidth: 340, margin: 0, color: colors.muted, borderLeft: \`3px solid \${colors.green}\`, paddingLeft: 12 }}>Generated locally at <code>{data.generatedAt}</code>.</p>
      </header>
      <section style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))", gap: 10 }}>
        {cards.map(([label, value]) => <Card key={label} label={label} value={value} />)}
      </section>
      <section style={{ border: \`1px solid \${colors.line}\`, borderRadius: 8, background: colors.panel, padding: 18 }}>
        <h2 style={{ margin: "0 0 10px" }}>Chain Map</h2>
        <p style={{ margin: "0 0 16px", color: colors.muted }}>Detected routes, model calls, tools, and risks.</p>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: 12 }}>
          {data.routes.map((route) => <Node key={route.id} type="Route" title={route.file} meta={(route.aiPatterns || []).join(", ") || "No AI pattern"} color={colors.amber} />)}
          {data.chains.map((chain) => <Node key={chain.id} type={chain.type} title={chain.model} meta={\`\${chain.file}:\${chain.line}\`} color={colors.violet} />)}
          {data.tools.map((tool) => <Node key={tool.id} type="Tool" title={tool.name} meta={tool.schema} color={colors.green} />)}
          {data.risks.map((risk) => <Node key={risk.id} type={\`\${risk.severity} risk\`} title={risk.kind} meta={\`\${risk.file}:\${risk.line}\`} color={colors.red} />)}
        </div>
      </section>
      <section style={{ border: \`1px solid \${colors.line}\`, borderRadius: 8, background: colors.panel, padding: 18 }}>
        <h2 style={{ margin: "0 0 10px" }}>Agents</h2>
        <div style={{ display: "grid", gap: 10 }}>
          {data.agents.length ? data.agents.map((agent) => (
            <div key={agent.id} style={{ borderTop: \`1px solid \${colors.line}\`, paddingTop: 10 }}>
              <span style={{ color: colors.muted, fontSize: 11, textTransform: "uppercase", letterSpacing: ".08em" }}>{agent.id}</span>
              <strong style={{ display: "block", marginTop: 6 }}>{agent.name}</strong>
              <code style={{ display: "block", marginTop: 8, color: colors.muted, overflowWrap: "anywhere", fontSize: 12 }}>{(agent.files || []).join(", ")}</code>
            </div>
          )) : <p style={{ color: colors.muted }}>No agent candidates detected.</p>}
        </div>
      </section>
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
  fs.writeFileSync(pagePath, renderNextPage(trace));
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

- Agent selection: ${selection.selectedAgent ? `${selection.selectedAgent.name} (${selection.selectedAgent.id})` : "All detected agents"}
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
write("index.html", renderHtmlReport(trace, report));
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
