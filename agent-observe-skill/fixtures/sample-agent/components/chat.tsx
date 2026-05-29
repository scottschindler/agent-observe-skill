"use client";
import { useChat } from "ai/react";

export function Chat() {
  return useChat({ api: "/api/chat" });
}
