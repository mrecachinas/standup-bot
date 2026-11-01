import { del } from "../../../api/client";
import type { MemberAvailabilityPayload } from "../../../api/types/member";
import { useMutation } from "../../../hooks/useMutation";

/** "I'm back": DELETE /api/me/availability/clear. Flashes the server's notice. */
export function useClearAway(onSuccess: (result: MemberAvailabilityPayload) => void) {
  return useMutation(() => del<MemberAvailabilityPayload>("/api/me/availability/clear"), { onSuccess, flashError: true });
}
