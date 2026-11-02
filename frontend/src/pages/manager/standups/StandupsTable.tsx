import { Link as RouterLink } from "react-router";
import { ActionList, ActionMenu, IconButton, ProgressBar } from "@primer/react";
import { DataTable, type Column } from "@primer/react/experimental";
import { KebabHorizontalIcon, PauseIcon, PlayIcon } from "@primer/octicons-react";
import type { OverviewStandup } from "../../../api/types/standups";
import { AvatarStack, StatusLabel, StandupStatusLabel } from "../../../components";
import { Sparkline } from "../../../components/charts";
import { paths } from "../../../paths";
import { progressBgForTone } from "./tone";
import styles from "./StandupsTable.module.css";

export interface StandupsTableProps {
  standups: OverviewStandup[];
  labelledBy: string;
  onPauseResume: (standup: OverviewStandup) => void;
}

/** One row per standup: schedule, people, completion, trend, latest run and an actions menu. */
export function StandupsTable({ standups, labelledBy, onPauseResume }: StandupsTableProps) {
  const columns: Column<OverviewStandup>[] = [
    {
      header: "Standup",
      id: "name",
      rowHeader: true,
      width: "growCollapse",
      minWidth: "12rem",
      renderCell: (standup) => (
        <div>
          <div className={styles.nameRow}>
            <RouterLink to={paths.standup(standup.id)} className={styles.name}>
              {standup.name}
            </RouterLink>
            {!standup.active && <StandupStatusLabel active={false} />}
          </div>
          <div className={styles.sub}>{channelLabel(standup)}</div>
        </div>
      ),
    },
    {
      header: "Schedule",
      id: "schedule",
      width: "auto",
      renderCell: (standup) => (
        <div>
          <div>{standup.schedule_summary}</div>
          <div className={styles.sub} title={standup.next_run.title}>
            {standup.next_run.label}
          </div>
        </div>
      ),
    },
    {
      header: "Participants",
      id: "participants",
      width: "auto",
      renderCell: (standup) =>
        standup.participant_count > 0 ? (
          <div>
            <AvatarStack people={standup.participant_avatars} limit={standup.avatar_limit} />
            <div className={styles.sub}>{standup.participant_label}</div>
          </div>
        ) : (
          <span className={styles.muted}>{standup.participant_label}</span>
        ),
    },
    {
      header: "Completion",
      id: "completion",
      width: "auto",
      minWidth: "9rem",
      renderCell: (standup) =>
        standup.expected_responses > 0 ? (
          <div>
            <div className={styles.meter}>
              <ProgressBar
                className={styles.meterBar}
                progress={Math.min(Math.max(standup.completion_rate ?? 0, 0), 100)}
                bg={progressBgForTone(standup.completion_tone)}
                aria-label={`${standup.name} completion`}
              />
              <span className={styles.meterValue}>{standup.completion_rate_label}</span>
            </div>
            <div className={styles.sub}>{standup.completion_sub_label}</div>
          </div>
        ) : (
          <span className={styles.muted}>{standup.completion_sub_label}</span>
        ),
    },
    {
      header: "Trend",
      id: "trend",
      width: "auto",
      renderCell: (standup) => <Sparkline values={standup.trend_rates} />,
    },
    {
      header: "Latest run",
      id: "latest",
      width: "auto",
      renderCell: (standup) =>
        standup.latest_run_summary ? (
          <div className={styles.nameRow}>
            <span className={styles.nowrap}>{standup.latest_run_summary}</span>
            {standup.latest_run_pending && <StatusLabel tone={standup.latest_run_status_tone}>{standup.latest_run_status}</StatusLabel>}
          </div>
        ) : (
          <span className={styles.muted}>{standup.latest_run_status}</span>
        ),
    },
    {
      header: () => <span className={styles.srOnly}>Actions</span>,
      id: "actions",
      align: "end",
      width: "auto",
      renderCell: (standup) => <RowActions standup={standup} onPauseResume={onPauseResume} />,
    },
  ];

  return (
    <div className={styles.scroll}>
      <DataTable aria-labelledby={labelledBy} data={standups} columns={columns} />
    </div>
  );
}

function RowActions({ standup, onPauseResume }: { standup: OverviewStandup; onPauseResume: (standup: OverviewStandup) => void }) {
  const links: [string, string][] = [
    ["Insights", paths.standupAnalytics(standup.id)],
    ["Responses", paths.standupResponses(standup.id)],
    ["People", paths.standupParticipants(standup.id)],
    ["Settings", paths.editStandup(standup.id)],
  ];

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton icon={KebabHorizontalIcon} variant="invisible" size="small" aria-label={`Actions for ${standup.name}`} />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay align="end">
        <ActionList>
          {links.map(([label, to]) => (
            <ActionList.LinkItem key={label} as={RouterLink} to={to}>
              {label}
            </ActionList.LinkItem>
          ))}
          <ActionList.Divider />
          <ActionList.Item onSelect={() => onPauseResume(standup)}>
            <ActionList.LeadingVisual>{standup.active ? <PauseIcon /> : <PlayIcon />}</ActionList.LeadingVisual>
            {standup.active ? "Pause" : "Resume"}
          </ActionList.Item>
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  );
}

function channelLabel(standup: OverviewStandup): string {
  const label = standup.channel_label || standup.platform_channel || "";
  return standup.platform === "slack" ? `#${label.replace(/^#/, "")}` : label;
}
