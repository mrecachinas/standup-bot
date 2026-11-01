import type { ReactNode } from "react";
import styles from "./me.module.css";

/** The chat-command hint shown under the member pages. */
export function MemberTip({ children }: { children: ReactNode }) {
  return (
    <p className={styles.tip}>
      {children} DM the bot <code className={styles.code}>away 3</code> to skip the next three days, or <code className={styles.code}>back</code> to
      return early.
    </p>
  );
}
