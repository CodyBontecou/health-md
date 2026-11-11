// Local-only Health.md CSV handling. No network, storage, metric reduction or deduplication.
export const CSV_HEADER = Object.freeze(['Date', 'Category', 'Metric', 'Value', 'Unit', 'Timestamp']);
export const CSV_LIMITS = Object.freeze({ files: 31, fileBytes: 1024 * 1024, totalBytes: 5 * 1024 * 1024, rows: 50000, fieldChars: 256 * 1024 });
export class CsvCombineError extends Error {}
const fail = message => { throw new CsvCombineError(message); };
const sameHeader = row => row.length === CSV_HEADER.length && row.every((cell, i) => cell === CSV_HEADER[i]);

export function parseHealthmdCsv(input) {
  const text = input.replace(/^\uFEFF/, '');
  const rows = [];
  let row = [], field = '', quoted = false, closed = false, started = false;
  function fieldEnd() {
    row.push(field);
    if (row.length > 6) fail('A row has more than six fields. Use an original Health.md CSV export.');
    field = ''; closed = false; started = false;
  }
  function rowEnd() {
    fieldEnd();
    if (!(row.length === 1 && row[0] === '')) rows.push(row);
    if (rows.length > CSV_LIMITS.rows + 1) fail('Too many rows. Combine a smaller selection.');
    row = [];
  }
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (quoted) {
      if (char === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else { quoted = false; closed = true; }
      } else field += char;
    } else if (char === ',') fieldEnd();
    else if (char === '\r' || char === '\n') {
      rowEnd();
      if (char === '\r' && text[i + 1] === '\n') i++;
    } else if (closed) fail('Unexpected text after a quoted field. Use an original CSV export.');
    else if (char === '"') {
      if (started) fail('A quote appears inside an unquoted field. Use an original CSV export.');
      quoted = true; started = true;
    } else { field += char; started = true; }
    if (field.length > CSV_LIMITS.fieldChars) fail('A field is too large. Use smaller Summary exports.');
  }
  if (quoted) fail('A quoted field is incomplete. Select the complete CSV file.');
  if (row.length || started || closed || field.length) rowEnd();
  if (!rows.length || !sameHeader(rows[0])) fail('Expected Date,Category,Metric,Value,Unit,Timestamp. XML archives and other CSV layouts are not supported.');
  return rows;
}

function validateCell(cell) {
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(cell)) fail('A field contains unsupported control characters. Use an original CSV export.');
  const trimmed = cell.trimStart();
  const numeric = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(trimmed);
  if (/^[\t\r\n]/.test(cell) || (/^[=+\-@＝＋－＠]/.test(trimmed) && !numeric)) {
    fail('A formula-like field was found. Use original exports rather than spreadsheet formulas.');
  }
}

export async function combineHealthmdCsv(files, { onProgress = () => {}, isCancelled = () => false } = {}) {
  const selection = Array.from(files);
  if (!selection.length) fail('Choose at least one Health.md CSV file.');
  if (selection.length > CSV_LIMITS.files) fail('Choose no more than 31 files at a time.');
  let totalBytes = 0;
  for (const file of selection) {
    if (!file || typeof file.arrayBuffer !== 'function' || !/\.csv$/i.test(file.name || '')) fail('Choose files ending in .csv.');
    if (!Number.isSafeInteger(file.size) || file.size < 0 || file.size > CSV_LIMITS.fileBytes) fail('Each file must be 1 MiB or smaller. Use smaller Summary exports.');
    totalBytes += file.size;
  }
  if (totalBytes > CSV_LIMITS.totalBytes) fail('The selection must be 5 MiB or smaller. Combine fewer files.');
  const output = [CSV_HEADER.join(',')];
  let rowCount = 0, repeatedHeaders = 0;
  for (let i = 0; i < selection.length; i++) {
    if (isCancelled()) fail('Cancelled.');
    onProgress(i + 1, selection.length);
    let bytes;
    try { bytes = await selection[i].arrayBuffer(); }
    catch { fail(`File ${i + 1} could not be read. Select it again.`); }
    if (isCancelled()) fail('Cancelled.');
    if (bytes.byteLength !== selection[i].size || bytes.byteLength > CSV_LIMITS.fileBytes) fail('A file changed while reading. Select the files again.');
    let text;
    try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
    catch { fail(`File ${i + 1} is not valid UTF-8. Export it as UTF-8 CSV first.`); }
    let rows;
    try { rows = parseHealthmdCsv(text); }
    catch (error) { if (error instanceof CsvCombineError) fail(`File ${i + 1}: ${error.message}`); throw error; }
    for (const row of rows.slice(1)) {
      if (sameHeader(row)) { repeatedHeaders++; continue; }
      if (row.length !== 5 && row.length !== 6) fail(`File ${i + 1} contains a row with an unexpected field count. Expected five or six fields.`);
      for (const cell of row) validateCell(cell);
      if (++rowCount > CSV_LIMITS.rows) fail('The combined selection exceeds 50,000 rows. Combine fewer files.');
      // Quote every value, retain five/six-field shape, and never interpret numeric cells.
      output.push(row.map(cell => '"' + cell.replaceAll('"', '""') + '"').join(','));
    }
    await new Promise(resolve => setTimeout(resolve, 0));
  }
  if (isCancelled()) fail('Cancelled.');
  return { csv: '\uFEFF' + output.join('\r\n') + '\r\n', rowCount, fileCount: selection.length, repeatedHeaders };
}
