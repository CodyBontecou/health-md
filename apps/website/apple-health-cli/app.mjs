import { buildCommand } from './command.mjs';

const form = document.querySelector('#builder');
const output = document.querySelector('#command');
const copy = document.querySelector('#copy');
const status = document.querySelector('#copy-status');
const error = document.querySelector('#error');
const custom = document.querySelector('#custom-dates');
const note = document.querySelector('#output-note');
let command = '';

function render() {
  const values = Object.fromEntries(new FormData(form));
  custom.hidden = values.range !== 'custom';
  status.textContent = '';
  copy.textContent = 'Copy command';
  try {
    const result = buildCommand(values);
    command = result.command;
    output.textContent = command;
    error.textContent = '';
    copy.disabled = false;
    note.textContent = result.receipt
      ? `Saves ${result.filename}. The extraction receipt is saved separately as ${result.receipt}.`
      : `Saves ${result.filename}, including an extraction receipt with status and missing dates.`;
  } catch (cause) {
    command = '';
    output.textContent = 'Choose your dates to see the command.';
    error.textContent = cause.message;
    copy.disabled = true;
    note.textContent = '';
  }
}
form.addEventListener('input', render);
form.addEventListener('change', render);
form.addEventListener('submit', (event) => event.preventDefault());
copy.addEventListener('click', async () => {
  const current = command;
  try {
    await navigator.clipboard.writeText(current);
    if (command === current) {
      copy.textContent = 'Copied';
      status.textContent = 'Command copied. Paste it into your computer’s terminal.';
    }
  } catch {
    const selection = window.getSelection();
    const range = document.createRange();
    range.selectNodeContents(output);
    selection.removeAllRanges();
    selection.addRange(range);
    status.textContent = 'Clipboard unavailable. The command is selected; copy it manually.';
  }
});
render();
