import { useState, type CSSProperties } from "react";
import { clsx } from "clsx";
import { avatarColors, initialsFor, isSafeAvatarUrl } from "./avatarColors";
import styles from "./Avatar.module.css";

export interface AvatarProps {
  name: string;
  /** Photo URL; falls back to initials when missing, unsafe or broken. */
  src?: string | null;
  /** Pixel size (default 32). */
  size?: number;
  square?: boolean;
  className?: string;
}

/** A person's photo over coloured initials. Decorative: pair it with the visible name. */
export function Avatar({ name, src, size = 32, square = false, className }: AvatarProps) {
  const [failedSrc, setFailedSrc] = useState<string | null>(null);
  const [background, foreground] = avatarColors(name);
  const showPhoto = isSafeAvatarUrl(src) && failedSrc !== src;

  const style = {
    "--avatar-bg": background,
    "--avatar-fg": foreground,
    width: size,
    height: size,
    fontSize: Math.max(9, Math.round(size * 0.4)),
  } as CSSProperties;

  return (
    <span className={clsx(styles.avatar, square && styles.square, className)} style={style} title={name} aria-hidden="true" data-testid="avatar">
      {initialsFor(name)}
      {showPhoto && (
        <img
          className={styles.photo}
          src={src}
          alt=""
          loading="lazy"
          referrerPolicy="no-referrer"
          onError={() => setFailedSrc(src)}
        />
      )}
    </span>
  );
}
