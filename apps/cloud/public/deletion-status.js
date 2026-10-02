const form = document.getElementById("deletion-status-form");
const tokenInput = document.getElementById("deletion-status-token");
const status = document.getElementById("status");

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  status.textContent = "Checking…";
  try {
    const response = await fetch("/api/account/deletion-status", {
      method: "GET",
      credentials: "omit",
      cache: "no-store",
      headers: { Authorization: `Bearer ${tokenInput.value}` },
    });
    const body = await response.json();
    if (!response.ok) throw new Error(body.message || "Deletion status is unavailable.");
    status.textContent = body.status === "completed" ?
      "Deletion completed. The account and retained encrypted exports were removed." :
      "Deletion is pending. Access remains disabled while encrypted exports are removed.";
  } catch (error) {
    status.textContent = error instanceof Error ? error.message : "Deletion status is unavailable.";
  }
});
