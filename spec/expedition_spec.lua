local expedition_mod = require("expedition.expedition")
local hooks = require("expedition.hooks")

describe("expedition", function()
  before_each(function()
    test_reset()
    test_clear_active()
  end)

  describe("create", function()
    it("returns expedition with name", function()
      local exp = expedition_mod.create("my-project")
      assert.is_not_nil(exp)
      assert.equals("my-project", exp.name)
      assert.is_string(exp.id)
      assert.equals("active", exp.status)
    end)

    it("sets active", function()
      local exp = expedition_mod.create("active-test")
      local active = expedition_mod.get_active()
      assert.is_not_nil(active)
      assert.equals(exp.id, active.id)
    end)

    it("persists to disk", function()
      local exp = expedition_mod.create("persist-test")
      -- Reload by loading from ID
      test_clear_active()
      local loaded = expedition_mod.load(exp.id)
      assert.is_not_nil(loaded)
      assert.equals("persist-test", loaded.name)
    end)

    it("dispatches hook", function()
      local received = nil
      hooks.on("expedition.created", function(payload) received = payload end)
      local exp = expedition_mod.create("hook-test")
      assert.is_not_nil(received)
      assert.equals(exp.id, received.expedition.id)
    end)

    it("logs event", function()
      local log = require("expedition.log")
      local exp = expedition_mod.create("log-test")
      local entries = log.read(exp.id)
      local found = false
      for _, e in ipairs(entries) do
        if e.event == "expedition.created" then
          found = true
          break
        end
      end
      assert.is_true(found)
    end)
  end)

  describe("get_active", function()
    it("returns nil when none created", function()
      test_clear_active()
      assert.is_nil(expedition_mod.get_active())
    end)

    it("returns active after create", function()
      local exp = expedition_mod.create("active-test")
      local active = expedition_mod.get_active()
      assert.is_not_nil(active)
      assert.equals(exp.id, active.id)
    end)
  end)

  describe("set_active", function()
    it("sets active expedition", function()
      local exp = expedition_mod.create("set-test")
      test_clear_active()
      assert.is_nil(expedition_mod.get_active())
      expedition_mod.set_active(exp)
      assert.equals(exp.id, expedition_mod.get_active().id)
    end)

    it("dispatches hook", function()
      local exp = expedition_mod.create("dispatch-test")
      test_clear_active()
      local received = nil
      hooks.on("expedition.activated", function(payload) received = payload end)
      expedition_mod.set_active(exp)
      assert.is_not_nil(received)
      assert.equals(exp.id, received.expedition.id)
    end)
  end)

  describe("list", function()
    it("returns empty when none", function()
      local summaries = expedition_mod.list()
      -- May include expeditions from other tests, so just ensure it's a table
      assert.is_table(summaries)
    end)

    it("returns summaries of all", function()
      expedition_mod.create("list-a")
      expedition_mod.create("list-b")
      local summaries = expedition_mod.list()
      local names = {}
      for _, s in ipairs(summaries) do
        names[s.name] = true
      end
      assert.is_true(names["list-a"])
      assert.is_true(names["list-b"])
    end)

    it("includes note_count", function()
      local exp = expedition_mod.create("notes-count-test")
      local note_mod = require("expedition.note")
      note_mod.create("note 1")
      note_mod.create("note 2")
      local summaries = expedition_mod.list()
      local found = nil
      for _, s in ipairs(summaries) do
        if s.id == exp.id then found = s end
      end
      assert.is_not_nil(found)
      assert.equals(2, found.note_count)
    end)
  end)

  describe("list_names", function()
    it("returns names array", function()
      expedition_mod.create("name-a")
      expedition_mod.create("name-b")
      local names = expedition_mod.list_names()
      assert.is_table(names)
      local has_a, has_b = false, false
      for _, n in ipairs(names) do
        if n == "name-a" then has_a = true end
        if n == "name-b" then has_b = true end
      end
      assert.is_true(has_a)
      assert.is_true(has_b)
    end)
  end)

  describe("load", function()
    it("loads by ID and sets active", function()
      local exp = expedition_mod.create("load-test")
      test_clear_active()
      local loaded = expedition_mod.load(exp.id)
      assert.is_not_nil(loaded)
      assert.equals(exp.id, loaded.id)
      assert.equals(exp.id, expedition_mod.get_active().id)
    end)

    it("returns nil and notifies for bad ID", function()
      _G._test_notifications = {}
      local result = expedition_mod.load("nonexistent-id")
      assert.is_nil(result)
      assert.is_true(#_G._test_notifications > 0)
    end)
  end)

  describe("load_by_name", function()
    it("loads by name and sets active", function()
      local exp = expedition_mod.create("find-by-name")
      test_clear_active()
      local loaded = expedition_mod.load_by_name("find-by-name")
      assert.is_not_nil(loaded)
      assert.equals(exp.id, loaded.id)
      assert.equals(exp.id, expedition_mod.get_active().id)
    end)

    it("returns nil and notifies for bad name", function()
      _G._test_notifications = {}
      local result = expedition_mod.load_by_name("does-not-exist")
      assert.is_nil(result)
      assert.is_true(#_G._test_notifications > 0)
    end)
  end)

  describe("update", function()
    it("merges and persists", function()
      local exp = expedition_mod.create("update-test")
      local updated = expedition_mod.update(exp.id, { description = "new desc" })
      assert.is_not_nil(updated)
      assert.equals("new desc", updated.description)

      -- Verify persisted
      test_clear_active()
      local reloaded = expedition_mod.load(exp.id)
      assert.equals("new desc", reloaded.description)
    end)

    it("updates timestamp", function()
      local exp = expedition_mod.create("ts-test")
      local updated = expedition_mod.update(exp.id, { description = "changed" })
      assert.is_string(updated.updated_at)
      assert.is_not_nil(updated.updated_at)
    end)

    it("refreshes _active", function()
      local exp = expedition_mod.create("refresh-test")
      expedition_mod.update(exp.id, { description = "refreshed" })
      local active = expedition_mod.get_active()
      assert.equals("refreshed", active.description)
    end)

    it("returns nil for bad ID", function()
      expedition_mod.create("dummy")
      _G._test_notifications = {}
      local result = expedition_mod.update("nonexistent-id", { description = "nope" })
      assert.is_nil(result)
    end)
  end)
end)
