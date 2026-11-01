import { Link as RouterLink } from "react-router";
import { CheckCircleFillIcon } from "@primer/octicons-react";
import type { StandupTemplate } from "../../../api/types/standups";
import styles from "./TemplatePicker.module.css";

export interface TemplatePickerProps {
  templates: StandupTemplate[];
  selected: string | null;
  /** The URL (with ?template=) for a template key. */
  hrefFor: (key: string) => string;
}

/** Template cards for a new standup, plus "start from scratch". */
export function TemplatePicker({ templates, selected, hrefFor }: TemplatePickerProps) {
  return (
    <div className={styles.picker}>
      <nav aria-label="Templates">
        <ul className={styles.templates}>
          {templates.map((template) => {
            const current = template.key === selected;
            return (
              <li key={template.key}>
                <RouterLink to={hrefFor(template.key)} className={styles.template} aria-current={current ? "true" : undefined} replace>
                  <span className={styles.title}>
                    {template.label}
                    {current && <CheckCircleFillIcon size={16} className={styles.check} />}
                  </span>
                  <span className={styles.meta}>{template.meta}</span>
                </RouterLink>
              </li>
            );
          })}
        </ul>
      </nav>
      <p className={styles.scratch}>
        Or{" "}
        <RouterLink to={hrefFor("blank")} aria-current={selected === "blank" ? "true" : undefined} replace>
          start from scratch
        </RouterLink>
        .
      </p>
    </div>
  );
}
