import { useId } from "react";
import { CHART_WIDTH } from "./runs";
import { ChartEmpty } from "./ChartEmpty";
import { YAxis } from "./YAxis";
import { clamp, round2 } from "./scale";
import styles from "./charts.module.css";

export interface RatePoint {
  /** X-axis label, e.g. "Oct 2". */
  label: string;
  /** Percentage, 0–100. */
  value: number;
  /** Tooltip; defaults to "<label>: <value>%". */
  title?: string;
}

export interface RateLineChartProps {
  points: RatePoint[];
  height?: number;
  width?: number;
  label?: string;
}

/** Line + area for a percentage series (0–100). */
export function RateLineChart({ points, height = 200, width = CHART_WIDTH, label = "Completion rate" }: RateLineChartProps) {
  const gradientId = `rate-area-${useId().replace(/[^a-zA-Z0-9_-]/g, "")}`;
  if (points.length === 0) return <ChartEmpty message="Not enough data to chart yet." />;

  const left = 36;
  const bottom = 22;
  const top = 10;
  const right = 8;
  const plotWidth = width - left - right;
  const plotHeight = height - bottom - top;
  const step = points.length > 1 ? plotWidth / (points.length - 1) : 0;
  const coords = points.map((point, index) => {
    const x = points.length > 1 ? left + step * index : left + plotWidth / 2;
    const y = top + plotHeight - (clamp(Number(point.value) || 0, 0, 100) / 100) * plotHeight;
    return [round2(x), round2(y)] as const;
  });
  const labelEvery = Math.min(Math.max(Math.ceil(points.length / 8), 1), 100);
  const baseline = top + plotHeight;
  const area = `M${coords[0][0]},${baseline} ${coords.map(([x, y]) => `L${x},${y}`).join(" ")} L${coords[coords.length - 1][0]},${baseline} Z`;

  return (
    <svg className={styles.chart} viewBox={`0 0 ${width} ${height}`} role="img" aria-label={label}>
      <defs>
        <linearGradient id={gradientId} x1={0} y1={0} x2={0} y2={1}>
          <stop offset="0%" className={styles.gradientStart} />
          <stop offset="100%" className={styles.gradientEnd} />
        </linearGradient>
      </defs>
      <YAxis max={100} left={left} top={top} plotHeight={plotHeight} width={width} suffix="%" right={right} />
      <path d={area} className="area" fill={`url(#${gradientId})`} />
      <polyline points={coords.map(([x, y]) => `${x},${y}`).join(" ")} className="line" />
      {points.map((point, index) => {
        const [x, y] = coords[index];
        return (
          <g key={`${point.label}-${index}`}>
            <circle cx={x} cy={y} r={3} className="point">
              <title>{point.title ?? `${point.label}: ${Math.round(point.value)}%`}</title>
            </circle>
            {(index % labelEvery === 0 || index === points.length - 1) && (
              <text x={x} y={height - 6} textAnchor="middle">
                {point.label}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}
