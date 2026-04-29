# Codex Port Of Claude Files

This directory contains the Codex-facing port of the repository's Claude Code
setup.

## Source Mapping

| Claude source | Codex output | Notes |
| --- | --- | --- |
| `CLAUDE.md` | `AGENTS.md` | Root project guidance that Codex auto-loads. |
| `sprites/CLAUDE.md` | `sprites/AGENTS.md` | Nested sprite-pipeline guidance for Codex. |
| `.claude/hooks/rebuild-sim.sh` | `codex/hooks/rebuild-sim.sh` | Manual rebuild/install/relaunch helper. |
| `.claude/hooks/restart-webui.sh` | `codex/hooks/restart-webui.sh` | Manual web UI restart helper. |
| `.claude/settings.local.json` | This README | Claude permissions/hooks are not a Codex config format. |

## Hook Behavior

The original Claude settings use two ideas:

- After edits to Swift files, assets, or `project.pbxproj`, mark
  `/tmp/pvogame-dirty`.
- After edits to `sprites/*.py`, mark `/tmp/pvogame-webui-dirty`.
- On Claude stop, rebuild and relaunch the simulator if the app is dirty, and
  restart running sprite web UI servers if the web UI is dirty.

Codex does not read `.claude/settings.local.json` and does not run these
Claude hooks automatically. Use the helper scripts manually when appropriate:

```bash
# After Swift, asset, or project file edits
codex/hooks/rebuild-sim.sh

# After sprites/*.py edits, if web_ui.py is running
codex/hooks/restart-webui.sh
```

## Permission Notes

The Claude file contains a long allow-list for Bash, web search/fetch, git,
Python, Xcode, simulator, and sprite-generation commands. That list is not
portable to Codex. In Codex, command approval is handled by the active sandbox
and session policy.

Practical mapping for future Codex work:

- `xcodebuild`, `xcrun simctl`, and `open -a Simulator` may require approval
  depending on the active sandbox.
- Sprite generation that calls external APIs requires network access and an
  API key; dry-runs and post-processing-only runs do not.
- Git operations should be explicit. Never revert unrelated user changes.
- The hook scripts write logs and temporary files under `/tmp` and operate only
  on this project path.
