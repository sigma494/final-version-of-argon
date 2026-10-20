/* argon/web/app.js - the whole front end. No frameworks, no build step.
 *
 * Rules followed here:
 *  - every value from the vault is inserted with textContent (never innerHTML),
 *    so an entry named `<img onerror=...>` stays a string;
 *  - the session token comes from a <meta> tag the server fills in;
 *  - secrets are fetched on demand per entry, revealed only on request, and
 *    cleared from the DOM when you navigate away or lock.
 */
"use strict";

const TOKEN = (document.querySelector('meta[name="argon-token"]') || {}).content || "";
const $ = (id) => document.getElementById(id);
const IDLE_LOCK_MS = 15 * 60 * 1000;

const state = {
  entries: [],
  selectedId: null,
  detail: null,
  revealed: false,
  totp: { code: "", remaining: 0, timer: null, entryId: null },
  idleTimer: null,
  q: "",
};

/* ------------------------------------------------------------------ */
/* api                                                                 */
/* ------------------------------------------------------------------ */
async function api(path, { method = "GET", body } = {}) {
  const res = await fetch(`/api/${path}`, {
    method,
    headers: {
      "X-Argon-Token": TOKEN,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
    credentials: "same-origin",
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `${res.status} ${res.statusText}`);
  return data;
}

/* ------------------------------------------------------------------ */
/* helpers                                                             */
/* ------------------------------------------------------------------ */
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === "class") node.className = v;
    else if (k === "text") node.textContent = v;
    else if (k === "dataset") Object.assign(node.dataset, v);
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else if (v !== null && v !== undefined) node.setAttribute(k, v);
  }
  for (const child of children) {
    if (child === null || child === undefined) continue;
    node.appendChild(typeof child === "string" ? document.createTextNode(child) : child);
  }
  return node;
}

function toast(message, kind = "ok") {
  const node = el("div", { class: `toast ${kind === "error" ? "error" : ""}`, text: message });
  $("toasts").appendChild(node);
  setTimeout(() => node.remove(), 3200);
}

async function copyText(text, label = "Copied") {
  if (!text) return toast("Nothing to copy", "error");
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    const ta = el("textarea", {});
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch { toast("Copy failed", "error"); }
    ta.remove();
  }
  toast(`${label} - clears clipboard in 30s`);
  setTimeout(async () => {
    try {
      const current = await navigator.clipboard.readText();
      if (current === text) await navigator.clipboard.writeText("");
    } catch { /* clipboard read needs permission; ignore */ }
  }, 30000);
}

function setMeter(fillEl, bits, labelEl) {
  const pct = Math.max(4, Math.min(100, (bits / 100) * 100));
  fillEl.style.width = `${pct}%`;
  fillEl.style.background = bits < 40 ? "#f87171" : bits < 60 ? "#fbbf24" : bits < 80 ? "#34d399" : "#2dd4bf";
  if (labelEl) labelEl.textContent = `${bits.toFixed(0)} bits of entropy`;
}

/* ------------------------------------------------------------------ */
/* gate: unlock or create                                              */
/* ------------------------------------------------------------------ */
function showGate(mode, status, message) {
  $("gate").hidden = false;
  $("workspace").hidden = true;
  $("new-btn").hidden = true;
  $("lock-btn").hidden = true;
  $("audit-btn").hidden = true;
  $("status-pill").hidden = true;

  const creating = mode === "create";
  $("gate-title").textContent = creating ? "Create your vault" : "Unlock your vault";
  $("gate-hint").textContent = creating
    ? "Pick a master password. It is never stored - lose it and the data is gone."
    : "Your master password never leaves this process.";
  $("confirm-field").hidden = !creating;
  $("meter").hidden = !creating;
  $("master-confirm").required = creating;
  $("gate-submit").textContent = creating ? "Create vault" : "Unlock";
  $("gate-path").textContent = status && status.path ? `vault: ${status.path}` : "";
  $("gate-error").hidden = !message;
  if (message) $("gate-error").textContent = message;
  $("master-password").value = "";
  $("master-confirm").value = "";
  $("master-password").focus();
}

async function onSubmitGate(event) {
  event.preventDefault();
  const password = $("master-password").value;
  const confirm = $("master-confirm").value;
  const creating = !$("confirm-field").hidden;
  const btn = $("gate-submit");
  btn.disabled = true;
  btn.textContent = creating ? "Deriving key..." : "Deriving key...";
  $("gate-error").hidden = true;
  try {
    if (creating) {
      if (password !== confirm) throw new Error("passwords did not match");
      if (password.length < 8) throw new Error("use at least 8 characters");
      await api("init", { method: "POST", body: { password, confirm } });
    } else {
      await api("unlock", { method: "POST", body: { password } });
    }
    $("master-password").value = "";
    $("master-confirm").value = "";
    await enterVault();
  } catch (err) {
    $("gate-error").hidden = false;
    $("gate-error").textContent = err.message;
    $("master-password").select();
  } finally {
    btn.disabled = false;
    btn.textContent = creating ? "Create vault" : "Unlock";
  }
}

async function enterVault() {
  $("gate").hidden = true;
  $("workspace").hidden = false;
  for (const id of ["new-btn", "lock-btn", "audit-btn", "status-pill"]) $(id).hidden = false;
  $("status-text").textContent = "unlocked";
  await loadEntries();
  resetIdle();
}

function lock() {
  stopTotp();
  state.detail = null;
  state.selectedId = null;
  state.revealed = false;
  state.entries = [];
  $("entry-view").hidden = true;
  $("entry-view").replaceChildren();
  $("detail-empty").hidden = false;
  $("entry-list").replaceChildren();
  api("lock", { method: "POST" }).catch(() => {});
  setLockedGate();
}

async function setLockedGate() {
  const status = await api("status").catch(() => ({ exists: true, path: "" }));
  showGate(status.exists ? "unlock" : "create", status, "");
}

/* ------------------------------------------------------------------ */
/* entries list                                                        */
/* ------------------------------------------------------------------ */
async function loadEntries() {
  const q = $("search").value.trim();
  const data = await api(`entries${q ? `?q=${encodeURIComponent(q)}` : ""}`);
  state.entries = data.entries;
  renderList();
}

function renderList() {
  const list = $("entry-list");
  list.replaceChildren();
  for (const entry of state.entries) {
    const chips = el("div", { class: "chips" });
    for (const tag of entry.tags.slice(0, 4)) chips.appendChild(el("span", { class: "chip", text: tag }));
    const li = el(
      "li",
      {
        class: entry.id === state.selectedId ? "active" : "",
        onclick: () => selectEntry(entry.id),
        tabindex: "0",
        onkeydown: (e) => { if (e.key === "Enter") selectEntry(entry.id); },
      },
      el("span", { class: "name", text: entry.name }),
      el("span", { class: "meta", text: entry.username || entry.url || "no username" }),
      entry.tags.length ? chips : null
    );
    list.appendChild(li);
  }
  const count = state.entries.length;
  $("list-count").textContent = state.q
    ? `${count} match${count === 1 ? "" : "es"}`
    : `${count} entr${count === 1 ? "y" : "ies"}`;
  if (!count && !$("search").value) {
    list.appendChild(el("li", { class: "muted", text: "No entries yet. Press N to add one." }));
  }
}

/* ------------------------------------------------------------------ */
/* entry detail                                                        */
/* ------------------------------------------------------------------ */
async function selectEntry(id) {
  stopTotp();
  state.selectedId = id;
  state.revealed = false;
  renderList();
  try {
    const data = await api(`entries/${encodeURIComponent(id)}`);
    state.detail = data.entry;
    renderDetail();
  } catch (err) {
    toast(err.message, "error");
  }
}

function detailRow(label, value, { mono = false, secret = false, field = "" } = {}) {
  const shown = secret && !state.revealed ? "•".repeat(Math.min(value.length, 24)) : value;
  const valueEl = el("div", { class: `value${mono ? " mono" : ""}`, text: shown });
  const actions = el("div", { class: "actions" });
  if (value) {
    actions.appendChild(el("button", {
      class: "btn icon ghost",
      text: "Copy",
      onclick: () => copyText(value, `${label} copied`),
    }));
  }
  if (secret && value) {
    actions.appendChild(el("button", {
      class: "btn icon ghost",
      text: state.revealed ? "Hide" : "Reveal",
      onclick: () => { state.revealed = !state.revealed; renderDetail(); },
    }));
  }
  return el("div", { class: "row" }, el("div", { class: "label", text: label }), valueEl, actions);
}

function renderDetail() {
  const entry = state.detail;
  if (!entry) return;
  const view = $("entry-view");
  $("detail-empty").hidden = true;
  view.hidden = false;
  view.replaceChildren();

  const url = entry.url
    ? el("a", { class: "url", href: /^https?:\/\//i.test(entry.url) ? entry.url : `https://${entry.url}`,
                target: "_blank", rel: "noopener noreferrer", text: entry.url })
    : null;

  view.appendChild(el("div", { class: "entry-head" },
    el("div", {}, el("h2", { text: entry.name }), url),
    el("div", { class: "actions" },
      el("button", { class: "btn ghost", text: "Edit", onclick: () => openEditor(entry) }),
      el("button", { class: "btn danger", text: "Delete", onclick: () => removeEntry(entry) })
    )
  ));

  if (entry.username) view.appendChild(detailRow("Username", entry.username, { mono: true }));
  if (entry.password) view.appendChild(detailRow("Password", entry.password, { mono: true, secret: true }));
  if (entry.totp) view.appendChild(totpRow(entry));

  if (entry.tags.length) {
    const chips = el("div", { class: "actions" });
    entry.tags.forEach((t) => chips.appendChild(el("span", { class: "chip", text: t })));
    view.appendChild(el("div", { class: "row" }, el("div", { class: "label", text: "Tags" }), chips));
  }
  if (entry.notes) {
    view.appendChild(el("div", { class: "row" },
      el("div", { class: "label", text: "Notes" }),
      el("div", { class: "value notes-block", text: entry.notes })
    ));
  }
  view.appendChild(el("div", { class: "entry-foot muted small", text: `updated ${entry.updated}` }));
}

function totpRow(entry) {
  const code = el("div", { class: "totp-code", text: "······" });
  const bar = el("div", {});
  const row = el("div", { class: "row" },
    el("div", { class: "label", text: "TOTP" }),
    el("div", { class: "value" }, code),
    el("div", { class: "totp-bar" }, bar),
    el("div", { class: "actions" },
      el("button", { class: "btn icon ghost", text: "Copy",
        onclick: () => copyText(code.textContent.replace(/[^0-9]/g, ""), "Code copied") })
    )
  );
  startTotp(entry.id, code, bar);
  return row;
}

function startTotp(id, codeEl, barEl) {
  stopTotp();
  state.totp.entryId = id;
  const refresh = async () => {
    try {
      const data = await api(`entries/${encodeURIComponent(id)}/totp`);
      state.totp.code = data.code;
      state.totp.remaining = data.remaining;
      codeEl.textContent = data.code.replace(/(\d{3})(?=\d)/, "$1 ");
      barEl.style.width = `${(data.remaining / 30) * 100}%`;
    } catch {
      stopTotp();
    }
  };
  refresh();
  state.totp.timer = setInterval(() => {
    state.totp.remaining -= 1;
    if (state.totp.remaining <= 0) refresh();
    else barEl.style.width = `${(state.totp.remaining / 30) * 100}%`;
  }, 1000);
}

function stopTotp() {
  if (state.totp.timer) clearInterval(state.totp.timer);
  state.totp.timer = null;
  state.totp.entryId = null;
}

async function removeEntry(entry) {
  if (!confirm(`Delete "${entry.name}"? This cannot be undone.`)) return;
  try {
    await api(`entries/${encodeURIComponent(entry.id)}`, { method: "DELETE" });
    state.detail = null;
    state.selectedId = null;
    $("entry-view").hidden = true;
    $("detail-empty").hidden = false;
    stopTotp();
    await loadEntries();
    toast("Entry deleted");
  } catch (err) {
    toast(err.message, "error");
  }
}

/* ------------------------------------------------------------------ */
/* editor                                                              */
/* ------------------------------------------------------------------ */
function openEditor(entry = null) {
  $("editor-title").textContent = entry ? "Edit entry" : "New entry";
  $("editor-id").value = entry ? entry.id : "";
  $("f-name").value = entry ? entry.name : "";
  $("f-username").value = entry ? entry.username : "";
  $("f-url").value = entry ? entry.url : "";
  $("f-tags").value = entry ? entry.tags.join(", ") : "";
  $("f-password").value = entry ? entry.password || "" : "";
  $("f-totp").value = entry ? entry.totp || "" : "";
  $("f-notes").value = entry ? entry.notes || "" : "";
  $("editor-error").hidden = true;
  $("gen-panel").hidden = true;
  $("editor-overlay").hidden = false;
  setTimeout(() => $("f-name").focus(), 40);
}

function closeEditor() {
  $("editor-overlay").hidden = true;
  $("editor-form").reset();
  $("editor-id").value = "";
}

async function saveEntry(event) {
  event.preventDefault();
  const id = $("editor-id").value;
  const payload = {
    name: $("f-name").value.trim(),
    username: $("f-username").value,
    url: $("f-url").value,
    tags: $("f-tags").value,
    password: $("f-password").value,
    totp: $("f-totp").value.trim(),
    notes: $("f-notes").value,
  };
  if (!payload.name) {
    $("editor-error").hidden = false;
    $("editor-error").textContent = "Name is required";
    return;
  }
  try {
    if (id) await api(`entries/${encodeURIComponent(id)}`, { method: "PUT", body: payload });
    else await api("entries", { method: "POST", body: payload });
    closeEditor();
    await loadEntries();
    const target = id || (state.entries.find((e) => e.name === payload.name) || {}).id;
    if (target) await selectEntry(target);
    toast(id ? "Entry updated" : "Entry saved");
  } catch (err) {
    $("editor-error").hidden = false;
    $("editor-error").textContent = err.message;
  }
}

async function generateIntoEditor() {
  $("gen-panel").hidden = false;
  const body = {
    length: Number($("gen-length").value),
    upper: $("gen-upper").checked,
    lower: $("gen-lower").checked,
    digits: $("gen-digits").checked,
    symbols: $("gen-symbols").checked,
    exclude_ambiguous: $("gen-ambiguous").checked,
  };
  try {
    const data = await api("generate", { method: "POST", body });
    $("f-password").value = data.password;
    $("gen-strength").textContent = `${data.strength.label} - ${data.strength.bits} bits`;
    setMeter($("gen-meter-fill"), data.strength.bits);
  } catch (err) {
    toast(err.message, "error");
  }
}

/* ------------------------------------------------------------------ */
/* audit                                                               */
/* ------------------------------------------------------------------ */
async function openAudit() {
  try {
    const data = await api("audit");
    $("audit-summary").textContent = data.ok
      ? `Chain verified: ${data.message}`
      : `CHAIN BROKEN: ${data.message}`;
    $("audit-summary").style.color = data.ok ? "" : "#f87171";
    const list = $("audit-list");
    list.replaceChildren();
    for (const record of [...data.records].reverse()) {
      list.appendChild(el("div", { class: "audit-row" },
        el("span", { text: record.ts }),
        el("span", { class: "action", text: record.action }),
        el("span", { text: record.detail })
      ));
    }
    $("audit-overlay").hidden = false;
  } catch (err) {
    toast(err.message, "error");
  }
}

/* ------------------------------------------------------------------ */
/* idle auto-lock + wiring                                             */
/* ------------------------------------------------------------------ */
function resetIdle() {
  if (state.idleTimer) clearTimeout(state.idleTimer);
  if ($("workspace").hidden) return;
  state.idleTimer = setTimeout(() => {
    if (!$("workspace").hidden) {
      lock();
      toast("Locked after 15 minutes idle");
    }
  }, IDLE_LOCK_MS);
}

function bind() {
  $("gate-form").addEventListener("submit", onSubmitGate);
  $("master-password").addEventListener("input", async (e) => {
    if ($("confirm-field").hidden) return;
    const pwd = e.target.value;
    if (!pwd) { setMeter($("meter-fill"), 0); $("meter-label").textContent = ""; return; }
    setMeter($("meter-fill"), estimateBits(pwd));
  });
  $("editor-form").addEventListener("submit", saveEntry);
  $("editor-cancel").addEventListener("click", closeEditor);
  $("gen-btn").addEventListener("click", generateIntoEditor);
  $("gen-length").addEventListener("input", (e) => { $("gen-length-label").textContent = e.target.value; generateIntoEditor(); });
  ["gen-upper", "gen-lower", "gen-digits", "gen-symbols", "gen-ambiguous"].forEach((id) =>
    $(id).addEventListener("change", generateIntoEditor)
  );
  $("new-btn").addEventListener("click", () => openEditor(null));
  $("lock-btn").addEventListener("click", () => { lock(); toast("Vault locked"); });
  $("audit-btn").addEventListener("click", openAudit);
  $("audit-close").addEventListener("click", () => { $("audit-overlay").hidden = true; });

  let searchTimer = null;
  $("search").addEventListener("input", () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(loadEntries, 140);
  });

  document.addEventListener("keydown", (e) => {
    const typing = ["INPUT", "TEXTAREA"].includes(document.activeElement.tagName);
    if (e.key === "Escape") {
      if (!$("editor-overlay").hidden) closeEditor();
      if (!$("audit-overlay").hidden) $("audit-overlay").hidden = true;
      return;
    }
    if (typing || $("workspace").hidden) return;
    if (e.key === "/") { e.preventDefault(); $("search").focus(); }
    if (e.key.toLowerCase() === "n") { e.preventDefault(); openEditor(null); }
    if (e.key.toLowerCase() === "l") { e.preventDefault(); lock(); }
  });

  ["click", "keydown", "mousemove"].forEach((evt) =>
    document.addEventListener(evt, () => { if (!$("workspace").hidden) resetIdle(); }, { passive: true })
  );
}

/* local estimate for the create screen (the server does the real scoring) */
function estimateBits(password) {
  let classes = 0;
  if (/[a-z]/.test(password)) classes += 26;
  if (/[A-Z]/.test(password)) classes += 26;
  if (/\d/.test(password)) classes += 10;
  if (/[^A-Za-z0-9]/.test(password)) classes += 33;
  const raw = password.length * Math.log2(Math.max(classes, 1));
  return Math.min(raw, 200);
}

async function boot() {
  bind();
  if (!TOKEN || TOKEN.includes("__ARGON")) {
    showGate("unlock", {}, "Open the page through the URL printed by `argon serve` (it carries a session token).");
    $("gate-submit").disabled = true;
    return;
  }
  try {
    const status = await api("status");
    if (status.unlocked) {
      await enterVault();          // page reload inside an unlocked session
      return;
    }
    showGate(status.exists ? "unlock" : "create", status, "");
  } catch (err) {
    showGate("unlock", {}, err.message);
  }
}

boot();
