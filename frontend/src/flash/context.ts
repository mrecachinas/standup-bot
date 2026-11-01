import { createContext, useContext } from "react";
import type { FlashMessage } from "../api/types";

export interface FlashEntry extends FlashMessage {
  id: number;
}

export interface FlashValue {
  messages: FlashEntry[];
  /** Show a toast, e.g. `push({ type: "success", message: response.notice })`. */
  push: (message: FlashMessage) => void;
  dismiss: (id: number) => void;
  clear: () => void;
}

export const FlashContext = createContext<FlashValue>({
  messages: [],
  push: () => {},
  dismiss: () => {},
  clear: () => {},
});

export function useFlash(): FlashValue {
  return useContext(FlashContext);
}
