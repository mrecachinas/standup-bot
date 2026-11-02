import { useId, type ReactNode } from "react";
import { clsx } from "clsx";
import { Heading } from "@primer/react";
import styles from "./Panel.module.css";

export interface PanelProps {
  title: ReactNode;
  description?: ReactNode;
  /** Right side of the header (buttons, a legend…). */
  actions?: ReactNode;
  footer?: ReactNode;
  /** No body padding, for lists and tables that run edge to edge. */
  flush?: boolean;
  headingLevel?: "h2" | "h3";
  id?: string;
  /** Id for the heading, e.g. for a table's aria-labelledby. */
  headingId?: string;
  className?: string;
  children?: ReactNode;
}

/** A bordered section with a header. */
export function Panel({ title, description, actions, footer, flush = false, headingLevel = "h2", id, headingId: headingIdProp, className, children }: PanelProps) {
  const generatedId = useId();
  const headingId = headingIdProp ?? generatedId;
  return (
    <section id={id} className={clsx(styles.panel, className)} aria-labelledby={headingId}>
      <div className={styles.header}>
        <div className={styles.headerText}>
          <Heading as={headingLevel} id={headingId} className={styles.title}>
            {title}
          </Heading>
          {description && <p className={styles.description}>{description}</p>}
        </div>
        {actions && <div className={styles.actions}>{actions}</div>}
      </div>
      {children !== undefined && children !== null && children !== false && <div className={flush ? styles.flush : styles.body}>{children}</div>}
      {footer && <div className={styles.footer}>{footer}</div>}
    </section>
  );
}

/** A divided list inside a flush Panel. */
export function PanelList({ children, label, className }: { children: ReactNode; label?: string; className?: string }) {
  return (
    <ul className={clsx(styles.list, className)} aria-label={label}>
      {children}
    </ul>
  );
}

export interface PanelListItemProps {
  leadingVisual?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  trailing?: ReactNode;
  id?: string;
  children?: ReactNode;
}

export function PanelListItem({ leadingVisual, title, description, trailing, id, children }: PanelListItemProps) {
  return (
    <li id={id} className={styles.item}>
      {leadingVisual && <span className={styles.itemVisual}>{leadingVisual}</span>}
      <div className={styles.itemText}>
        <div className={styles.itemTitle}>{title}</div>
        {description && <div className={styles.itemDescription}>{description}</div>}
        {children}
      </div>
      {trailing && <div className={styles.itemTrailing}>{trailing}</div>}
    </li>
  );
}

/** Term/value pairs ("Channel  #standup"). */
export function KeyValueList({ items, className }: { items: { label: ReactNode; value: ReactNode; mono?: boolean; strong?: boolean }[]; className?: string }) {
  return (
    <dl className={clsx(styles.kv, className)}>
      {items.map((item, index) => (
        <div key={index} className={styles.kvRow}>
          <dt>{item.label}</dt>
          <dd className={clsx(item.mono && styles.mono, item.strong && styles.strong)}>{item.value}</dd>
        </div>
      ))}
    </dl>
  );
}

/** A short muted line for empty lists inside a Panel. */
export function PanelEmptyText({ children }: { children: ReactNode }) {
  return <p className={styles.emptyText}>{children}</p>;
}
