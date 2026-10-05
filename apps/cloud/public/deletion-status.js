(() => {
"use strict";
const form = document.getElementById("deletion-status-form");
const tokenInput = document.getElementById("deletion-status-token");
const status = document.getElementById("status");
let sequence = 0;
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const current = ++sequence;
  status.textContent = "Checking…";
  try {
    const response = await fetch("/api/account/deletion-status", {
      method: "GET", credentials: "omit", cache: "no-store",
      headers: { Authorization: `Bearer ${tokenInput.value}` },
    });
    const body = await response.json();
    if (current !== sequence) return;
    if (!response.ok) throw new Error(body.message || "Deletion status is unavailable.");
    status.textContent = body.status === "completed" ?
      "Deletion completed. The account and retained encrypted exports were removed." :
      "Deletion is pending. Access remains disabled while encrypted exports are removed.";
  } catch (error) {
    if (current === sequence) status.textContent = error instanceof Error ? error.message : "Deletion status is unavailable.";
  }
});
window.addEventListener("pagehide", () => { sequence++; tokenInput.value = ""; status.textContent = ""; });
})();
