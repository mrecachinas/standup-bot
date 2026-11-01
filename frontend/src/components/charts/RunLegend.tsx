import styles from "./charts.module.css";

/** Swatches for RunBreakdownChart; include "Pending" when a run is still open. */
export function RunLegend({ pending = false }: { pending?: boolean }) {
  const items: [string, string][] = [
    ["completed", "Completed"],
    ["skipped", "Skipped"],
  ];
  if (pending) items.push(["pending", "Pending"]);
  items.push(["missed", "Missed"]);

  return (
    <div className={styles.legend}>
      {items.map(([key, text]) => (
        <span key={key}>
          <i className={`swatch-${key}`} aria-hidden="true" />
          {text}
        </span>
      ))}
    </div>
  );
}
