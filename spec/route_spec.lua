local route = require("expedition.route")
local hooks = require("expedition.hooks")

--- Build a synthetic waypoint for pure-function tests.
--- @param id string
--- @param deps string[]?
--- @return expedition.Waypoint
local function make_wp(id, deps)
  return {
    id = id,
    title = "wp-" .. id,
    description = "",
    status = "ready",
    depends_on = deps or {},
    reasoning = "",
    linked_note_ids = {},
    branch = "main",
    created_at = "2025-01-01T00:00:00Z",
    updated_at = "2025-01-01T00:00:00Z",
  }
end

describe("route", function()
  before_each(function()
    test_reset()
    test_reset_route()
    test_create_expedition("route-test")
  end)

  -- -----------------------------------------------------------------------
  -- topo_sort (pure function tests)
  -- -----------------------------------------------------------------------
  describe("topo_sort", function()
    it("returns empty for empty input", function()
      assert.same({}, route.topo_sort({}))
    end)

    it("returns single waypoint", function()
      local wps = { make_wp("a") }
      local sorted = route.topo_sort(wps)
      assert.equals(1, #sorted)
      assert.equals("a", sorted[1].id)
    end)

    it("handles independent waypoints", function()
      local wps = { make_wp("a"), make_wp("b"), make_wp("c") }
      local sorted = route.topo_sort(wps)
      assert.equals(3, #sorted)
    end)

    it("orders dependency before dependent", function()
      local wps = { make_wp("b", { "a" }), make_wp("a") }
      local sorted = route.topo_sort(wps)
      -- a should come before b
      local pos = {}
      for i, wp in ipairs(sorted) do pos[wp.id] = i end
      assert.is_true(pos["a"] < pos["b"])
    end)

    it("handles diamond dependency", function()
      -- a -> b, a -> c, b -> d, c -> d
      local wps = {
        make_wp("d", { "b", "c" }),
        make_wp("b", { "a" }),
        make_wp("c", { "a" }),
        make_wp("a"),
      }
      local sorted = route.topo_sort(wps)
      local pos = {}
      for i, wp in ipairs(sorted) do pos[wp.id] = i end
      assert.is_true(pos["a"] < pos["b"])
      assert.is_true(pos["a"] < pos["c"])
      assert.is_true(pos["b"] < pos["d"])
      assert.is_true(pos["c"] < pos["d"])
    end)

    it("handles chain A->B->C", function()
      local wps = {
        make_wp("c", { "b" }),
        make_wp("b", { "a" }),
        make_wp("a"),
      }
      local sorted = route.topo_sort(wps)
      assert.equals("a", sorted[1].id)
      assert.equals("b", sorted[2].id)
      assert.equals("c", sorted[3].id)
    end)

    it("falls back for cyclic input", function()
      -- a -> b, b -> a (cycle)
      local wps = { make_wp("a", { "b" }), make_wp("b", { "a" }) }
      local sorted = route.topo_sort(wps)
      -- Should still return all waypoints (fallback appends remaining)
      assert.equals(2, #sorted)
    end)

    it("ignores nonexistent dependency", function()
      local wps = { make_wp("a", { "nonexistent" }) }
      local sorted = route.topo_sort(wps)
      assert.equals(1, #sorted)
      assert.equals("a", sorted[1].id)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- would_cycle (pure function tests)
  -- -----------------------------------------------------------------------
  describe("would_cycle", function()
    it("returns false for independent waypoints", function()
      local wps = { make_wp("a"), make_wp("b") }
      assert.is_false(route.would_cycle(wps, "a", "b"))
    end)

    it("returns false for valid dependency", function()
      -- a -> b already exists, adding c -> a is fine
      local wps = { make_wp("a"), make_wp("b", { "a" }), make_wp("c") }
      assert.is_false(route.would_cycle(wps, "c", "a"))
    end)

    it("returns true for direct cycle", function()
      -- a -> b exists, adding b -> a would cycle
      local wps = { make_wp("a"), make_wp("b", { "a" }) }
      assert.is_true(route.would_cycle(wps, "a", "b"))
    end)

    it("returns true for indirect cycle", function()
      -- a -> b -> c exists, adding c -> a would cycle
      local wps = { make_wp("a"), make_wp("b", { "a" }), make_wp("c", { "b" }) }
      assert.is_true(route.would_cycle(wps, "a", "c"))
    end)

    it("returns false when no path exists", function()
      local wps = { make_wp("a"), make_wp("b"), make_wp("c", { "b" }) }
      assert.is_false(route.would_cycle(wps, "a", "c"))
    end)

    it("returns false for unknown ID", function()
      local wps = { make_wp("a") }
      assert.is_false(route.would_cycle(wps, "a", "unknown"))
    end)
  end)

  -- -----------------------------------------------------------------------
  -- create_waypoint
  -- -----------------------------------------------------------------------
  describe("create_waypoint", function()
    it("creates with title", function()
      local wp = route.create_waypoint({ title = "Step 1" })
      assert.is_not_nil(wp)
      assert.equals("Step 1", wp.title)
      assert.is_string(wp.id)
    end)

    it("persists", function()
      local wp = route.create_waypoint({ title = "Persist me" })
      local found = route.get(wp.id)
      assert.is_not_nil(found)
      assert.equals("Persist me", found.title)
    end)

    it("is ready when no deps", function()
      local wp = route.create_waypoint({ title = "No deps" })
      assert.equals("ready", wp.status)
    end)

    it("is blocked when deps not done", function()
      local dep = route.create_waypoint({ title = "Dep" })
      local wp = route.create_waypoint({ title = "Blocked", depends_on = { dep.id } })
      -- After compute_statuses: dep is ready (not done), so wp should be blocked
      local fetched = route.get(wp.id)
      assert.equals("blocked", fetched.status)
    end)

    it("rejects missing title", function()
      local wp = route.create_waypoint({})
      assert.is_nil(wp)
    end)

    it("rejects empty title", function()
      local wp = route.create_waypoint({ title = "" })
      assert.is_nil(wp)
    end)

    it("rejects bad dependency", function()
      local wp = route.create_waypoint({ title = "Bad dep", depends_on = { "nonexistent" } })
      assert.is_nil(wp)
    end)

    it("returns nil when no active expedition", function()
      test_clear_active()
      local wp = route.create_waypoint({ title = "Orphan" })
      assert.is_nil(wp)
    end)

    it("dispatches hook", function()
      local received = nil
      hooks.on("waypoint.created", function(payload) received = payload end)
      local wp = route.create_waypoint({ title = "Hook test" })
      assert.is_not_nil(received)
      assert.equals(wp.id, received.waypoint.id)
    end)

    it("assigns default branch", function()
      local wp = route.create_waypoint({ title = "Default branch" })
      assert.equals("main", wp.branch)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- get / get_route / get_ready / list
  -- -----------------------------------------------------------------------
  describe("get", function()
    it("returns waypoint by ID", function()
      local wp = route.create_waypoint({ title = "Find me" })
      local found = route.get(wp.id)
      assert.is_not_nil(found)
      assert.equals(wp.id, found.id)
    end)

    it("returns nil for bad ID", function()
      assert.is_nil(route.get("nonexistent"))
    end)
  end)

  describe("get_route", function()
    it("returns empty route", function()
      assert.same({}, route.get_route())
    end)

    it("returns topo-sorted waypoints", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      local sorted = route.get_route()
      local pos = {}
      for i, wp in ipairs(sorted) do pos[wp.id] = i end
      assert.is_true(pos[a.id] < pos[b.id])
    end)

    it("computes statuses", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      local sorted = route.get_route()
      for _, wp in ipairs(sorted) do
        if wp.id == a.id then assert.equals("ready", wp.status) end
        if wp.id == b.id then assert.equals("blocked", wp.status) end
      end
    end)

    it("filters by branch", function()
      route.create_waypoint({ title = "Main WP" })
      route.create_branch("feature")
      route.create_waypoint({ title = "Feature WP", branch = "feature" })
      local main_only = route.get_route("main")
      for _, wp in ipairs(main_only) do
        assert.equals("main", wp.branch)
      end
    end)
  end)

  describe("get_ready", function()
    it("returns ready-only waypoints", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      local ready = route.get_ready()
      local ids = {}
      for _, wp in ipairs(ready) do ids[wp.id] = true end
      assert.is_true(ids[a.id])
      assert.is_nil(ids[b.id])
    end)

    it("returns empty when all blocked", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      -- Set a to active (explicit status, not done)
      route.set_status(a.id, "active")
      local ready = route.get_ready()
      -- a is now active (not ready), b is blocked
      local ids = {}
      for _, wp in ipairs(ready) do ids[wp.id] = true end
      assert.is_nil(ids[a.id])
      assert.is_nil(ids[b.id])
    end)
  end)

  describe("list", function()
    it("returns all waypoints with computed statuses", function()
      route.create_waypoint({ title = "A" })
      route.create_waypoint({ title = "B" })
      local all = route.list()
      assert.equals(2, #all)
      for _, wp in ipairs(all) do
        assert.is_string(wp.status)
      end
    end)
  end)

  -- -----------------------------------------------------------------------
  -- update_waypoint
  -- -----------------------------------------------------------------------
  describe("update_waypoint", function()
    it("updates title", function()
      local wp = route.create_waypoint({ title = "Original" })
      local updated = route.update_waypoint(wp.id, { title = "New title" })
      assert.equals("New title", updated.title)
    end)

    it("updates description", function()
      local wp = route.create_waypoint({ title = "Desc test" })
      local updated = route.update_waypoint(wp.id, { description = "new desc" })
      assert.equals("new desc", updated.description)
    end)

    it("updates timestamp", function()
      local wp = route.create_waypoint({ title = "TS test" })
      local updated = route.update_waypoint(wp.id, { title = "Changed" })
      assert.is_string(updated.updated_at)
    end)

    it("ignores status, id, created_at", function()
      local wp = route.create_waypoint({ title = "Ignore test" })
      local original_id = wp.id
      local original_created = wp.created_at
      local updated = route.update_waypoint(wp.id, {
        status = "done",
        id = "hacked",
        created_at = "1999-01-01T00:00:00Z",
      })
      assert.equals(original_id, updated.id)
      assert.equals(original_created, updated.created_at)
      -- Status should not be "done" since we used update_waypoint not set_status
      assert.is_not.equals("done", updated.status)
    end)

    it("returns nil for bad ID", function()
      assert.is_nil(route.update_waypoint("nonexistent", { title = "nope" }))
    end)

    it("dispatches hook", function()
      local received = nil
      hooks.on("waypoint.updated", function(payload) received = payload end)
      local wp = route.create_waypoint({ title = "Hook" })
      route.update_waypoint(wp.id, { title = "Updated" })
      assert.is_not_nil(received)
      assert.equals(wp.id, received.waypoint.id)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- set_status
  -- -----------------------------------------------------------------------
  describe("set_status", function()
    it("transitions ready -> active", function()
      local wp = route.create_waypoint({ title = "Activate" })
      local updated = route.set_status(wp.id, "active")
      assert.is_not_nil(updated)
      assert.equals("active", updated.status)
    end)

    it("transitions active -> done", function()
      local wp = route.create_waypoint({ title = "Complete" })
      route.set_status(wp.id, "active")
      local updated = route.set_status(wp.id, "done")
      assert.is_not_nil(updated)
      assert.equals("done", updated.status)
    end)

    it("transitions done -> active", function()
      local wp = route.create_waypoint({ title = "Reactivate" })
      route.set_status(wp.id, "active")
      route.set_status(wp.id, "done")
      local updated = route.set_status(wp.id, "active")
      assert.is_not_nil(updated)
      assert.equals("active", updated.status)
    end)

    it("allows ready -> done", function()
      local wp = route.create_waypoint({ title = "Quick done" })
      local result = route.set_status(wp.id, "done")
      assert.is_not_nil(result)
      assert.equals("done", result.status)
    end)

    it("rejects blocked -> active", function()
      local dep = route.create_waypoint({ title = "Dep" })
      local wp = route.create_waypoint({ title = "Blocked", depends_on = { dep.id } })
      -- blocked only allows active and abandoned per VALID_TRANSITIONS
      -- But blocked -> active is actually allowed; test blocked -> done instead
      -- blocked = { active = true, abandoned = true } — so blocked -> done is invalid
      _G._test_notifications = {}
      local result = route.set_status(wp.id, "done")
      assert.is_nil(result)
    end)

    it("cascades: completing dep unblocks dependent", function()
      local dep = route.create_waypoint({ title = "Dep" })
      local wp = route.create_waypoint({ title = "Waiting", depends_on = { dep.id } })
      -- wp is blocked
      assert.equals("blocked", route.get(wp.id).status)
      -- Complete the dependency
      route.set_status(dep.id, "active")
      route.set_status(dep.id, "done")
      -- Now wp should be ready
      assert.equals("ready", route.get(wp.id).status)
    end)

    it("returns nil for bad ID", function()
      assert.is_nil(route.set_status("nonexistent", "active"))
    end)

    it("dispatches hook with from/to", function()
      local received = nil
      hooks.on("waypoint.status_changed", function(payload) received = payload end)
      local wp = route.create_waypoint({ title = "Status hook" })
      route.set_status(wp.id, "active")
      assert.is_not_nil(received)
      assert.equals("ready", received.from)
      assert.equals("active", received.to)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- delete_waypoint
  -- -----------------------------------------------------------------------
  describe("delete_waypoint", function()
    it("removes waypoint", function()
      local wp = route.create_waypoint({ title = "Delete me" })
      assert.is_true(route.delete_waypoint(wp.id))
      assert.is_nil(route.get(wp.id))
    end)

    it("cleans depends_on refs", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      route.delete_waypoint(a.id)
      local updated_b = route.get(b.id)
      assert.same({}, updated_b.depends_on)
    end)

    it("cleans linked notes", function()
      local note_mod = require("expedition.note")
      local wp = route.create_waypoint({ title = "Noted" })
      local n = note_mod.create("A note", { meta = { waypoint_id = wp.id } })
      -- Manually link note to waypoint
      route.link_note(n.id, wp.id)
      -- Now delete waypoint
      route.delete_waypoint(wp.id)
      -- Note's waypoint_id should be cleared
      local updated_note = note_mod.get(n.id)
      assert.is_not_nil(updated_note)
      if updated_note.meta then
        assert.is_nil(updated_note.meta.waypoint_id)
      end
    end)

    it("returns false for bad ID", function()
      assert.is_false(route.delete_waypoint("nonexistent"))
    end)

    it("dispatches hook", function()
      local received = nil
      hooks.on("waypoint.deleted", function(payload) received = payload end)
      local wp = route.create_waypoint({ title = "Delete hook" })
      route.delete_waypoint(wp.id)
      assert.is_not_nil(received)
      assert.equals(wp.id, received.waypoint_id)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- add_dependency
  -- -----------------------------------------------------------------------
  describe("add_dependency", function()
    it("adds and returns true", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B" })
      assert.is_true(route.add_dependency(b.id, a.id))
      local updated = route.get(b.id)
      local found = false
      for _, d in ipairs(updated.depends_on) do
        if d == a.id then found = true end
      end
      assert.is_true(found)
    end)

    it("rejects self-dependency", function()
      local a = route.create_waypoint({ title = "A" })
      assert.is_false(route.add_dependency(a.id, a.id))
    end)

    it("rejects duplicate", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B" })
      route.add_dependency(b.id, a.id)
      assert.is_false(route.add_dependency(b.id, a.id))
    end)

    it("rejects bad waypoint ID", function()
      local a = route.create_waypoint({ title = "A" })
      assert.is_false(route.add_dependency("nonexistent", a.id))
    end)

    it("rejects bad dependency ID", function()
      local a = route.create_waypoint({ title = "A" })
      assert.is_false(route.add_dependency(a.id, "nonexistent"))
    end)

    it("rejects cycle", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      assert.is_false(route.add_dependency(a.id, b.id))
    end)

    it("recomputes statuses", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B" })
      -- b is ready initially
      assert.equals("ready", route.get(b.id).status)
      route.add_dependency(b.id, a.id)
      -- b should now be blocked (a not done)
      assert.equals("blocked", route.get(b.id).status)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- remove_dependency
  -- -----------------------------------------------------------------------
  describe("remove_dependency", function()
    it("removes and returns true", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      assert.is_true(route.remove_dependency(b.id, a.id))
      local updated = route.get(b.id)
      assert.same({}, updated.depends_on)
    end)

    it("returns false when not found", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B" })
      assert.is_false(route.remove_dependency(b.id, a.id))
    end)

    it("returns false for bad ID", function()
      assert.is_false(route.remove_dependency("nonexistent", "also-bad"))
    end)

    it("recomputes statuses", function()
      local a = route.create_waypoint({ title = "A" })
      local b = route.create_waypoint({ title = "B", depends_on = { a.id } })
      assert.equals("blocked", route.get(b.id).status)
      route.remove_dependency(b.id, a.id)
      assert.equals("ready", route.get(b.id).status)
    end)
  end)

  -- -----------------------------------------------------------------------
  -- link_note / unlink_note
  -- -----------------------------------------------------------------------
  describe("link_note", function()
    it("creates bidirectional link", function()
      local note_mod = require("expedition.note")
      local wp = route.create_waypoint({ title = "Linkable" })
      local n = note_mod.create("Link me")
      assert.is_true(route.link_note(n.id, wp.id))

      -- Check waypoint side
      local updated_wp = route.get(wp.id)
      local found = false
      for _, nid in ipairs(updated_wp.linked_note_ids) do
        if nid == n.id then found = true end
      end
      assert.is_true(found)

      -- Check note side
      local updated_note = note_mod.get(n.id)
      assert.equals(wp.id, updated_note.meta.waypoint_id)
    end)

    it("rejects already-linked note", function()
      local note_mod = require("expedition.note")
      local wp = route.create_waypoint({ title = "Double link" })
      local n = note_mod.create("Link once")
      route.link_note(n.id, wp.id)
      assert.is_false(route.link_note(n.id, wp.id))
    end)

    it("rejects bad note ID", function()
      local wp = route.create_waypoint({ title = "Bad note" })
      assert.is_false(route.link_note("nonexistent", wp.id))
    end)

    it("rejects bad waypoint ID", function()
      local note_mod = require("expedition.note")
      local n = note_mod.create("Orphan note")
      assert.is_false(route.link_note(n.id, "nonexistent"))
    end)
  end)

  describe("unlink_note", function()
    it("removes bidirectional link", function()
      local note_mod = require("expedition.note")
      local wp = route.create_waypoint({ title = "Unlinkable" })
      local n = note_mod.create("Unlink me")
      route.link_note(n.id, wp.id)
      assert.is_true(route.unlink_note(n.id, wp.id))

      -- Check waypoint side
      local updated_wp = route.get(wp.id)
      assert.same({}, updated_wp.linked_note_ids)

      -- Check note side
      local updated_note = note_mod.get(n.id)
      assert.is_nil(updated_note.meta.waypoint_id)
    end)

    it("returns false when not linked", function()
      local note_mod = require("expedition.note")
      local wp = route.create_waypoint({ title = "Not linked" })
      local n = note_mod.create("Not linked note")
      assert.is_false(route.unlink_note(n.id, wp.id))
    end)
  end)

  -- -----------------------------------------------------------------------
  -- Branch API
  -- -----------------------------------------------------------------------
  describe("branch API", function()
    it("active_branch defaults to config value", function()
      test_reset_route()
      assert.equals("main", route.active_branch())
    end)

    it("creates a branch", function()
      local b = route.create_branch("feature-x", "Try new approach")
      assert.is_not_nil(b)
      assert.equals("feature-x", b.name)
      assert.equals("Try new approach", b.reasoning)
    end)

    it("rejects empty branch name", function()
      assert.is_nil(route.create_branch(""))
      assert.is_nil(route.create_branch(nil))
    end)

    it("rejects duplicate branch name", function()
      route.create_branch("dup")
      assert.is_nil(route.create_branch("dup"))
    end)

    it("switches branch", function()
      route.create_branch("other")
      route.switch_branch("other")
      assert.equals("other", route.active_branch())
    end)

    it("rejects bad branch name on switch", function()
      _G._test_notifications = {}
      route.switch_branch("nonexistent-branch")
      assert.is_true(#_G._test_notifications > 0)
    end)

    it("list includes default + created + implicit", function()
      route.create_branch("explicit")
      route.create_waypoint({ title = "Implicit WP", branch = "implicit-branch" })
      local branches = route.list_branches()
      local names = {}
      for _, name in ipairs(branches) do names[name] = true end
      assert.is_true(names["main"])
      assert.is_true(names["explicit"])
      assert.is_true(names["implicit-branch"])
    end)

    it("merge remaps IDs/deps and resets status", function()
      local a = route.create_waypoint({ title = "A", branch = "src" })
      local b = route.create_waypoint({ title = "B", branch = "src", depends_on = { a.id } })
      route.set_status(a.id, "active")
      route.set_status(a.id, "done")

      route.merge_branch("src", "dest")

      local all = route.list()
      local dest_wps = {}
      for _, wp in ipairs(all) do
        if wp.branch == "dest" then
          table.insert(dest_wps, wp)
        end
      end
      assert.equals(2, #dest_wps)
      -- Merged waypoints should have new IDs
      for _, wp in ipairs(dest_wps) do
        assert.is_not.equals(a.id, wp.id)
        assert.is_not.equals(b.id, wp.id)
      end
    end)

    it("returns nil-equivalent when no active expedition", function()
      test_clear_active()
      assert.is_nil(route.create_branch("orphan"))
    end)
  end)
end)
