local types = require("expedition.types")

describe("types", function()
  describe("new_expedition", function()
    it("creates expedition with defaults", function()
      local exp = types.new_expedition("my-project")
      assert.is_string(exp.id)
      assert.equals(8, #exp.id)
      assert.truthy(exp.id:match("^%x+$"))
      assert.equals("my-project", exp.name)
      assert.equals("active", exp.status)
      assert.equals("", exp.description)
      assert.is_string(exp.created_at)
      assert.is_string(exp.updated_at)
      assert.equals(exp.created_at, exp.updated_at)
      assert.same({}, exp.meta)
    end)

    it("creates expedition with opts", function()
      local exp = types.new_expedition("proj", {
        description = "A test project",
        status = "paused",
        meta = { key = "value" },
      })
      assert.equals("A test project", exp.description)
      assert.equals("paused", exp.status)
      assert.same({ key = "value" }, exp.meta)
    end)
  end)

  describe("new_note", function()
    it("creates note with defaults", function()
      local note = types.new_note("exp-123", "some body text")
      assert.is_string(note.id)
      assert.equals(8, #note.id)
      assert.equals("exp-123", note.expedition_id)
      assert.equals("some body text", note.body)
      assert.same({}, note.tags)
      assert.is_nil(note.anchor)
      assert.is_string(note.created_at)
      assert.is_string(note.updated_at)
      assert.same({}, note.meta)
    end)

    it("creates note with opts", function()
      local anchor = types.new_anchor("src/main.lua", 10)
      local note = types.new_note("exp-123", "body", {
        tags = { "bug", "urgent" },
        anchor = anchor,
        meta = { waypoint_id = "wp-1" },
      })
      assert.same({ "bug", "urgent" }, note.tags)
      assert.equals("src/main.lua", note.anchor.file)
      assert.equals(10, note.anchor.line)
      assert.same({ waypoint_id = "wp-1" }, note.meta)
    end)
  end)

  describe("new_anchor", function()
    it("creates anchor with defaults", function()
      local a = types.new_anchor("src/foo.lua", 42)
      assert.equals("src/foo.lua", a.file)
      assert.equals(42, a.line)
      assert.is_nil(a.end_line)
      assert.is_nil(a.symbol)
      assert.equals("", a.snapshot_hash)
      assert.same({}, a.snapshot_lines)
    end)

    it("creates anchor with opts", function()
      local a = types.new_anchor("src/foo.lua", 42, {
        end_line = 50,
        symbol = "function:parse",
        snapshot_hash = "abc123",
        snapshot_lines = { "line1", "line2" },
      })
      assert.equals(50, a.end_line)
      assert.equals("function:parse", a.symbol)
      assert.equals("abc123", a.snapshot_hash)
      assert.same({ "line1", "line2" }, a.snapshot_lines)
    end)
  end)

  describe("new_waypoint", function()
    it("creates waypoint with defaults", function()
      local wp = types.new_waypoint("Implement parser")
      assert.is_string(wp.id)
      assert.equals(8, #wp.id)
      assert.equals("Implement parser", wp.title)
      assert.equals("", wp.description)
      assert.equals("ready", wp.status)
      assert.same({}, wp.depends_on)
      assert.equals("", wp.reasoning)
      assert.same({}, wp.linked_note_ids)
      assert.equals("main", wp.branch)
      assert.is_string(wp.created_at)
      assert.is_string(wp.updated_at)
    end)

    it("creates waypoint with opts", function()
      local wp = types.new_waypoint("Step 2", {
        description = "Do the thing",
        status = "blocked",
        depends_on = { "wp-1" },
        reasoning = "Because reasons",
        linked_note_ids = { "n-1" },
        branch = "feature-x",
      })
      assert.equals("Do the thing", wp.description)
      assert.equals("blocked", wp.status)
      assert.same({ "wp-1" }, wp.depends_on)
      assert.equals("Because reasons", wp.reasoning)
      assert.same({ "n-1" }, wp.linked_note_ids)
      assert.equals("feature-x", wp.branch)
    end)
  end)

  describe("new_summit_condition", function()
    it("creates condition with default status", function()
      local c = types.new_summit_condition("All tests pass")
      assert.is_string(c.id)
      assert.equals(8, #c.id)
      assert.equals("All tests pass", c.text)
      assert.equals("open", c.status)
      assert.is_string(c.created_at)
      assert.is_string(c.updated_at)
    end)

    it("creates condition with opts", function()
      local c = types.new_summit_condition("Deployed", { status = "met" })
      assert.equals("met", c.status)
    end)
  end)

  describe("new_branch", function()
    it("creates branch with defaults", function()
      local b = types.new_branch("feature-x")
      assert.equals("feature-x", b.name)
      assert.equals("", b.reasoning)
      assert.is_string(b.created_at)
    end)

    it("creates branch with reasoning", function()
      local b = types.new_branch("refactor", "Clean up old code")
      assert.equals("refactor", b.name)
      assert.equals("Clean up old code", b.reasoning)
    end)
  end)

  describe("new_breadcrumb", function()
    it("creates breadcrumb", function()
      local bc = types.new_breadcrumb("src/init.lua", 15)
      assert.equals("src/init.lua", bc.file)
      assert.equals(15, bc.line)
      assert.is_string(bc.timestamp)
    end)
  end)

  describe("new_campfire_message", function()
    it("creates message", function()
      local msg = types.new_campfire_message("user", "Hello there")
      assert.equals("user", msg.role)
      assert.equals("Hello there", msg.content)
      assert.is_string(msg.timestamp)
    end)

    it("supports assistant role", function()
      local msg = types.new_campfire_message("assistant", "Hi!")
      assert.equals("assistant", msg.role)
    end)
  end)

  describe("new_log_entry", function()
    it("creates log entry with data", function()
      local entry = types.new_log_entry("note.created", "exp-1", { note_id = "n-1" })
      assert.is_string(entry.timestamp)
      assert.equals("note.created", entry.event)
      assert.equals("exp-1", entry.expedition_id)
      assert.same({ note_id = "n-1" }, entry.data)
    end)

    it("defaults data to empty table", function()
      local entry = types.new_log_entry("expedition.created", "exp-1")
      assert.same({}, entry.data)
    end)
  end)
end)
