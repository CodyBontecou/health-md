"use strict";
const $ = (id) => document.getElementById(id);
const status = (text) => { $("message").textContent = text; };

async function api(path, method = "GET", body) {
  const response = await fetch(path, {
    method,
    credentials: "same-origin",
    cache: "no-store",
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(method !== "GET" ? { "X-HealthMd-Intent": "dashboard" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.message || "Request failed. Please retry.");
  return result;
}

function addTextRow(list, label, details, action) {
  const row = document.createElement("li");
  const text = document.createElement("span");
  text.textContent = `${label} · ${details}`;
  row.append(text);
  if (action) row.append(action);
  list.append(row);
}

async function showTokens() {
  const { tokens } = await api("/api/ingest-tokens");
  const list = $("token-list");
  list.replaceChildren();
  if (!tokens.length) addTextRow(list, "No tokens yet", "Create one to connect your phone");
  for (const token of tokens) {
    const details = token.revokedAt ? "Revoked" : `•••• ${token.lastFour}`;
    let button = null;
    if (!token.revokedAt) {
      button = document.createElement("button");
      button.className = "subtle";
      button.textContent = "Revoke";
      button.addEventListener("click", async () => {
        if (!confirm(`Revoke export token ${token.name}? Your phone will stop uploading until you add a new token.`)) return;
        try {
          await api(`/api/ingest-tokens/${token.id}`, "DELETE");
          status("Export token revoked.");
          await showTokens();
        } catch (error) { status(error.message); }
      });
    }
    addTextRow(list, token.name, details, button);
  }
}

async function showExports() {
  const { exports, days, storage } = await api("/api/exports");
  $("storage").textContent = `${storage.count} envelopes · ${(storage.bytes / 1048576).toFixed(2)} MiB stored (first 50 shown)`;
  const list = $("export-list");
  list.replaceChildren();
  if (!exports.length) addTextRow(list, "No exports yet", "Send a single day from your phone to begin");
  for (const item of exports) {
    const link = document.createElement("a");
    link.href = `/api/exports/${item.id}/download`;
    link.textContent = "Download JSON";
    addTextRow(list, `${item.dateStart} – ${item.dateEnd}`,
      `${item.recordCount} days · ${item.source} · ${new Date(item.receivedAt).toLocaleString()}`, link);
  }
  const dayList = $("day-list");
  dayList.replaceChildren();
  if (!days.length) addTextRow(dayList, "No daily snapshots", "Send an export to begin");
  for (const day of days) {
    addTextRow(dayList, day.date, `v${day.schemaVersion} · ${day.captureStatus || "status not reported"}`);
  }
}

async function initLogin() {
  const fragment = new URLSearchParams(location.hash.slice(1));
  const token = fragment.get("token");
  if (location.hash) history.replaceState(null, "", location.pathname);
  let runtime;
  try { runtime = await api("/api/runtime"); }
  catch (error) { status(error.message); return; }
  $("login-form").hidden = runtime.authMode !== "email_link";
  $("password-form").hidden = runtime.authMode !== "password";
  $("unbacked-warning").hidden = !runtime.unbackedPersonalMvp;
  if (runtime.authMode === "email_link") {
    $("login-description").textContent = "Request a single-use email link to access your private export dashboard.";
    if (token) {
      status("Verifying your sign-in link…");
      try {
        await api("/api/auth/consume-link", "POST", { token });
        location.replace("/dashboard");
      } catch (error) { status(error.message); }
    }
  }
  $("login-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const response = await api("/api/auth/request-link", "POST", { email: $("email").value });
      status(response.message);
      if (response.devLink) {
        const link = document.createElement("a");
        link.href = response.devLink;
        link.textContent = "Development sign-in link";
        $("message").append(document.createTextNode(" "), link);
      }
    } catch (error) { status(error.message); }
  });
  $("password-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      await api("/api/auth/password-login", "POST", {
        username: $("username").value, password: $("password").value,
      });
      $("password").value = "";
      location.replace("/dashboard");
    } catch (error) { $("password").value = ""; status(error.message); }
  });
}

async function initDashboard() {
  $("endpoint").value = `${location.origin}/api/v1/exports`;
  $("logout").addEventListener("click", async () => {
    try {
      await api("/api/auth/logout", "POST");
      location.replace("/login");
    } catch (error) { status(error.message); }
  });
  $("create-token-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const result = await api("/api/ingest-tokens", "POST", { name: $("token-name").value });
      $("new-token").value = result.token;
      $("new-token-panel").hidden = false;
      $("token-name").value = "";
      status("Copy your write-only token now. It will not be shown again.");
      await showTokens();
    } catch (error) { status(error.message); }
  });
  $("hide-token").addEventListener("click", () => {
    $("new-token").value = "";
    $("new-token-panel").hidden = true;
  });
  $("delete-account-form").addEventListener("submit", async (event) => {
    event.preventDefault();
    try {
      const result = await api("/api/account/delete", "POST", {
        password: $("delete-password").value,
        confirmation: $("delete-confirmation").value,
      });
      $("delete-password").value = "";
      $("connect-section").hidden = true;
      $("deletion-section").hidden = true;
      $("export-list").replaceChildren();
      $("day-list").replaceChildren();
      status(`Account disabled. Deletion job ${result.deletionId} is pending; contact the operator to confirm completion.`);
    } catch (error) { $("delete-password").value = ""; status(error.message); }
  });
  try {
    const runtime = await api("/api/runtime");
    $("synthetic-warning").hidden = !runtime.syntheticPreviewOnly;
    $("unbacked-warning").hidden = !runtime.unbackedPersonalMvp;
    $("connect-section").hidden = runtime.syntheticPreviewOnly;
    $("deletion-section").hidden = runtime.syntheticPreviewOnly || runtime.authMode !== "password";
    const account = await api("/api/account");
    $("account").textContent = `Signed in as ${account.email}`;
    await Promise.all([showTokens(), showExports()]);
  } catch (error) {
    if (error.message === "Sign in to continue.") location.replace("/login");
    else status(error.message);
  }
}

if (document.body.dataset.page === "login") initLogin();
if (document.body.dataset.page === "dashboard") initDashboard();
