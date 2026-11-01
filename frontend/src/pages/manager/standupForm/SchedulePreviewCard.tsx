import { FormControl, IconButton, Select, Spinner } from "@primer/react";
import { LocationIcon, SyncIcon } from "@primer/octicons-react";
import type { SchedulePreview, StandupFormPayload } from "../../../api/types/standups";
import { OccurrenceList } from "../standups/OccurrenceList";
import { Section } from "../standups/Section";
import standupStyles from "../standups/standups.module.css";
import styles from "./StandupForm.module.css";
import { detectedZoneName } from "./useSchedulePreview";

export interface SchedulePreviewCardProps {
  options: StandupFormPayload["time_zone_options"];
  preview: SchedulePreview;
  error: string | null;
  loading: boolean;
  timezone: string;
  onTimezoneChange: (timezone: string) => void;
  onRefresh: () => void;
}

export function SchedulePreviewCard({ options, preview, error, loading, timezone, onTimezoneChange, onRefresh }: SchedulePreviewCardProps) {
  const detected = detectedZoneName(options);

  return (
    <Section title="Next runs" flush>
      <div className={styles.previewControls}>
        <FormControl className={styles.grow}>
          <FormControl.Label visuallyHidden>Preview timezone</FormControl.Label>
          <Select block size="small" value={timezone} onChange={(event) => onTimezoneChange(event.target.value)}>
            {options.map((option) => (
              <Select.Option key={option.name} value={option.name}>
                {option.name}
              </Select.Option>
            ))}
          </Select>
        </FormControl>
        {detected && (
          <IconButton
            icon={LocationIcon}
            size="small"
            variant="invisible"
            aria-label="Detect my timezone"
            disabled={detected === timezone}
            onClick={() => onTimezoneChange(detected)}
          />
        )}
        {loading ? (
          <span className={styles.previewSpinner}>
            <Spinner size="small" srText="Updating preview" />
          </span>
        ) : (
          <IconButton icon={SyncIcon} size="small" variant="invisible" aria-label="Preview schedule" onClick={onRefresh} />
        )}
      </div>
      <div aria-live="polite">
        {error ? (
          <p className={standupStyles.inlineEmpty}>{error}</p>
        ) : preview.error ? (
          <p className={standupStyles.inlineEmpty}>{preview.error}</p>
        ) : preview.occurrences.length > 0 ? (
          <OccurrenceList occurrences={preview.occurrences} label="Next runs" />
        ) : (
          <p className={standupStyles.inlineEmpty}>{preview.empty_message}</p>
        )}
      </div>
    </Section>
  );
}
