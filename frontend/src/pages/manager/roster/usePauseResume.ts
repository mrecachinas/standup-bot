import { useCallback } from "react";
import { patch } from "../../../api/client";
import type { Standup } from "../../../api/types";
import { useMutation } from "../../../hooks/useMutation";

/** PATCH /api/standups/:id/pause|resume, then hand the updated standup back and refresh the sidebar. */
export function usePauseResume(standup: Pick<Standup, "id" | "active"> | undefined, onUpdated: (standup: Standup) => void) {
  const mutation = useMutation(
    (id: number, active: boolean) => patch<{ standup: Standup; notice?: string }>(`/api/standups/${id}/${active ? "pause" : "resume"}`),
    { refreshSidebar: true, flashError: true, onSuccess: (result) => onUpdated(result.standup) },
  );
  const { run } = mutation;

  const toggle = useCallback(async () => {
    if (!standup) return;
    await run(standup.id, standup.active);
  }, [run, standup]);

  return { toggle, busy: mutation.loading };
}
