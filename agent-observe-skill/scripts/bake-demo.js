#!/usr/bin/env node
const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "../..");
const reportPath = path.join(repoRoot, "agent-observe-skill/fixtures/sample-agent/.agent-observe-skill/agent-report.html");
const uiPath = path.join(__dirname, "_report-ui-script.js");
const outPath = path.join(repoRoot, "demo/index.html");

const report = fs.readFileSync(reportPath, "utf8");
const ui = fs.readFileSync(uiPath, "utf8");
const traceMatch = report.match(/const trace = ([\s\S]*?);\s*\/\/ Embedded/);
if (!traceMatch) {
  console.error("Could not extract trace from agent-report.html. Run skill.sh on the fixture first.");
  process.exit(1);
}

let traceJson = traceMatch[1].replace(/"root":"[^"]*"/, '"root":"/sample-agent"');
const head = report.match(/<head>[\s\S]*?<\/head>/)[0].replace(
  "<title>Agent Observe Report</title>",
  "<title>Agent Observe — Demo</title>",
);
const bodyInner = report.match(/<main class="flex-grow[\s\S]*?<\/main>/)[0].replace("pt-10", "pt-4");

let agentCount = "?";
let riskCount = "?";
try {
  const trace = JSON.parse(traceJson);
  agentCount = trace.summary?.agents ?? trace.agents?.length ?? "?";
  riskCount = trace.summary?.risks ?? trace.risks?.length ?? "?";
} catch {
  // Keep the demo bake resilient if the embedded trace changes shape.
}

const demo = `<!doctype html>
<html lang="en">
${head}
  <link rel="stylesheet" href="../assets/theme.css" />
  <body class="bg-black text-[#ededed] selection:bg-[#0070f3] selection:text-white min-h-screen flex flex-col relative overflow-x-hidden font-sans">
    <div class="v-grid-bg fixed inset-0 pointer-events-none" aria-hidden="true"></div>
    <div class="v-glow fixed inset-x-0 top-0 h-[420px] pointer-events-none" aria-hidden="true"></div>
    <header class="v-nav sticky top-0 z-50 relative">
      <div class="max-w-6xl mx-auto px-6 h-14 flex items-center justify-between">
        <div class="flex items-center gap-3 text-sm">
          <span class="v-pill">ai@6.0.0</span>
          <span class="text-[#666] hidden sm:inline">${agentCount} agents · ${riskCount} risks</span>
        </div>
        <nav class="flex items-center gap-5 text-sm">
          <a href="../" class="text-[#888] hover:text-[#ededed] transition-colors">Home</a>
          <a href="https://github.com/scottschindler/agent-observe-skill" class="text-[#888] hover:text-[#ededed] transition-colors" target="_blank" rel="noopener noreferrer">GitHub</a>
        </nav>
      </div>
    </header>
    ${bodyInner}
    <script>
      const trace = ${traceJson};
      ${ui}
    </script>
  </body>
</html>
`;

fs.writeFileSync(outPath, demo);
console.log(`Demo written to ${outPath}`);
