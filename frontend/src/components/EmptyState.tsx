import type { ReactNode } from "react";
import type { Icon } from "@primer/octicons-react";
import { Blankslate } from "@primer/react/experimental";

export interface EmptyStateProps {
  title: string;
  description?: ReactNode;
  icon?: Icon;
  /** A Button/LinkButton (or anything) under the description. */
  action?: ReactNode;
  secondaryAction?: ReactNode;
  border?: boolean;
  narrow?: boolean;
  size?: "small" | "medium" | "large";
  headingLevel?: "h2" | "h3";
}

export function EmptyState({ title, description, icon: IconComponent, action, secondaryAction, border = true, narrow = false, size = "medium", headingLevel = "h2" }: EmptyStateProps) {
  return (
    <Blankslate border={border} narrow={narrow} size={size}>
      {IconComponent && (
        <Blankslate.Visual>
          <IconComponent size="medium" />
        </Blankslate.Visual>
      )}
      <Blankslate.Heading as={headingLevel}>{title}</Blankslate.Heading>
      {description && <Blankslate.Description>{description}</Blankslate.Description>}
      {action && <div style={{ marginTop: "var(--base-size-16)" }}>{action}</div>}
      {secondaryAction && <div style={{ marginTop: "var(--base-size-8)" }}>{secondaryAction}</div>}
    </Blankslate>
  );
}
