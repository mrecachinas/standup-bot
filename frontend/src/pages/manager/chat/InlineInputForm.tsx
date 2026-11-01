import { useState, type FormEvent } from "react";
import { Button, FormControl, TextInput } from "@primer/react";
import type { Icon } from "@primer/octicons-react";
import styles from "./chat.module.css";

export interface InlineInputFormProps {
  /** Visually hidden label for the input. */
  label: string;
  name: string;
  submitLabel: string;
  initialValue?: string;
  placeholder?: string;
  type?: "text" | "search";
  leadingVisual?: Icon;
  loading?: boolean;
  /** Field error from a 422 (shown under the input). */
  validation?: string;
  /** Return true to clear the input afterwards. */
  onSubmit: (value: string) => void | boolean | Promise<void | boolean>;
}

/** One input and its button on a row, e.g. "Channel ID [Save channel]". */
export function InlineInputForm({ label, name, submitLabel, initialValue = "", placeholder, type = "text", leadingVisual, loading = false, validation, onSubmit }: InlineInputFormProps) {
  const [value, setValue] = useState(initialValue);

  const handleSubmit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const clear = await onSubmit(value.trim());
    if (clear === true) setValue("");
  };

  return (
    <form className={styles.inlineForm} onSubmit={handleSubmit}>
      <FormControl>
        <FormControl.Label visuallyHidden>{label}</FormControl.Label>
        <TextInput
          type={type}
          name={name}
          value={value}
          placeholder={placeholder}
          leadingVisual={leadingVisual}
          onChange={(event) => setValue(event.target.value)}
          validationStatus={validation ? "error" : undefined}
          block
        />
        {validation && <FormControl.Validation variant="error">{validation}</FormControl.Validation>}
      </FormControl>
      <Button type="submit" loading={loading}>
        {submitLabel}
      </Button>
    </form>
  );
}
