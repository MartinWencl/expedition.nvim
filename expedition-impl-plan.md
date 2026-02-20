# Expedition.nvim — Implementation Plan

## Project Structure

```
expedition.nvim/
  lua/
    expedition/
      init.lua              -- plugin entry, setup(), commands
      config.lua            -- user config with defaults
      core/
        expedition.lua      -- expedition CRUD, lifecycle
        note.lua            -- field notes CRUD, anchoring, drift
        route.lua           -- waypoints, dependencies, branches
        log.lua             -- expedition log (append-only)
      storage/
        fs.lua              -- JSON read/write, file management
        serializer.lua      -- expedition state → structured text (for AI + display)
      ai/
        init.lua            -- AI interface (plan, replan, campfire, evaluate)
        prompt.lua          -- base camp → prompt construction
        provider.lua        -- abstraction over Claude API / CLI / etc
      hooks/
        init.lua            -- hook registry, event dispatch
        presets.lua          -- shipped hook recipes
      ui/
        panel.lua           -- side panel (expedition overview)
        input.lua           -- floating input window
        gutter.lua          -- sign column markers
        campfire.lua        -- chat buffer for AI brainstorm
        picker.lua          -- telescope/fzf integration for searching notes etc
      util/
        id.lua              -- uuid generation
        hash.lua            -- snapshot hashing for drift
        time.lua            -- timestamp helpers
  plugin/
    expedition.lua          -- vim command registration
```

---

## Phase 0 — Scaffolding

### 0.1 — Plugin skeleton
- Create directory structure above (empty files)
- `init.lua` with `setup(opts)` that merges user config with defaults
- `config.lua` with default config table:
  ```
  {
    data_dir = ".expeditions",  -- relative to project root
    keymaps = {
      add_note = "<leader>en",
      open_panel = "<leader>ep",
      -- etc, all rebindable
    },
    ai = {
      enabled = false,
      provider = "claude_cli",  -- or "api"
      model = "claude-sonnet-4-20250514",
    },
    hooks = {
      presets = {},  -- list of preset names to enable
    },
    breadcrumbs = {
      enabled = false,
    },
  }
  ```
- Register user commands: `:Expedition`, `:ExpeditionNew`, `:ExpeditionNote`, etc
- **Done when:** plugin installs via lazy.nvim, `setup()` runs without error, commands exist (can be no-ops)

### 0.2 — Storage layer
- `fs.lua`: `read_json(path) → table`, `write_json(path, table)`, `ensure_dir(path)`, `file_exists(path)`
- Use `vim.fn.json_encode` / `vim.fn.json_decode` (built-in, no deps)
- Handle edge cases: missing files return empty defaults, write creates parent dirs
- **Done when:** can round-trip a Lua table to JSON file and back, directory creation works

### 0.3 — ID and time utilities
- `id.lua`: generate short unique ids (timestamp + random suffix is fine, no need for full uuid)
- `time.lua`: ISO timestamp generation, human-readable formatting
- `hash.lua`: simple string hash for snapshot comparison (vim.fn.sha256 or similar)
- **Done when:** unit-testable utility functions exist

---

## Phase 1 — Field Notes (the knowledge base)

### 1.1 — Expedition CRUD
- `expedition.lua`:
  - `create(name, summit_conditions) → expedition` — creates directory + expedition.json
  - `load(name) → expedition` — reads from disk
  - `list() → [expedition]` — lists all expeditions in data_dir
  - `set_active(name)` — stores active expedition ref (in a state file or vim global)
  - `get_active() → expedition | nil`
- Data shape:
  ```
  expedition.json = {
    id, name, created_at, updated_at,
    summit_conditions = [{ id, text, status = "open" | "met" | "abandoned" }],
    active_branch = "main",
    branches = [{ name, created_at, parent_branch, reasoning }],
  }
  ```
- **Done when:** can create, list, switch between expeditions from nvim commands

### 1.2 — Note data model and CRUD
- `note.lua`:
  - `create(expedition, { text, anchor?, type_tag? }) → note`
  - `get(expedition, note_id) → note`
  - `list(expedition, filters?) → [note]` — filters by type_tag, has_anchor, file, etc
  - `update(expedition, note_id, changes) → note`
  - `delete(expedition, note_id)`
- Data shape (in notes.json, array of):
  ```
  {
    id, created_at, updated_at,
    text,                          -- required, human input
    type_tag = nil,                -- "landmark" | "hazard" | "unknown" | "dependency" | nil
    anchor = nil | {
      file,                        -- relative path from project root
      line_start, line_end,
      symbol,                      -- nearest named symbol (function/class)
      snapshot,                    -- literal code text at pin time
      snapshot_hash,               -- for drift detection
    },
    linked_waypoint_ids = [],
    metadata = {},                 -- extensible, hooks can write here
  }
  ```
- Notes stored as flat array in notes.json, indexed by id in memory on load
- **Done when:** can programmatically create/read/update/delete notes, persisted to disk

### 1.3 — Note creation UI (the core interaction)
- `input.lua`: floating window for quick note input
  - Small floating buffer, insert mode by default
  - `<CR>` to confirm, `<Esc>` to cancel
  - Receives a callback with the entered text
- Context-aware note creation:
  - If visual selection active: extract selected text as snapshot, capture file + line range, resolve nearest symbol (via treesitter `vim.treesitter.get_node()` walking up to named function/class)
  - If no selection: free note, optionally attach current file as loose reference
- Type tag: for MVP, parse keywords from note text ("risk:", "question:", "depends on:", "??" at end → unknown). No picker yet, just convention.
- Keybind: `<leader>en` → opens input, creates note on confirm
- **Done when:** can select code, hit keybind, type a thought, and see a note persisted with the correct anchor

### 1.4 — Expedition log
- `log.lua`:
  - `append(expedition, event_type, data)` — writes to log.json
  - `read(expedition, filters?) → [event]` — read log, optionally filter by type/time
- Event types: `note_created`, `note_updated`, `note_deleted`, `expedition_created`, `expedition_resumed`
  (more added in later phases)
- Every note CRUD operation calls `log.append` automatically
- Log is append-only, never edited
- **Done when:** every note action produces a log entry, log is readable

### 1.5 — Side panel (expedition overview)
- `panel.lua`: opens a vsplit buffer (not editable for now) showing expedition state
- Renders as markdown-ish text:
  ```
  # My Auth Refactor
  ## Summit Conditions
  - [ ] Auth module supports OAuth2
  - [ ] Token refresh has test coverage

  ## Field Notes (7)
  [10:23] 🏔 auth/handler.rs:45 — "Token validation only supports JWT"
  [10:30] ⚠ (free) — "Token refresh flow has no tests"
  [10:45] 🏔 auth/config.rs:12 — "Provider config is hardcoded"
  ...
  ```
- Icons/prefixes based on type_tag (🏔 landmark, ⚠ hazard, ❓ unknown, 🔗 dependency, 📝 untagged)
- Auto-refreshes when notes change (use autocmd or manual refresh keybind)
- Keybind on a note line: `<CR>` to jump to anchored file/line, `e` to edit note text
- **Done when:** panel opens, shows notes, can navigate to anchored code

### 1.6 — Gutter signs
- `gutter.lua`: places signs in the sign column for files that have anchored notes
- On `BufEnter`, check if current file has notes in active expedition, place signs at anchor lines
- Different sign for different type_tags
- Keybind or hover to preview note text (floating window)
- Handle line drift gracefully: if exact line doesn't match, try to find the symbol
- **Done when:** opening a file with anchored notes shows signs, can preview note from gutter

---

## Phase 2 — Route (manual planning)

### 2.1 — Waypoint data model and CRUD
- `route.lua`:
  - `create_waypoint(expedition, { title, description, depends_on?, reasoning? }) → waypoint`
  - `update_waypoint(expedition, waypoint_id, changes)`
  - `set_status(expedition, waypoint_id, status)` — validates transition (can't complete if deps not met)
  - `get_route(expedition, branch?) → [waypoint]` — returns waypoints for branch, sorted topologically
  - `get_ready(expedition) → [waypoint]` — returns waypoints whose deps are all done
  - `delete_waypoint(expedition, waypoint_id)` — also cleans up from others' depends_on
- Data shape (in route.json):
  ```
  {
    waypoints: [{
      id, title, description,
      status,                     -- "blocked" | "ready" | "active" | "done" | "abandoned"
      depends_on = [],            -- waypoint ids
      reasoning,                  -- why this task, annotated by human and/or AI
      linked_note_ids = [],       -- relevant field notes
      branch = "main",
      created_at, updated_at,
    }],
  }
  ```
- Status derivation: "blocked" is computed (any dep not done), "ready" is computed (all deps done, not started). "active", "done", "abandoned" are set explicitly.
- Log events: `waypoint_created`, `waypoint_status_changed`, `waypoint_updated`
- **Done when:** can create waypoints with dependencies, status transitions work, topological sort works

### 2.2 — Route in the side panel
- Extend `panel.lua` to show route below notes:
  ```
  ## Route (main)
  - [x] Add OAuth2 provider config
  - [x] Write token refresh tests
  - [ ] Implement OAuth2 flow (blocked by: Implement OAuth2 flow)
  - [ ] Update auth middleware (ready)
  ```
- Keybinds on waypoint lines:
  - `x` — toggle done (if ready)
  - `a` — set active
  - `d` — mark abandoned
  - `o` — add new waypoint (opens input)
  - `D` — add dependency (prompts for waypoint id/selection)
  - `<CR>` — expand waypoint (show description, reasoning, linked notes)
- **Done when:** can manage full route lifecycle from the panel

### 2.3 — Link notes to waypoints
- Keybind in panel: on a note line, `l` to link to a waypoint (picker shows waypoint list)
- Keybind on waypoint: show linked notes
- When creating a note during execution, optionally prompt "link to active waypoint?"
- **Done when:** notes and waypoints are cross-referenced, visible in panel

---

## Phase 3 — AI Integration

### 3.1 — AI provider abstraction
- `provider.lua`:
  - `call(prompt, opts) → response` — the one function that talks to AI
  - Supports multiple backends behind the same interface:
    - `claude_cli`: writes prompt to temp file, shells out to `claude` CLI, reads response
    - `api`: direct HTTP to Anthropic API via `plenary.curl` or `vim.system`
  - Handles: timeouts, error parsing, async (returns via callback, doesn't block editor)
- Config selects provider + model
- **Done when:** can send a prompt string, get a response string, without blocking nvim

### 3.2 — Prompt construction
- `prompt.lua`:
  - `build_planning_prompt(expedition) → string` — serializes base camp + summit conditions into structured text, asks AI to propose a route
  - `build_replan_prompt(expedition, trigger_context) → string` — includes current route + what changed
  - `build_campfire_prompt(expedition, conversation) → string` — base camp + route + chat history
  - `build_summit_eval_prompt(expedition) → string`
- Output format instruction: ask AI to respond in a parseable format (JSON block inside markdown, or structured sections with clear delimiters)
- **Done when:** prompts produce well-structured context from expedition data

### 3.3 — Route generation (propose-approve loop)
- `ai/init.lua`:
  - `plan(expedition, callback)` — builds prompt, calls provider, parses response into proposed waypoints
  - Response parsing: extract waypoints from AI response (JSON preferred, with fallback to structured text parsing)
- UI flow:
  - User triggers `:ExpeditionPlan`
  - Panel shows "Proposed Route" with AI's waypoints
  - Each waypoint has keybinds: `y` accept, `n` reject, `e` edit, `r` add reasoning/feedback
  - On confirm: accepted waypoints become the route
  - On feedback: re-send to AI with annotations, get revised proposal
- **Done when:** AI proposes a route from notes, user can review/modify/accept, result becomes the active route

### 3.4 — Replanning
- Trigger: user command `:ExpeditionReplan` or hook (see Phase 4)
- AI receives: current base camp + current route + what's new (recent notes, completed waypoints)
- AI proposes: modifications to remaining waypoints (add/remove/reorder)
- Same approve UI as 3.3, but showing diffs against current route
- **Done when:** can replan mid-execution with new context, see what changed

### 3.5 — Campfire (brainstorm session)
- `campfire.lua`: a chat buffer in a split
  - User types messages, sends with `<CR>`
  - AI responds inline (streamed if provider supports it, otherwise after loading indicator)
  - Full conversation history maintained in buffer
  - AI has base camp + route context (via prompt.lua)
- Special keybinds in campfire buffer:
  - `<leader>n` on an AI response — promote to field note
  - `<leader>w` on an AI response — create waypoint from it
  - `q` — close campfire
- Conversation is ephemeral (not persisted) unless user promotes content
- **Done when:** can have a multi-turn conversation with AI about the expedition, promote insights

### 3.6 — Summit evaluation
- Trigger: `:ExpeditionEvaluate` or hook on waypoint completion
- AI reads base camp + route progress + summit conditions
- Returns assessment per condition: "likely met" / "not yet" / "unclear" + reasoning
- Shown in panel under summit conditions
- User manually confirms/checks off
- **Done when:** AI can assess summit conditions, assessment visible in panel

---

## Phase 4 — Hooks, Drift, Branches

### 4.1 — Hook system
- `hooks/init.lua`:
  - `register(event_name, callback)` — registers a lua function
  - `dispatch(event_name, data)` — calls all registered callbacks for event
  - Called from core modules at appropriate points (note created, waypoint changed, etc)
- Events:
  ```
  on_note_created(note, expedition)
  on_note_updated(note, old_note, expedition)
  on_anchor_drift(note, old_hash, new_hash, expedition)
  on_waypoint_status_changed(waypoint, old_status, expedition)
  on_route_changed(route, expedition)
  on_expedition_resumed(expedition)
  ```
- **Done when:** hooks fire correctly, custom lua callbacks work

### 4.2 — Preset hooks
- `hooks/presets.lua`: shipped recipes, enabled via config
  - `ai_conflict_check`: on_note_created during execution → AI checks if new note affects ready/active waypoints, shows warning
  - `ai_drift_review`: on_anchor_drift → AI assesses impact on linked waypoints
  - `auto_summit_eval`: on_waypoint_status_changed to "done" → trigger summit evaluation
- **Done when:** presets work when enabled in config

### 4.3 — Drift detection
- On `BufWritePost`: check if file has anchored notes in active expedition
- For each affected note: hash current code at anchor range, compare to snapshot_hash
- If different: update a `drift_status` field on the note, dispatch `on_anchor_drift`
- Visual indicator in panel and gutter (⚡ or similar)
- Command to update snapshot: acknowledge drift, re-snapshot current code
- **Done when:** editing code with anchored notes triggers drift detection, visible in UI

### 4.4 — Branches
- `route.lua` additions:
  - `create_branch(expedition, name, reasoning)` — snapshots current route state, creates new branch
  - `switch_branch(expedition, branch_name)` — changes active branch
  - `list_branches(expedition) → [branch]`
  - `merge_branch(expedition, source, target)` — for MVP, just copies waypoints. Real merge logic is a later problem.
- Panel shows current branch name, command to switch
- Log events: `branch_created`, `branch_switched`
- **Done when:** can fork a route, switch between branches, see branch history

### 4.5 — Breadcrumbs (passive tracking, opt-in)
- When enabled in config: track `BufEnter` events with timestamps
- Store in separate `breadcrumbs.json` (not in notes.json, never in base camp)
- Command: `:ExpeditionBreadcrumbs` — shows where you've been, with option to promote any entry to a note
- **Done when:** passive tracking works, promotion to notes works

---

## Phase 5 — Polish and Quality of Life

### 5.1 — Telescope/picker integration
- Search notes by text, type, file
- Search waypoints by title, status
- Jump to anchored code from search results
- Fuzzy find across everything in an expedition

### 5.2 — Re-entry experience
- On `:Expedition` with an existing active expedition: show a summary
  - Time since last session
  - Notes added last session
  - Route progress (X/Y waypoints done)
  - Any drift detected
  - AI-generated summary if AI is enabled (optional hook)

### 5.3 — Export
- Export expedition to markdown (for sharing, documentation)
- Export route to GitHub issues / linear / etc (hook-based, community can build these)

### 5.4 — Multi-expedition management
- `:ExpeditionList` — shows all expeditions with status
- Quick switch between expeditions
- Optional: cross-expedition note search

---

## Future Directions

Ideas for further development beyond the core phases.

### Note relationships
Notes are currently flat (optionally linked to a single waypoint via meta). Richer connection models:
- **Note-to-note links** — explicit "relates to" edges between notes, forming a zettelkasten-style graph within an expedition
- **Note threads** — reply chains on a single anchor so context accumulates over time instead of living in one monolithic body
- **Cross-file references** — "the code here calls the function noted there", with bidirectional navigation

### Expedition templates
Every expedition currently starts blank. Reusable templates for common exploration patterns:
- **Bug investigation** — pre-populated summit conditions ("root cause identified", "fix verified") with starter waypoint scaffolding
- **Feature exploration** — waypoints like "understand existing code", "identify integration points", "prototype"
- **Code review** — per-file or per-concern waypoint structure
- **User-defined** — save the structure of a completed expedition as a template for future use

### Export and sharing
No way to get expedition data out of the plugin currently:
- **Markdown export** — render a full expedition as a structured document (notes grouped by file, route as task list, conditions as checklist)
- **GitHub issue export** — turn waypoints into issues with conditions as acceptance criteria
- **Session narrative** — AI-generated summary of what was explored, discovered, and decided, suitable for sharing with a team

### Campfire persistence
Campfire conversations are ephemeral (lost when the buffer closes). Persisting to `campfire.json` would enable:
- Resuming brainstorm sessions across Neovim restarts
- Referencing past AI conversations when revisiting decisions
- Including campfire history in serialized context for future AI calls, giving the AI memory of prior discussions

### Smarter drift handling
Drift detection is currently binary (snapshot hash match or mismatch). Richer analysis:
- **Semantic drift** — use treesitter to distinguish signature changes from formatting changes
- **Auto-relocate** — if a function moved lines but the symbol name still exists, follow it automatically
- **Drift severity** — classify as "minor" (whitespace, comments, formatting) vs "major" (logic, signature, deletion) to reduce noise
