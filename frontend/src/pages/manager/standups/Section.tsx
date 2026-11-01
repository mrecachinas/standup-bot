import { useId, type ReactNode } from "react";
import { clsx } from "clsx";
import styles from "./standups.module.css";

export interface SectionProps {
  /** Omit (with no actions) for a card without a header. */
  title?: ReactNode;
  hint?: ReactNode;
  /** Buttons/links on the right of the header. */
  actions?: ReactNode;
  /** No padding around the body (lists and tables run edge to edge). */
  flush?: boolean;
  id?: string;
  className?: string;
  children: ReactNode;
}

/** A bordered card with a header: the console's main content block. */
export function Section({ title, hint, actions, flush = false, id, className, children }: SectionProps) {
  const headingId = useId();
  return (
    <section className={clsx(styles.card, className)} aria-labelledby={title ? headingId : undefined} id={id}>
      {(title || actions) && (
        <div className={styles.cardHeader}>
          {title && (
            <div>
              <h2 className={styles.cardTitle} id={headingId}>
                {title}
              </h2>
              {hint && <p className={styles.cardHint}>{hint}</p>}
            </div>
          )}
          {actions && <div className={styles.cardActions}>{actions}</div>}
        </div>
      )}
      {flush ? children : <div className={styles.cardBody}>{children}</div>}
    </section>
  );
}
