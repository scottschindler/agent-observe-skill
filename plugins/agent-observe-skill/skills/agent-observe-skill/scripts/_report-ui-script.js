// Embedded into renderSimpleHtmlReport — client-side only (no Node).
const PHASE_META = {
  entry: { label: "Entry", tone: "info" },
  route: { label: "Route", tone: "info" },
  prompt: { label: "Prompt", tone: "low" },
  model: { label: "Model", tone: "info" },
  tool: { label: "Tool", tone: "ok" },
  "side-effect": { label: "Action", tone: "high" },
  output: { label: "Output", tone: "ok" },
  empty: { label: "—", tone: "low" },
};

const state = {
  agentId: (trace.agents || [])[0]?.id || "",
  selectedId: "",
  kind: "",
};

const escapeHtml = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (char) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char],
  );

const byAgent = (items) => (items || []).filter((item) => item.agentId === state.agentId);
const currentAgent = () => (trace.agents || []).find((agent) => agent.id === state.agentId) || null;

function agentButtonClass(active) {
  return [
    "rounded-lg border px-3 py-1.5 text-sm font-medium transition-all focus:outline-none focus:ring-2 focus:ring-gray-200 whitespace-nowrap",
    active
      ? "border-blue-600 text-blue-600 bg-blue-50"
      : "border-gray-200 text-gray-700 bg-white hover:border-gray-300 hover:bg-gray-50",
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
    '<p class="text-[15px] text-gray-700">' +
    escapeHtml(step.subtitle) +
    "</p>" +
    '<p class="text-sm text-gray-500">' +
    escapeHtml(step.note) +
    "</p>" +
    (chain
      ? section("Source", preBlock(chain.snippet)) +
        locBar(chain) +
        '<p class="text-xs text-gray-400 mt-2">In the UI, streamed tokens appear in the chat component; non-stream responses render as a single message or JSON payload.</p>'
      : "") +
    "</div>"
  );
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
      section("Prompt text", preBlock(item.text || item.preview)) + section("Source context", preBlock(item.snippet));
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
      (item.sideEffect
        ? '<p class="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-800">Mutates external state when the model invokes this tool.</p>'
        : "") +
      section("Description", escapeHtml(item.descriptionFull || item.description || "—")) +
      section(
        "Input schema",
        schemaRows
          ? '<table class="w-full text-left"><thead><tr><th class="pb-2 text-xs text-gray-500">Field</th><th class="pb-2 text-xs text-gray-500">Type</th></tr></thead><tbody>' +
            schemaRows +
            "</tbody></table>"
          : '<p class="text-gray-500 text-sm">' + escapeHtml(item.schema || "No schema") + "</p>",
      ) +
      section("Source context", preBlock(item.snippet));
  } else if (kind === "chains") {
    body =
      section("Model", escapeHtml(item.modelFull || item.model)) +
      section("Prompts", escapeHtml((item.prompts || []).join("; ") || "—")) +
      section("Tools", escapeHtml((item.tools || []).join(", ") || "—")) +
      section("Source context", preBlock(item.snippet));
  } else if (kind === "routes") {
    body =
      section("Methods", escapeHtml((item.methods || []).join(", ") || "unknown")) +
      section("AI patterns", escapeHtml((item.aiPatterns || []).join(", ") || "none")) +
      section("Source context", preBlock(item.snippet));
  } else if (kind === "entrypoints") {
    body =
      section("Hook", escapeHtml(item.hook)) +
      section("API target", escapeHtml(item.api)) +
      section("Source context", preBlock(item.snippet));
  }

  return (
    '<div class="grid gap-4">' +
    '<div class="flex flex-wrap items-start gap-2"><h2 class="text-lg font-semibold text-gray-900 flex-1">' +
    escapeHtml(step ? step.title : item.name || item.hook) +
    "</h2>" +
    (badges.length ? '<div class="flex flex-wrap gap-1">' + badges.join("") + "</div>" : "") +
    "</div>" +
    (step && step.note ? '<p class="text-sm text-gray-500">' + escapeHtml(step.note) + "</p>" : "") +
    locBar(item) +
    body +
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
          escapeHtml(step.title) +
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

  const noteEl = document.querySelector("#flow-note");
  if (noteEl) noteEl.textContent = trace.flowNote || "";

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
