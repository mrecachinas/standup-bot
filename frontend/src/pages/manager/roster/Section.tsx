import type { ReactNode } from "react";
import { clsx } from "clsx";
import { ChevronRightIcon } from "@primer/octicons-react";
import { parseApiDate } from "../../../components";
import styles from "./roster.module.css";

export interface SectionProps {
  title: ReactNode;
  /** Muted text under the title. */
  hint?: ReactNode;
  /** Right-aligned header content (buttons, counts, filters). */
  actions?: ReactNode;
  /** Use for the heading id so lists/tables can point aria-labelledby at it. */
  titleId?: string;
  footer?: ReactNode;
  children?: ReactNode;
  className?: string;
  id?: string;
}

/** A bordered card with a heading row; children render flush (wrap them in SectionBody for padding). */
export function Section({ title, hint, actions, titleId, footer, children, className, id }: SectionProps) {
  return (
    <section className={clsx(styles.section, className)} aria-labelledby={titleId} id={id}>
      <div className={styles.sectionHeader}>
        <div className={styles.sectionHeading}>
          <h2 className={styles.sectionTitle} id={titleId}>
            {title}
          </h2>
          {hint && <p className={styles.hint}>{hint}</p>}
        </div>
        {actions && <div className={styles.sectionActions}>{actions}</div>}
      </div>
      {children}
      {footer && <div className={styles.sectionFooter}>{footer}</div>}
    </section>
  );
}

export function SectionBody({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={clsx(styles.sectionBody, className)}>{children}</div>;
}

export interface DisclosureProps {
  summary: ReactNode;
  open: boolean;
  onToggle: (open: boolean) => void;
  children: ReactNode;
}

/** A keyboard-accessible <details> row inside a Section. */
export function Disclosure({ summary, open, onToggle, children }: DisclosureProps) {
  return (
    <details className={styles.disclosure} open={open} onToggle={(event) => onToggle(event.currentTarget.open)}>
      <summary>
        <ChevronRightIcon className={styles.chevron} size={16} />
        {summary}
      </summary>
      {children}
    </details>
  );
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Calendar tile ("OCT" over "2") for an ISO date. Decorative: pair it with a written date. */
export function DateTile({ date, blocked = false }: { date: string; blocked?: boolean }) {
  const parsed = parseApiDate(date);
  if (!parsed) return null;
  return (
    <span className={clsx(styles.dateTile, blocked && styles.dateTileBlocked)} aria-hidden="true">
      <span className={styles.dateTileMonth}>{MONTHS[parsed.getMonth()]}</span>
      <span className={styles.dateTileDay}>{parsed.getDate()}</span>
    </span>
  );
}
