import type { ReactNode } from "react";
import { Link as RouterLink } from "react-router";
import { NavList } from "@primer/react";
import { CalendarIcon, GearIcon, PaperAirplaneIcon } from "@primer/octicons-react";
import { settingsPath, type SettingsSection } from "../../../paths";
import styles from "./SettingsLayout.module.css";

const SECTIONS: { key: SettingsSection; label: string; icon: typeof GearIcon }[] = [
  { key: "general", label: "General", icon: GearIcon },
  { key: "schedule", label: "Schedule", icon: CalendarIcon },
  { key: "reports", label: "Reports", icon: PaperAirplaneIcon },
];

export interface SettingsLayoutProps {
  standupId: number | string;
  section: SettingsSection;
  children: ReactNode;
}

/** A standup's Settings tab: a side nav (like a GitHub repo's settings) next to the current section. */
export function SettingsLayout({ standupId, section, children }: SettingsLayoutProps) {
  return (
    <div className={styles.layout}>
      <NavList aria-label="Settings" className={styles.nav}>
        {SECTIONS.map((item) => (
          <NavList.Item key={item.key} as={RouterLink} to={settingsPath(standupId, item.key)} aria-current={item.key === section ? "page" : undefined}>
            <NavList.LeadingVisual>
              <item.icon />
            </NavList.LeadingVisual>
            {item.label}
          </NavList.Item>
        ))}
      </NavList>
      <div className={styles.content}>{children}</div>
    </div>
  );
}
