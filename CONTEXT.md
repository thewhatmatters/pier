# Pier

A personal macOS dock overlay: app pins plus live tiles.

## Language

**Cursor tile**:
The strip widget for Cursor — running or off, the open project, and working agents as the subtitle.
_Avoid_: Cursor status, agent activity, frontmost

**Working**:
An agent session whose transcript was just written and has not recorded `turn_ended`.
_Avoid_: live (as a check on a raw event)

**Quiet**:
No working agent sessions.
_Avoid_: idle, stale (as the tile word)

**Project label**:
The folder or workspace name shown as the Cursor tile headline.
_Avoid_: window title, slug
