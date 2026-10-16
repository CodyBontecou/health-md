const metrics = {
  steps: 'steps',
  sleep: 'sleep_total',
  heart: 'resting_heart_rate',
  workouts: 'workouts',
};

function validDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;
}

export function buildCommand({ metric, range, format, detail, from, to }) {
  if (!Object.hasOwn(metrics, metric) || !['json', 'jsonl'].includes(format) ||
      !['summary', 'lossless'].includes(detail)) throw new Error('Choose a supported metric, format, and detail level.');
  let dates;
  if (range === 'yesterday') dates = '--yesterday';
  else if (['7', '30', '90'].includes(range)) dates = `--last ${range}`;
  else if (range === 'custom') {
    if (!validDate(from) || !validDate(to)) throw new Error('Choose a valid start and end date.');
    if (from > to) throw new Error('End date must be on or after start date.');
    dates = `--from ${from} --to ${to}`;
  } else throw new Error('Choose a supported date range.');
  const filename = `${metrics[metric].replaceAll('_', '-')}.${format}`;
  return {
    command: `healthmd extract --metric ${metrics[metric]} ${dates} --detail ${detail} --format ${format} --output ${filename}`,
    filename,
    receipt: format === 'jsonl' ? `${filename}.receipt.json` : null,
  };
}
