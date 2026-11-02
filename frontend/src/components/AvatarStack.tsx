import { clsx } from "clsx";
import { toSentence } from "../lib/format";
import { Avatar } from "./Avatar";
import styles from "./Avatar.module.css";

export interface AvatarPerson {
  name: string;
  avatar_url?: string | null;
}

export interface AvatarStackProps {
  people: (AvatarPerson | string)[];
  /** How many avatars to show before "+N" (default 5). */
  limit?: number;
  size?: number;
  className?: string;
}

export function AvatarStack({ people, limit = 5, size = 24, className }: AvatarStackProps) {
  const normalized = people.map((person) => (typeof person === "string" ? { name: person } : person));
  const hidden = normalized.length - limit;
  const names = toSentence(normalized.map((person) => person.name));

  return (
    <span className={clsx(styles.stack, className)} title={names} role="img" aria-label={names}>
      {normalized.slice(0, limit).map((person, index) => (
        <Avatar key={`${person.name}-${index}`} name={person.name} src={person.avatar_url} size={size} />
      ))}
      {hidden > 0 && (
        <span className={styles.more} style={{ minWidth: size, height: size, padding: "0 4px" }} aria-hidden="true">
          +{hidden}
        </span>
      )}
    </span>
  );
}
