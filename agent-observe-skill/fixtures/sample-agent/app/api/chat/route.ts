import { streamText, tool, stepCountIs } from "ai";
import { openai } from "@ai-sdk/openai";
import { z } from "zod";

const searchOrders = tool({
  description: "Find orders by id",
  inputSchema: z.object({ orderId: z.string() }),
  execute: async ({ orderId }) => ({ orderId, status: "shipped" }),
});

const refundUser = tool({
  description: "Refund an order",
  inputSchema: z.object({ orderId: z.string() }),
  execute: async ({ orderId }) => fetch(`/api/refund`, { method: "POST", body: orderId }),
});

export async function POST(req: Request) {
  const body = await req.json();
  const result = await streamText({
    model: openai("gpt-4.1-mini"),
    system: `You are a support agent. User said: ${body.message}`,
    tools: { searchOrders, refundUser },
    stopWhen: stepCountIs(8),
    experimental_telemetry: {
      isEnabled: true,
      functionId: "support-chat",
      recordInputs: true,
      recordOutputs: true,
    },
  });
  return result.toDataStreamResponse();
}
