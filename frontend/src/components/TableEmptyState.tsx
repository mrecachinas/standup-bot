import { EmptyState, type EmptyStateProps } from "./EmptyState";
import styles from "./TableEmptyState.module.css";

/**
 * An EmptyState for a Primer Table.Container. The container is a CSS grid, so
 * anything that isn't a Table.* part would otherwise land in the actions cell.
 */
export function TableEmptyState(props: EmptyStateProps) {
  return (
    <div className={styles.row}>
      <EmptyState size="small" headingLevel="h3" {...props} />
    </div>
  );
}
