import { isRouteErrorResponse, useRouteError } from "react-router";
import { Button } from "@primer/react";
import { ErrorBanner } from "../components";
import { useDocumentTitle } from "../hooks/useDocumentTitle";

/** Last-resort error view for render errors anywhere in the route tree. */
export function RouteErrorPage() {
  useDocumentTitle("Something went wrong");
  const error = useRouteError();
  const message = isRouteErrorResponse(error) ? `${error.status} ${error.statusText}` : error;

  return (
    <div style={{ maxWidth: 640, margin: "var(--base-size-64) auto", padding: "0 var(--base-size-16)" }}>
      <ErrorBanner
        title="Something went wrong"
        error={message || "Unexpected error."}
        action={<Button onClick={() => window.location.reload()}>Reload</Button>}
      />
    </div>
  );
}
