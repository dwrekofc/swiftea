const { ItemView, Notice, Plugin, PluginSettingTab, Setting } = require("obsidian");
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");

const VIEW_TYPE = "swiftea-inbox-view";

const DEFAULT_SETTINGS = {
  cliPath: "swea",
  title: "Inbox",
  pageSize: 200,
  confirmDelete: true
};

const ROW_HEIGHT_PX = 44;
const OVERSCAN_ROWS = 10;

function execFileAsync(file, args, options) {
  return new Promise((resolve, reject) => {
    execFile(
      file,
      args,
      {
        ...options,
        windowsHide: true,
        maxBuffer: 1024 * 1024 * 20
      },
      (error, stdout, stderr) => {
        if (error) {
          const details = (stderr || stdout || "").trim();
          reject(new Error(details ? `${error.message}\n${details}` : error.message));
          return;
        }
        resolve({ stdout, stderr });
      }
    );
  });
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function formatShortDate(isoString) {
  if (!isoString) return "";
  const d = new Date(isoString);
  if (Number.isNaN(d.getTime())) return isoString;
  return d.toLocaleString(undefined, { month: "short", day: "2-digit" });
}

async function copyToClipboard(text) {
  const value = String(text || "");
  if (!value) return false;
  try {
    if (navigator?.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      return true;
    }
  } catch {
    // fall back below
  }

  try {
    const el = document.createElement("textarea");
    el.value = value;
    el.readOnly = true;
    el.style.position = "fixed";
    el.style.top = "-1000px";
    document.body.appendChild(el);
    el.select();
    const ok = document.execCommand("copy");
    el.remove();
    return ok;
  } catch {
    return false;
  }
}

class SwiftEAEmailSource {
  constructor(app, settings) {
    this.app = app;
    this.settings = settings;
  }

  getVaultPath() {
    const adapter = this.app.vault.adapter;
    if (!adapter || typeof adapter.getBasePath !== "function") {
      throw new Error("SwiftEA Inbox requires Obsidian Desktop (filesystem vault).");
    }
    return adapter.getBasePath();
  }

  resolveCliPath() {
    const vaultPath = this.getVaultPath();
    const configured = String(this.settings.cliPath || DEFAULT_SETTINGS.cliPath).trim() || DEFAULT_SETTINGS.cliPath;

    const candidates = [];

    // If user provided a path (absolute or relative), resolve relative to vault root.
    if (path.isAbsolute(configured) || configured.includes("/") || configured.startsWith(".")) {
      candidates.push(path.resolve(vaultPath, configured));
    } else {
      // Default/bare command: try common install locations first to avoid macOS GUI PATH issues.
      const home = process.env.HOME || "";
      candidates.push("/opt/homebrew/bin/swea");
      candidates.push("/usr/local/bin/swea");
      if (home) candidates.push(path.join(home, ".local", "bin", "swea"));
      if (home) candidates.push(path.join(home, "bin", "swea"));

      // Dev build locations when the vault is inside the repo (e.g., ./test-vault).
      candidates.push(path.resolve(vaultPath, "..", ".build", "arm64-apple-macosx", "debug", "swea"));
      candidates.push(path.resolve(vaultPath, "..", ".build", "debug", "swea"));

      // Fall back to PATH lookup last.
      candidates.push(configured);
    }

    for (const candidate of candidates) {
      try {
        if (!candidate) continue;
        if (candidate === configured) break; // PATH lookup fallback handled by returning configured
        fs.accessSync(candidate, fs.constants.X_OK);
        return candidate;
      } catch {
        // continue
      }
    }

    return configured;
  }

  async listInbox({ offset, limit }) {
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    const { stdout } = await execFileAsync(
      cli,
      ["mail", "inbox", "--json", "--limit", String(limit), "--offset", String(offset)],
      { cwd }
    );
    const parsed = JSON.parse(stdout);
    if (!Array.isArray(parsed)) throw new Error("Unexpected JSON from swea mail inbox.");
    return parsed.map((item) => ({
      id: String(item.id || ""),
      sender: String(item.sender || ""),
      subject: String(item.subject || ""),
      preview: String(item.preview || ""),
      date: String(item.date || "")
    }));
  }

  async getBody(id) {
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    const { stdout } = await execFileAsync(
      cli,
      ["mail", "show", String(id), "--json"],
      { cwd }
    );
    const parsed = JSON.parse(stdout);
    return {
      from: String(parsed.from || ""),
      subject: String(parsed.subject || ""),
      date: String(parsed.date || ""),
      body: String(parsed.body || "")
    };
  }

  async archiveMessage(id) {
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    await execFileAsync(cli, ["mail", "archive", "--id", String(id), "--yes"], { cwd });
  }

  async archiveMessages(ids) {
    const list = Array.isArray(ids) ? ids.map((v) => String(v).trim()).filter(Boolean) : [];
    if (!list.length) return;
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    await execFileAsync(cli, ["mail", "archive", "--ids", list.join(","), "--yes"], { cwd });
  }

  async deleteMessage(id) {
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    await execFileAsync(cli, ["mail", "delete", "--id", String(id), "--yes"], { cwd });
  }

  async deleteMessages(ids) {
    const list = Array.isArray(ids) ? ids.map((v) => String(v).trim()).filter(Boolean) : [];
    if (!list.length) return;
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    await execFileAsync(cli, ["mail", "delete", "--ids", list.join(","), "--yes"], { cwd });
  }

  async syncMail() {
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    await execFileAsync(cli, ["mail", "sync"], { cwd });
  }

  async ensureWatchDaemon(intervalSeconds = 60) {
    const cwd = this.getVaultPath();
    const cli = this.resolveCliPath();
    try {
      await execFileAsync(cli, ["mail", "sync", "--ensure-watch", "--interval", String(intervalSeconds)], { cwd });
    } catch (e) {
      const message = String(e?.message || "");
      if (message.includes("--ensure-watch")) {
        await execFileAsync(cli, ["mail", "sync", "--watch", "--interval", String(intervalSeconds)], { cwd });
        return;
      }
      throw e;
    }
  }
}

class SwiftEAInboxView extends ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
    this.source = new SwiftEAEmailSource(plugin.app, plugin.settings);

    this.emails = [];
    this.selectedIndex = 0;
    this.selectedIds = new Set();
    this.rangeAnchorIndex = null;
    this.isLoading = false;
    this.hasMore = true;
    this.overlayLoadSeq = 0;
    this.actionInProgress = false;
    this.overlayEmailId = null;
    this.manualSyncInProgress = false;
    this.externalRefreshTimer = null;
    this.fsWatcher = null;
    this.pollInterval = null;
    this.pendingExternalRefresh = false;

    this._onScroll = this.onScroll.bind(this);
    this._onKeyDownList = this.onKeyDownList.bind(this);
    this._onKeyDownOverlay = this.onKeyDownOverlay.bind(this);
  }

  getViewType() {
    return VIEW_TYPE;
  }

  getDisplayText() {
    return this.plugin.settings.title || "Inbox";
  }

  getIcon() {
    return "mail";
  }

  async onOpen() {
    this.containerEl.addClass("swiftea-inbox");
    this.contentEl.empty();

    this.headerEl = this.contentEl.createDiv({ cls: "swiftea-inbox__header" });
    this.headerRowEl = this.headerEl.createDiv({ cls: "swiftea-inbox__header-row" });
    this.headerTextEl = this.headerRowEl.createDiv({ cls: "swiftea-inbox__header-text" });
    this.titleEl = this.headerTextEl.createDiv({ cls: "swiftea-inbox__title" });
    this.countEl = this.headerTextEl.createDiv({ cls: "swiftea-inbox__count" });
    this.actionsEl = this.headerRowEl.createDiv({ cls: "swiftea-inbox__actions" });
    this.syncButtonEl = this.actionsEl.createEl("button", {
      cls: "swiftea-inbox__sync-button",
      text: "Sync"
    });
    this.syncButtonEl.addEventListener("click", (evt) => {
      evt.preventDefault();
      evt.stopPropagation();
      void this.runManualSync();
    });

    // Sync button state with plugin-level sync status (handles view recreation mid-sync)
    if (this.plugin._syncPromise) {
      this.setSyncButtonState(true);
    }

    this.columnsEl = this.headerEl.createDiv({ cls: "swiftea-inbox__columns" });
    this.columnsEl.createDiv({ cls: "swiftea-inbox__col swiftea-inbox__col--select", text: "" });
    this.columnsEl.createDiv({ cls: "swiftea-inbox__col swiftea-inbox__col--sender", text: "Sender" });
    this.columnsEl.createDiv({ cls: "swiftea-inbox__col swiftea-inbox__col--subject", text: "Subject" });
    this.columnsEl.createDiv({ cls: "swiftea-inbox__col swiftea-inbox__col--preview", text: "Preview" });
    this.columnsEl.createDiv({ cls: "swiftea-inbox__col swiftea-inbox__col--date", text: "Date" });

    this.statusContainerEl = this.contentEl.createDiv({ cls: "swiftea-inbox__status-container" });

    this.scrollEl = this.contentEl.createDiv({ cls: "swiftea-inbox__scroll" });
    this.scrollEl.setAttr("tabindex", "0");
    this.scrollEl.addEventListener("scroll", this._onScroll, { passive: true });
    this.scrollEl.addEventListener("keydown", this._onKeyDownList);

    this.spacerEl = this.scrollEl.createDiv({ cls: "swiftea-inbox__spacer" });
    this.rowsEl = this.spacerEl.createDiv({ cls: "swiftea-inbox__rows" });

    this.hintEl = this.contentEl.createDiv({ cls: "swiftea-inbox__hint" });
    this.hintEl.setText(
      "Click/Cmd+click/Shift+click select • Shift+↑/↓ range • Enter open • e archive • d delete • Esc close • g/G jump • Ctrl+u/d page"
    );

    this.updateHeader();
    this.scrollEl.focus();

    await this.reload();
    this.startRealtimeRefresh();
  }

  async onClose() {
    this.closeOverlay();
    this.stopRealtimeRefresh();
    if (this.scrollEl) {
      this.scrollEl.removeEventListener("scroll", this._onScroll);
      this.scrollEl.removeEventListener("keydown", this._onKeyDownList);
    }
  }

  updateHeader() {
    const title = this.plugin.settings.title || "Inbox";
    this.titleEl.setText(title);
    this.countEl.setText(this.emails.length ? `(${this.emails.length} emails)` : "");
  }

  async reload() {
    this.emails = [];
    this.selectedIndex = 0;
    this.selectedIds = new Set();
    this.rangeAnchorIndex = null;
    this.hasMore = true;
    if (this.errorEl) this.errorEl.addClass("is-hidden");
    this.updateHeader();
    this.updateSpacerHeight();
    this.renderVisible();
    await this.loadMore();
  }

  setSyncButtonState(isSyncing) {
    if (!this.syncButtonEl) return;
    if (isSyncing) {
      this.syncButtonEl.setAttribute("disabled", "true");
      this.syncButtonEl.textContent = "Syncing…";
      return;
    }
    this.syncButtonEl.removeAttribute("disabled");
    this.syncButtonEl.textContent = "Sync";
  }

  async runManualSync() {
    if (this.manualSyncInProgress) return;
    this.manualSyncInProgress = true;
    this.setSyncButtonState(true);
    let ok = false;
    try {
      await this.plugin.syncMailNow();
      ok = true;
    } catch (e) {
      new Notice("SwiftEA sync failed. See console for details.");
      // eslint-disable-next-line no-console
      console.error("[SwiftEA Inbox] sync failed:", e);
    } finally {
      this.manualSyncInProgress = false;
      this.setSyncButtonState(false);
    }

    if (ok) {
      await this.refreshFromExternalChange("manual-sync");
      new Notice("SwiftEA sync complete.");
    }
  }

  startRealtimeRefresh() {
    this.stopRealtimeRefresh();

    const vaultPath = this.source.getVaultPath();
    const swifteaDir = path.join(vaultPath, "Swiftea");

    try {
      this.fsWatcher = fs.watch(swifteaDir, { persistent: false }, (_event, filename) => {
        if (filename && !String(filename).startsWith("mail.db")) return;
        this.scheduleExternalRefresh("fs-watch");
      });
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("[SwiftEA Inbox] could not watch Swiftea/ for updates:", e);
    }

    // Fallback polling in case filesystem notifications are dropped.
    this.pollInterval = window.setInterval(() => {
      this.scheduleExternalRefresh("poll");
    }, 30_000);
  }

  stopRealtimeRefresh() {
    if (this.externalRefreshTimer) {
      window.clearTimeout(this.externalRefreshTimer);
      this.externalRefreshTimer = null;
    }
    if (this.pollInterval) {
      window.clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
    if (this.fsWatcher) {
      try {
        this.fsWatcher.close();
      } catch {
        // ignore
      }
      this.fsWatcher = null;
    }
  }

  scheduleExternalRefresh(_reason) {
    if (this.externalRefreshTimer) window.clearTimeout(this.externalRefreshTimer);
    this.externalRefreshTimer = window.setTimeout(() => {
      this.externalRefreshTimer = null;
      void this.refreshFromExternalChange(_reason);
    }, 500);
  }

  async refreshFromExternalChange(_reason) {
    if (this.actionInProgress || this.isLoading || this.manualSyncInProgress) return;

    // If the overlay is open, avoid resetting list state while the user is reading.
    if (this.overlayEl) {
      this.pendingExternalRefresh = true;
      return;
    }

    const scrollTop = this.scrollEl?.scrollTop ?? 0;
    const selectedEmailId = this.emails[this.selectedIndex]?.id || null;
    const loadedCount = Math.max(this.emails.length, this.plugin.settings.pageSize || DEFAULT_SETTINGS.pageSize);

    try {
      const next = await this.source.listInbox({ offset: 0, limit: loadedCount });
      this.emails = next;

      if (selectedEmailId) {
        const nextIndex = this.emails.findIndex((m) => m.id === selectedEmailId);
        if (nextIndex >= 0) this.selectedIndex = nextIndex;
      }

      // Keep any still-present selections.
      const nextIdSet = new Set(this.emails.map((m) => m.id));
      this.selectedIds = new Set(Array.from(this.selectedIds).filter((id) => nextIdSet.has(id)));

      this.hasMore = next.length >= loadedCount;
      this.ensureSelection();
      this.updateHeader();
      this.updateSpacerHeight();
      this.renderVisible();
      if (this.scrollEl) this.scrollEl.scrollTop = scrollTop;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("[SwiftEA Inbox] background refresh failed:", e);
    }
  }

  removeEmailAtIndex(index) {
    if (index < 0 || index >= this.emails.length) return;

    const removed = this.emails[index];
    this.emails.splice(index, 1);
    if (removed?.id) this.selectedIds.delete(removed.id);
    if (this.selectedIndex > index) {
      this.selectedIndex -= 1;
    } else if (this.selectedIndex >= this.emails.length) {
      this.selectedIndex = Math.max(0, this.emails.length - 1);
    }

    this.ensureSelection();
    this.updateHeader();
    this.updateSpacerHeight();
    this.renderVisible();

    if (this.hasMore && this.scrollEl) {
      const filled = this.emails.length * ROW_HEIGHT_PX;
      if (filled < this.scrollEl.clientHeight + ROW_HEIGHT_PX * 2) void this.loadMore();
    }
  }

  async archiveSelected() {
    if (this.actionInProgress) return;
    const ids = this.getSelectedIds();
    if (!ids.length) return;

    this.actionInProgress = true;
    try {
      if (ids.length === 1) {
        await this.source.archiveMessage(ids[0]);
        if (this.overlayEl) this.closeOverlay();
        this.removeEmailAtIndex(this.selectedIndex);
        new Notice("Archived.");
        return;
      }

      await this.source.archiveMessages(ids);
      if (this.overlayEl) this.closeOverlay();
      this.removeEmailsByIdSet(new Set(ids));
      new Notice(`Archived ${ids.length} messages.`);
    } catch (e) {
      new Notice("Archive failed. See console for details.");
      // eslint-disable-next-line no-console
      console.error("[SwiftEA Inbox] archive failed:", e);
      if (ids.length > 1) {
        try {
          await this.reload();
        } catch {
          // ignore
        }
      }
    } finally {
      this.actionInProgress = false;
    }
  }

  async deleteSelected() {
    if (this.actionInProgress) return;
    const ids = this.getSelectedIds();
    if (!ids.length) return;

    if (this.plugin.settings.confirmDelete) {
      const ok =
        ids.length > 1
          ? window.confirm(`Delete ${ids.length} messages? This will move them to Trash in Mail.app.`)
          : window.confirm("Delete this message? This will move it to Trash in Mail.app.");
      if (!ok) return;
    }

    this.actionInProgress = true;
    try {
      if (ids.length === 1) {
        await this.source.deleteMessage(ids[0]);
        if (this.overlayEl) this.closeOverlay();
        this.removeEmailAtIndex(this.selectedIndex);
        new Notice("Deleted.");
        return;
      }

      await this.source.deleteMessages(ids);
      if (this.overlayEl) this.closeOverlay();
      this.removeEmailsByIdSet(new Set(ids));
      new Notice(`Deleted ${ids.length} messages.`);
    } catch (e) {
      new Notice("Delete failed. See console for details.");
      // eslint-disable-next-line no-console
      console.error("[SwiftEA Inbox] delete failed:", e);
      if (ids.length > 1) {
        try {
          await this.reload();
        } catch {
          // ignore
        }
      }
    } finally {
      this.actionInProgress = false;
    }
  }

  getSelectedIds() {
    if (!this.emails.length) return [];
    if (this.selectedIds && this.selectedIds.size) return Array.from(this.selectedIds);
    const focused = this.emails[this.selectedIndex];
    return focused?.id ? [focused.id] : [];
  }

  ensureSelection() {
    if (!this.emails.length) {
      this.selectedIds = new Set();
      this.rangeAnchorIndex = null;
      this.selectedIndex = 0;
      return;
    }

    // Keep focus index in bounds.
    this.selectedIndex = clamp(this.selectedIndex, 0, this.emails.length - 1);

    // If selection is empty, select focused row.
    if (!this.selectedIds || this.selectedIds.size === 0) {
      const id = this.emails[this.selectedIndex]?.id;
      if (id) this.selectedIds = new Set([id]);
      if (this.rangeAnchorIndex == null) this.rangeAnchorIndex = this.selectedIndex;
      return;
    }

    // Drop ids that no longer exist in the list.
    const present = new Set(this.emails.map((e) => e.id));
    for (const id of Array.from(this.selectedIds)) {
      if (!present.has(id)) this.selectedIds.delete(id);
    }
    if (this.selectedIds.size === 0) {
      const id = this.emails[this.selectedIndex]?.id;
      if (id) this.selectedIds.add(id);
    }

    // Ensure focused row is selected.
    const focusedId = this.emails[this.selectedIndex]?.id;
    if (focusedId && !this.selectedIds.has(focusedId)) {
      this.selectedIds = new Set([focusedId]);
      this.rangeAnchorIndex = this.selectedIndex;
    }
  }

  setSingleSelection(index) {
    if (!this.emails.length) return;
    this.selectedIndex = clamp(index, 0, this.emails.length - 1);
    const id = this.emails[this.selectedIndex]?.id;
    this.selectedIds = new Set(id ? [id] : []);
    this.rangeAnchorIndex = this.selectedIndex;
    this.ensureSelectedVisible();
    this.renderVisible();
  }

  toggleSelection(index) {
    if (!this.emails.length) return;
    const i = clamp(index, 0, this.emails.length - 1);
    const id = this.emails[i]?.id;
    if (!id) return;

    this.selectedIndex = i;
    if (!this.selectedIds) this.selectedIds = new Set();

    if (this.selectedIds.has(id)) this.selectedIds.delete(id);
    else this.selectedIds.add(id);

    if (this.selectedIds.size === 0) this.selectedIds.add(id);

    this.rangeAnchorIndex = i;
    this.ensureSelectedVisible();
    this.renderVisible();
  }

  selectRangeTo(index, additive) {
    if (!this.emails.length) return;
    const target = clamp(index, 0, this.emails.length - 1);
    const anchor = this.rangeAnchorIndex == null ? this.selectedIndex : this.rangeAnchorIndex;
    const start = Math.min(anchor, target);
    const end = Math.max(anchor, target);

    const idsInRange = [];
    for (let i = start; i <= end; i++) {
      const id = this.emails[i]?.id;
      if (id) idsInRange.push(id);
    }

    if (!additive) this.selectedIds = new Set(idsInRange);
    else {
      if (!this.selectedIds) this.selectedIds = new Set();
      for (const id of idsInRange) this.selectedIds.add(id);
    }

    this.selectedIndex = target;
    this.ensureSelectedVisible();
    this.renderVisible();
  }

  handleRowClick(index, evt) {
    const ctrlOrMeta = evt.ctrlKey || evt.metaKey;
    if (evt.shiftKey) {
      if (this.rangeAnchorIndex == null) this.rangeAnchorIndex = this.selectedIndex;
      this.selectRangeTo(index, ctrlOrMeta);
      return;
    }

    if (ctrlOrMeta) {
      this.toggleSelection(index);
      return;
    }

    this.setSingleSelection(index);
  }

  removeEmailsByIdSet(idsToRemove) {
    if (!idsToRemove || !idsToRemove.size) return;
    const oldSelectedIndex = this.selectedIndex;
    const focusedId = this.emails[this.selectedIndex]?.id || null;

    this.emails = this.emails.filter((e) => !idsToRemove.has(e.id));
    for (const id of idsToRemove) this.selectedIds.delete(id);

    if (this.emails.length === 0) {
      this.selectedIndex = 0;
      this.selectedIds = new Set();
      this.rangeAnchorIndex = null;
    } else if (focusedId) {
      const newFocusedIndex = this.emails.findIndex((e) => e.id === focusedId);
      this.selectedIndex = newFocusedIndex >= 0 ? newFocusedIndex : Math.min(oldSelectedIndex, this.emails.length - 1);
      this.selectedIds = new Set([this.emails[this.selectedIndex].id]);
      this.rangeAnchorIndex = this.selectedIndex;
    } else {
      this.selectedIndex = clamp(oldSelectedIndex, 0, this.emails.length - 1);
      this.selectedIds = new Set([this.emails[this.selectedIndex].id]);
      this.rangeAnchorIndex = this.selectedIndex;
    }

    this.updateHeader();
    this.updateSpacerHeight();
    this.renderVisible();

    if (this.hasMore && this.scrollEl) {
      const filled = this.emails.length * ROW_HEIGHT_PX;
      if (filled < this.scrollEl.clientHeight + ROW_HEIGHT_PX * 2) void this.loadMore();
    }
  }

  updateSpacerHeight() {
    this.spacerEl.style.height = `${this.emails.length * ROW_HEIGHT_PX}px`;
  }

  onScroll() {
    this.renderVisible();

    if (this.isLoading || !this.hasMore) return;
    const nearBottom = this.scrollEl.scrollTop + this.scrollEl.clientHeight >= this.scrollEl.scrollHeight - ROW_HEIGHT_PX * 10;
    if (nearBottom) void this.loadMore();
  }

  async loadMore() {
    if (this.isLoading || !this.hasMore) return;
    this.isLoading = true;
    this.showLoadingRow(true);
    this.showEmptyState(false);

    try {
      const pageSize = Math.max(20, Number(this.plugin.settings.pageSize) || DEFAULT_SETTINGS.pageSize);
      const offset = this.emails.length;
      const items = await this.source.listInbox({ offset, limit: pageSize });
      if (items.length < pageSize) this.hasMore = false;
      this.emails.push(...items);
      this.ensureSelection();
      this.updateHeader();
      this.updateSpacerHeight();
      this.renderVisible();
    } catch (e) {
      this.hasMore = false;
      this.showErrorRow(e?.message || String(e));
    } finally {
      this.isLoading = false;
      this.showLoadingRow(false);
      if (this.emails.length === 0 && !this.errorEl) this.showEmptyState(true);
    }
  }

  showLoadingRow(isVisible) {
    if (!this.loadingEl) {
      this.loadingEl = this.statusContainerEl.createDiv({ cls: "swiftea-inbox__status" });
    }
    this.loadingEl.toggleClass("is-hidden", !isVisible);
    if (isVisible) this.loadingEl.setText("Loading…");
  }

  showEmptyState(isVisible) {
    if (!this.emptyEl) {
      this.emptyEl = this.statusContainerEl.createDiv({ cls: "swiftea-inbox__status" });
      this.emptyEl.setText("No emails to display.");
    }
    this.emptyEl.toggleClass("is-hidden", !isVisible);
  }

  showErrorRow(message) {
    if (!this.errorEl) {
      this.errorEl = this.statusContainerEl.createDiv({ cls: "swiftea-inbox__status swiftea-inbox__status--error" });
      this.errorTextEl = this.errorEl.createSpan();
      this.retryBtn = this.errorEl.createEl("button", { text: "Retry" });
      this.retryBtn.addEventListener("click", () => void this.reload());
    }
    this.errorEl.toggleClass("is-hidden", false);
    this.errorEl.setAttr("aria-live", "polite");
    const extra =
      typeof message === "string" && message.includes("ENOENT")
        ? " (SwiftEA CLI not found. Set “SwiftEA CLI path” in settings to your swea binary.)"
        : "";
    this.errorTextEl.setText(`Couldn’t load emails. ${message}${extra} `);
  }

  renderVisible() {
    if (!this.scrollEl) return;
    const total = this.emails.length;
    if (total === 0) {
      this.rowsEl.empty();
      if (!this.isLoading && (!this.errorEl || this.errorEl.hasClass("is-hidden"))) {
        this.showEmptyState(true);
      }
      return;
    }
    this.showEmptyState(false);

    const scrollTop = this.scrollEl.scrollTop;
    const viewportHeight = this.scrollEl.clientHeight;
    const startIndex = clamp(Math.floor(scrollTop / ROW_HEIGHT_PX) - OVERSCAN_ROWS, 0, total - 1);
    const endIndex = clamp(Math.ceil((scrollTop + viewportHeight) / ROW_HEIGHT_PX) + OVERSCAN_ROWS, 0, total - 1);

    this.rowsEl.style.transform = `translateY(${startIndex * ROW_HEIGHT_PX}px)`;
    this.rowsEl.empty();

    const frag = document.createDocumentFragment();
    for (let i = startIndex; i <= endIndex; i++) {
      const email = this.emails[i];
      const row = document.createElement("div");
      row.className = "swiftea-inbox__row";
      if (this.selectedIds && this.selectedIds.has(email.id)) row.classList.add("is-selected");
      if (i === this.selectedIndex) row.classList.add("is-focused");
      row.dataset.index = String(i);
      row.style.height = `${ROW_HEIGHT_PX}px`;

      const selectCell = document.createElement("div");
      selectCell.className = "swiftea-inbox__cell swiftea-inbox__cell--select";
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "swiftea-inbox__checkbox";
      checkbox.checked = !!(this.selectedIds && this.selectedIds.has(email.id));
      checkbox.setAttribute("aria-label", "Select message");
      checkbox.addEventListener("click", (evt) => {
        evt.stopPropagation();
        const mouseEvt = evt;
        const ctrlOrMeta = mouseEvt.ctrlKey || mouseEvt.metaKey;
        if (mouseEvt.shiftKey) {
          if (this.rangeAnchorIndex == null) this.rangeAnchorIndex = this.selectedIndex;
          this.selectRangeTo(i, ctrlOrMeta);
          return;
        }
        this.toggleSelection(i);
        this.scrollEl.focus();
      });
      selectCell.appendChild(checkbox);

      const sender = document.createElement("div");
      sender.className = "swiftea-inbox__cell swiftea-inbox__cell--sender";
      sender.textContent = email.sender || "Unknown";

      const subject = document.createElement("div");
      subject.className = "swiftea-inbox__cell swiftea-inbox__cell--subject";
      subject.textContent = email.subject || "(No subject)";

      const preview = document.createElement("div");
      preview.className = "swiftea-inbox__cell swiftea-inbox__cell--preview";
      preview.textContent = email.preview || "";

      const date = document.createElement("div");
      date.className = "swiftea-inbox__cell swiftea-inbox__cell--date";
      date.textContent = formatShortDate(email.date);

      row.appendChild(selectCell);
      row.appendChild(sender);
      row.appendChild(subject);
      row.appendChild(preview);
      row.appendChild(date);

      row.addEventListener("click", (evt) => {
        this.handleRowClick(i, evt);
        this.scrollEl.focus();
      });
      row.addEventListener("dblclick", () => void this.openSelected());

      frag.appendChild(row);
    }

    this.rowsEl.appendChild(frag);
  }

  selectIndex(index) {
    this.setSingleSelection(index);
  }

  ensureSelectedVisible() {
    const top = this.selectedIndex * ROW_HEIGHT_PX;
    const bottom = top + ROW_HEIGHT_PX;
    const viewTop = this.scrollEl.scrollTop;
    const viewBottom = viewTop + this.scrollEl.clientHeight;
    if (top < viewTop) this.scrollEl.scrollTop = top;
    else if (bottom > viewBottom) this.scrollEl.scrollTop = bottom - this.scrollEl.clientHeight;
  }

  async openSelected() {
    const email = this.emails[this.selectedIndex];
    if (!email) return;
    await this.openOverlay(email);
  }

  onKeyDownList(evt) {
    if (this.overlayEl) return;

    const key = evt.key;
    const ctrl = evt.ctrlKey || evt.metaKey;
    const shift = evt.shiftKey;

    if (key === "j" || key === "ArrowDown") {
      evt.preventDefault();
      if (shift) {
        if (this.rangeAnchorIndex == null) this.rangeAnchorIndex = this.selectedIndex;
        this.selectRangeTo(this.selectedIndex + 1, ctrl);
      } else {
        this.selectIndex(this.selectedIndex + 1);
      }
      return;
    }
    if (key === "k" || key === "ArrowUp") {
      evt.preventDefault();
      if (shift) {
        if (this.rangeAnchorIndex == null) this.rangeAnchorIndex = this.selectedIndex;
        this.selectRangeTo(this.selectedIndex - 1, ctrl);
      } else {
        this.selectIndex(this.selectedIndex - 1);
      }
      return;
    }
    if (key === "g" && !ctrl) {
      evt.preventDefault();
      this.selectIndex(0);
      return;
    }
    if (key === "G") {
      evt.preventDefault();
      this.selectIndex(this.emails.length - 1);
      return;
    }
    if (ctrl && (key === "d" || key === "PageDown")) {
      evt.preventDefault();
      const page = Math.max(1, Math.floor(this.scrollEl.clientHeight / ROW_HEIGHT_PX));
      this.selectIndex(this.selectedIndex + page);
      return;
    }
    if (ctrl && (key === "u" || key === "PageUp")) {
      evt.preventDefault();
      const page = Math.max(1, Math.floor(this.scrollEl.clientHeight / ROW_HEIGHT_PX));
      this.selectIndex(this.selectedIndex - page);
      return;
    }
    if (key === "Enter" || key === " ") {
      evt.preventDefault();
      void this.openSelected();
      return;
    }

    if (!ctrl && key === "e") {
      evt.preventDefault();
      void this.archiveSelected();
      return;
    }

    if (!ctrl && (key === "s" || key === "S")) {
      evt.preventDefault();
      void this.runManualSync();
      return;
    }

    if (!ctrl && key === "d") {
      evt.preventDefault();
      void this.deleteSelected();
      return;
    }
  }

  async openOverlay(_email) {
    this.closeOverlay();

    this.overlayEl = this.contentEl.createDiv({ cls: "swiftea-inbox__overlay" });
    this.overlayEl.addEventListener("keydown", this._onKeyDownOverlay);

    const backdrop = this.overlayEl.createDiv({ cls: "swiftea-inbox__backdrop" });
    const panel = this.overlayEl.createDiv({ cls: "swiftea-inbox__panel" });

    backdrop.addEventListener("click", () => this.closeOverlay());

    const panelHeader = panel.createDiv({ cls: "swiftea-inbox__panel-header" });
    this.overlayFromEl = panelHeader.createDiv({ cls: "swiftea-inbox__meta" });
    this.overlaySubjectEl = panelHeader.createDiv({ cls: "swiftea-inbox__meta" });
    this.overlayDateEl = panelHeader.createDiv({ cls: "swiftea-inbox__meta" });
    this.overlayIdEl = panelHeader.createDiv({ cls: "swiftea-inbox__meta swiftea-inbox__meta--id" });

    panel.createDiv({ cls: "swiftea-inbox__divider" });

    this.overlayBodyWrap = panel.createDiv({ cls: "swiftea-inbox__body" });
    this.overlayBodyWrap.setAttr("tabindex", "0");

    this.overlayBodyWrap.focus();
    await this.loadOverlayForIndex(this.selectedIndex);
  }

  async loadOverlayForIndex(index) {
    const email = this.emails[index];
    if (!email || !this.overlayEl) return;

    this.selectIndex(index);

    const seq = ++this.overlayLoadSeq;
    this.overlayEmailId = email.id;
    this.overlayFromEl.setText(`From: ${email.sender || "Unknown"}`);
    this.overlaySubjectEl.setText(`Subject: ${email.subject || "(No subject)"}`);
    this.overlayDateEl.setText(`Date: ${email.date || ""}`);
    this.overlayIdEl.empty();
    this.overlayIdEl.appendText("ID: ");
    const idLink = this.overlayIdEl.createEl("a", { text: email.id, cls: "swiftea-inbox__id-link" });
    idLink.setAttr("href", "#");
    idLink.setAttr("aria-label", "Copy SwiftEA email ID");
    idLink.addEventListener("click", async (evt) => {
      evt.preventDefault();
      const ok = await copyToClipboard(this.overlayEmailId);
      new Notice(ok ? "Copied email ID." : "Couldn’t copy email ID.");
    });

    this.overlayBodyWrap.setText("Loading…");

    try {
      const full = await this.source.getBody(email.id);
      if (!this.overlayEl || seq !== this.overlayLoadSeq) return;

      this.overlayFromEl.setText(`From: ${full.from || email.sender || "Unknown"}`);
      this.overlaySubjectEl.setText(`Subject: ${full.subject || email.subject || "(No subject)"}`);
      this.overlayDateEl.setText(`Date: ${full.date || email.date || ""}`);
      this.overlayBodyWrap.empty();
      this.overlayBodyWrap.createEl("pre", {
        cls: "swiftea-inbox__body-pre",
        text: full.body || "(No message body available)"
      });
    } catch (e) {
      if (!this.overlayEl || seq !== this.overlayLoadSeq) return;
      this.overlayBodyWrap.setText(`Couldn’t load message.\n\n${e?.message || String(e)}`);
      new Notice("SwiftEA Inbox: couldn’t load message body.");
    } finally {
      if (this.overlayBodyWrap) this.overlayBodyWrap.focus();
    }
  }

  onKeyDownOverlay(evt) {
    if (evt.key === "Escape") {
      evt.preventDefault();
      this.closeOverlay();
      return;
    }

    if (evt.key === " ") {
      evt.preventDefault();
      this.closeOverlay();
      return;
    }

    const ctrlOrMeta = evt.ctrlKey || evt.metaKey;
    if (ctrlOrMeta && evt.key.toLowerCase() === "c") {
      const selection = String(window.getSelection?.()?.toString?.() || "");
      if (!selection.trim()) {
        evt.preventDefault();
        void (async () => {
          const ok = await copyToClipboard(this.overlayEmailId);
          new Notice(ok ? "Copied email ID." : "Couldn’t copy email ID.");
        })();
      }
      return;
    }

    if (evt.key === "j" || evt.key === "ArrowDown") {
      evt.preventDefault();
      const nextIndex = clamp(this.selectedIndex + 1, 0, this.emails.length - 1);
      if (nextIndex !== this.selectedIndex) void this.loadOverlayForIndex(nextIndex);
      return;
    }

    if (evt.key === "k" || evt.key === "ArrowUp") {
      evt.preventDefault();
      const prevIndex = clamp(this.selectedIndex - 1, 0, this.emails.length - 1);
      if (prevIndex !== this.selectedIndex) void this.loadOverlayForIndex(prevIndex);
      return;
    }

    if (evt.key === "e") {
      evt.preventDefault();
      void this.archiveSelected();
      return;
    }

    if (evt.key === "s" || evt.key === "S") {
      evt.preventDefault();
      void this.runManualSync();
      return;
    }

    if (evt.key === "d") {
      evt.preventDefault();
      void this.deleteSelected();
      return;
    }
  }

  closeOverlay() {
    if (!this.overlayEl) return;
    this.overlayEl.removeEventListener("keydown", this._onKeyDownOverlay);
    this.overlayEl.remove();
    this.overlayEl = null;
    this.overlayFromEl = null;
    this.overlaySubjectEl = null;
    this.overlayDateEl = null;
    this.overlayIdEl = null;
    this.overlayBodyWrap = null;
    this.overlayEmailId = null;
    if (this.scrollEl) this.scrollEl.focus();

    if (this.pendingExternalRefresh) {
      this.pendingExternalRefresh = false;
      this.scheduleExternalRefresh("overlay-closed");
    }
  }
}

module.exports = class SwiftEAInboxPlugin extends Plugin {
  async onload() {
    await this.loadSettings();

    this.registerView(VIEW_TYPE, (leaf) => new SwiftEAInboxView(leaf, this));

    this.addCommand({
      id: "open-swiftea-inbox",
      name: "Open SwiftEA Inbox",
      callback: () => this.activateView()
    });

    this.addCommand({
      id: "swiftea-sync-mail",
      name: "SwiftEA: Sync mail now",
      hotkeys: [{ modifiers: [], key: "s" }],
      callback: () => void this.syncMailNow()
    });

    this.addSettingTab(new SwiftEAInboxSettingTab(this.app, this));

    // Ensure the background sync daemon is running so the inbox updates continuously.
    void this.ensureWatchDaemonStarted();
  }

  onunload() {
    this.app.workspace.detachLeavesOfType(VIEW_TYPE);
  }

  async syncMailNow() {
    if (this._syncPromise) return this._syncPromise;
    const source = new SwiftEAEmailSource(this.app, this.settings);
    this._syncPromise = (async () => {
      await source.syncMail();
      this.refreshOpenViews();
    })();

    try {
      await this._syncPromise;
    } finally {
      this._syncPromise = null;
      this.resetSyncButtonsOnAllViews();
    }
  }

  resetSyncButtonsOnAllViews() {
    const leaves = this.app.workspace.getLeavesOfType(VIEW_TYPE);
    for (const leaf of leaves) {
      const view = leaf.view;
      if (view && typeof view.setSyncButtonState === "function") {
        view.setSyncButtonState(false);
        view.manualSyncInProgress = false;
      }
    }
  }

  async ensureWatchDaemonStarted() {
    const now = Date.now();
    if (this._lastEnsureWatchAttempt && now - this._lastEnsureWatchAttempt < 60_000) return;
    this._lastEnsureWatchAttempt = now;

    if (this._ensureWatchPromise) return this._ensureWatchPromise;
    const source = new SwiftEAEmailSource(this.app, this.settings);
    this._ensureWatchPromise = (async () => {
      await source.ensureWatchDaemon(60);
    })();

    try {
      await this._ensureWatchPromise;
    } catch (e) {
      // eslint-disable-next-line no-console
      console.warn("[SwiftEA Inbox] could not ensure watch daemon is running:", e);
      new Notice("SwiftEA: couldn't start background sync. Run `swea mail sync --watch` once from the vault root.");
    } finally {
      this._ensureWatchPromise = null;
    }
  }

  refreshOpenViews() {
    const leaves = this.app.workspace.getLeavesOfType(VIEW_TYPE);
    for (const leaf of leaves) {
      const view = leaf.view;
      if (view && typeof view.refreshFromExternalChange === "function") {
        void view.refreshFromExternalChange("plugin-refresh");
      }
    }
  }

  async activateView() {
    const leaf = this.app.workspace.getLeaf(true);
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    this.app.workspace.revealLeaf(leaf);
  }

  async loadSettings() {
    this.settings = Object.assign({}, DEFAULT_SETTINGS, await this.loadData());
  }

  async saveSettings() {
    await this.saveData(this.settings);
  }
};

class SwiftEAInboxSettingTab extends PluginSettingTab {
  constructor(app, plugin) {
    super(app, plugin);
    this.plugin = plugin;
  }

  display() {
    const { containerEl } = this;
    containerEl.empty();

    containerEl.createEl("h2", { text: "SwiftEA Inbox" });

    new Setting(containerEl)
      .setName("SwiftEA CLI path")
      .setDesc("Executable to run (default: swea).")
      .addText((text) =>
        text.setValue(this.plugin.settings.cliPath).onChange(async (value) => {
          this.plugin.settings.cliPath = value.trim() || DEFAULT_SETTINGS.cliPath;
          await this.plugin.saveSettings();
        })
      );

    new Setting(containerEl)
      .setName("Inbox title")
      .setDesc("Title shown in the view header.")
      .addText((text) =>
        text.setValue(this.plugin.settings.title).onChange(async (value) => {
          this.plugin.settings.title = value.trim() || DEFAULT_SETTINGS.title;
          await this.plugin.saveSettings();
        })
      );

    new Setting(containerEl)
      .setName("Page size")
      .setDesc("How many emails to fetch per page.")
      .addText((text) =>
        text.setValue(String(this.plugin.settings.pageSize)).onChange(async (value) => {
          const n = Number(value);
          this.plugin.settings.pageSize = Number.isFinite(n) ? Math.max(20, Math.floor(n)) : DEFAULT_SETTINGS.pageSize;
          await this.plugin.saveSettings();
        })
      );

    new Setting(containerEl)
      .setName("Confirm delete")
      .setDesc("When enabled, shows a confirmation prompt before deleting.")
      .addToggle((toggle) =>
        toggle.setValue(!!this.plugin.settings.confirmDelete).onChange(async (value) => {
          this.plugin.settings.confirmDelete = !!value;
          await this.plugin.saveSettings();
        })
      );
  }
}
