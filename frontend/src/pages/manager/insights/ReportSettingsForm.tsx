import { useState, type FormEvent } from "react";
import { Banner, Button, FormControl, Select, TextInput, Textarea } from "@primer/react";
import type { ApiError } from "../../../api/client";
import type { ReportConfigurationParams, ReportPayload } from "../../../api/types/insights";
import { Panel } from "./Panel";
import styles from "./insights.module.css";

export interface ReportSettingsFormProps {
  payload: ReportPayload;
  saving: boolean;
  error: ApiError | null;
  onSubmit: (params: ReportConfigurationParams["report_configuration"]) => void;
}

/** "Delivery settings": channel, extra recipients, format and detail level. */
export function ReportSettingsForm({ payload, saving, error, onSubmit }: ReportSettingsFormProps) {
  const { report_configuration: config, options, copy } = payload;
  const [deliveryChannel, setDeliveryChannel] = useState(config.delivery_channel ?? "");
  const [recipientsText, setRecipientsText] = useState(config.recipients_text ?? "");
  const [reportFormat, setReportFormat] = useState(config.report_format);
  const [detailLevel, setDetailLevel] = useState(config.detail_level);

  const validationErrors = error?.status === 422 ? error.errors : [];
  const channelError = error?.fieldError("delivery_channel");
  const recipientsError = error?.fieldError("recipients") ?? error?.fieldError("recipients_text");
  const formatError = error?.fieldError("report_format");
  const detailError = error?.fieldError("detail_level");

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    onSubmit({ delivery_channel: deliveryChannel.trim(), recipients_text: recipientsText, report_format: reportFormat, detail_level: detailLevel });
  };

  return (
    <form onSubmit={handleSubmit} noValidate aria-label="Delivery settings">
      <Panel
        title="Delivery settings"
        description="Where the end-of-run summary is posted and how much it includes."
        footer={
          <Button type="submit" variant="primary" loading={saving}>
            Save settings
          </Button>
        }
      >
        <div className={styles.form}>
          {validationErrors.length > 0 && (
            <Banner
              variant="critical"
              title="Fix the report settings"
              description={
                <ul className={styles.errorList}>
                  {validationErrors.map((message) => (
                    <li key={message}>{message}</li>
                  ))}
                </ul>
              }
            />
          )}
          {error && error.status !== 422 && <Banner variant="critical" title="Couldn't save the report settings" description={error.message} />}

          <FormControl>
            <FormControl.Label>Post to channel</FormControl.Label>
            <TextInput
              name="delivery_channel"
              value={deliveryChannel}
              placeholder={copy.delivery_channel_placeholder}
              onChange={(event) => setDeliveryChannel(event.target.value)}
              validationStatus={channelError ? "error" : undefined}
              block
            />
            {channelError ? <FormControl.Validation variant="error">{channelError}</FormControl.Validation> : <FormControl.Caption>{copy.delivery_channel_hint}</FormControl.Caption>}
          </FormControl>

          <FormControl>
            <FormControl.Label>Also send to</FormControl.Label>
            <Textarea
              name="recipients_text"
              rows={3}
              value={recipientsText}
              placeholder={copy.recipients_placeholder}
              onChange={(event) => setRecipientsText(event.target.value)}
              validationStatus={recipientsError ? "error" : undefined}
              block
              resize="vertical"
            />
            {recipientsError ? <FormControl.Validation variant="error">{recipientsError}</FormControl.Validation> : <FormControl.Caption>{copy.recipients_hint}</FormControl.Caption>}
          </FormControl>

          <div className={styles.formRow}>
            <FormControl>
              <FormControl.Label>Format</FormControl.Label>
              <Select name="report_format" value={reportFormat} onChange={(event) => setReportFormat(event.target.value)} validationStatus={formatError ? "error" : undefined} block>
                {options.report_formats.map((option) => (
                  <Select.Option key={option.value} value={option.value}>
                    {option.label}
                  </Select.Option>
                ))}
              </Select>
              {formatError && <FormControl.Validation variant="error">{formatError}</FormControl.Validation>}
            </FormControl>
            <FormControl>
              <FormControl.Label>Detail</FormControl.Label>
              <Select name="detail_level" value={detailLevel} onChange={(event) => setDetailLevel(event.target.value)} validationStatus={detailError ? "error" : undefined} block>
                {options.detail_levels.map((option) => (
                  <Select.Option key={option.value} value={option.value}>
                    {option.label}
                  </Select.Option>
                ))}
              </Select>
              {detailError && <FormControl.Validation variant="error">{detailError}</FormControl.Validation>}
            </FormControl>
          </div>
        </div>
      </Panel>
    </form>
  );
}
