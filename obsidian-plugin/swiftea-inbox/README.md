# SwiftEA Inbox (Obsidian plugin)

Lightweight, keyboard-first inbox UI inside an Obsidian pane. Email storage and retrieval are handled by the SwiftEA CLI (`swea`).

## Install (development)

1. Build/install `swea` so it is available on your `PATH`.
2. Ensure your vault is a SwiftEA vault (it contains a `.swiftea/` directory). If not, run `swea init` from the vault root.
3. Copy `obsidian-plugin/swiftea-inbox/` into your vault at:
   - `<vault>/.obsidian/plugins/swiftea-inbox/`
4. In Obsidian: Settings → Community plugins → enable “SwiftEA Inbox”.

## Usage

- Command palette: “Open SwiftEA Inbox”
- Manual sync: click `Sync` in the inbox header or use command “SwiftEA: Sync mail now” (default hotkey: `S`)
- Selection (list): click, `Cmd+click` toggle, `Shift+click` range, `Shift+↑/↓` range, checkboxes on the left
- Keys (list): `j/k`, `↑/↓`, `g/G`, `Ctrl+u/d`, `Enter`/`Space`, `e` archive (selection), `d` delete (selection), `s` sync
- Keys (overlay): `j/k` next/prev, `e` archive, `d` delete, `s` sync, `Esc`
- Keys (overlay): `Space` closes (same as `Esc`)
- Copy ID (overlay): click the `ID: ...` line or press `Ctrl+C` (or `Cmd+C`) with no text selected

## Real-time updates

This view auto-refreshes when `Swiftea/mail.db` changes (e.g., from `swea mail sync` or the watch daemon).

On startup, the plugin attempts to ensure the watch daemon is installed and running:

- `swea mail sync --ensure-watch --interval 60`

## Data source

This plugin shells out to:

- `swea mail inbox --json --limit <n> --offset <n>`
- `swea mail show <id> --json`
- `swea mail sync`
- `swea mail archive --id <id> --yes` or `swea mail archive --ids <id1,id2,...> --yes`
- `swea mail delete --id <id> --yes` or `swea mail delete --ids <id1,id2,...> --yes`
