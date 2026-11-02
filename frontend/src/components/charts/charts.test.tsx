import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { RateLineChart, RunBreakdownChart, RunLegend, Sparkline } from ".";
import { niceMax } from "./scale";

describe("niceMax", () => {
  it("matches ChartsHelper#nice_max", () => {
    expect(niceMax(0)).toBe(2);
    expect(niceMax(2)).toBe(2);
    expect(niceMax(3)).toBe(10);
    expect(niceMax(4)).toBe(10);
    expect(niceMax(10)).toBe(10);
    expect(niceMax(12)).toBe(20);
    expect(niceMax(21)).toBe(50);
    expect(niceMax(60)).toBe(100);
    expect(niceMax(150)).toBe(200);
    expect(niceMax(4.9)).toBe(10);
  });
});

describe("RunBreakdownChart", () => {
  const runs = [
    { date: "2026-10-01", expected: 4, completed: 3, skipped: 1, pending: 0, missed: 0, completion_rate: 75.0 },
    { date: "2026-10-02", expected: 4, completed: 2, skipped: 0, pending: 0, missed: 2, completion_rate: 50.0 },
  ];

  it("renders a stacked bar group per run", () => {
    const { container } = render(<RunBreakdownChart runs={runs} width={480} />);
    const svg = screen.getByRole("img", { name: "Responses per run" });
    expect(svg.getAttribute("viewBox")).toMatch(/^0 0 480 /);
    expect(container.querySelectorAll(".bar-group")).toHaveLength(2);
    expect(container.querySelectorAll(".bar-completed")).toHaveLength(2);
    expect(container.querySelectorAll(".bar-skipped")).toHaveLength(1);
    expect(container.querySelectorAll(".bar-missed")).toHaveLength(1);
    expect(container.textContent).toContain("Oct 2, 2026: 2 completed, 0 skipped, 2 missed (50%)");
  });

  it("uses a nice y-axis maximum", () => {
    const { container } = render(<RunBreakdownChart runs={runs} />);
    const labels = Array.from(container.querySelectorAll("text")).map((node) => node.textContent);
    // Largest run is 4 responses → nice_max 10 → ticks 0, 5, 10.
    expect(labels).toEqual(expect.arrayContaining(["0", "5", "10", "Oct 1", "Oct 2"]));
  });

  it("mentions pending responses", () => {
    const { container } = render(<RunBreakdownChart runs={[{ date: "2026-10-03", expected: 3, completed: 1, skipped: 0, pending: 2, missed: 0, completion_rate: 33.3 }]} />);
    expect(container.textContent).toContain("Oct 3, 2026: 1 completed, 0 skipped, 0 missed, 2 pending (33%)");
  });

  it("shows an empty state without runs", () => {
    render(<RunBreakdownChart runs={[]} />);
    expect(screen.getByText("No standup runs in this period yet.")).toBeInTheDocument();
  });
});

describe("RateLineChart", () => {
  it("draws a line with labelled points", () => {
    const { container } = render(
      <RateLineChart
        points={[
          { label: "Oct 1", value: 75 },
          { label: "Oct 2", value: 50 },
        ]}
      />,
    );
    expect(screen.getByRole("img", { name: "Completion rate" })).toBeInTheDocument();
    expect(container.querySelector("polyline")).not.toBeNull();
    expect(container.querySelectorAll("circle")).toHaveLength(2);
    expect(container.textContent).toContain("Oct 2: 50%");
    expect(container.textContent).toContain("100%");
  });

  it("shows an empty state without points", () => {
    render(<RateLineChart points={[]} />);
    expect(screen.getByText("Not enough data to chart yet.")).toBeInTheDocument();
  });
});

describe("Sparkline", () => {
  it("needs at least two points", () => {
    const { container, rerender } = render(<Sparkline values={[50]} />);
    expect(container).toHaveTextContent("—");

    rerender(<Sparkline values={[50, 75, 100]} />);
    expect(container.querySelector("polyline")).not.toBeNull();
    expect(screen.getByRole("img", { name: "Completion trend: 50%, 75%, 100%" })).toBeInTheDocument();
  });
});

describe("RunLegend", () => {
  it("includes Pending only when asked", () => {
    const { rerender } = render(<RunLegend />);
    expect(screen.queryByText("Pending")).toBeNull();
    rerender(<RunLegend pending />);
    expect(screen.getByText("Pending")).toBeInTheDocument();
  });
});
