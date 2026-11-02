import { useRef, useState, type FormEvent, type RefObject } from "react";
import { Link as RouterLink } from "react-router";
import { Button, FormControl, SegmentedControl, Spinner, TextInput } from "@primer/react";
import { DownloadIcon, HistoryIcon } from "@primer/octicons-react";
import type { InsightsRange } from "../../../api/types/insights";
import layout from "../../../styles/layout.module.css";
import styles from "./insights.module.css";

export interface RangeToolbarProps {
  range: InsightsRange;
  csvPath: string;
  historyPath: string;
  loading?: boolean;
  onChange: (range: { start_date: string; end_date: string }) => void;
}

/** Date range presets, a custom range form, and the history/CSV links. */
export function RangeToolbar({ range, csvPath, historyPath, loading = false, onChange }: RangeToolbarProps) {
  const [customMode, setCustomMode] = useState(false);
  const startRef = useRef<HTMLInputElement>(null);
  const presetSelected = range.presets.some((preset) => preset.selected);
  const customSelected = customMode || !presetSelected;

  const handleSegment = (index: number) => {
    const preset = range.presets[index];
    if (preset) {
      setCustomMode(false);
      onChange({ start_date: preset.start_date, end_date: preset.end_date });
    } else {
      setCustomMode(true);
      startRef.current?.focus();
    }
  };

  return (
    <div className={styles.toolbar}>
      <div className={styles.toolbarGroup}>
        <SegmentedControl aria-label="Date range" onChange={handleSegment}>
          {range.presets.map((preset) => (
            <SegmentedControl.Button key={preset.days} selected={!customSelected && preset.selected}>
              {preset.label}
            </SegmentedControl.Button>
          ))}
          <SegmentedControl.Button selected={customSelected}>Custom</SegmentedControl.Button>
        </SegmentedControl>
        <CustomRangeForm
          key={`${range.start_date}:${range.end_date}`}
          range={range}
          startRef={startRef}
          onSubmit={(next) => {
            setCustomMode(false);
            onChange(next);
          }}
        />
        {loading && <Spinner size="small" srText="Updating insights" />}
      </div>
      <div className={styles.toolbarGroup}>
        <Button as={RouterLink} to={historyPath} leadingVisual={HistoryIcon}>
          Response history
        </Button>
        <Button as="a" href={csvPath} leadingVisual={DownloadIcon} download>
          Export CSV
        </Button>
      </div>
    </div>
  );
}

function CustomRangeForm({
  range,
  startRef,
  onSubmit,
}: {
  range: InsightsRange;
  startRef: RefObject<HTMLInputElement | null>;
  onSubmit: (range: { start_date: string; end_date: string }) => void;
}) {
  const [start, setStart] = useState(range.start_date);
  const [end, setEnd] = useState(range.end_date);

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    onSubmit({ start_date: start, end_date: end });
  };

  return (
    <form className={styles.rangeForm} onSubmit={handleSubmit} aria-label="Custom date range">
      <FormControl>
        <FormControl.Label visuallyHidden>Start date</FormControl.Label>
        <TextInput ref={startRef} type="date" name="start_date" value={start} max={end || undefined} onChange={(event) => setStart(event.target.value)} />
      </FormControl>
      <span className={layout.muted} aria-hidden="true">
        –
      </span>
      <FormControl>
        <FormControl.Label visuallyHidden>End date</FormControl.Label>
        <TextInput type="date" name="end_date" value={end} min={start || undefined} onChange={(event) => setEnd(event.target.value)} />
      </FormControl>
      <Button type="submit">Apply</Button>
    </form>
  );
}
