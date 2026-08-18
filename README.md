# Linear Issues

Your open [Linear](https://linear.app) issues in the DankBar. Browse them by
status, open one in the Linear app, and move it through the workflow without
leaving the bar.

![status](https://img.shields.io/badge/DMS-%3E%3D1.5.0-blue) ![license](https://img.shields.io/badge/license-MIT-green)

## What it does

- The Linear mark in the bar, with a dot when you have open issues. The dot
  turns to the accent colour once something is In Progress, and red if Linear
  cannot be reached.
- A popout listing your issues grouped the way Linear's board groups them —
  In Progress, Todo, Triage, Backlog — each section sorted by priority, then by
  how recently the issue moved.
- Click a row to open the issue. Click the state glyph on the left and that
  team's real workflow states unfold in place; pick one and the issue moves.
  An issue that lands in a state the list does not cover (Done, Canceled, or
  Backlog when it is hidden) drops off, exactly as it would in Linear.

Each row shows the identifier, title, team, project, due date and up to two
labels. Overdue issues turn red, issues due within a week turn amber.

## Setup

1. In Linear: **Settings → Security & access → Personal API keys**. Create a key
   and copy it.
2. In DMS: **Settings → Plugins → Linear Issues**, paste the key into
   **Personal API key**.
3. Add the widget: **Settings → DankBar → Widgets**, then drop *Linear Issues*
   into a section.

A read-only key is enough to browse. Changing a status needs a key with write
access.

### Keeping the key out of your config

The key is stored in `plugin_settings.json` in plaintext. If you would rather it
was not, leave **Personal API key** empty and set **API key command** to
something that prints the key on stdout:

```
pass show linear/api
secret-tool lookup service linear
gopass show -o linear/api
```

The command takes precedence over the field, and only runs on the first fetch
and on a manual refresh — not on every poll — so a password manager will not
prompt you every few minutes.

Either way the key never reaches a process argument list: it is handed to `curl`
over stdin as a config file, so it is not visible in `/proc` to other users on
the machine. Redirects are not followed, so the auth header cannot be replayed
to another host.

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| Personal API key | — | Your Linear key, masked in the UI |
| API key command | — | Shell command printing the key; overrides the field above |
| Issues to show | Assigned to me | Assigned to me, created by me, or either |
| Include backlog | On | Show backlog issues alongside todo and in-progress work |
| Refresh interval | 5 minutes | How often to poll Linear |
| Maximum issues | 50 | Upper bound on how many issues are fetched |
| Open in the Linear app | On | Use `linear://` when the desktop app is installed |
| Show issue count in the bar | Off | Show the number next to the icon instead of a dot |

## Interactions

| Where | Action |
| --- | --- |
| Bar pill, left click | Open the popout |
| Bar pill, right click | Force a refresh, re-reading the key command |
| Issue row | Open the issue |
| State glyph | Unfold that team's workflow states |
| Header refresh button | Refresh now |

Opening an issue tries the `linear://` deep link when the Linear desktop app has
registered the scheme handler, and falls back to the browser otherwise. The
check runs once at startup, so no handler means every issue opens on the web.

## Requirements

- DankMaterialShell ≥ 1.5.0
- `curl`

`xdg-mime` is used to detect the desktop app; without it, issues open in the
browser.

## Files

| File | Role |
| --- | --- |
| `Linear.js` | GraphQL payloads, curl config, response shaping, sorting. Pure JS, no Qt — runnable under plain node |
| `GraphQlRequest.qml` | One round trip over curl, reconciling the stdout stream and the process exit into a single result |
| `LinearIssuesWidget.qml` | Bar pill, popout, fetch and mutation flow |
| `IssueRow.qml` | One issue row and its inline status picker |
| `SecretSetting.qml` | Masked text field for the API key |
| `LinearIssuesSettings.qml` | Settings tab |

## Notes

- Workflow states are fetched per team and cached until the set of teams in your
  list changes, so the status picker costs one extra request, not one per issue.
- Only one status change is in flight at a time; the rest of the list is inert
  while it lands, so two clicks cannot race each other.
- "Assigned to or created by me" runs both filters in a single request and
  merges the overlap.

## License

MIT
