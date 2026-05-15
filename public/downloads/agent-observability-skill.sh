#!/usr/bin/env bash
set -u

ROOT="${1:-$(pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)"
OUT_DIR="$ROOT/.agent-observability"
SELF_PATH="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"

mkdir -p "$OUT_DIR"

say() {
  printf '%s\n' "$*"
}

if command -v node >/dev/null 2>&1; then
  SKILL_SELF="$SELF_PATH" node - "$ROOT" "$OUT_DIR" <<'NODE'
const fs = require("fs");
const path = require("path");

const root = process.argv[2];
const outDir = process.argv[3];
const selfPath = path.resolve(process.env.SKILL_SELF || "");

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
  ".agent-observability",
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

function pushRisk(kind, severity, file, line, message, evidence, targetId = "") {
  const risk = {
    id: id("risk", file, line, `${kind}:${records.risks.length + 1}`),
    kind,
    severity,
    file: rel(file),
    line,
    message,
    evidence: preview(evidence, 220),
    targetId,
  };
  records.risks.push(risk);
  return risk;
}

const files = walk(root);

for (const file of files) {
  const text = read(file);
  const relative = rel(file);

  const isAppRoute = /^app\/api\/.*\/route\.[cm]?[jt]sx?$/.test(relative);
  const isPagesRoute = /^pages\/api\/.*\.[cm]?[jt]sx?$/.test(relative);
  if (isAppRoute || isPagesRoute) {
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
    });
  }

  eachMatch(text, /\b(useChat|useCompletion|useAssistant)\s*\(/g, (m) => {
    const snippet = extractBalancedCall(text, m.index);
    records.uiEntrypoints.push({
      id: id("ui", file, lineOf(text, m.index), m[1]),
      file: relative,
      line: lineOf(text, m.index),
      hook: m[1],
      api: preview(extractProperty(snippet, "api") || "Default or indirect API route", 100),
      evidence: preview(snippet, 220),
    });
  });

  eachMatch(text, /\b(system|prompt|messages)\s*:\s*(`(?:\\.|[^`])*`|"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|\[[\s\S]{0,700}?\]|[A-Za-z_$][\w$.[\]]*)/g, (m) => {
    const value = m[2] || "";
    const inline = /^[`"']/.test(value) || (m[1] === "messages" && value.trim().startsWith("["));
    const prompt = {
      id: id("prompt", file, lineOf(text, m.index), `${m[1]}:${records.prompts.length + 1}`),
      file: relative,
      line: lineOf(text, m.index),
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
      );
    }
  });

  eachMatch(text, /(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*(?:Prompt|System|Messages|Instruction|Instructions)[A-Za-z_$\w]*)\s*=\s*(`(?:\\.|[^`])*`|"(?:\\.|[^"])*"|'(?:\\.|[^'])*')/gi, (m) => {
    records.prompts.push({
      id: id("prompt", file, lineOf(text, m.index), m[1]),
      file: relative,
      line: lineOf(text, m.index),
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
      pushRisk("missing-eval", "medium", file, line, `${m[1]} chain lacks nearby eval or test evidence.`, snippet, chain.id);
    }
    if (!chain.hasTrace) {
      pushRisk("missing-trace", "high", file, line, `${m[1]} chain lacks trace ID, structured logging, or AI SDK telemetry evidence.`, snippet, chain.id);
    }
  });

  eachMatch(text, /\bToolLoopAgent\b/g, (m) => {
    const line = lineOf(text, m.index);
    const snippet = text.slice(Math.max(0, m.index - 220), Math.min(text.length, m.index + 700));
    const chain = {
      id: id("chain", file, line, "ToolLoopAgent"),
      file: relative,
      line,
      type: "ToolLoopAgent",
      model: "Agent loop",
      prompts: [],
      tools: records.tools.filter((tool) => tool.file === relative).map((tool) => tool.name),
      hasEval: hasEvalEvidence(text, file),
      hasTrace: hasTraceEvidence(text),
      evidence: preview(snippet, 260),
    };
    records.chains.push(chain);
    if (!chain.hasEval) pushRisk("missing-eval", "medium", file, line, "ToolLoopAgent chain lacks nearby eval or test evidence.", snippet, chain.id);
    if (!chain.hasTrace) pushRisk("missing-trace", "high", file, line, "ToolLoopAgent chain lacks trace ID, structured logging, or telemetry evidence.", snippet, chain.id);
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
    );
  }
}

function rows(items, empty, render) {
  if (!items.length) return `- ${empty}\n`;
  return items.map(render).join("\n") + "\n";
}

function write(name, body) {
  fs.writeFileSync(path.join(outDir, name), body);
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

const report = `${header("Agent Observability Report")}## Summary

- Prompts detected: ${records.prompts.length}
- Tools detected: ${records.tools.length}
- Chains/model calls detected: ${records.chains.length}
- API routes detected: ${records.routes.length}
- UI entrypoints detected: ${records.uiEntrypoints.length}
- Risks detected: ${records.risks.length}

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
write(
  "trace-map.json",
  JSON.stringify(
    {
      generatedAt,
      root,
      scanner: "agent-observability-skill.sh",
      summary: {
        prompts: records.prompts.length,
        tools: records.tools.length,
        chains: records.chains.length,
        routes: records.routes.length,
        uiEntrypoints: records.uiEntrypoints.length,
        risks: records.risks.length,
      },
      ...records,
    },
    null,
    2,
  ) + "\n",
);

console.log(`Agent observability report written to ${outDir}`);
console.log(`Open ${path.join(outDir, "report.md")}`);
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

say "# Agent Observability Report" > "$REPORT"
say "" >> "$REPORT"
say "Generated locally from \`$ROOT\`." >> "$REPORT"
say "" >> "$REPORT"
say "Node was not available, so this Bash fallback used grep-based detection." >> "$REPORT"
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
  \( -name .git -o -name node_modules -o -name .next -o -name dist -o -name build -o -name coverage -o -name .agent-observability \) -prune \
  -o \( -name "*.js" -o -name "*.jsx" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mjs" -o -name "*.cjs" -o -name "*.mdx" \) -type f -print |
while IFS= read -r file; do
  [ "$(cd "$(dirname "$file")" 2>/dev/null && pwd)/$(basename "$file")" = "$SELF_PATH" ] && continue
  rel_file="${file#$ROOT/}"

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
  "scanner": "agent-observability-skill.sh",
  "mode": "bash-fallback",
  "root": "$(printf '%s' "$ROOT" | sed 's/"/\\"/g')",
  "note": "Install Node for rich trace-map records."
}
JSON

say "Agent observability report written to $OUT_DIR"
say "Open $REPORT"
