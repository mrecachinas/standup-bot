import { act, renderHook, waitFor } from "@testing-library/react";
import type { ReactNode } from "react";
import { describe, expect, it, vi } from "vitest";
import { post } from "../api/client";
import { FlashContext, type FlashValue } from "../flash/context";
import { jsonResponse } from "../test/fixtures";
import { useApi } from "./useApi";
import { useMutation } from "./useMutation";

describe("useApi", () => {
  it("loads, reloads and reports errors", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(jsonResponse({ name: "Daily" }))
      .mockResolvedValueOnce(jsonResponse({ error: "Standup not found" }, 404));
    vi.stubGlobal("fetch", fetchMock);

    const { result } = renderHook(() => useApi<{ name: string }>("/api/standups/1"));
    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.data).toEqual({ name: "Daily" });

    act(() => result.current.reload());
    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.error?.message).toBe("Standup not found");
    expect(result.current.data).toEqual({ name: "Daily" });
  });

  it("skips a null path", () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const { result } = renderHook(() => useApi(null));
    expect(result.current.loading).toBe(false);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("useMutation", () => {
  it("flashes the API notice and exposes field errors", async () => {
    const push = vi.fn();
    const flash: FlashValue = { messages: [], push, dismiss: vi.fn(), clear: vi.fn() };
    const wrapper = ({ children }: { children: ReactNode }) => <FlashContext.Provider value={flash}>{children}</FlashContext.Provider>;
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockResolvedValueOnce(jsonResponse({ notice: "Standup paused." }))
        .mockResolvedValueOnce(jsonResponse({ errors: ["Name can't be blank"], field_errors: { name: ["can't be blank"] } }, 422)),
    );

    const { result } = renderHook(() => useMutation((body?: unknown) => post<{ notice?: string }>("/api/standups/1/pause", body)), { wrapper });

    await act(async () => {
      await expect(result.current.run()).resolves.toEqual({ notice: "Standup paused." });
    });
    expect(push).toHaveBeenCalledWith({ type: "success", message: "Standup paused." });

    await act(async () => {
      await expect(result.current.run({})).resolves.toBeUndefined();
    });
    expect(result.current.error?.fieldError("name")).toBe("can't be blank");
  });
});
