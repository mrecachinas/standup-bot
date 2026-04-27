(() => {
  const editorSelector = "[data-question-editor]";
  const listSelector = "[data-question-list]";
  const rowSelector = "[data-question-row]";
  const inputSelector = "[data-question-input]";
  const positionSelector = "[data-question-position]";
  const moveSelector = "[data-question-move]";

  const rowsFor = (editor) => Array.from(editor.querySelectorAll(rowSelector));

  const refreshQuestionRows = (editor) => {
    rowsFor(editor).forEach((row, index, rows) => {
      row.querySelector(positionSelector).textContent = index + 1;

      const input = row.querySelector(inputSelector);
      input.setAttribute("aria-label", `Question ${index + 1}`);

      row.querySelectorAll(moveSelector).forEach((button) => {
        const direction = button.dataset.questionMove;
        button.disabled = (direction === "up" && index === 0) || (direction === "down" && index === rows.length - 1);
        button.setAttribute("aria-label", `Move question ${index + 1} ${direction}`);
      });
    });
  };

  const refreshQuestionEditors = () => {
    document.querySelectorAll(editorSelector).forEach(refreshQuestionRows);
  };

  const addQuestionRow = (editor) => {
    const list = editor.querySelector(listSelector);
    const existingRows = rowsFor(editor);
    const row = existingRows[existingRows.length - 1].cloneNode(true);
    const input = row.querySelector(inputSelector);

    input.value = "";
    list.append(row);
    refreshQuestionRows(editor);
    input.focus();
  };

  const moveQuestionRow = (editor, button) => {
    const row = button.closest(rowSelector);
    const direction = button.dataset.questionMove;

    if (direction === "up" && row.previousElementSibling) {
      row.previousElementSibling.before(row);
    } else if (direction === "down" && row.nextElementSibling) {
      row.nextElementSibling.after(row);
    }

    refreshQuestionRows(editor);
    row.querySelector(inputSelector).focus();
  };

  document.addEventListener("click", (event) => {
    const addButton = event.target.closest("[data-question-add]");
    const moveButton = event.target.closest(moveSelector);
    const editor = event.target.closest(editorSelector);

    if (!editor || (!addButton && !moveButton)) return;

    event.preventDefault();

    if (addButton) {
      addQuestionRow(editor);
    } else {
      moveQuestionRow(editor, moveButton);
    }
  });

  document.addEventListener("DOMContentLoaded", refreshQuestionEditors);
  document.addEventListener("turbo:load", refreshQuestionEditors);
  document.addEventListener("turbo:frame-load", refreshQuestionEditors);
})();
