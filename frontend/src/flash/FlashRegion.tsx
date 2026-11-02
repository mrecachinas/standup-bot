import { useEffect } from "react";
import { Banner } from "@primer/react";
import type { FlashType } from "../api/types";
import { useSession } from "../session/context";
import { useFlash } from "./context";
import styles from "./FlashRegion.module.css";

const VARIANTS: Record<FlashType, "success" | "critical" | "warning"> = {
  success: "success",
  danger: "critical",
  warning: "warning",
};

const TITLES: Record<FlashType, string> = { success: "Success", danger: "Error", warning: "Warning" };

/** Toasts for flash messages from the bootstrap (server flash) and from `useFlash().push`. */
export function FlashRegion() {
  const { messages, push, dismiss } = useFlash();
  const { bootstrap, consumeFlash } = useSession();
  const pending = bootstrap.flash;

  useEffect(() => {
    if (pending.length > 0) consumeFlash().forEach(push);
  }, [pending, consumeFlash, push]);

  return (
    <div className={styles.region} aria-live="polite" aria-label="Notifications" role="region">
      {messages.map((entry) => (
        <Banner
          key={entry.id}
          className={styles.toast}
          variant={VARIANTS[entry.type]}
          title={TITLES[entry.type]}
          hideTitle
          description={entry.message}
          onDismiss={() => dismiss(entry.id)}
        />
      ))}
    </div>
  );
}
