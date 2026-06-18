// Embedded into renderSimpleHtmlReport — client-side only (no Node).
const PHASE_META = {
  entry: { label: "Start", tone: "info" },
  route: { label: "Backend", tone: "info" },
  prompt: { label: "Instructions", tone: "low" },
  model: { label: "AI response", tone: "info" },
  tool: { label: "Lookup", tone: "ok" },
  "side-effect": { label: "Action", tone: "high" },
  output: { label: "Answer", tone: "ok" },
  empty: { label: "—", tone: "low" },
};

const state = {
  agentId: (trace.agents || [])[0]?.id || "",
  selectedId: "",
  kind: "",
  view: "report",
  severityFilter: "all",
  search: "",
};

const escapeHtml = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (char) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char],
  );

const byAgent = (items) => (items || []).filter((item) => item.agentId === state.agentId);
const currentAgent = () => (trace.agents || []).find((agent) => agent.id === state.agentId) || null;

function promptTitle(item, fallback) {
  if (!item) return fallback || "Prompt";
  const kind =
    item.kind === "system" || item.kind === "instructions"
      ? "System instructions are added"
      : item.kind === "messages"
        ? "Conversation context is added"
        : "User instructions are added";
  const name = String(item.name || "").trim();
  if (name && name.toLowerCase() !== String(item.kind || "").toLowerCase()) return kind + " · " + name;
  if (item.valueType === "reference") return kind + " from a shared reference";
  if (item.valueType === "named constant") return kind + " from a named prompt";
  return kind;
}

function displayStepTitle(step) {
  if (!step) return "";
  return step.title || "";
}

function agentButtonClass(active) {
  return [
    "rounded-full border px-3 py-1.5 text-sm font-medium transition-all focus:outline-none focus:ring-2 focus:ring-[#0070f3]/30 whitespace-nowrap",
    active
      ? "border-[#0070f3] text-[#3291ff] bg-[#0070f3]/10"
      : "border-[#333] text-[#888] bg-[#0a0a0a] hover:border-[#555] hover:text-[#ededed]",
  ].join(" ");
}

function viewButtonClass(active) {
  return [
    "rounded-md px-3 py-1.5 text-xs font-semibold transition-all focus:outline-none focus-visible:ring-2 focus-visible:ring-[#0070f3]/30",
    active ? "bg-[#ededed] text-black shadow-sm" : "text-[#888] hover:text-[#ededed]",
  ].join(" ");
}

function badge(text, tone) {
  const tones = {
    high: "bg-[#ff5555]/10 text-[#ff8888] border-[#ff5555]/30",
    medium: "bg-[#f5a623]/10 text-[#f5c26b] border-[#f5a623]/30",
    low: "bg-[#333]/50 text-[#888] border-[#444]",
    info: "bg-[#0070f3]/10 text-[#3291ff] border-[#0070f3]/30",
    ok: "bg-[#50e3c2]/10 text-[#50e3c2] border-[#50e3c2]/30",
  };
  return (
    '<span class="inline-flex items-center rounded-md border px-1.5 py-0.5 text-[10px] font-semibold uppercase tracking-wide ' +
    (tones[tone] || tones.low) +
    '">' +
    escapeHtml(text) +
    "</span>"
  );
}

function flowStepsForAgent(agentId) {
  if (trace.flows && trace.flows[agentId]) return trace.flows[agentId];
  return [];
}

function findItem(kind, id) {
  if (!kind || !id || id.endsWith(":output")) return null;
  const key =
    kind === "entrypoints"
      ? "uiEntrypoints"
      : kind === "chains"
        ? "chains"
        : kind === "routes"
          ? "routes"
          : kind === "tools"
            ? "tools"
            : kind === "prompts"
              ? "prompts"
              : kind;
  return (trace[key] || []).find((item) => item.id === id) || null;
}

function phaseAccent(phase) {
  const map = {
    entry: "bg-sky-500",
    route: "bg-indigo-500",
    prompt: "bg-violet-500",
    model: "bg-[#0070f3]",
    tool: "bg-emerald-500",
    "side-effect": "bg-rose-500",
    output: "bg-gray-800",
    empty: "bg-[#444]",
  };
  return map[phase] || "bg-gray-400";
}

function flowCardClass(active, nested) {
  return [
    "flow-card w-full text-left rounded-lg border transition-all",
    "focus:outline-none focus-visible:ring-2 focus-visible:ring-[#0070f3]/30 focus-visible:ring-offset-1 focus-visible:ring-offset-black",
    nested ? "border-[#2a2a2a] bg-[#111]" : "border-[#333] bg-[#0a0a0a]",
    active ? "!border-[#0070f3] ring-2 ring-[#0070f3]/20" : "hover:border-[#555]",
  ].join(" ");
}

function flowStepMarker(step, active) {
  if (step.nested) {
    return (
      '<div class="mt-3 flex h-2 w-2 shrink-0 rounded-full ' +
      (active ? "bg-[#0070f3]" : "bg-[#444]") +
      '" aria-hidden="true"></div>'
    );
  }
  return (
    '<div class="mt-2.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold tabular-nums ' +
    (active ? "bg-[#0070f3] text-white shadow-sm" : "border border-[#444] bg-[#0a0a0a] text-[#888]") +
    '">' +
    escapeHtml(String(step.order)) +
    "</div>"
  );
}

function section(title, body) {
  return (
    '<div class="grid gap-2"><h3 class="text-xs font-semibold uppercase tracking-wide text-[#888]">' +
    escapeHtml(title) +
    '</h3><div class="text-[15px] text-[#ededed]">' +
    body +
    "</div></div>"
  );
}

function paragraph(text, tone) {
  return '<p class="leading-relaxed ' + (tone || "text-[#ededed]") + '">' + escapeHtml(text) + "</p>";
}

function codeValue(value) {
  return '<code class="font-mono text-sm text-[#a1a1a1] break-words">' + escapeHtml(value || "—") + "</code>";
}

function detailList(items) {
  return (
    '<dl class="grid gap-2 text-sm">' +
    items
      .map(function (item) {
        return (
          '<div class="grid gap-1 sm:grid-cols-[9rem_minmax(0,1fr)] sm:gap-3">' +
          '<dt class="text-xs font-semibold uppercase tracking-wide text-[#666]">' +
          escapeHtml(item[0]) +
          "</dt>" +
          '<dd class="min-w-0 text-[#ededed]">' +
          item[1] +
          "</dd>" +
          "</div>"
        );
      })
      .join("") +
    "</dl>"
  );
}

function preBlock(text, roomy) {
  const sizeClass = roomy
    ? "max-h-[min(58vh,640px)] p-4 text-[13px] leading-relaxed"
    : "max-h-72 p-3 text-xs";
  return (
    '<pre class="mt-2 overflow-auto rounded-lg border border-[#333] bg-[#080808] font-mono text-[#ededed] whitespace-pre-wrap break-words ' +
    sizeClass +
    '">' +
    escapeHtml(text || "") +
    "</pre>"
  );
}

function itemLocation(item) {
  if (!item || !item.file) return "Unknown location";
  return item.file + (item.line ? ":" + item.line : "");
}

function promptText(item) {
  return item?.text || item?.preview || "No prompt text resolved";
}

function promptKindLabel(item) {
  if (!item) return "prompt";
  if (item.kind === "system") return "system prompt";
  if (item.kind === "instructions") return "instructions";
  if (item.kind === "messages") return "messages";
  return item.kind || "prompt";
}

function promptsForChain(chain) {
  const linked = (chain?.promptIds || [])
    .map((promptId) => (trace.prompts || []).find((prompt) => prompt.id === promptId))
    .filter(Boolean);
  if (linked.length) return linked;
  return (chain?.prompts || []).map(function (value, index) {
    return {
      id: chain.id + ":prompt-fallback-" + index,
      kind: value.split(":")[0] || "prompt",
      valueType: "call argument",
      file: chain.file,
      line: chain.line,
      preview: value,
      text: value,
    };
  });
}

function toolsForChain(chain) {
  const linked = (chain?.toolIds || [])
    .map((toolId) => (trace.tools || []).find((tool) => tool.id === toolId))
    .filter(Boolean);
  if (linked.length) return linked;
  return (chain?.tools || []).map(function (name, index) {
    return {
      id: chain.id + ":tool-fallback-" + index,
      name,
      description: "Referenced by this model call",
      schema: "No schema resolved",
      file: chain.file,
      line: chain.line,
      sideEffect: false,
    };
  });
}

function chainsForPrompt(prompt) {
  return (trace.chains || []).filter(function (chain) {
    if ((chain.promptIds || []).includes(prompt.id)) return true;
    const text = promptText(prompt);
    return (chain.prompts || []).some(function (value) {
      return String(value || "").includes(text) || text.includes(String(value || ""));
    });
  });
}

function chainsForTool(tool) {
  return (trace.chains || []).filter(function (chain) {
    return (chain.toolIds || []).includes(tool.id) || (chain.tools || []).includes(tool.name);
  });
}

function relationCards(items, empty) {
  if (!items.length) return '<p class="text-sm text-[#888]">' + escapeHtml(empty) + "</p>";
  return (
    '<div class="grid gap-3">' +
    items
      .map(function (item) {
        return (
          '<div class="rounded-lg border border-[#2a2a2a] bg-[#111] p-3">' +
          '<div class="flex flex-wrap items-center gap-2">' +
          (item.badge ? badge(item.badge, item.tone || "info") : "") +
          '<h4 class="text-sm font-semibold text-[#ededed]">' +
          escapeHtml(item.title) +
          "</h4></div>" +
          (item.meta ? '<p class="mt-1 font-mono text-xs text-[#888] break-all">' + escapeHtml(item.meta) + "</p>" : "") +
          (item.body ? '<div class="mt-2 text-sm leading-relaxed text-[#a1a1a1]">' + item.body + "</div>" : "") +
          "</div>"
        );
      })
      .join("") +
    "</div>"
  );
}

function chainRelationCard(chain) {
  return {
    badge: chain.type || "model",
    tone: "info",
    title: "Feeds " + (chain.type || "model call"),
    meta: itemLocation(chain),
    body:
      detailList([
        ["Model", codeValue(chain.modelFull || chain.model)],
        ["Tools", escapeHtml((chain.tools || []).join(", ") || "none")],
      ]),
  };
}

function promptRelationCard(prompt) {
  return {
    badge: promptKindLabel(prompt),
    tone: "low",
    title: promptTitle(prompt, "Prompt"),
    meta: itemLocation(prompt),
    body: preBlock(promptText(prompt), true),
  };
}

function toolRelationCard(tool) {
  return {
    badge: tool.sideEffect ? "action" : "lookup",
    tone: tool.sideEffect ? "high" : "ok",
    title: tool.name || "Tool",
    meta: itemLocation(tool),
    body:
      '<p class="text-sm text-[#a1a1a1]">' +
      escapeHtml(tool.descriptionFull || tool.description || "No description detected") +
      "</p>" +
      detailList([
        ["Input", codeValue(tool.schema || "No schema resolved")],
        ["State change", codeValue(tool.sideEffect ? "yes" : "no")],
      ]),
  };
}

function searchTextForStep(step) {
  const item = findItem(step.kind, step.id);
  if (!item) return [step.title, step.subtitle, step.note].join(" ");
  if (step.kind === "prompts") return [step.title, step.subtitle, step.note, promptText(item)].join(" ");
  if (step.kind === "chains") {
    return [
      step.title,
      step.subtitle,
      step.note,
      item.model,
      item.modelFull,
      (item.prompts || []).join(" "),
      promptsForChain(item).map(promptText).join(" "),
      (item.tools || []).join(" "),
    ].join(" ");
  }
  if (step.kind === "tools") {
    return [step.title, step.subtitle, step.note, item.name, item.descriptionFull, item.description, item.schema, item.evidence].join(" ");
  }
  return [step.title, step.subtitle, step.note].join(" ");
}

function editorHref(item, scheme) {
  const root = (trace.root || "").replace(/\\/g, "/");
  const file = (item.file || "").replace(/\\/g, "/");
  return scheme + "://file/" + root + "/" + file + ":" + item.line;
}

function locBar(item) {
  const loc = item.file + ":" + item.line;
  return (
    '<div class="flex flex-wrap items-center gap-2 text-sm">' +
    '<code class="font-mono text-xs text-[#888]">' +
    escapeHtml(loc) +
    "</code>" +
    '<a class="text-xs font-medium text-[#3291ff] hover:underline" href="' +
    escapeHtml(editorHref(item, "cursor")) +
    '">Open in Cursor</a>' +
    '<a class="text-xs font-medium text-[#3291ff] hover:underline" href="' +
    escapeHtml(editorHref(item, "vscode")) +
    '">VS Code</a>' +
    '<button type="button" class="copy-path text-xs font-medium text-[#888] hover:text-[#ededed]" data-copy="' +
    escapeHtml(loc) +
    '">Copy path</button>' +
    "</div>"
  );
}

function matchesSearch(text) {
  const q = (state.search || "").trim().toLowerCase();
  if (!q) return true;
  return String(text || "").toLowerCase().includes(q);
}

function filterRisks(risks) {
  return risks.filter(function (risk) {
    if (state.severityFilter !== "all" && risk.severity !== state.severityFilter) return false;
    return matchesSearch([risk.message, risk.kind, risk.file, risk.evidence].join(" "));
  });
}

function buildMermaidForAgent(agentId) {
  const steps = flowStepsForAgent(agentId).filter(function (s) {
    return s.phase !== "empty";
  });
  if (!steps.length) return "";
  const lines = ["flowchart TD"];
  steps.forEach(function (step, index) {
    const nodeId = "N" + index;
    const label = (step.title || step.phase || "step").replace(/"/g, "'");
    lines.push('  ' + nodeId + '["' + label + '"]');
    if (index > 0) lines.push("  N" + (index - 1) + " --> " + nodeId);
  });
  return lines.join("\n");
}

function renderOutputDetail(step, chain) {
  return (
    '<div class="grid gap-4">' +
    '<h2 class="text-lg font-semibold text-[#ededed]">' +
    escapeHtml(step.title) +
    "</h2>" +
    section("What this means", paragraph(step.note || "The product shows the AI response to the user.")) +
    (chain
      ? section(
          "Code details",
          detailList([
            ["Output", codeValue(step.subtitle)],
            ["Model call", codeValue(chain.type || "model call")],
          ]),
        ) +
        locBar(chain) +
        '<p class="text-xs text-[#666] mt-2">In the UI, streamed tokens appear in the chat component; non-stream responses render as a single message or JSON payload.</p>'
      : "") +
    "</div>"
  );
}

function productMeaning(kind, item, step) {
  if (kind === "entrypoints") {
    return "This is the product moment where a user starts the AI experience, usually by sending a message or prompt.";
  }
  if (kind === "routes") {
    return "This backend endpoint receives the user's request and prepares the AI work.";
  }
  if (kind === "prompts") {
    return "These instructions shape how the AI should behave before it answers the user.";
  }
  if (kind === "chains") {
    return "This is where the app asks an AI model to generate the next response.";
  }
  if (kind === "tools" && item && item.sideEffect) {
    return "The AI can call this helper to change something outside the chat, such as a database, payment, email, or another service.";
  }
  if (kind === "tools") {
    return "The AI can call this helper to look up information before it answers.";
  }
  return step && step.note ? step.note : "This is one step in the AI flow.";
}

function renderDetail(item, kind, step) {
  if (step && step.phase === "output") {
    const chainId = step.id.replace(/:output$/, "");
    const chain = (trace.chains || []).find((c) => c.id === chainId);
    return renderOutputDetail(step, chain);
  }
  if (!item) {
    if (step && step.phase === "empty") {
      return '<p class="text-[15px] text-[#888]">' + escapeHtml(step.subtitle) + "</p>";
    }
    return '<p class="text-[15px] text-[#888]">Select a step in the flow to inspect it.</p>';
  }

  const badges = [];
  if (kind === "tools" && item.sideEffect) badges.push(badge("side effect", "high"));
  if (kind === "prompts" && item.inline) badges.push(badge("inline", "medium"));
  if (kind === "chains") {
    if (!item.hasEval) badges.push(badge("no eval", "medium"));
    if (!item.hasTrace) badges.push(badge("no trace", "high"));
    else badges.push(badge("trace ok", "ok"));
  }

  let body = "";
  if (kind === "prompts") {
    const promptChains = chainsForPrompt(item);
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      section("Full prompt text", preBlock(promptText(item), true)) +
      section(
        "This prompt feeds into",
        relationCards(
          promptChains.map(chainRelationCard),
          "No model call was linked to this prompt. It may be assembled dynamically or passed through another helper.",
        ),
      ) +
      section(
        "Code details",
        detailList([
          ["Prompt type", codeValue(item.kind)],
          ["Value source", codeValue(item.valueType)],
        ]),
      );
  } else if (kind === "tools") {
    const schemaRows = (item.schemaFields || [])
      .map(
        (f) =>
          '<tr class="border-t border-[#2a2a2a]"><td class="py-2 pr-4 font-mono text-xs">' +
          escapeHtml(f.name) +
          '</td><td class="py-2 font-mono text-xs text-[#888]">' +
          escapeHtml(f.type) +
          "</td></tr>",
      )
      .join("");
    const callerChains = chainsForTool(item);
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      (item.sideEffect
        ? '<p class="rounded-lg border border-[#ff5555]/30 bg-[#ff5555]/10 px-3 py-2 text-sm text-[#ff8888]">This can change real product state. Review permissions, logging, and tests before trusting model-triggered calls.</p>'
        : "") +
      section(
        "Model calls that can call this tool",
        relationCards(
          callerChains.map(chainRelationCard),
          "No model call was linked to this tool. It may be passed dynamically or exported for another file.",
        ),
      ) +
      section(
        "Code details",
        detailList([
          ["Tool name", codeValue(item.name)],
          ["Description", escapeHtml(item.descriptionFull || item.description || "—")],
          ["Can change state", codeValue(item.sideEffect ? "yes" : "no")],
        ]),
      ) +
      section(
        "Input data this tool expects",
        schemaRows
          ? '<table class="w-full text-left"><thead><tr><th class="pb-2 text-xs text-[#888]">Field</th><th class="pb-2 text-xs text-[#888]">Type</th></tr></thead><tbody>' +
            schemaRows +
            "</tbody></table>"
          : '<p class="text-[#888] text-sm">' + escapeHtml(item.schema || "No schema") + "</p>",
      ) +
      section("Tool implementation", preBlock(item.evidence || item.snippet || "No tool implementation captured", true));
  } else if (kind === "chains") {
    const loopRows = [];
    if (item.loop) {
      if (item.loop.hasStopWhen) loopRows.push(["Loop bound", codeValue(item.loop.stepCount ? "stepCountIs(" + item.loop.stepCount + ")" : item.loop.stopWhen || item.loop.maxSteps)]);
      if (item.loop.toolChoice) loopRows.push(["toolChoice", codeValue(item.loop.toolChoice)]);
      if (item.loop.prepareStep) loopRows.push(["prepareStep", codeValue("yes")]);
    }
    if (item.telemetry) {
      loopRows.push(["Telemetry", codeValue(item.telemetry.isEnabled ? "experimental_telemetry on" : "not detected")]);
      if (item.telemetry.hasFunctionId) loopRows.push(["functionId", codeValue("set")]);
    }
    const chainPrompts = promptsForChain(item);
    const chainTools = toolsForChain(item);
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      section(
        "Code details",
        detailList([
          ["Model", codeValue(item.modelFull || item.model)],
          ["Prompt inputs", escapeHtml(chainPrompts.length ? chainPrompts.map((prompt) => promptKindLabel(prompt)).join(", ") : "—")],
          ["Tools available", escapeHtml(chainTools.length ? chainTools.map((tool) => tool.name).join(", ") : "—")],
          ...loopRows,
        ]),
      ) +
      section(
        "Prompts read by this model call",
        relationCards(
          chainPrompts.map(promptRelationCard),
          "No prompt text was linked to this model call.",
        ),
      ) +
      section(
        "Tools this model can call",
        relationCards(
          chainTools.map(toolRelationCard),
          "No tools were linked to this model call.",
        ),
      );
  } else if (kind === "routes") {
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      section(
        "Code details",
        detailList([
          ["HTTP methods", codeValue((item.methods || []).join(", ") || "unknown")],
          ["AI code found", codeValue((item.aiPatterns || []).join(", ") || "none")],
        ]),
      );
  } else if (kind === "entrypoints") {
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      section("How the user starts this", codeValue(item.hook)) +
      section("Where the message is sent", codeValue(item.api));
  }

  return (
    '<div class="grid gap-4">' +
    '<div class="flex flex-wrap items-start gap-2"><h2 class="text-lg font-semibold text-[#ededed] flex-1">' +
    escapeHtml(step ? displayStepTitle(step) : kind === "prompts" ? promptTitle(item, "") : item.name || item.hook) +
    "</h2>" +
    (badges.length ? '<div class="flex flex-wrap gap-1">' + badges.join("") + "</div>" : "") +
    "</div>" +
    body +
    locBar(item) +
    "</div>"
  );
}

function riskTone(severity) {
  if (severity === "high") return "high";
  if (severity === "medium") return "medium";
  return "low";
}

function renderRiskTimeline(risks) {
  if (!risks.length) {
    return '<p class="text-sm text-[#888]">No risks detected for this agent.</p>';
  }
  return (
    '<ol class="grid gap-3 list-none m-0 p-0">' +
    risks
      .map(function (risk, index) {
        const active = state.selectedId === risk.id;
        return (
          '<li><button type="button" class="' +
          flowCardClass(active, false) +
          '" data-risk-id="' +
          escapeHtml(risk.id) +
          '">' +
          '<div class="flex gap-3 px-3.5 py-3">' +
          '<div class="w-1 shrink-0 rounded-full ' +
          (risk.severity === "high" ? "bg-[#ff5555]" : risk.severity === "medium" ? "bg-[#f5a623]" : "bg-[#666]") +
          '" aria-hidden="true"></div>' +
          '<div class="min-w-0 flex-1">' +
          '<div class="flex flex-wrap items-center gap-2">' +
          '<span class="text-[10px] font-semibold uppercase tracking-[0.08em] text-[#666]">Risk ' +
          escapeHtml(String(index + 1)) +
          "</span>" +
          badge(risk.severity || "risk", riskTone(risk.severity)) +
          "</div>" +
          '<div class="mt-1 text-[15px] font-medium leading-snug text-[#ededed]">' +
          escapeHtml(risk.message || "Risk") +
          "</div>" +
          '<div class="mt-1 font-mono text-[12px] leading-relaxed text-[#888] break-all">' +
          escapeHtml((risk.kind || "risk") + " · " + risk.file + ":" + risk.line) +
          "</div>" +
          "</div></div></button></li>"
        );
      })
      .join("") +
    "</ol>"
  );
}

function renderRiskDetail(risk) {
  if (!risk) return '<p class="text-[15px] text-[#888]">Select a risk to inspect it.</p>';
  return (
    '<div class="grid gap-4">' +
    '<div class="flex flex-wrap items-start gap-2"><h2 class="text-lg font-semibold text-[#ededed] flex-1">' +
    escapeHtml(risk.message || "Risk") +
    "</h2>" +
    '<div class="flex flex-wrap gap-1">' +
    badge(risk.severity || "risk", riskTone(risk.severity)) +
    badge(risk.kind || "risk", "low") +
    "</div></div>" +
    locBar(risk) +
    section("Why this was flagged", preBlock(risk.evidenceFull || risk.evidence || "No evidence captured")) +
    section(
      "Recommended fix",
      '<p class="text-[15px] leading-relaxed text-[#ededed] mb-2">Copy this snippet into the referenced call site:</p>' +
        preBlock(risk.fixSnippet || risk.fix || "Review this risk in the referenced code path.") +
        '<button type="button" class="copy-fix mt-2 rounded-lg border border-[#333] bg-[#111] px-3 py-1.5 text-xs font-semibold text-[#a1a1a1] hover:bg-[#1a1a1a]" data-copy="' +
        escapeHtml(risk.fixSnippet || risk.fix || "") +
        '">Copy fix snippet</button>',
    ) +
    (risk.targetId ? section("Code target", '<code class="font-mono text-xs text-[#888]">' + escapeHtml(risk.targetId) + "</code>") : "") +
    "</div>"
  );
}

function renderFlowTimeline(steps) {
  if (!steps.length) {
    return '<p class="text-sm text-[#888]">No execution flow for this agent.</p>';
  }
  return (
    '<ol class="flow-track list-none m-0 p-0">' +
    steps
      .map(function (step, index) {
        const meta = PHASE_META[step.phase] || PHASE_META.empty;
        const active = state.selectedId === step.id;
        const nested = !!step.nested;
        const isLast = index === steps.length - 1;
        const railPad = nested ? "pt-0" : "pt-0";
        return (
          '<li class="flow-step grid grid-cols-[2.75rem_minmax(0,1fr)] gap-x-3' +
          (nested ? " flow-step-nested" : "") +
          '">' +
          '<div class="flow-rail flex flex-col items-center ' +
          railPad +
          '">' +
          flowStepMarker(step, active) +
          (!isLast ? '<div class="flow-rail-line w-px flex-1 min-h-3 bg-[#333] mt-1"></div>' : "") +
          "</div>" +
          '<div class="pb-3 min-w-0">' +
          '<button type="button" class="' +
          flowCardClass(active, nested) +
          '" data-flow-id="' +
          escapeHtml(step.id) +
          '" data-flow-kind="' +
          escapeHtml(step.kind) +
          '">' +
          '<div class="flex gap-3 px-3.5 py-3">' +
          '<div class="w-1 shrink-0 rounded-full ' +
          phaseAccent(step.phase) +
          '" aria-hidden="true"></div>' +
          '<div class="min-w-0 flex-1">' +
          '<div class="text-[10px] font-semibold uppercase tracking-[0.08em] text-[#666]">' +
          escapeHtml(meta.label) +
          "</div>" +
          '<div class="mt-1 text-[15px] font-medium leading-snug text-[#ededed]">' +
          escapeHtml(displayStepTitle(step)) +
          "</div>" +
          '<div class="mt-1 font-mono text-[12px] leading-relaxed text-[#888] break-all">' +
          escapeHtml(step.subtitle) +
          "</div>" +
          "</div>" +
          "</div>" +
          "</button>" +
          "</div>" +
          "</li>"
        );
      })
      .join("") +
    "</ol>"
  );
}

async function copyText(value) {
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(value);
      return;
    }
  } catch (e) {}
  const ta = document.createElement("textarea");
  ta.value = value;
  document.body.appendChild(ta);
  ta.select();
  document.execCommand("copy");
  document.body.removeChild(ta);
}

function renderScanDiffBanner() {
  const el = document.querySelector("#scan-diff-banner");
  if (!el || !trace.scanDiff?.hasPrevious) {
    if (el) el.textContent = "";
    return;
  }
  const d = trace.scanDiff;
  el.innerHTML =
    '<span class="text-[#50e3c2] font-medium">' +
    d.fixedCount +
    " fixed</span> · <span class=\"text-[#f5c26b] font-medium\">" +
    d.newCount +
    " new</span> since " +
    escapeHtml(d.previousAt || "last scan");
}

function renderMermaid() {
  const container = document.querySelector("#mermaid-flow");
  if (!container) return;
  const def = buildMermaidForAgent(state.agentId);
  if (!def || state.view === "risks") {
    container.classList.add("hidden");
    container.innerHTML = "";
    return;
  }
  container.classList.remove("hidden");
  container.innerHTML = '<pre class="mermaid text-sm">' + escapeHtml(def) + "</pre>";
  if (window.mermaid) {
    try {
      window.mermaid.initialize({ startOnLoad: false, theme: "neutral", securityLevel: "loose" });
      window.mermaid.run({ nodes: container.querySelectorAll(".mermaid") });
    } catch (e) {
      /* mermaid optional */
    }
  }
}

function renderRiskFilters() {
  const el = document.querySelector("#risk-filters");
  if (!el) return;
  const risks = byAgent(trace.risks || []);
  const counts = { all: risks.length, high: 0, medium: 0, low: 0 };
  risks.forEach(function (r) {
    if (counts[r.severity] !== undefined) counts[r.severity] += 1;
  });
  el.innerHTML = ["all", "high", "medium", "low"]
    .map(function (sev) {
      const active = state.severityFilter === sev;
      return (
        '<button type="button" class="rounded-md border px-2 py-1 text-[11px] font-semibold ' +
        (active ? "border-[#0070f3] bg-[#0070f3]/10 text-[#3291ff]" : "border-[#333] text-[#888] hover:bg-[#111]") +
        '" data-severity="' +
        sev +
        '">' +
        escapeHtml(sev) +
        " (" +
        counts[sev] +
        ")</button>"
      );
    })
    .join("");
  el.querySelectorAll("[data-severity]").forEach(function (button) {
    button.addEventListener("click", function () {
      state.severityFilter = button.dataset.severity;
      state.selectedId = "";
      render();
    });
  });
}

function preferredInitialStep(steps) {
  return steps.find((step) => step.phase === "prompt") || steps[0] || null;
}

function render() {
  const agent = currentAgent();
  const steps = flowStepsForAgent(state.agentId).filter(function (step) {
    return matchesSearch(searchTextForStep(step));
  });
  const risks = filterRisks(byAgent(trace.risks || []));
  renderScanDiffBanner();
  renderRiskFilters();
  const searchInput = document.querySelector("#report-search");
  if (searchInput && searchInput !== document.activeElement) {
    searchInput.value = state.search;
  }
  if (searchInput && !searchInput.dataset.bound) {
    searchInput.dataset.bound = "1";
    searchInput.addEventListener("input", function () {
      state.search = searchInput.value;
      render();
    });
  }
  const copyCtxBtn = document.querySelector("#copy-agent-context");
  if (copyCtxBtn && !copyCtxBtn.dataset.bound) {
    copyCtxBtn.dataset.bound = "1";
    copyCtxBtn.addEventListener("click", function () {
      const md = (trace.agentContexts && trace.agentContexts[state.agentId]) || "";
      copyText(md || "No agent context available.");
    });
  }

  document.querySelector("#agents").innerHTML =
    (trace.agents || [])
      .map(function (item) {
        return (
          '<button type="button" class="' +
          agentButtonClass(item.id === state.agentId) +
          '" data-agent="' +
          escapeHtml(item.id) +
          '">' +
          escapeHtml(item.name) +
          "</button>"
        );
      })
      .join("") ||
    '<span class="text-sm text-[#888]">No agents detected</span>';

  document.querySelectorAll("[data-agent]").forEach(function (button) {
    button.addEventListener("click", function () {
      state.agentId = button.dataset.agent;
      state.selectedId = "";
      state.kind = "";
      render();
    });
  });

  const agentName = document.querySelector("#agent-name");
  if (agentName) agentName.textContent = agent ? agent.name : "No agent detected";
  const agentDescription = document.querySelector("#agent-description");
  if (agentDescription) {
    agentDescription.textContent = agent
      ? agent.description || "Static scan found agent-like behavior in this code path."
      : "Run the scanner on a repo with AI SDK routes or client hooks.";
  }

  const tabs = document.querySelector("#view-tabs");
  if (tabs) {
    tabs.innerHTML =
      '<button type="button" class="' +
      viewButtonClass(state.view === "report") +
      '" data-view="report">Report</button>' +
      '<button type="button" class="' +
      viewButtonClass(state.view === "risks") +
      '" data-view="risks">Risks ' +
      escapeHtml(String(risks.length)) +
      "</button>";
    tabs.querySelectorAll("[data-view]").forEach(function (button) {
      button.addEventListener("click", function () {
        state.view = button.dataset.view;
        state.selectedId = "";
        state.kind = "";
        render();
      });
    });
  }

  const noteEl = document.querySelector("#flow-note");
  const kicker = document.querySelector("#section-kicker");
  if (kicker) kicker.textContent = state.view === "risks" ? "Risks" : "User journey";
  if (noteEl) {
    noteEl.textContent =
      state.view === "risks"
        ? "Static risks found for the selected agent. Treat these as review targets, not runtime proof."
        : trace.flowNote || "";
  }

  if (state.view === "risks") {
    if (!state.selectedId && risks[0]) {
      state.selectedId = risks[0].id;
      state.kind = "risks";
    }
    const currentRisk = risks.find(function (risk) {
      return risk.id === state.selectedId;
    });
    if (state.selectedId && !currentRisk && risks[0]) {
      state.selectedId = risks[0].id;
      state.kind = "risks";
    }

    document.querySelector("#flow-timeline").innerHTML = renderRiskTimeline(risks);
    document.querySelectorAll("[data-risk-id]").forEach(function (button) {
      button.addEventListener("click", function () {
        state.selectedId = button.dataset.riskId;
        state.kind = "risks";
        render();
      });
    });

    const risk = risks.find(function (item) {
      return item.id === state.selectedId;
    });
    const riskIndex = risk ? risks.findIndex((item) => item.id === risk.id) + 1 : 0;
    document.querySelector("#detail-title").textContent = risk ? "Risk " + riskIndex + " · " + (risk.severity || "review") : "Risk details";
    const detailBox = document.querySelector("#detail-box");
    detailBox.className =
      "min-h-[480px] rounded-xl bg-[#0a0a0a] p-5 shadow-sm " +
      (risk ? "border-2 border-[#0070f3] ring-2 ring-[#0070f3]/20" : "border border-[#333]");
    detailBox.innerHTML = renderRiskDetail(risk);

    document.querySelectorAll(".copy-path, .copy-fix").forEach(function (button) {
      button.addEventListener("click", function () {
        copyText(button.dataset.copy);
      });
    });
    renderMermaid();
    return;
  }

  if (!state.selectedId && steps[0]) {
    const initialStep = preferredInitialStep(steps);
    state.selectedId = initialStep.id;
    state.kind = initialStep.kind;
  }
  const currentStep = steps.find(function (s) {
    return s.id === state.selectedId;
  });
  if (state.selectedId && !currentStep && steps[0]) {
    const initialStep = preferredInitialStep(steps);
    state.selectedId = initialStep.id;
    state.kind = initialStep.kind;
  }

  document.querySelector("#flow-timeline").innerHTML = renderFlowTimeline(steps);
  document.querySelectorAll("[data-flow-id]").forEach(function (button) {
    button.addEventListener("click", function () {
      state.selectedId = button.dataset.flowId;
      state.kind = button.dataset.flowKind;
      render();
    });
  });

  const step = steps.find(function (s) {
    return s.id === state.selectedId;
  });
  const item = findItem(state.kind, state.selectedId);
  document.querySelector("#detail-title").textContent = step ? "Step " + step.order + " · " + (PHASE_META[step.phase]?.label || "Details") : "Step details";
  const detailBox = document.querySelector("#detail-box");
  detailBox.className =
    "min-h-[560px] rounded-xl bg-[#0a0a0a] p-5 shadow-sm " +
    (step ? "border-2 border-[#0070f3] ring-2 ring-[#0070f3]/20" : "border border-[#333]");
  detailBox.innerHTML = renderDetail(item, state.kind, step);

  document.querySelectorAll(".copy-path, .copy-fix").forEach(function (button) {
    button.addEventListener("click", function () {
      copyText(button.dataset.copy);
    });
  });
  renderMermaid();
}

render();
