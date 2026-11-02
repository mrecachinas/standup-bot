/** Confirmation copy for removing a manager (or yourself). */
export function removeManagerCopy(name: string, standupName: string, isSelf: boolean) {
  return isSelf
    ? { title: `Stop managing ${standupName}?`, message: `Stop managing ${standupName}? You'll lose access to it.`, confirm: "Stop managing" }
    : { title: `Remove ${name} as a manager?`, message: `Remove ${name} as a manager of ${standupName}?`, confirm: "Remove manager" };
}
