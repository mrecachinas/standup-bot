import { useState } from "react";
import { useNavigate, useParams } from "react-router";
import { Button, ConfirmationDialog } from "@primer/react";
import { del, patch, post } from "../../api/client";
import type { Standup } from "../../api/types";
import type {
  AddManagerResult,
  ParticipantMutationResult,
  ParticipantParams,
  ParticipantsConsole,
  RemoveManagerResult,
  RosterParticipant,
} from "../../api/types/roster";
import { ErrorBanner, LoadingState, StandupHeader } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useMutation } from "../../hooks/useMutation";
import { paths } from "../../paths";
import { useRefreshSidebar, useSession } from "../../session/context";
import { AddPeopleSection } from "./roster/AddPeopleSection";
import { EditParticipantDialog } from "./roster/EditParticipantDialog";
import { ManagersSection } from "./roster/ManagersSection";
import { PeopleSection, type ParticipantAction } from "./roster/PeopleSection";
import { StandupLoadError } from "./roster/StandupLoadError";
import { usePauseResume } from "./roster/usePauseResume";
import styles from "./roster/roster.module.css";

type Confirmable = Exclude<ParticipantAction, "edit" | "toggle-active">;

interface ActionOutcome {
  notice?: string;
  can_manage?: boolean;
}

export function StandupParticipantsPage() {
  const { id = "" } = useParams();
  const navigate = useNavigate();
  const refreshSidebar = useRefreshSidebar();
  const currentUserId = useSession().bootstrap.user?.id;
  const { data, error, loading, reload, setData } = useApi<ParticipantsConsole>(`/api/standups/${id}/participants?view=console`);
  useDocumentTitle(data ? `People · ${data.standup.name}` : "People");

  const base = `/api/standups/${id}`;
  const [editing, setEditing] = useState<RosterParticipant | null>(null);
  const [confirming, setConfirming] = useState<{ action: Confirmable; participant: RosterParticipant } | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);

  const pauseResume = usePauseResume(data?.standup, (standup: Standup) => setData((current) => ({ ...(current as ParticipantsConsole), standup })));

  // Row actions and manager changes share one error banner. Losing your own
  // manager role means losing access, so leave for the standups list.
  const action = useMutation((call: () => Promise<ActionOutcome>) => call(), {
    onSuccess: async (outcome) => {
      if (outcome.can_manage === false) {
        await refreshSidebar().catch(() => undefined);
        navigate(paths.standups);
        return;
      }
      reload();
    },
  });

  const save = useMutation(
    (participantId: number, params: ParticipantParams) => patch<ParticipantMutationResult>(`${base}/participants/${participantId}`, { participant: params }),
    {
      onSuccess: () => {
        setEditing(null);
        reload();
      },
    },
  );

  const runFor = async (participant: RosterParticipant, call: () => Promise<ActionOutcome>) => {
    setBusyId(participant.id);
    try {
      await action.run(call);
    } finally {
      setBusyId(null);
    }
  };

  const removeManager = (userId: number) => () => del<RemoveManagerResult>(`${base}/managers/${userId}`);

  const handleAction = (kind: ParticipantAction, participant: RosterParticipant) => {
    if (kind === "edit") {
      save.reset();
      setEditing(participant);
    } else if (kind === "toggle-active") {
      void runFor(participant, () =>
        patch<ParticipantMutationResult>(`${base}/participants/${participant.id}`, { participant: { active: !participant.active } }),
      );
    } else {
      setConfirming({ action: kind, participant });
    }
  };

  const handleConfirm = async () => {
    if (!confirming) return;
    const { action: kind, participant } = confirming;
    setConfirming(null);
    if (kind === "make-manager") {
      await runFor(participant, () => post<AddManagerResult>(`${base}/managers`, { participant_id: participant.id }));
    } else if (kind === "remove-manager" && participant.manager_user_id) {
      await runFor(participant, removeManager(participant.manager_user_id));
    } else if (kind === "remove") {
      const standupName = data?.standup.name ?? "this standup";
      await runFor(participant, async () => {
        await del(`${base}/participants/${participant.id}`);
        return { notice: `Removed ${participant.display_name} from ${standupName}.` };
      });
    }
  };

  if (!data) {
    if (error) return <StandupLoadError error={error} title="People" onRetry={reload} />;
    return <LoadingState label="Loading participants…" />;
  }

  const { standup, platform, managers, summary, participants } = data;
  const copy = confirming && confirmCopy(confirming.action, confirming.participant, standup.name, currentUserId);

  return (
    <div className={styles.page}>
      <StandupHeader
        standup={standup}
        active="participants"
        participantCount={summary.active_count}
        onPauseResume={pauseResume.toggle}
        pauseResumeBusy={pauseResume.busy}
      />

      {error && !loading && <ErrorBanner error={error} title="Couldn't refresh participants" action={<Button onClick={reload}>Try again</Button>} />}
      <ErrorBanner error={action.error} title="That didn't work" onDismiss={action.reset} />

      <AddPeopleSection standupId={standup.id} roster={data} onChanged={reload} />

      <ManagersSection standupName={standup.name} managers={managers} onRemove={(manager) => action.run(removeManager(manager.id))} />

      <PeopleSection participants={participants} summary={summary} platformLabel={platform.label} busyId={busyId} onAction={handleAction} />

      {editing && (
        <EditParticipantDialog
          participant={editing}
          saving={save.loading}
          error={save.error}
          onSave={(params) => void save.run(editing.id, params)}
          onClose={() => setEditing(null)}
        />
      )}

      {confirming && copy && (
        <ConfirmationDialog
          title={copy.title}
          onClose={(gesture) => (gesture === "confirm" ? void handleConfirm() : setConfirming(null))}
          confirmButtonContent={copy.confirm}
          confirmButtonType={confirming.action === "make-manager" ? "primary" : "danger"}
        >
          {copy.message}
        </ConfirmationDialog>
      )}
    </div>
  );
}

function confirmCopy(kind: Confirmable, participant: RosterParticipant, standupName: string, currentUserId: number | undefined) {
  const name = participant.display_name;
  switch (kind) {
    case "make-manager":
      return {
        title: `Make ${name} a manager?`,
        message: `Let ${name} manage ${standupName}? They'll be able to change its settings, people, and schedule.`,
        confirm: "Make manager",
      };
    case "remove-manager":
      return participant.manager_user_id === currentUserId
        ? { title: `Stop managing ${standupName}?`, message: `Stop managing ${standupName}? You'll lose access to it.`, confirm: "Stop managing" }
        : { title: `Remove ${name} as a manager?`, message: `Remove ${name} as a manager of ${standupName}?`, confirm: "Remove manager" };
    case "remove":
      return { title: `Remove ${name}?`, message: `Remove ${name} from ${standupName}?`, confirm: "Remove" };
  }
}
