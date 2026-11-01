import styles from "./charts.module.css";

export function ChartEmpty({ message }: { message: string }) {
  return <div className={styles.empty}>{message}</div>;
}
