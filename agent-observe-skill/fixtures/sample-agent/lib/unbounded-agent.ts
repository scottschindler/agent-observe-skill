import { generateText, isLoopFinished } from "ai";
import { openai } from "@ai-sdk/openai";

export async function runUnbounded() {
  return generateText({
    model: openai("gpt-4.1-mini"),
    prompt: "Research this topic thoroughly",
    stopWhen: isLoopFinished(),
  });
}
