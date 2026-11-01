/** Rounds to 2 decimal places, like Ruby's Float#round(2). */
export function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max);
}

/** A "nice", even y-axis maximum at or above `value` (ChartsHelper#nice_max). */
export function niceMax(value: number): number {
  const n = Math.trunc(value);
  if (n <= 2) return 2;

  const magnitude = 10 ** Math.floor(Math.log10(n));
  const candidate = [1, 2, 2.5, 5, 10].map((factor) => Math.ceil(factor * magnitude)).find((c) => c >= n && c % 2 === 0);
  return candidate ?? n + (n % 2);
}
