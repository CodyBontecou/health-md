const ISO_WEEKDAY = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

function getZonedParts(utcMs, tz) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    weekday: "short",
    hourCycle: "h23"
  }).formatToParts(new Date(utcMs));
  const get = (type) => parts.find((p) => p.type === type).value;
  const weekday = ISO_WEEKDAY[get("weekday")] ?? 0;
  return {
    year: Number(get("year")),
    month: Number(get("month")),
    day: Number(get("day")),
    hour: Number(get("hour")),
    minute: Number(get("minute")),
    second: Number(get("second")),
    weekday
  };
}
function tzOffsetMinutes(tz, utcMs) {
  const z = getZonedParts(utcMs, tz);
  const asUtc = Date.UTC(z.year, z.month - 1, z.day, z.hour, z.minute, z.second);
  return Math.round((asUtc - utcMs) / 6e4);
}
function zonedTimeToUtcMs(year, month, day, hour, minute, tz) {
  let guess = Date.UTC(year, month - 1, day, hour, minute);
  const offset1 = tzOffsetMinutes(tz, guess);
  guess -= offset1 * 6e4;
  const offset2 = tzOffsetMinutes(tz, guess);
  if (offset2 !== offset1)
    guess -= (offset2 - offset1) * 6e4;
  return guess;
}
function computeNextFire(schedule, tz, nowSec) {
  const nowMs = nowSec * 1e3;
  const z = getZonedParts(nowMs, tz);
  let candidate = zonedTimeToUtcMs(z.year, z.month, z.day, schedule.hour, schedule.minute, tz);
  let daysToAdd = 0;
  if (schedule.frequency === "daily") {
    if (candidate <= nowMs)
      daysToAdd = 1;
  } else {
    const target = schedule.weekday;
    if (target === void 0 || target < 1 || target > 7) {
      throw new Error("Weekly schedule requires weekday in [1,7]");
    }
    daysToAdd = (target - z.weekday + 7) % 7;
    if (daysToAdd === 0 && candidate <= nowMs)
      daysToAdd = 7;
  }
  if (daysToAdd > 0) {
    candidate = zonedTimeToUtcMs(
      z.year,
      z.month,
      z.day + daysToAdd,
      schedule.hour,
      schedule.minute,
      tz
    );
  }
  return Math.floor(candidate / 1e3);
}

export { computeNextFire };
