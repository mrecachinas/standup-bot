import { Link as RouterLink } from "react-router";
import { Button, UnderlineNav } from "@primer/react";
import { GlobeIcon, HashIcon, PauseIcon, PencilIcon, PeopleIcon, PlayIcon, SyncIcon } from "@primer/octicons-react";
import type { Standup } from "../api/types";
import { pluralize } from "../lib/format";
import { paths, standupTabPath, type StandupTab } from "../paths";
import { PageHeader } from "./PageHeader";
import { StandupStatusLabel } from "./StatusLabel";
import styles from "./StandupHeader.module.css";

/** The StandupSerializer keys the header uses; pass the API payload as-is. */
export type StandupHeaderStandup = Pick<Standup, "id" | "name" | "platform" | "platform_channel" | "active" | "respect_timezone"> &
  Partial<Pick<Standup, "platform_label" | "platform_channel_name" | "schedule_summary" | "participants_count" | "active_participants_count">>;

export interface StandupHeaderProps {
  standup: StandupHeaderStandup;
  /** Which tab is current. */
  active: StandupTab;
  /** Pause when active, resume when paused. Omit to hide the button. */
  onPauseResume?: () => void | Promise<void>;
  /** Disables the pause/resume button while its request runs. */
  pauseResumeBusy?: boolean;
  /** Overrides the participant count (defaults to active_participants_count, then participants_count). */
  participantCount?: number;
}

export function StandupHeader({ standup, active, onPauseResume, pauseResumeBusy = false, participantCount }: StandupHeaderProps) {
  const count = participantCount ?? standup.active_participants_count ?? standup.participants_count;
  const platformLabel = standup.platform_label ?? (standup.platform === "teams" ? "Microsoft Teams" : "Slack");
  const channel = (standup.platform_channel_name || standup.platform_channel || "No channel").replace(/^#/, "");
  const ChannelIcon = standup.platform === "teams" ? PeopleIcon : HashIcon;

  const tabs: { key: StandupTab; label: string; counter?: number }[] = [
    { key: "overview", label: "Overview" },
    { key: "insights", label: "Insights" },
    { key: "responses", label: "Responses" },
    { key: "participants", label: "Participants", counter: count },
    { key: "schedule", label: "Schedule" },
    { key: "reports", label: "Reports" },
    { key: "chat", label: platformLabel },
    { key: "settings", label: "Settings" },
  ];

  return (
    <div className={styles.header}>
      <PageHeader
        title={standup.name}
        trailingVisual={<StandupStatusLabel active={standup.active} />}
        breadcrumbs={[{ label: "Standups", to: paths.standups }, { label: standup.name }]}
        actions={
          <div className={styles.actions}>
            {onPauseResume && (
              <Button
                leadingVisual={standup.active ? PauseIcon : PlayIcon}
                onClick={() => void onPauseResume()}
                loading={pauseResumeBusy}
                aria-label={`${standup.active ? "Pause" : "Resume"} ${standup.name}`}
              >
                {standup.active ? "Pause" : "Resume"}
              </Button>
            )}
            {active !== "settings" && (
              <Button as={RouterLink} to={standupTabPath(standup.id, "settings")} variant="primary" leadingVisual={PencilIcon}>
                Edit standup
              </Button>
            )}
          </div>
        }
      >
        <div className={styles.meta}>
          <span title={`${platformLabel} channel`}>
            <ChannelIcon size={16} />
            {channel}
          </span>
          {standup.schedule_summary && (
            <span>
              <SyncIcon size={16} />
              {standup.schedule_summary}
            </span>
          )}
          {count !== undefined && (
            <span>
              <PeopleIcon size={16} />
              {pluralize(count, "participant")}
            </span>
          )}
          <span>
            <GlobeIcon size={16} />
            {standup.respect_timezone ? "Participant timezones" : "UTC"}
          </span>
        </div>
      </PageHeader>

      <UnderlineNav aria-label={`${standup.name} sections`}>
        {tabs.map((tab) => (
          <UnderlineNav.Item
            key={tab.key}
            as={RouterLink}
            to={standupTabPath(standup.id, tab.key)}
            aria-current={tab.key === active ? "page" : undefined}
            counter={tab.counter}
          >
            {tab.label}
          </UnderlineNav.Item>
        ))}
      </UnderlineNav>
    </div>
  );
}
