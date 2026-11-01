import { DatabaseIcon, HashIcon, PeopleIcon, ServerIcon, StackIcon, type Icon } from "@primer/octicons-react";
import type { HealthCheck } from "../../../api/types/admin";
import { RelativeTime } from "../../../components/RelativeTime";
import { StatusLabel } from "../../../components/StatusLabel";
import { KeyValueList } from "../../manager/insights/Panel";
import styles from "./admin.module.css";

const ICONS: Record<string, Icon> = {
  database: DatabaseIcon,
  stack: StackIcon,
  hash: HashIcon,
  people: PeopleIcon,
};

/** One health check (database, job queue, Slack, Teams) with its details. */
export function HealthCard({ check }: { check: HealthCheck }) {
  const IconComponent = ICONS[check.icon] ?? ServerIcon;
  const headingId = `health-${check.key.replace(/_/g, "-")}-heading`;

  return (
    <section id={`health-${check.key.replace(/_/g, "-")}`} className={styles.healthCard} data-status={check.status} aria-labelledby={headingId}>
      <span className={styles.healthIcon} aria-hidden="true">
        <IconComponent size={16} />
      </span>
      <div className={styles.healthBody}>
        <div className={styles.healthTitleRow}>
          <h2 id={headingId} className={styles.healthTitle}>
            {check.label}
          </h2>
          <StatusLabel tone={check.status_tone}>{check.status_label}</StatusLabel>
        </div>
        <KeyValueList
          items={check.details.map((detail) => ({
            label: detail.label,
            value: detail.time ? <RelativeTime datetime={detail.time} /> : (detail.value ?? "—"),
            strong: detail.strong,
          }))}
        />
      </div>
    </section>
  );
}
