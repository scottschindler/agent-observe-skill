import { streamText, tool } from "ai";
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

export async function POST() {
  const result = await streamText({
    model: openai("gpt-4.1-mini"),
    system: `You are a support agent. Be concise.`,
    tools: { searchOrders, refundUser },
  });
  return result.toDataStreamResponse();
}
