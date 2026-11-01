import { round2 } from "./scale";

interface YAxisProps {
  max: number;
  left: number;
  top: number;
  plotHeight: number;
  width: number;
  suffix?: string;
  right?: number;
}

/** Baseline, middle and top gridlines with labels. */
export function YAxis({ max, left, top, plotHeight, width, suffix = "", right = 0 }: YAxisProps) {
  const ticks = [0, max / 2, max];
  return (
    <>
      {ticks.map((tick) => {
        const y = round2(top + plotHeight - (tick / max) * plotHeight);
        return (
          <g key={tick}>
            <line x1={left} x2={width - right} y1={y} y2={y} className={tick === 0 ? "axis-line" : "grid-line"} />
            <text x={left - 8} y={y + 3.5} textAnchor="end">
              {`${Math.round(tick)}${suffix}`}
            </text>
          </g>
        );
      })}
    </>
  );
}
