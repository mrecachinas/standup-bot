import { useState, type ReactNode } from "react";
import { Button, ConfirmationDialog, type ButtonProps } from "@primer/react";

export interface ConfirmButtonProps extends Omit<ButtonProps, "onClick" | "children"> {
  /** Button content. */
  children: ReactNode;
  /** Dialog title, e.g. "Delete Daily standup?". */
  title: string;
  /** Dialog body. */
  message?: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  /** Red confirm button (destructive actions). */
  danger?: boolean;
  /** Runs on confirm; the dialog stays open with a spinner until it settles. Handle errors inside it. */
  onConfirm: () => unknown | Promise<unknown>;
}

/** A button that asks for confirmation in a Primer ConfirmationDialog before running `onConfirm`. */
export function ConfirmButton({ children, title, message, confirmLabel = "Confirm", cancelLabel = "Cancel", danger = false, onConfirm, ...buttonProps }: ConfirmButtonProps) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  const handleClose = async (gesture: "confirm" | "close-button" | "cancel" | "escape") => {
    if (gesture !== "confirm") {
      if (!busy) setOpen(false);
      return;
    }
    setBusy(true);
    try {
      await onConfirm();
    } catch {
      // onConfirm reports its own errors (useMutation sets `error`); just close.
    } finally {
      setBusy(false);
      setOpen(false);
    }
  };

  return (
    <>
      <Button {...buttonProps} onClick={() => setOpen(true)}>
        {children}
      </Button>
      {open && (
        <ConfirmationDialog
          title={title}
          onClose={handleClose}
          confirmButtonContent={confirmLabel}
          cancelButtonContent={cancelLabel}
          confirmButtonType={danger ? "danger" : "primary"}
          confirmButtonLoading={busy}
        >
          {message}
        </ConfirmationDialog>
      )}
    </>
  );
}
