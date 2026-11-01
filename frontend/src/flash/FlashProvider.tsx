import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { FlashMessage } from "../api/types";
import { FlashContext, type FlashEntry } from "./context";

/** Success toasts dismiss themselves after this long; warnings and errors stay. */
export const SUCCESS_TIMEOUT_MS = 6000;

export function FlashProvider({ children }: { children: ReactNode }) {
  const [messages, setMessages] = useState<FlashEntry[]>([]);
  const nextId = useRef(1);
  const timers = useRef(new Map<number, ReturnType<typeof setTimeout>>());

  const dismiss = useCallback((id: number) => {
    const timer = timers.current.get(id);
    if (timer) clearTimeout(timer);
    timers.current.delete(id);
    setMessages((current) => current.filter((entry) => entry.id !== id));
  }, []);

  const push = useCallback(
    (message: FlashMessage) => {
      if (!message.message) return;
      const id = nextId.current++;
      setMessages((current) => {
        const withoutDuplicate = current.filter((entry) => !(entry.type === message.type && entry.message === message.message));
        return [...withoutDuplicate, { ...message, id }];
      });
      if (message.type === "success") timers.current.set(id, setTimeout(() => dismiss(id), SUCCESS_TIMEOUT_MS));
    },
    [dismiss],
  );

  const clear = useCallback(() => {
    timers.current.forEach((timer) => clearTimeout(timer));
    timers.current.clear();
    setMessages([]);
  }, []);

  useEffect(() => {
    const pending = timers.current;
    return () => pending.forEach((timer) => clearTimeout(timer));
  }, []);

  const value = useMemo(() => ({ messages, push, dismiss, clear }), [messages, push, dismiss, clear]);

  return <FlashContext.Provider value={value}>{children}</FlashContext.Provider>;
}
