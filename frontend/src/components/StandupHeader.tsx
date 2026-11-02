import { Link as RouterLink } from "react-router";
import { Button, IconButton, UnderlineNav } from "@primer/react";
import { GlobeIcon, HashIcon, PauseIcon, PencilIcon, PeopleIcon, PlayIcon, SyncIcon } from "@primer/octicons-react";
import type { Standup } from "../api/types";
import { NARROW_QUERY, useMediaQuery } from "../hooks/useMediaQuery";
import { usePauseResume } from "../hooks/usePauseResume";
import { pluralize } from "../lib/format";
import { paths, standupTabPath, type StandupTab } from "../paths";
import { PageHeader } from "./PageHeader";
import { StandupStatusLabel } from "./StatusLabel";
import styles from "./StandupHeader.module.css";

export interface StandupHeaderProps {
  standup: Standup;
  /** Which tab is current. */
  active: StandupTab;
  /** Shows Pause/Resume; called with the updated standup afterwards. */
  onStandupChange?: (standup: Standup) => void;
  /** Overrides the participant count (defaults to active_participants_count, then participants_count). */
  participantCount?: number;
}

export function StandupHeader({ standup, active, onStandupChange, participantCount }: StandupHeaderProps) {
  const pauseResume = usePauseResume(onStandupChange);
  const count = participantCount ?? standup.active_participants_count ?? standup.participants_count;
  const platformLabel = standup.platform_label;
  const channel = standup.channel_label.replace(/^#/, "") || "No channel";
  const ChannelIcon = standup.platform === "teams" ? PeopleIcon : HashIcon;
  // On phones the buttons go icon-only so the title keeps its room.
  const narrow = useMediaQuery(NARROW_QUERY);
  const pauseLabel = `${standup.active ? "Pause" : "Resume"} ${standup.name}`;

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
            {onStandupChange &&
              (narrow ? (
                <IconButton
                  icon={standup.active ? PauseIcon : PlayIcon}
                  onClick={() => void pauseResume.run(standup)}
                  loading={pauseResume.loading}
                  aria-label={pauseLabel}
                />
              ) : (
                <Button leadingVisual={standup.active ? PauseIcon : PlayIcon} onClick={() => void pauseResume.run(standup)} loading={pauseResume.loading} aria-label={pauseLabel}>
                  {standup.active ? "Pause" : "Resume"}
                </Button>
              ))}
            {active !== "settings" &&
              (narrow ? (
                <IconButton as={RouterLink} to={standupTabPath(standup.id, "settings")} variant="primary" icon={PencilIcon} aria-label="Edit standup" />
              ) : (
                <Button as={RouterLink} to={standupTabPath(standup.id, "settings")} variant="primary" leadingVisual={PencilIcon}>
                  Edit standup
                </Button>
              ))}
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
            {standup.timezone_label}
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
