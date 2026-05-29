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
};

const escapeHtml = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (char) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char],
  );

const byAgent = (items) => (items || []).filter((item) => item.agentId === state.agentId);
const currentAgent = () => (trace.agents || []).find((agent) => agent.id === state.agentId) || null;

function promptTitle(item, fallback) {
  if (!item) return fallback || "Prompt";
  const kind = item.kind === "system" ? "System instructions are added" : item.kind === "messages" ? "Conversation context is added" : "User instructions are added";
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
    "rounded-lg border px-3 py-1.5 text-sm font-medium transition-all focus:outline-none focus:ring-2 focus:ring-gray-200 whitespace-nowrap",
    active
      ? "border-blue-600 text-blue-600 bg-blue-50"
      : "border-gray-200 text-gray-700 bg-white hover:border-gray-300 hover:bg-gray-50",
  ].join(" ");
}

function viewButtonClass(active) {
  return [
    "rounded-md px-3 py-1.5 text-xs font-semibold transition-all focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-200",
    active ? "bg-white text-blue-700 shadow-sm" : "text-gray-500 hover:text-gray-900",
  ].join(" ");
}

function badge(text, tone) {
  const tones = {
    high: "bg-red-50 text-red-700 border-red-200",
    medium: "bg-amber-50 text-amber-800 border-amber-200",
    low: "bg-gray-50 text-gray-600 border-gray-200",
    info: "bg-blue-50 text-blue-700 border-blue-200",
    ok: "bg-emerald-50 text-emerald-700 border-emerald-200",
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
    model: "bg-blue-600",
    tool: "bg-emerald-500",
    "side-effect": "bg-rose-500",
    output: "bg-gray-800",
    empty: "bg-gray-300",
  };
  return map[phase] || "bg-gray-400";
}

function flowCardClass(active, nested) {
  return [
    "flow-card w-full text-left rounded-lg border transition-all",
    "focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-200 focus-visible:ring-offset-1",
    nested ? "border-gray-200/90 bg-gray-50/80" : "border-gray-200 bg-white shadow-sm",
    active ? "!border-blue-500 ring-2 ring-blue-100" : "hover:border-gray-300 hover:shadow",
  ].join(" ");
}

function flowStepMarker(step, active) {
  if (step.nested) {
    return (
      '<div class="mt-3 flex h-2 w-2 shrink-0 rounded-full ' +
      (active ? "bg-blue-600" : "bg-gray-300") +
      '" aria-hidden="true"></div>'
    );
  }
  return (
    '<div class="mt-2.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-[11px] font-semibold tabular-nums ' +
    (active ? "bg-blue-600 text-white shadow-sm" : "border border-gray-300 bg-white text-gray-600") +
    '">' +
    escapeHtml(String(step.order)) +
    "</div>"
  );
}

function section(title, body) {
  return (
    '<div class="grid gap-2"><h3 class="text-xs font-semibold uppercase tracking-wide text-gray-500">' +
    escapeHtml(title) +
    '</h3><div class="text-[15px] text-gray-800">' +
    body +
    "</div></div>"
  );
}

function paragraph(text, tone) {
  return '<p class="leading-relaxed ' + (tone || "text-gray-800") + '">' + escapeHtml(text) + "</p>";
}

function codeValue(value) {
  return '<code class="font-mono text-sm text-gray-700 break-words">' + escapeHtml(value || "—") + "</code>";
}

function detailList(items) {
  return (
    '<dl class="grid gap-2 text-sm">' +
    items
      .map(function (item) {
        return (
          '<div class="grid gap-1 sm:grid-cols-[9rem_minmax(0,1fr)] sm:gap-3">' +
          '<dt class="text-xs font-semibold uppercase tracking-wide text-gray-400">' +
          escapeHtml(item[0]) +
          "</dt>" +
          '<dd class="min-w-0 text-gray-800">' +
          item[1] +
          "</dd>" +
          "</div>"
        );
      })
      .join("") +
    "</dl>"
  );
}

function preBlock(text) {
  return (
    '<pre class="mt-2 max-h-64 overflow-auto rounded-lg border border-gray-200 bg-gray-50 p-3 font-mono text-xs text-gray-800 whitespace-pre-wrap break-words">' +
    escapeHtml(text || "") +
    "</pre>"
  );
}

function editorHref(item) {
  const root = (trace.root || "").replace(/\\/g, "/");
  const file = (item.file || "").replace(/\\/g, "/");
  return "vscode://file/" + root + "/" + file + ":" + item.line;
}

function locBar(item) {
  const loc = item.file + ":" + item.line;
  return (
    '<div class="flex flex-wrap items-center gap-2 text-sm">' +
    '<code class="font-mono text-xs text-gray-600">' +
    escapeHtml(loc) +
    "</code>" +
    '<a class="text-xs font-medium text-blue-600 hover:underline" href="' +
    escapeHtml(editorHref(item)) +
    '">Open in editor</a>' +
    '<button type="button" class="copy-path text-xs font-medium text-gray-500 hover:text-gray-900" data-copy="' +
    escapeHtml(loc) +
    '">Copy path</button>' +
    "</div>"
  );
}

function renderOutputDetail(step, chain) {
  return (
    '<div class="grid gap-4">' +
    '<h2 class="text-lg font-semibold text-gray-900">' +
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
        '<p class="text-xs text-gray-400 mt-2">In the UI, streamed tokens appear in the chat component; non-stream responses render as a single message or JSON payload.</p>'
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
      return '<p class="text-[15px] text-gray-500">' + escapeHtml(step.subtitle) + "</p>";
    }
    return '<p class="text-[15px] text-gray-500">Select a step in the flow to inspect it.</p>';
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
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      section("Prompt text", preBlock(item.text || item.preview || "No prompt text resolved")) +
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
          '<tr class="border-t border-gray-100"><td class="py-2 pr-4 font-mono text-xs">' +
          escapeHtml(f.name) +
          '</td><td class="py-2 font-mono text-xs text-gray-600">' +
          escapeHtml(f.type) +
          "</td></tr>",
      )
      .join("");
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      (item.sideEffect
        ? '<p class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">This can change real product state. Review permissions, logging, and tests before trusting model-triggered calls.</p>'
        : "") +
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
          ? '<table class="w-full text-left"><thead><tr><th class="pb-2 text-xs text-gray-500">Field</th><th class="pb-2 text-xs text-gray-500">Type</th></tr></thead><tbody>' +
            schemaRows +
            "</tbody></table>"
          : '<p class="text-gray-500 text-sm">' + escapeHtml(item.schema || "No schema") + "</p>",
      );
  } else if (kind === "chains") {
    body =
      section("What this means", paragraph(productMeaning(kind, item, step))) +
      section(
        "Code details",
        detailList([
          ["Model", codeValue(item.modelFull || item.model)],
          ["Prompt inputs", escapeHtml((item.prompts || []).join("; ") || "—")],
          ["Tools available", escapeHtml((item.tools || []).join(", ") || "—")],
        ]),
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
    '<div class="flex flex-wrap items-start gap-2"><h2 class="text-lg font-semibold text-gray-900 flex-1">' +
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
    return '<p class="text-sm text-gray-500">No risks detected for this agent.</p>';
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
          (risk.severity === "high" ? "bg-red-500" : risk.severity === "medium" ? "bg-amber-500" : "bg-gray-400") +
          '" aria-hidden="true"></div>' +
          '<div class="min-w-0 flex-1">' +
          '<div class="flex flex-wrap items-center gap-2">' +
          '<span class="text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400">Risk ' +
          escapeHtml(String(index + 1)) +
          "</span>" +
          badge(risk.severity || "risk", riskTone(risk.severity)) +
          "</div>" +
          '<div class="mt-1 text-[15px] font-medium leading-snug text-gray-900">' +
          escapeHtml(risk.message || "Risk") +
          "</div>" +
          '<div class="mt-1 font-mono text-[12px] leading-relaxed text-gray-500 break-all">' +
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
  if (!risk) return '<p class="text-[15px] text-gray-500">Select a risk to inspect it.</p>';
  return (
    '<div class="grid gap-4">' +
    '<div class="flex flex-wrap items-start gap-2"><h2 class="text-lg font-semibold text-gray-900 flex-1">' +
    escapeHtml(risk.message || "Risk") +
    "</h2>" +
    '<div class="flex flex-wrap gap-1">' +
    badge(risk.severity || "risk", riskTone(risk.severity)) +
    badge(risk.kind || "risk", "low") +
    "</div></div>" +
    locBar(risk) +
    section("Why this was flagged", preBlock(risk.evidenceFull || risk.evidence || "No evidence captured")) +
    section("Recommended next step", '<p class="text-[15px] leading-relaxed text-gray-800">' + escapeHtml(risk.fix || "Review this risk in the referenced code path.") + "</p>") +
    (risk.targetId ? section("Code target", '<code class="font-mono text-xs text-gray-600">' + escapeHtml(risk.targetId) + "</code>") : "") +
    "</div>"
  );
}

function renderFlowTimeline(steps) {
  if (!steps.length) {
    return '<p class="text-sm text-gray-500">No execution flow for this agent.</p>';
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
          (!isLast ? '<div class="flow-rail-line w-px flex-1 min-h-3 bg-gray-200 mt-1"></div>' : "") +
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
          '<div class="text-[10px] font-semibold uppercase tracking-[0.08em] text-gray-400">' +
          escapeHtml(meta.label) +
          "</div>" +
          '<div class="mt-1 text-[15px] font-medium leading-snug text-gray-900">' +
          escapeHtml(displayStepTitle(step)) +
          "</div>" +
          '<div class="mt-1 font-mono text-[12px] leading-relaxed text-gray-500 break-all">' +
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

function render() {
  const agent = currentAgent();
  const steps = flowStepsForAgent(state.agentId);
  const risks = byAgent(trace.risks || []);

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
    '<span class="text-sm text-gray-500">No agents detected</span>';

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
      "min-h-[280px] rounded-xl bg-white p-5 shadow-sm " +
      (risk ? "border-2 border-blue-500 ring-2 ring-blue-50" : "border border-gray-200");
    detailBox.innerHTML = renderRiskDetail(risk);

    document.querySelectorAll(".copy-path").forEach(function (button) {
      button.addEventListener("click", function () {
        copyText(button.dataset.copy);
      });
    });
    return;
  }

  if (!state.selectedId && steps[0]) {
    state.selectedId = steps[0].id;
    state.kind = steps[0].kind;
  }
  const currentStep = steps.find(function (s) {
    return s.id === state.selectedId;
  });
  if (state.selectedId && !currentStep && steps[0]) {
    state.selectedId = steps[0].id;
    state.kind = steps[0].kind;
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
    "min-h-[280px] rounded-xl bg-white p-5 shadow-sm " +
    (step ? "border-2 border-blue-500 ring-2 ring-blue-50" : "border border-gray-200");
  detailBox.innerHTML = renderDetail(item, state.kind, step);

  document.querySelectorAll(".copy-path").forEach(function (button) {
    button.addEventListener("click", function () {
      copyText(button.dataset.copy);
    });
  });
}

render();
