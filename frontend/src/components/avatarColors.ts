/** Same palette and rules as UiHelper (AVATAR_PALETTE / initials_for), so avatars look the same everywhere. */
export const AVATAR_PALETTE: readonly (readonly [background: string, foreground: string])[] = [
  ["#e0e7ff", "#3730a3"],
  ["#dcfce7", "#166534"],
  ["#fef3c7", "#92400e"],
  ["#fce7f3", "#9d174d"],
  ["#e0f2fe", "#075985"],
  ["#ede9fe", "#5b21b6"],
  ["#ffedd5", "#9a3412"],
  ["#ccfbf1", "#115e59"],
];

/** "Jane Q. Doe" → "JD", "jane" → "JA", "" → "?". */
export function initialsFor(name: string | null | undefined): string {
  const words = (name ?? "").match(/[\p{L}\p{M}\p{N}]+/gu) ?? [];
  if (words.length === 0) return "?";

  const first = Array.from(words[0] ?? "");
  const last = Array.from(words[words.length - 1] ?? "");
  const initials = words.length === 1 ? first.slice(0, 2).join("") : `${first[0] ?? ""}${last[0] ?? ""}`;
  return initials.toUpperCase();
}

/** Ruby's String#sum: the byte sum of the UTF-8 string, modulo 2^16. */
function byteSum(value: string): number {
  let sum = 0;
  for (const byte of new TextEncoder().encode(value)) sum += byte;
  return sum % 65536;
}

export function avatarColors(name: string | null | undefined): readonly [string, string] {
  return AVATAR_PALETTE[byteSum(name ?? "") % AVATAR_PALETTE.length];
}

/** Only https photo URLs are shown; the server already filters to trusted hosts. */
export function isSafeAvatarUrl(url: string | null | undefined): url is string {
  if (!url) return false;
  try {
    return new URL(url).protocol === "https:";
  } catch {
    return false;
  }
}
