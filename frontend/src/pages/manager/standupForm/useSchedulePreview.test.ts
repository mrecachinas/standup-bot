import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { SchedulePreview, StandupFormPayload } from "../../../api/types/standups";
import { jsonResponse } from "../../../test/fixtures";
import { useSchedulePreview } from "./useSchedulePreview";

const initialPreview: SchedulePreview = { occurrences: [], preview_timezone: "UTC", error: null, empty_message: "initial" };

const payload = {
  platform: { key: "slack" },
  preview_timezone: "UTC",
  detect_preview_timezone: false,
  time_zone_options: [],
  schedule_preview: initialPreview,
} as unknown as StandupFormPayload;

function renderPreview() {
  return renderHook(({ days }: { days: number[] }) => useSchedulePreview(payload, { days }), { initialProps: { days: [1] } });
}

afterEach(() => vi.useRealTimers());

describe("useSchedulePreview", () => {
  it("doesn't fetch the schedule the server already previewed", async () => {
    vi.useFakeTimers();
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);

    const { result } = renderPreview();
    await act(async () => vi.advanceTimersByTime(1000));

    expect(fetchMock).not.toHaveBeenCalled();
    expect(result.current.preview).toBe(initialPreview);
    expect(result.current.loading).toBe(false);
  });

  it("refetches when an in-flight request is cancelled and the schedule changes back", async () => {
    vi.useFakeTimers();
    const pending: ((response: Response) => void)[] = [];
    const fetchMock = vi.fn(() => new Promise<Response>((resolve) => pending.push(resolve)));
    vi.stubGlobal("fetch", fetchMock);

    const { result, rerender } = renderPreview();
    rerender({ days: [1, 2] });
    await act(async () => vi.advanceTimersByTime(300));
    expect(result.current.loading).toBe(true);

    rerender({ days: [1, 2, 3] });
    rerender({ days: [1, 2] });
    await act(async () => vi.advanceTimersByTime(300));

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(result.current.loading).toBe(true);

    const fresh = { ...initialPreview, empty_message: "fresh" };
    await act(async () => pending[1](jsonResponse(fresh)));
    expect(result.current.loading).toBe(false);
    expect(result.current.preview).toEqual(fresh);
  });

  it("stops loading when the schedule returns to what's already shown", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", vi.fn(() => new Promise<Response>(() => {})));

    const { result, rerender } = renderPreview();
    rerender({ days: [1, 2] });
    await act(async () => vi.advanceTimersByTime(300));
    expect(result.current.loading).toBe(true);

    rerender({ days: [1] });
    await act(async () => vi.advanceTimersByTime(1000));

    expect(result.current.loading).toBe(false);
    expect(result.current.preview).toBe(initialPreview);
  });
});
