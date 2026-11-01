import { Spinner } from "@primer/react";

export interface LoadingStateProps {
  label?: string;
  /** Centre in the viewport (app boot) instead of the content area. */
  fullPage?: boolean;
}

export function LoadingState({ label = "Loading…", fullPage = false }: LoadingStateProps) {
  return (
    <div
      role="status"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: "var(--base-size-8)",
        minHeight: fullPage ? "100vh" : "12rem",
        color: "var(--fgColor-muted)",
      }}
    >
      <Spinner size="small" srText={null} />
      <span>{label}</span>
    </div>
  );
}
