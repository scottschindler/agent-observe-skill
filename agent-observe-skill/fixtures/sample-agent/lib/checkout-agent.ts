import { ToolLoopAgent, stepCountIs, tool } from "ai";
import { openai } from "@ai-sdk/openai";
import { z } from "zod";

const chargeCard = tool({
  description: "Charge the customer card",
  inputSchema: z.object({ amount: z.number() }),
  execute: async ({ amount }) => fetch("/api/charge", { method: "POST", body: String(amount) }),
});

const done = tool({
  description: "Signal checkout completion",
  inputSchema: z.object({ summary: z.string() }),
});

export const checkoutAgent = new ToolLoopAgent({
  model: openai("gpt-4.1-mini"),
  instructions: "You are a checkout assistant.",
  tools: { chargeCard, done },
  stopWhen: stepCountIs(5),
  toolChoice: "required",
});
