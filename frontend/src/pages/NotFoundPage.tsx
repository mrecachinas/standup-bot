import { Link as RouterLink } from "react-router";
import { Button } from "@primer/react";
import { QuestionIcon } from "@primer/octicons-react";
import { EmptyState } from "../components/EmptyState";
import { useDocumentTitle } from "../hooks/useDocumentTitle";

export function NotFoundPage() {
  useDocumentTitle("Page not found");
  return (
    <EmptyState
      icon={QuestionIcon}
      title="Page not found"
      description="That page doesn't exist, or you don't have access to it."
      action={
        <Button as={RouterLink} to="/">
          Go home
        </Button>
      }
    />
  );
}
