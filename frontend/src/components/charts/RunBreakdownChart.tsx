import { formatShortDate, parseApiDate } from "../../lib/format";
import type { RunTotals } from "../../api/types";
import { CHART_WIDTH, RUN_SEGMENTS, runSummary } from "./runs";
import { ChartEmpty } from "./ChartEmpty";
import { YAxis } from "./YAxis";
import { niceMax, round2 } from "./scale";
import styles from "./charts.module.css";

export interface RunBreakdownChartProps {
  runs: RunTotals[];
  height?: number;
  width?: number;
  label?: string;
}

/** Stacked columns, one per standup run: completed / skipped / pending / missed. */
export function RunBreakdownChart({ runs, height = 200, width = CHART_WIDTH, label = "Responses per run" }: RunBreakdownChartProps) {
  if (runs.length === 0) return <ChartEmpty message="No standup runs in this period yet." />;

  const left = 32;
  const bottom = 22;
  const top = 8;
  const plotWidth = width - left;
  const plotHeight = height - bottom - top;
  const max = niceMax(Math.max(...runs.map((run) => RUN_SEGMENTS.reduce((sum, key) => sum + run[key], 0))));
  const band = plotWidth / runs.length;
  const barWidth = Math.min(band * 0.62, 28);
  const labelEvery = Math.min(Math.max(Math.ceil(runs.length / 10), 1), 100);

  return (
    <svg className={styles.chart} viewBox={`0 0 ${width} ${height}`} role="img" aria-label={label}>
      <YAxis max={max} left={left} top={top} plotHeight={plotHeight} width={width} />
      {runs.map((run, index) => {
        const date = parseApiDate(run.date);
        const x = left + band * index + (band - barWidth) / 2;
        const segments = [];
        let y = top + plotHeight;
        for (const key of RUN_SEGMENTS) {
          const value = run[key];
          if (value === 0) continue;
          const segmentHeight = (value / max) * plotHeight;
          y -= segmentHeight;
          segments.push(<rect key={key} x={round2(x)} y={round2(y)} width={round2(barWidth)} height={round2(segmentHeight)} className={`bar-${key}`} />);
        }

        return (
          <g key={`${run.date}-${index}`}>
            <g className="bar-group">
              <title>{runSummary(run)}</title>
              {segments}
              <rect x={round2(left + band * index)} y={top} width={round2(band)} height={plotHeight} fill="transparent" />
            </g>
            {index % labelEvery === 0 && date && (
              <text x={round2(x + barWidth / 2)} y={height - 6} textAnchor="middle">
                {formatShortDate(date)}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}
