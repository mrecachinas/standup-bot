import { useState } from "react";
import { useNavigate, useParams } from "react-router";
import { ConfirmationDialog } from "@primer/react";
import { del, patch, post } from "../../api/client";
import type { AddManagerResult, ParticipantMutationResult, ParticipantParams, ParticipantsConsole, RemoveManagerResult, RosterParticipant } from "../../api/types/roster";
import { ErrorBanner, StandupHeader } from "../../components";
import { useMutation } from "../../hooks/useMutation";
import { paths } from "../../paths";
import { useSession } from "../../session/context";
import { AddPeopleSection } from "./roster/AddPeopleSection";
import { EditParticipantDialog } from "./roster/EditParticipantDialog";
import { ManagersSection } from "./roster/ManagersSection";
import { removeManagerCopy } from "./roster/managerCopy";
import { PeopleSection, type ParticipantAction } from "./roster/PeopleSection";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";

type Outcome = { notice?: string; can_manage?: boolean };

interface Confirmation {
  participant: RosterParticipant;
  title: string;
  message: string;
  confirm: string;
  danger: boolean;
  request: () => Promise<Outcome>;
}

export function StandupParticipantsPage() {
  const { id = "" } = useParams();
  const navigate = useNavigate();
  const session = useSession();
  const base = `/api/standups/${id}`;
  const { data, error, loading, reload, setStandup } = useStandupPage<ParticipantsConsole>(`${base}/participants?view=console`, "Participants");
  const [editing, setEditing] = useState<RosterParticipant | null>(null);
  const [confirming, setConfirming] = useState<Confirmation | null>(null);
  const [busyId, setBusyId] = useState<number | null>(null);

  // Row actions and manager changes share one error banner. Losing your own
  // manager role means losing access, so leave for the standups list.
  const action = useMutation((request: () => Promise<Outcome>) => request(), {
    onSuccess: async (outcome) => {
      if (outcome.can_manage === false) {
        await session.refresh().catch(() => undefined);
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

  if (!data) return <StandupLoadState error={error} onRetry={reload} title="Participants" />;

  const { standup, platform, managers, summary, participants } = data;

  const runFor = async (participant: RosterParticipant, request: () => Promise<Outcome>) => {
    setBusyId(participant.id);
    await action.run(request);
    setBusyId(null);
  };

  const removeManager = (userId: number) => () => del<RemoveManagerResult>(`${base}/managers/${userId}`);

  const handleAction = (kind: ParticipantAction, participant: RosterParticipant) => {
    const name = participant.display_name;
    switch (kind) {
      case "edit":
        save.reset();
        setEditing(participant);
        return;
      case "toggle-active":
        void runFor(participant, () => patch<ParticipantMutationResult>(`${base}/participants/${participant.id}`, { participant: { active: !participant.active } }));
        return;
      case "make-manager":
        setConfirming({
          participant,
          title: `Make ${name} a manager?`,
          message: `Let ${name} manage ${standup.name}? They'll be able to change its settings, people, and schedule.`,
          confirm: "Make manager",
          danger: false,
          request: () => post<AddManagerResult>(`${base}/managers`, { participant_id: participant.id }),
        });
        return;
      case "remove-manager":
        if (participant.manager_user_id === null) return;
        setConfirming({
          participant,
          ...removeManagerCopy(name, standup.name, participant.manager_user_id === session.bootstrap.user?.id),
          danger: true,
          request: removeManager(participant.manager_user_id),
        });
        return;
      case "remove":
        setConfirming({
          participant,
          title: `Remove ${name}?`,
          message: `Remove ${name} from ${standup.name}?`,
          confirm: "Remove",
          danger: true,
          request: async () => {
            await del(`${base}/participants/${participant.id}`);
            return { notice: `Removed ${name} from ${standup.name}.` };
          },
        });
    }
  };

  return (
    <div className={layout.page}>
      <StandupHeader standup={standup} active="participants" participantCount={summary.active_count} onStandupChange={setStandup} />

      {error && !loading && <ErrorBanner error={error} title="Couldn't refresh participants" />}
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

      {confirming && (
        <ConfirmationDialog
          title={confirming.title}
          onClose={(gesture) => {
            setConfirming(null);
            if (gesture === "confirm") void runFor(confirming.participant, confirming.request);
          }}
          confirmButtonContent={confirming.confirm}
          confirmButtonType={confirming.danger ? "danger" : "primary"}
        >
          {confirming.message}
        </ConfirmationDialog>
      )}
    </div>
  );
}
