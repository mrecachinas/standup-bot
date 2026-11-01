import { AlertFillIcon } from "@primer/octicons-react";
import styles from "./StandupForm.module.css";

/** A validation message for a group of controls that FormControl.Validation can't wrap. */
export function FieldError({ id, message }: { id: string; message: string | undefined }) {
  if (!message) return null;
  return (
    <div id={id} className={styles.fieldError}>
      <AlertFillIcon size={12} />
      <span>{message}</span>
    </div>
  );
}
