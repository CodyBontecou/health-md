import { combineHealthmdCsv, CsvCombineError } from './csv-combiner-core.js';

export function mountCsvCombiner(root, { urlApi = URL, BlobType = Blob } = {}) {
  const select = name => root.querySelector(`[data-csv-${name}]`);
  const files = select('files'), combine = select('combine'), demo = select('demo'), clear = select('clear');
  const status = select('status'), error = select('error'), download = select('download');
  let generation = 0, objectUrl = null;
  function discardResult() {
    if (objectUrl) urlApi.revokeObjectURL(objectUrl);
    objectUrl = null;
    download.hidden = true;
    download.removeAttribute('href');
  }
  function busy(value) {
    root.setAttribute('aria-busy', String(value));
    files.disabled = value; demo.disabled = value;
    combine.disabled = value || !files.files.length;
  }
  function reset() {
    generation++;
    discardResult();
    files.value = '';
    error.hidden = true; error.textContent = '';
    status.textContent = 'Choose daily CSV exports, or try the fictional example.';
    clear.disabled = true;
    busy(false);
  }
  async function run(selection, example = false) {
    const current = ++generation;
    discardResult(); error.hidden = true; error.textContent = '';
    clear.disabled = false; busy(true);
    try {
      const result = await combineHealthmdCsv(selection, {
        isCancelled: () => current !== generation,
        onProgress: (file, count) => { status.textContent = `Reading file ${file} of ${count} in this tab…`; },
      });
      if (current !== generation) return;
      objectUrl = urlApi.createObjectURL(new BlobType([result.csv], { type: 'text/csv;charset=utf-8' }));
      download.href = objectUrl;
      download.download = example ? 'healthmd-combined-example.csv' : 'healthmd-combined.csv';
      download.hidden = false;
      status.textContent = `${example ? 'Fictional example: ' : ''}${result.fileCount} files combined; ${result.rowCount} rows copied. One header is kept. Duplicate rows remain.${result.repeatedHeaders ? ` ${result.repeatedHeaders} extra header rows removed.` : ''}`;
    } catch (problem) {
      if (current !== generation) return;
      error.textContent = problem instanceof CsvCombineError ? problem.message : 'The files could not be combined. Clear the selection and try smaller exports.';
      error.hidden = false;
      status.textContent = 'No combined file was created.';
    } finally { if (current === generation) busy(false); }
  }
  files.addEventListener('change', () => {
    generation++; discardResult(); error.hidden = true; error.textContent = '';
    clear.disabled = !files.files.length;
    status.textContent = files.files.length ? `${files.files.length} files selected. Ready to combine in selection order.` : 'Choose daily CSV exports, or try the fictional example.';
    busy(false);
  });
  combine.addEventListener('click', () => run(Array.from(files.files)));
  demo.addEventListener('click', () => {
    // Deliberately tiny, fictional examples; never fetch or upload a user's file.
    const header = 'Date,Category,Metric,Value,Unit,Timestamp\n';
    const examples = [
      '2026-03-15,Activity,Steps,12500,count\n2026-03-15,Sleep,Total Duration,27900,seconds\n',
      '2026-03-16,Activity,Steps,11000,count\n2026-03-16,Sleep,Total Duration,28800,seconds\n',
    ].map((body, index) => {
      const blob = new BlobType([header, body], { type: 'text/csv' });
      return { name: `example-${index + 1}.csv`, size: blob.size, arrayBuffer: () => blob.arrayBuffer() };
    });
    return run(examples, true);
  });
  clear.addEventListener('click', reset);
  root.removeAttribute('hidden');
  reset();
}

if (typeof document !== 'undefined') {
  const root = document.querySelector('[data-csv-combiner]');
  if (root) mountCsvCombiner(root);
}
