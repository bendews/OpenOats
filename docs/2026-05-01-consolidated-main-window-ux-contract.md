# Consolidated Main Window UX Contract

**Date:** 2026-05-01  
**Status:** Ready for review  
**Issue:** HOU-14 / GitHub #563

## Goal

Use one primary window for the idle/home experience and past-meeting browsing so users can move from "what's next" to "what already happened" without juggling a second Notes window.

## Scope

This contract covers the **not-recording** shell and the navigation rules that replace the current standalone Notes window.

Out of scope for this contract:
- changing the active live-recording layout beyond its entry/exit points
- removing the separate pop-out Transcript window used during a live session
- redesigning note-generation controls inside the detail pane

## Decision Summary

| Area | Decision |
|---|---|
| Primary browsing surface | Use **one primary app window**. The idle/home shell becomes the browsing surface for upcoming meetings and saved meeting history. |
| Standalone Notes window | **Retire it as a user-facing window** once the merged shell ships. Reuse Notes detail components inside the main window instead of keeping a parallel browsing scene. |
| Existing "Past Meetings" entry points | Rename/reframe them as **Timeline** entry points and route them to the main window. They should never open a second primary browsing window. |
| Window modes | Support **single-pane timeline**, **expanded two-pane detail**, and **expanded no-selection** states. |
| Expand/collapse rule | Selecting a timeline row expands the main window into two panes. Using the back/collapse affordance returns to the single-pane timeline. |
| Timeline order | Show **upcoming/current items first**, then an **Earlier Today** disclosure, then **saved history** below the forward-looking schedule. |
| Artifact badges | `waveform` means **transcript available**. `doc.text.fill` means **notes available**. Show both when both exist. |
| Return path | Use a **leading back/collapse button** in the detail header. Also support `Esc` and `⌘[` when focus/context allows. |
| Implementation blockers | **None.** Follow-on tickets can proceed against this contract. |

## User-Facing Information Architecture

### 1. Single-pane timeline

This is the default idle state.

- The main window opens in a compact single-column layout.
- The content is a single scrollable timeline, not a separate "Coming up" card plus a separate Notes browser.
- The header action currently labeled **Past Meetings** becomes **Timeline** if it remains visible at all; in the merged shell, the timeline is already on screen, so the button can be removed or replaced with a focus/scroll action rather than a navigation action.
- Clicking any timeline row selects it and expands into the two-pane layout.

### 2. Expanded two-pane detail

This is the default state after a user selects any timeline entry.

- The left pane remains the timeline.
- The right pane shows detail for the selected item.
- The selected row stays highlighted in the left pane.
- Switching rows updates the right pane without opening a new window.
- The right pane reuses existing Notes/Transcript/detail components rather than inventing a third detail system.

### 3. Expanded no-selection state

This state is explicit and supported.

It appears when the window is already expanded but nothing is selected, for example:
- the user clears selection after deleting an item
- an entry point opens the timeline without a concrete target
- a previously selected session disappears or can no longer be loaded

Behavior:
- Keep the window expanded.
- Keep the timeline visible and interactive in the left pane.
- Show a simple empty state in the right pane: "Select a meeting" plus one sentence explaining that the user can choose an upcoming event or saved meeting from the timeline.
- Do **not** automatically shrink the window in this state; shrinking is a deliberate user action via collapse/back.

## Window Contract

### Collapsed / single-pane size

- Default size: **420 × 620**
- Minimum size: **380 × 540**
- Preferred width range while collapsed: **380–520 pt**
- The app remembers the user's last collapsed size.

### Expanded / two-pane size

- Default size: **980 × 680**
- Minimum size: **860 × 600**
- Left timeline pane target width: **320 pt**
- Left timeline pane resizable range: **280–360 pt**
- Right detail pane minimum width: **520 pt**
- The app remembers the user's last expanded size and split position.

### Resizing behavior

- Selecting an item from collapsed mode expands the window to the saved expanded size.
- Collapsing returns to the saved collapsed size.
- The transition should preserve timeline scroll position and current filters.
- Manual window resizing is allowed in both modes; the app should persist the last size per mode rather than forcing one static width.

## Timeline Composition

The merged timeline is optimized for "what do I need next?" while still exposing history in the same surface.

Top-to-bottom order:

1. **Current / next meetings**
   - Current meeting first if one is in progress
   - Remaining upcoming meetings for today after that
2. **Earlier Today**
   - Shown as a collapsed disclosure inside the Today section
   - Used for meetings that already ended today but still belong to today's context
3. **Future days**
   - Tomorrow, then later days in chronological order
4. **Saved History**
   - Separate section below the forward-looking schedule
   - Sorted newest-first
   - Grouped by relative day/date headings as needed

Rules:
- Saved history does **not** interleave above future meetings.
- The timeline is one scroll surface even though it has section headers.
- Calendar-only items and saved-session items can coexist in the same surface, but they keep distinct affordances and metadata.

## Row Semantics and Badges

Each row can represent one of three things:
- an upcoming/current calendar event with no saved session yet
- a meeting family with prior history
- a concrete saved session

### Availability badges

Use distinct artifact icons on the trailing side of the row:

- `waveform` = transcript exists
- `doc.text.fill` = notes exist
- show both icons side-by-side when both exist
- show no artifact icon for calendar-only rows with no saved content yet

### Meaning

- **Transcript available** means the user can open a transcript detail immediately.
- **Notes available** means the user can open generated or manually written notes immediately.
- If only notes exist, the row still opens into the notes view first.
- If only a transcript exists, the row opens into transcript first and offers note generation from there.

## Detail-Pane Rules

### When the selected item is an upcoming event

The right pane opens to the **meeting-family overview**:
- event metadata
- prep notes
- start/join actions when relevant
- previous-meeting/history section
- link-related-meetings tools

### When the selected item is a saved session

The right pane opens directly to the most useful artifact:
- **Notes first** if notes exist
- **Transcript first** if only transcript exists
- **Transcript first** for imported/manual-transcript flows unless notes already exist

### Existing Notes flow inside the merged shell

Keep these behaviors, but host them in the right pane instead of a separate window:
- transcript vs notes segmented control
- meeting-family overview when no concrete session is focused
- previous meetings / link meetings section
- note generation, transcript maintenance, folder/tag actions

## Navigation Contract

### How users return to the single-pane timeline

Primary return path:
- a leading **back/collapse** button in the right-pane header

Secondary return paths:
- `Esc` collapses detail when no higher-priority modal/editor interaction is active
- `⌘[` triggers the same collapse action

Collapse behavior:
- clears the current detail selection
- returns to single-pane size
- preserves timeline scroll position
- preserves filter/tag state

### Fate of current entry points

These all route to the main window, not a separate Notes window:
- header button currently labeled **Past Meetings**
- `⇧⌘M` menu command
- post-session banner actions like **View Notes**, **Generate Notes**, **Open Session**
- deep links that currently target the Notes scene

Routing rules:
- if an entry point has a specific session ID, open the main window expanded with that session selected
- if it has a meeting/event target, open expanded with the meeting-family overview selected
- if it has no target, open the timeline in single-pane mode or expanded no-selection mode depending on the caller intent

## OpenOatsApp / Shell Implications

This contract implies the following implementation direction:

- `OpenOatsApp` stops exposing a separate user-facing `Window("Notes", id: "notes")` as the primary browsing path.
- `ContentView` becomes the shell that owns collapsed vs expanded browsing state.
- `IdleHomeDashboardView` stops being just a "Coming up" card and becomes the basis of the left timeline content.
- Current `NotesView` behavior is split into reusable right-pane detail sections instead of remaining a separate full-window experience.

## Approval Checklist

- [x] Single-pane state defined
- [x] Expanded two-pane state defined
- [x] Expanded no-selection state defined
- [x] Standalone Notes window fate decided
- [x] Existing Past Meetings entry points decided
- [x] Timeline mix of upcoming, earlier-today, and history decided
- [x] Transcript-vs-notes badge meaning decided
- [x] Return path from detail pane decided
- [x] No blocking UX questions remain for implementation
