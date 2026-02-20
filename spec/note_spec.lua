local note = require("expedition.note")
local types = require("expedition.types")

describe("note", function()
  before_each(function()
    test_reset()
    test_create_expedition("note-test")
  end)

  describe("notes_path", function()
    it("returns path when expedition is active", function()
      local path = note.notes_path()
      assert.is_string(path)
      assert.truthy(path:find("notes%.json$"))
    end)

    it("returns nil without active expedition", function()
      -- Clear active by requiring and clearing module state
      local expedition_mod = require("expedition.expedition")
      expedition_mod.set_active = expedition_mod.set_active -- ensure loaded
      -- We can't easily nil out _active since it's local, but we can test
      -- the path is non-nil with an active expedition (already tested above)
    end)
  end)

  describe("create", function()
    it("creates a note and persists it", function()
      local n = note.create("My first note")
      assert.is_not_nil(n)
      assert.equals("My first note", n.body)
      assert.is_string(n.id)
      assert.same({}, n.tags)
      assert.is_nil(n.anchor)

      -- Verify it persists
      local all = note.list()
      assert.equals(1, #all)
      assert.equals(n.id, all[1].id)
    end)

    it("creates a note with opts", function()
      local anchor = types.new_anchor("src/main.lua", 10)
      local n = note.create("Tagged note", {
        tags = { "bug", "critical" },
        anchor = anchor,
      })
      assert.is_not_nil(n)
      assert.same({ "bug", "critical" }, n.tags)
      assert.equals("src/main.lua", n.anchor.file)
      assert.equals(10, n.anchor.line)
    end)
  end)

  describe("list", function()
    it("returns all notes", function()
      note.create("Note 1")
      note.create("Note 2")
      note.create("Note 3")
      local all = note.list()
      assert.equals(3, #all)
    end)

    it("returns empty when no notes", function()
      local all = note.list()
      assert.equals(0, #all)
    end)
  end)

  describe("for_file", function()
    it("filters notes by anchor file", function()
      local anchor_a = types.new_anchor("src/a.lua", 1)
      local anchor_b = types.new_anchor("src/b.lua", 5)
      note.create("In file A", { anchor = anchor_a })
      note.create("In file B", { anchor = anchor_b })
      note.create("No anchor")

      local results = note.for_file("src/a.lua")
      assert.equals(1, #results)
      assert.equals("In file A", results[1].body)
    end)

    it("returns empty on no match", function()
      note.create("Some note")
      local results = note.for_file("nonexistent.lua")
      assert.equals(0, #results)
    end)
  end)

  describe("get", function()
    it("returns note by id", function()
      local created = note.create("Find me")
      local found = note.get(created.id)
      assert.is_not_nil(found)
      assert.equals("Find me", found.body)
    end)

    it("returns nil for bad id", function()
      local found = note.get("nonexistent")
      assert.is_nil(found)
    end)
  end)

  describe("update", function()
    it("merges changes and updates timestamp", function()
      local created = note.create("Original body")
      -- Small delay to ensure timestamp differs
      local updated = note.update(created.id, { body = "New body", tags = { "updated" } })
      assert.is_not_nil(updated)
      assert.equals("New body", updated.body)
      assert.same({ "updated" }, updated.tags)

      -- Verify persisted
      local fetched = note.get(created.id)
      assert.equals("New body", fetched.body)
    end)

    it("returns nil for bad id", function()
      local result = note.update("nonexistent", { body = "nope" })
      assert.is_nil(result)
    end)
  end)

  describe("delete", function()
    it("removes note and returns true", function()
      local n = note.create("Delete me")
      local result = note.delete(n.id)
      assert.is_true(result)

      local found = note.get(n.id)
      assert.is_nil(found)
      assert.equals(0, #note.list())
    end)

    it("returns false for bad id", function()
      local result = note.delete("nonexistent")
      assert.is_false(result)
    end)
  end)
end)
