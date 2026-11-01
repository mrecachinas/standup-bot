import { clamp, round2 } from "./scale";
import styles from "./charts.module.css";

export interface SparklineProps {
  /** Percentages (0–100); null/undefined entries are skipped. */
  values: (number | null | undefined)[];
  width?: number;
  height?: number;
}

/** A tiny completion-trend line; "—" with fewer than two points. */
export function Sparkline({ values, width = 96, height = 28 }: SparklineProps) {
  const series = values.filter((value): value is number => typeof value === "number" && !Number.isNaN(value));
  if (series.length < 2) return <span className={styles.subtle}>—</span>;

  const step = width / (series.length - 1);
  const coords = series.map((value, index) => [round2(step * index), round2(height - 2 - (clamp(value, 0, 100) / 100) * (height - 4))] as const);
  const line = coords.map(([x, y]) => `${x},${y}`).join(" ");
  const area = `M0,${height} ${coords.map(([x, y]) => `L${x},${y}`).join(" ")} L${width},${height} Z`;

  return (
    <svg
      className={styles.sparkline}
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      role="img"
      aria-label={`Completion trend: ${series.map((value) => `${Math.round(value)}%`).join(", ")}`}
    >
      <path d={area} className="area" />
      <polyline points={line} className="line" />
    </svg>
  );
}
