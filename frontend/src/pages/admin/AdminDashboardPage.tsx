import { Link as RouterLink } from "react-router";
import { Button, Link, ProgressBar } from "@primer/react";
import { DataTable, Table } from "@primer/react/experimental";
import { CheckIcon, SyncIcon } from "@primer/octicons-react";
import type { AdminDashboard, AdminUser } from "../../api/types/admin";
import { Avatar, EmptyState, ErrorBanner, LoadingState, PageHeader, Panel, PanelEmptyText, PanelList, PanelListItem, RelativeTime, StatCard, StatGrid, StatusDot, StatusLabel } from "../../components";
import { pluralize } from "../../lib/format";
import { progressBgForTone } from "../../lib/tone";
import { RunBreakdownChart, RunLegend } from "../../components/charts";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { HealthCard } from "./components/HealthCard";
import layout from "../../styles/layout.module.css";
import styles from "./components/admin.module.css";

export function AdminDashboardPage() {
  useDocumentTitle("Admin");
  const { data, error, loading, reload } = useApi<AdminDashboard>("/api/admin/dashboard");

  const refresh = (
    <Button leadingVisual={SyncIcon} onClick={reload} loading={loading && Boolean(data)}>
      Refresh
    </Button>
  );

  if (!data) {
    return (
      <div className={layout.page}>
        <PageHeader title="Admin" description="Installation health, usage, and recent changes." />
        {error ? <ErrorBanner error={error} title="Couldn't load the admin dashboard" action={<Button onClick={reload}>Try again</Button>} /> : <LoadingState label="Checking installation health…" />}
      </div>
    );
  }

  const { health, stats } = data;

  return (
    <div className={layout.page}>
      <PageHeader
        title="Admin"
        trailingVisual={<StatusLabel tone={health.status_tone}>{health.status_label}</StatusLabel>}
        description={
          <>
            Installation health, usage, and recent changes. Checked <RelativeTime datetime={health.checked_at} />.
          </>
        }
        actions={refresh}
      />

      <ErrorBanner error={error} title="Couldn't refresh the admin dashboard" />

      <div className={styles.healthGrid}>
        {data.health_checks.map((check) => (
          <HealthCard key={check.key} check={check} />
        ))}
      </div>

      <StatGrid>
        <StatCard label="Standups" value={stats.standups_total} hint={`${stats.standups_active} active · ${stats.standups_paused} paused`} />
        <StatCard label="People" value={stats.active_people} hint={`${pluralize(stats.active_participants, "active membership")} across standups`} />
        <StatCard label="Responses (24h)" value={stats.responses_last_24h} hint={`${stats.completed_last_24h} completed`} />
        <StatCard label="Users" value={stats.users_active} hint={`${pluralize(stats.users_admin, "admin")} · ${stats.standup_owners} running standups`} />
      </StatGrid>

      <div className={layout.mainAside}>
        <Panel title="Response activity" description={`Last ${data.activity_days} days, all standups`} actions={<RunLegend pending={data.daily_activity_has_pending} />}>
          <RunBreakdownChart runs={data.daily_activity} height={200} label="Responses per day across the installation" />
        </Panel>

        <Panel title="All-time responses">
          {data.response_totals.total > 0 ? (
            <div className={styles.totals}>
              {data.response_totals.statuses.map((row) => (
                <div key={row.status}>
                  <div className={styles.totalRow}>
                    <span>{row.label}</span>
                    <span className={styles.count}>{row.count.toLocaleString("en-US")}</span>
                  </div>
                  <ProgressBar progress={row.percent} bg={progressBgForTone(row.tone)} aria-label={`${row.label} responses`} aria-valuetext={`${row.percent}%`} />
                </div>
              ))}
            </div>
          ) : (
            <p className={layout.muted}>No responses yet.</p>
          )}
        </Panel>
      </div>

      <UsersTable users={data.users} />

      <div className={layout.twoColumns}>
        <Panel title="Recent changes" flush>
          {data.audit_logs.length > 0 ? (
            <PanelList label="Recent changes">
              {data.audit_logs.map((log) => (
                <PanelListItem
                  key={log.id}
                  leadingVisual={<Avatar name={log.actor_name} src={log.actor_avatar_url} size={24} />}
                  title={
                    <>
                      {log.actor_name} <span className={styles.action}>{log.action_label}</span>
                    </>
                  }
                  description={log.auditable_label}
                  trailing={<RelativeTime datetime={log.created_at} className={`${layout.hint} ${layout.nowrap}`} />}
                />
              ))}
            </PanelList>
          ) : (
            <PanelEmptyText>No changes recorded yet.</PanelEmptyText>
          )}
        </Panel>

        <Panel title="Failed reports" flush>
          {data.failed_reports.length > 0 ? (
            <PanelList label="Failed reports">
              {data.failed_reports.map((report) => (
                <PanelListItem
                  key={report.id}
                  leadingVisual={<StatusDot tone="danger" label="Failed" />}
                  title={
                    <Link as={RouterLink} to={paths.standupReport(report.standup_id)}>
                      {report.standup_name ?? `Standup #${report.standup_id}`}
                    </Link>
                  }
                  description={report.error_message}
                  trailing={<RelativeTime datetime={report.requested_at} className={`${layout.hint} ${layout.nowrap}`} />}
                />
              ))}
            </PanelList>
          ) : (
            <EmptyState icon={CheckIcon} title="No failed report deliveries." border={false} size="small" headingLevel="h3" />
          )}
        </Panel>
      </div>
    </div>
  );
}

function UsersTable({ users }: { users: AdminUser[] }) {
  return (
    <Table.Container>
      <Table.Title as="h2" id="admin-users">
        Users
      </Table.Title>
      <Table.Subtitle as="p" id="admin-users-subtitle">
        Anyone who signs in with Slack or Microsoft gets an account
      </Table.Subtitle>
      <DataTable
        aria-labelledby="admin-users"
        aria-describedby="admin-users-subtitle"
        data={users}
        columns={[
          {
            header: "Name",
            field: "name",
            rowHeader: true,
            renderCell: (user) => (
              <div className={styles.person}>
                <Avatar name={user.name} src={user.avatar_url} />
                <div className={layout.truncate}>
                  <div className={layout.title}>{user.name}</div>
                  <div className={layout.hint}>{user.subtitle}</div>
                </div>
              </div>
            ),
          },
          {
            header: "Access",
            field: "access_label",
            renderCell: (user) => <StatusLabel tone={user.access_tone}>{user.access_label}</StatusLabel>,
          },
          { header: "Owns", field: "owned_standups_label", align: "end" },
          {
            header: "Last sign-in",
            field: "last_signed_in_at",
            renderCell: (user) => <RelativeTime datetime={user.last_signed_in_at} />,
          },
          {
            header: "Status",
            field: "status_label",
            renderCell: (user) => <StatusLabel tone={user.status_tone}>{user.status_label}</StatusLabel>,
          },
        ]}
      />
    </Table.Container>
  );
}
