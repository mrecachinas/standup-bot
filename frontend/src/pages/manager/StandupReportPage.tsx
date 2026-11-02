import { clsx } from "clsx";
import { useParams } from "react-router";
import { Banner, Button } from "@primer/react";
import { DataTable, Table } from "@primer/react/experimental";
import { PaperAirplaneIcon } from "@primer/octicons-react";
import { ApiError, patch, post } from "../../api/client";
import type { ReportConfigurationParams, ReportGeneration, ReportPayload } from "../../api/types/insights";
import { EmptyState, KeyValueList, Panel, StandupHeader, StatusLabel } from "../../components";
import { formatPercent, formatShortDateTime } from "../../lib/format";
import { useMutation } from "../../hooks/useMutation";
import { ReportSettingsForm } from "./insights/ReportSettingsForm";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";

export function StandupReportPage() {
  const { id = "" } = useParams();
  const path = `/api/standups/${id}/report`;
  const { data, error, reload, setData, setStandup } = useStandupPage<ReportPayload>(path, "Reports");

  const save = useMutation((params: ReportConfigurationParams["report_configuration"]) => patch<ReportPayload>(path, { report_configuration: params }), {
    onSuccess: (result) => setData(result),
  });

  const generate = useMutation(
    async () => {
      try {
        return await post<ReportPayload>(`${path}/generate`);
      } catch (caught) {
        // A failed generation still returns the page payload (with the new failed row).
        if (caught instanceof ApiError && isReportPayload(caught.body)) setData(caught.body);
        throw caught;
      }
    },
    { onSuccess: (result) => setData(result) },
  );

  if (!data) return <StandupLoadState error={error} onRetry={reload} title="Reports" />;

  const { standup, report_configuration: config, summary } = data;

  return (
    <div className={layout.page}>
      <StandupHeader standup={standup} active="reports" onStandupChange={setStandup} />

      {generate.error && (
        <Banner variant="warning" title="Couldn't generate the report" description={generate.error.message} onDismiss={generate.reset} />
      )}

      <div className={layout.mainAside}>
        <div className={layout.stack}>
          <ReportSettingsForm key={config.updated_at ?? "new"} payload={data} saving={save.loading} error={save.error} onSubmit={(params) => void save.run(params)} />
          <ReportHistory generations={data.report_generations} />
        </div>

        <aside className={layout.stack} aria-label="Report actions">
          <Panel title="Send a report now">
            <p className={layout.hint}>
              Builds a report from today&apos;s responses using the saved settings.
            </p>
            <KeyValueList
              items={[
                { label: "Channel", value: config.delivery_channel || "—", mono: true },
                { label: "Also to", value: config.recipients_label },
                { label: "Detail", value: config.detail_level_label ?? config.detail_level },
              ]}
            />
            <Button leadingVisual={PaperAirplaneIcon} onClick={() => void generate.run()} loading={generate.loading} block>
              Generate report now
            </Button>
          </Panel>

          <Panel title={`Last ${summary.period_days} days`}>
            <KeyValueList
              items={[
                { label: "Completion rate", value: formatPercent(summary.completion_rate), strong: true },
                { label: "Completed", value: summary.completed_responses },
                { label: "Expected", value: summary.expected_responses },
              ]}
            />
          </Panel>
        </aside>
      </div>
    </div>
  );
}

function ReportHistory({ generations }: { generations: ReportGeneration[] }) {
  return (
    <Table.Container>
      <Table.Title as="h2" id="report-history">
        History
      </Table.Title>
      {generations.length === 0 ? (
        <EmptyState title="No reports have been sent yet." size="small" headingLevel="h3" />
      ) : (
        <DataTable
          aria-labelledby="report-history"
          data={generations}
          columns={[
            {
              header: "Requested",
              field: "requested_at",
              rowHeader: true,
              renderCell: (row) => (
                <div className={layout.nowrap}>
                  <div>{formatShortDateTime(row.requested_at)}</div>
                  <div className={layout.hint}>{row.requested_by_label}</div>
                </div>
              ),
            },
            {
              header: "Status",
              field: "status_label",
              renderCell: (row) => <StatusLabel tone={row.status_tone}>{row.status_label}</StatusLabel>,
            },
            {
              header: "Sent to",
              field: "delivery_channel",
              renderCell: (row) => (
                <div>
                  <span className={layout.mono}>{row.delivery_channel}</span>
                  <div className={layout.hint}>{row.detail_level_label}</div>
                </div>
              ),
            },
            {
              header: "Result",
              field: "result_label",
              renderCell: (row) =>
                <span className={clsx(layout.small, row.failed ? layout.danger : row.response_count === null && layout.muted)}>{row.result_label}</span>,
            },
          ]}
        />
      )}
    </Table.Container>
  );
}

function isReportPayload(body: unknown): body is ReportPayload {
  return typeof body === "object" && body !== null && "report_configuration" in body && "report_generations" in body;
}
