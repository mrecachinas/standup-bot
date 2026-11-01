(() => {
  const WEEKDAY_TYPES = new Set(["custom", "weekly", "biweekly"]);

  const toggleSection = (section, visible) => {
    if (!section) return;
    section.hidden = !visible;
    section.querySelectorAll("input, select").forEach((input) => {
      input.disabled = !visible;
    });
  };

  const syncScheduleFields = (root = document) => {
    root.querySelectorAll("[data-schedule-type-select]").forEach((select) => {
      const form = select.closest("form");
      if (!form) return;
      toggleSection(form.querySelector("[data-weekday-schedule-section]"), WEEKDAY_TYPES.has(select.value));
      toggleSection(form.querySelector("[data-monthly-schedule-section]"), select.value === "monthly");
    });
  };

  const renumber = (editor) => {
    editor.querySelectorAll("[data-row-index]").forEach((badge, index) => {
      badge.textContent = index + 1;
    });
  };

  const addRow = (editor) => {
    const template = editor.querySelector("template");
    const list = editor.querySelector("[data-rows]");
    if (!template || !list) return;
    const index = Date.now().toString();
    const fragment = template.content.cloneNode(true);
    fragment.querySelectorAll("[name], [id], [for]").forEach((element) => {
      ["name", "id", "for"].forEach((attribute) => {
        const value = element.getAttribute(attribute);
        if (value) element.setAttribute(attribute, value.replaceAll("__INDEX__", index));
      });
    });
    list.appendChild(fragment);
    renumber(editor);
    const inputs = list.querySelectorAll("input[type=text]");
    inputs[inputs.length - 1]?.focus();
  };

  let previewTimer;
  const schedulePreview = (form) => {
    const button = form.querySelector("[data-preview-button]");
    if (!button || typeof form.requestSubmit !== "function") return;
    clearTimeout(previewTimer);
    previewTimer = setTimeout(() => form.requestSubmit(button), 250);
  };

  document.addEventListener("click", (event) => {
    const add = event.target.closest("[data-add-row]");
    if (add) {
      event.preventDefault();
      addRow(add.closest("[data-row-editor]"));
      return;
    }

    const remove = event.target.closest("[data-remove-row]");
    if (remove) {
      event.preventDefault();
      const editor = remove.closest("[data-row-editor]");
      const row = remove.closest("[data-row]");
      const rows = editor.querySelectorAll("[data-row]");
      if (rows.length > 1) {
        row.remove();
      } else {
        row.querySelectorAll("input[type=text]").forEach((input) => { input.value = ""; });
      }
      renumber(editor);
      return;
    }

    document.querySelectorAll("details.menu[open]").forEach((menu) => {
      if (!menu.contains(event.target)) menu.removeAttribute("open");
    });
  });

  document.addEventListener("change", (event) => {
    if (event.target.matches("[data-schedule-type-select]")) syncScheduleFields(event.target.closest("form"));
    const form = event.target.closest("form");
    if (form && event.target.closest("[data-schedule-input]")) schedulePreview(form);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") {
      document.querySelectorAll("details.menu[open]").forEach((menu) => menu.removeAttribute("open"));
    }
  });

  const dismissFlashes = () => {
    document.querySelectorAll("[data-flashes] .alert-success").forEach((alert) => {
      setTimeout(() => alert.remove(), 5000);
    });
  };

  const init = (root) => {
    syncScheduleFields(root);
    dismissFlashes();
  };

  document.addEventListener("DOMContentLoaded", () => init(document));
  document.addEventListener("turbo:load", () => init(document));
  document.addEventListener("turbo:frame-load", (event) => init(event.target));
})();
