(() => {
  const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

  const toggleSection = (section, visible) => {
    if (!section) return;
    section.hidden = !visible;
    section.querySelectorAll("input, select").forEach((input) => {
      input.disabled = !visible;
    });
  };

  let nextIndex = Date.now();
  const uniqueIndex = () => String(nextIndex++);

  const cloneTemplate = (template) => {
    const index = uniqueIndex();
    const fragment = template.content.cloneNode(true);
    fragment.querySelectorAll("[name], [id], [for]").forEach((element) => {
      ["name", "id", "for"].forEach((attribute) => {
        const value = element.getAttribute(attribute);
        if (value) element.setAttribute(attribute, value.replaceAll("__INDEX__", index));
      });
    });
    return fragment.firstElementChild;
  };

  /* Row editors (questions) ------------------------------------------- */

  const renumber = (editor) => {
    editor.querySelectorAll("[data-row-index]").forEach((badge, index) => {
      badge.textContent = index + 1;
    });
  };

  const addRow = (editor, { after = null, value = "" } = {}) => {
    const template = editor.querySelector(":scope > template");
    const list = editor.querySelector("[data-rows]");
    if (!template || !list) return null;
    const row = cloneTemplate(template);
    const input = row.querySelector("input[type=text]");
    if (input) input.value = value;
    if (after) after.after(row); else list.appendChild(row);
    renumber(editor);
    input?.focus();
    return row;
  };

  const removeRow = (editor, row) => {
    const rows = editor.querySelectorAll("[data-row]");
    const value = row.querySelector("input[type=text]")?.value;
    if (rows.length > 1) {
      row.remove();
    } else {
      row.querySelectorAll("input[type=text]").forEach((input) => { input.value = ""; });
    }
    renumber(editor);
    if (value) showSuggestion(editor, value);
  };

  const showSuggestion = (editor, value) => {
    editor.querySelectorAll("[data-suggestion]").forEach((button) => {
      if (button.dataset.suggestion === value) button.hidden = false;
    });
  };

  /* Schedule summary -------------------------------------------------- */

  const formatClock = (value) => {
    const [hours, minutes] = (value || "").split(":").map(Number);
    if (Number.isNaN(hours) || Number.isNaN(minutes)) return "—";
    const suffix = hours >= 12 ? "PM" : "AM";
    return `${hours % 12 || 12}:${String(minutes).padStart(2, "0")} ${suffix}`;
  };

  const toSentence = (items) => {
    if (items.length <= 1) return items.join("");
    if (items.length === 2) return `${items[0]} and ${items[1]}`;
    return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
  };

  const scheduleSentence = (form) => {
    const frequency = form.querySelector("[data-frequency-input]:checked")?.value || "weekly";
    const days = [...form.querySelectorAll("input[name='standup[days][]'][type=checkbox]:checked")].map((input) => Number(input.value)).sort((a, b) => a - b);
    const names = days.map((day) => DAY_NAMES[day]);
    const time = formatClock(form.querySelector("#standup_send_time")?.value);
    const localTime = form.querySelector("[data-timezone-mode]")?.value !== "false";
    let base;

    if (frequency === "monthly") {
      base = `Monthly on day ${form.querySelector("#standup_monthly_day")?.value || 1}`;
    } else if (frequency === "biweekly") {
      base = days.length === 1 ? `Every 2 weeks on ${names[0]}` : "Every 2 weeks (pick one day)";
    } else if (days.length === 0) {
      return "Pick at least one day.";
    } else if (days.length === 7) {
      base = "Every day";
    } else if (days.join() === "1,2,3,4,5") {
      base = "Weekdays";
    } else if (days.length === 1) {
      base = `Weekly on ${names[0]}`;
    } else {
      base = names.join(", ");
    }

    return `${base} at ${time}, ${localTime ? "in each person's local time" : "UTC"}`;
  };

  /* Live editor preview ----------------------------------------------- */

  const syncEditor = (form) => {
    if (!form?.matches("form.editor")) return;

    const frequency = form.querySelector("[data-frequency-input]:checked")?.value || "weekly";
    toggleSection(form.querySelector("[data-day-picker]"), frequency !== "monthly");
    toggleSection(form.querySelector("[data-monthly-schedule-section]"), frequency === "monthly");
    const biweeklyHint = form.querySelector("[data-biweekly-hint]");
    if (biweeklyHint) biweeklyHint.hidden = frequency !== "biweekly";

    const summary = form.querySelector("[data-schedule-summary]");
    if (summary) summary.textContent = scheduleSentence(form);

    const time = form.querySelector("[data-preview-time]");
    if (time) time.textContent = formatClock(form.querySelector("#standup_send_time")?.value);

    const intro = form.querySelector("[data-preview-intro]");
    const introInput = form.querySelector("[data-intro-input]");
    if (intro && introInput) intro.textContent = introInput.value.trim();

    const questions = [...form.querySelectorAll("[data-question-input]")].map((input) => input.value.trim()).filter(Boolean);
    const question = form.querySelector("[data-preview-question]");
    if (question) question.textContent = questions[0] || "Your first question shows up here.";
    const count = form.querySelector("[data-preview-count]");
    if (count) count.textContent = `Question 1 of ${Math.max(questions.length, 1)}`;
  };

  let previewTimer;
  const schedulePreview = (form) => {
    const button = form.querySelector("[data-preview-button]");
    if (!button || typeof form.requestSubmit !== "function") return;
    clearTimeout(previewTimer);
    previewTimer = setTimeout(() => form.requestSubmit(button), 250);
  };

  /* People chips ------------------------------------------------------ */

  const addPeople = (input) => {
    const form = input.closest("form");
    const container = form?.querySelector("[data-people]");
    const template = form?.querySelector("[data-person-template]");
    if (!container || !template) return;

    const existing = new Set([...container.querySelectorAll("input[name$='[platform_user_id]']")].map((field) => field.value.toLowerCase()));
    input.value.split(/[,\n]/).map((handle) => handle.trim()).filter(Boolean).forEach((handle) => {
      if (existing.has(handle.toLowerCase())) return;
      existing.add(handle.toLowerCase());
      const chip = cloneTemplate(template);
      chip.querySelector("[data-person-handle]").value = handle;
      chip.querySelector("[data-person-label]").textContent = handle;
      const initials = chip.querySelector(".avatar");
      if (initials && initials.firstChild) initials.firstChild.textContent = handle.replace(/[^A-Za-z0-9]/g, "").slice(0, 2).toUpperCase() || "?";
      container.appendChild(chip);
    });
    input.value = "";
  };

  // Existing people use a real "remove" checkbox (works without JS); this just reflects it.
  const syncPersonChip = (checkbox) => {
    checkbox.closest("[data-person-chip]")?.classList.toggle("is-removed", checkbox.checked);
  };

  /* Unsaved changes --------------------------------------------------- */

  let dirtyForm = null;
  const markDirty = (form) => {
    if (form?.matches("[data-unsaved-guard]")) dirtyForm = form;
  };

  window.addEventListener("beforeunload", (event) => {
    if (dirtyForm && document.contains(dirtyForm)) {
      event.preventDefault();
      event.returnValue = "";
    }
  });

  document.addEventListener("turbo:before-visit", (event) => {
    if (dirtyForm && document.contains(dirtyForm) && !window.confirm("You have unsaved changes. Leave anyway?")) {
      event.preventDefault();
    }
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    const submitter = event.submitter;
    if (submitter?.hasAttribute("data-preview-button")) return;
    form.querySelectorAll("[data-people-input]").forEach((input) => {
      if (input.value.trim()) addPeople(input);
    });
    if (form === dirtyForm) dirtyForm = null;
  });

  /* Events ------------------------------------------------------------ */

  document.addEventListener("click", (event) => {
    const add = event.target.closest("[data-add-row]");
    if (add) {
      event.preventDefault();
      addRow(add.closest("[data-row-editor]"));
      markDirty(add.closest("form"));
      syncEditor(add.closest("form"));
      return;
    }

    const remove = event.target.closest("[data-remove-row]");
    if (remove) {
      event.preventDefault();
      const editor = remove.closest("[data-row-editor]");
      removeRow(editor, remove.closest("[data-row]"));
      markDirty(remove.closest("form"));
      syncEditor(editor.closest("form"));
      return;
    }

    const move = event.target.closest("[data-move-row]");
    if (move) {
      event.preventDefault();
      const row = move.closest("[data-row]");
      const editor = move.closest("[data-row-editor]");
      if (move.dataset.moveRow === "up" && row.previousElementSibling) row.previousElementSibling.before(row);
      if (move.dataset.moveRow === "down" && row.nextElementSibling) row.nextElementSibling.after(row);
      renumber(editor);
      move.focus();
      markDirty(move.closest("form"));
      syncEditor(move.closest("form"));
      return;
    }

    const suggestion = event.target.closest("[data-suggestion]");
    if (suggestion) {
      event.preventDefault();
      const editor = suggestion.closest("[data-row-editor]");
      const empty = [...editor.querySelectorAll("[data-rows] input[type=text]")].find((input) => !input.value.trim());
      if (empty) {
        empty.value = suggestion.dataset.suggestion;
      } else {
        addRow(editor, { value: suggestion.dataset.suggestion });
      }
      suggestion.hidden = true;
      markDirty(suggestion.closest("form"));
      syncEditor(suggestion.closest("form"));
      return;
    }

    const preset = event.target.closest("[data-set-days]");
    if (preset) {
      event.preventDefault();
      const days = new Set(preset.dataset.setDays.split(","));
      const form = preset.closest("form");
      form.querySelectorAll("input[name='standup[days][]'][type=checkbox]").forEach((input) => {
        input.checked = days.has(input.value);
      });
      markDirty(form);
      syncEditor(form);
      schedulePreview(form);
      return;
    }

    const personRemove = event.target.closest("[data-person-remove]");
    if (personRemove) {
      event.preventDefault();
      markDirty(personRemove.closest("form"));
      personRemove.closest("[data-person-chip]")?.remove();
      return;
    }

    document.querySelectorAll("details.menu[open]").forEach((menu) => {
      if (!menu.contains(event.target)) menu.removeAttribute("open");
    });
  });

  document.addEventListener("input", (event) => {
    const form = event.target.closest("form");
    if (!form) return;
    markDirty(form);
    syncEditor(form);
  });

  document.addEventListener("change", (event) => {
    if (event.target.matches("[data-person-destroy]")) syncPersonChip(event.target);
    const form = event.target.closest("form");
    if (!form) return;
    syncEditor(form);
    if (event.target.closest("[data-schedule-input]")) schedulePreview(form);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      document.querySelectorAll("details.menu[open]").forEach((menu) => menu.removeAttribute("open"));
      return;
    }

    const question = event.target.closest?.("[data-question-input]");
    if (question && event.key === "Enter") {
      event.preventDefault();
      addRow(question.closest("[data-row-editor]"), { after: question.closest("[data-row]") });
      return;
    }
    if (question && event.key === "Backspace" && question.value === "") {
      const editor = question.closest("[data-row-editor]");
      const row = question.closest("[data-row]");
      if (editor.querySelectorAll("[data-row]").length > 1) {
        event.preventDefault();
        const previous = row.previousElementSibling || row.nextElementSibling;
        removeRow(editor, row);
        previous?.querySelector("input[type=text]")?.focus();
        syncEditor(editor.closest("form"));
      }
      return;
    }

    const people = event.target.closest?.("[data-people-input]");
    if (people && (event.key === "Enter" || event.key === ",")) {
      event.preventDefault();
      addPeople(people);
      markDirty(people.closest("form"));
    }
  });

  // Fall back to initials if a Slack photo can't load.
  document.addEventListener("error", (event) => {
    if (event.target instanceof HTMLImageElement && event.target.classList.contains("avatar-img")) event.target.remove();
  }, true);

  /* Theme ------------------------------------------------------------- */

  const currentTheme = () => {
    try { return localStorage.getItem("theme") || "system"; } catch (_) { return "system"; }
  };

  const applyTheme = (theme) => {
    if (theme === "light" || theme === "dark") {
      document.documentElement.dataset.theme = theme;
    } else {
      delete document.documentElement.dataset.theme;
    }
    document.querySelectorAll("[data-theme-value]").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.themeValue === theme));
    });
  };

  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-theme-value]");
    if (!button) return;
    const theme = button.dataset.themeValue;
    try {
      if (theme === "system") localStorage.removeItem("theme"); else localStorage.setItem("theme", theme);
    } catch (_) {}
    applyTheme(theme);
  });

  /* Init -------------------------------------------------------------- */

  // New standups preview in the creator's timezone when the server doesn't know it.
  const detectPreviewTimezone = (root) => {
    root.querySelectorAll("select[data-detect-timezone]").forEach((select) => {
      select.removeAttribute("data-detect-timezone");
      let zone;
      try { zone = Intl.DateTimeFormat().resolvedOptions().timeZone; } catch (_) { return; }
      const option = zone && select.querySelector(`option[data-iana="${CSS.escape(zone)}"]`);
      if (!option || option.selected) return;
      select.value = option.value;
      const form = select.closest("form");
      if (form) schedulePreview(form);
    });
  };

  const dismissFlashes = () => {
    document.querySelectorAll("[data-flashes] .alert-success").forEach((alert) => {
      setTimeout(() => alert.remove(), 5000);
    });
  };

  const init = (root) => {
    root.querySelectorAll("form.editor").forEach((form) => syncEditor(form));
    detectPreviewTimezone(root);
    dismissFlashes();
    applyTheme(currentTheme());
  };

  document.addEventListener("DOMContentLoaded", () => init(document));
  document.addEventListener("turbo:load", () => { dirtyForm = null; init(document); });
  document.addEventListener("turbo:frame-load", (event) => init(event.target));
})();
