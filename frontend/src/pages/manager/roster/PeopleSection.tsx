import { ActionList, ActionMenu, Button, IconButton, VisuallyHidden } from "@primer/react";
import { DataTable, Table } from "@primer/react/experimental";
import { KebabHorizontalIcon, PencilIcon, PeopleIcon } from "@primer/octicons-react";
import type { RosterParticipant } from "../../../api/types/roster";
import { Avatar, EmptyState, StatusLabel } from "../../../components";
import { pluralize } from "../../../lib/format";
import styles from "./roster.module.css";

export type ParticipantAction = "edit" | "toggle-active" | "make-manager" | "remove-manager" | "remove";

export interface PeopleSectionProps {
  participants: RosterParticipant[];
  summary: { participant_count: number; active_count: number; stale_timezone_count: number; holiday_today: boolean };
  platformLabel: string;
  /** Row id currently being changed (disables its menu). */
  busyId?: number | null;
  onAction: (action: ParticipantAction, participant: RosterParticipant) => void;
}

export function PeopleSection({ participants, summary, platformLabel, busyId, onAction }: PeopleSectionProps) {
  const hint = [
    pluralize(summary.participant_count, "participant"),
    `${summary.active_count} active`,
    summary.stale_timezone_count > 0 ? `${pluralize(summary.stale_timezone_count, "timezone")} needing sync` : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <Table.Container>
      <Table.Title as="h2" id="people-heading">
        People
      </Table.Title>
      <Table.Subtitle as="p" id="people-subtitle">
        {hint}
      </Table.Subtitle>
      {summary.holiday_today && (
        <Table.Actions>
          <StatusLabel tone="warning">Holiday today</StatusLabel>
        </Table.Actions>
      )}
      {participants.length > 0 ? (
        <DataTable
          aria-labelledby="people-heading"
          aria-describedby="people-subtitle"
          data={participants}
          columns={[
            {
              header: "Name",
              field: "display_name",
              rowHeader: true,
              width: "growCollapse",
              minWidth: "12rem",
              renderCell: (row) => (
                <div className={styles.person}>
                  <Avatar name={row.display_name || row.platform_user_id} src={row.avatar_url} />
                  <div className={styles.grow}>
                    <div className={styles.cellTitle}>{row.display_name}</div>
                    <div className={`${styles.cellSub} ${styles.mono}`}>{row.platform_user_id}</div>
                  </div>
                </div>
              ),
            },
            {
              header: "Status",
              id: "status",
              width: "auto",
              renderCell: (row) => (
                <div className={styles.labels}>
                  <StatusLabel tone={row.status_tone}>{row.status_label}</StatusLabel>
                  {row.manager && <StatusLabel tone="info">Manager</StatusLabel>}
                </div>
              ),
            },
            {
              header: "Timezone",
              id: "timezone",
              width: "auto",
              renderCell: (row) => (
                <div>
                  <div>{row.timezone_label}</div>
                  <div className={styles.cellSub} title={row.timezone_cache_status_description}>
                    {row.timezone_synced ? "Synced" : <StatusLabel tone="warning">Needs sync</StatusLabel>}
                  </div>
                </div>
              ),
            },
            {
              header: "Availability",
              id: "availability",
              width: "auto",
              renderCell: (row) => (
                <div>
                  <div>{row.vacation_status}</div>
                  {row.holiday_status && <div className={styles.cellSub}>{row.holiday_status}</div>}
                </div>
              ),
            },
            {
              header: () => <VisuallyHidden>Actions</VisuallyHidden>,
              id: "actions",
              align: "end",
              width: "auto",
              renderCell: (row) => <RowActions participant={row} busy={busyId === row.id} onAction={onAction} />,
            },
          ]}
        />
      ) : (
        <EmptyState
          icon={PeopleIcon}
          headingLevel="h3"
          title="No participants yet"
          description={`Add people above, or sync everyone from a ${platformLabel} channel.`}
        />
      )}
    </Table.Container>
  );
}

function RowActions({ participant, busy, onAction }: { participant: RosterParticipant; busy: boolean; onAction: PeopleSectionProps["onAction"] }) {
  const name = participant.display_name;
  return (
    <div className={styles.inlineRow}>
      <Button size="small" variant="invisible" leadingVisual={PencilIcon} aria-label={`Edit ${name}`} onClick={() => onAction("edit", participant)}>
        Edit
      </Button>
      <ActionMenu>
        <ActionMenu.Anchor>
          <IconButton icon={KebabHorizontalIcon} size="small" variant="invisible" aria-label={`More actions for ${name}`} disabled={busy} />
        </ActionMenu.Anchor>
        <ActionMenu.Overlay width="medium">
          <ActionList>
            <ActionList.Item onSelect={() => onAction("toggle-active", participant)}>{participant.active ? "Mark inactive" : "Mark active"}</ActionList.Item>
            {participant.can_make_manager && <ActionList.Item onSelect={() => onAction("make-manager", participant)}>Make manager</ActionList.Item>}
            {participant.can_remove_manager && <ActionList.Item onSelect={() => onAction("remove-manager", participant)}>Remove as manager</ActionList.Item>}
            <ActionList.Divider />
            <ActionList.Item variant="danger" onSelect={() => onAction("remove", participant)}>
              Remove from standup
            </ActionList.Item>
          </ActionList>
        </ActionMenu.Overlay>
      </ActionMenu>
    </div>
  );
}
