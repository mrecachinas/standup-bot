import { useLayoutEffect, useRef, type KeyboardEvent } from "react";
import { Button, IconButton, TextInput } from "@primer/react";
import { ChevronDownIcon, ChevronUpIcon, PlusIcon, XIcon } from "@primer/octicons-react";
import { newKey, type QuestionRow } from "./formState";
import layout from "../../../styles/layout.module.css";
import styles from "./StandupForm.module.css";

export interface QuestionEditorProps {
  questions: QuestionRow[];
  onChange: (questions: QuestionRow[]) => void;
  suggestions: string[];
  /** id of a validation message to describe the inputs with. */
  describedBy?: string;
  invalid?: boolean;
}

type FocusTarget = { key: string; control: "input" | "up" | "down" };

/**
 * The questions list: type a question, Enter adds the next one, Backspace in
 * an empty row removes it, rows reorder with the arrows, and suggestions fill
 * the first empty row.
 */
export function QuestionEditor({ questions, onChange, suggestions, describedBy, invalid = false }: QuestionEditorProps) {
  const controls = useRef(new Map<string, HTMLElement>());
  const focusTarget = useRef<FocusTarget | null>(null);

  useLayoutEffect(() => {
    const target = focusTarget.current;
    if (!target) return;
    focusTarget.current = null;
    controls.current.get(`${target.key}:${target.control}`)?.focus();
  });

  const register = (key: string, control: FocusTarget["control"]) => (element: HTMLElement | null) => {
    const id = `${key}:${control}`;
    if (element) controls.current.set(id, element);
    else controls.current.delete(id);
  };

  const addRow = (afterIndex = questions.length - 1, text = "") => {
    const row = { key: newKey("question"), text };
    const next = [...questions];
    next.splice(afterIndex + 1, 0, row);
    focusTarget.current = { key: row.key, control: "input" };
    onChange(next);
  };

  const removeRow = (index: number, focusNeighbour = false) => {
    if (questions.length <= 1) {
      onChange([{ ...questions[0], text: "" }]);
      return;
    }
    const neighbour = questions[index - 1] ?? questions[index + 1];
    if (focusNeighbour && neighbour) focusTarget.current = { key: neighbour.key, control: "input" };
    onChange(questions.filter((_, position) => position !== index));
  };

  const moveRow = (index: number, direction: "up" | "down") => {
    const target = direction === "up" ? index - 1 : index + 1;
    if (target < 0 || target >= questions.length) return;
    const next = [...questions];
    [next[index], next[target]] = [next[target], next[index]];
    focusTarget.current = { key: questions[index].key, control: direction };
    onChange(next);
  };

  const updateRow = (index: number, text: string) => {
    onChange(questions.map((row, position) => (position === index ? { ...row, text } : row)));
  };

  const handleKeyDown = (index: number) => (event: KeyboardEvent<HTMLInputElement>) => {
    if (event.key === "Enter" && !event.nativeEvent.isComposing) {
      event.preventDefault();
      addRow(index);
    } else if (event.key === "Backspace" && event.currentTarget.value === "" && questions.length > 1) {
      event.preventDefault();
      removeRow(index, true);
    }
  };

  const applySuggestion = (text: string) => {
    const emptyIndex = questions.findIndex((row) => !row.text.trim());
    if (emptyIndex >= 0) {
      updateRow(emptyIndex, text);
    } else {
      onChange([...questions, { key: newKey("question"), text }]);
    }
  };

  const used = new Set(questions.map((row) => row.text.trim()));
  const available = suggestions.filter((text) => !used.has(text));

  return (
    <div className={styles.questionEditor}>
      <ol className={styles.questionRows}>
        {questions.map((row, index) => (
          <li key={row.key} className={styles.questionRow}>
            <span className={styles.rowIndex} aria-hidden="true">
              {index + 1}
            </span>
            <TextInput
              ref={register(row.key, "input")}
              className={layout.grow}
              block
              value={row.text}
              placeholder="Ask something…"
              aria-label={`Question ${index + 1}`}
              aria-describedby={describedBy}
              validationStatus={invalid ? "error" : undefined}
              onChange={(event) => updateRow(index, event.target.value)}
              onKeyDown={handleKeyDown(index)}
            />
            <span className={styles.rowActions}>
              <IconButton
                ref={register(row.key, "up")}
                icon={ChevronUpIcon}
                variant="invisible"
                size="small"
                aria-label={`Move question ${index + 1} up`}
                onClick={() => moveRow(index, "up")}
              />
              <IconButton
                ref={register(row.key, "down")}
                icon={ChevronDownIcon}
                variant="invisible"
                size="small"
                aria-label={`Move question ${index + 1} down`}
                onClick={() => moveRow(index, "down")}
              />
              <IconButton icon={XIcon} variant="invisible" size="small" aria-label={`Remove question ${index + 1}`} onClick={() => removeRow(index)} />
            </span>
          </li>
        ))}
      </ol>
      <div className={styles.suggestions}>
        <Button size="small" leadingVisual={PlusIcon} onClick={() => addRow()}>
          Add question
        </Button>
        {available.length > 0 && <span className={layout.hint}>or try:</span>}
        {available.map((text) => (
          <Button key={text} size="small" variant="invisible" className={styles.suggestion} onClick={() => applySuggestion(text)}>
            {text}
          </Button>
        ))}
      </div>
    </div>
  );
}
