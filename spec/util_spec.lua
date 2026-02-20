local util = require("expedition.util")

describe("util", function()
  describe("id", function()
    it("returns 8-char hex string", function()
      local id = util.id()
      assert.equals(8, #id)
      assert.truthy(id:match("^%x+$"))
    end)

    it("successive calls differ", function()
      local a = util.id()
      local b = util.id()
      assert.is_not.equals(a, b)
    end)
  end)

  describe("timestamp", function()
    it("returns ISO 8601 format", function()
      local ts = util.timestamp()
      assert.truthy(ts:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$"))
    end)

    it("ends in Z", function()
      local ts = util.timestamp()
      assert.truthy(ts:sub(-1) == "Z")
    end)
  end)

  describe("hash", function()
    it("returns 8-char hex string", function()
      local h = util.hash("hello")
      assert.equals(8, #h)
      assert.truthy(h:match("^%x+$"))
    end)

    it("is deterministic", function()
      local a = util.hash("test input")
      local b = util.hash("test input")
      assert.equals(a, b)
    end)

    it("different inputs produce different hashes", function()
      local a = util.hash("hello")
      local b = util.hash("world")
      assert.is_not.equals(a, b)
    end)
  end)

  describe("hash_lines", function()
    it("hashes an array of lines", function()
      local h = util.hash_lines({ "line1", "line2" })
      assert.equals(8, #h)
      assert.truthy(h:match("^%x+$"))
    end)

    it("equals hash of joined lines", function()
      local lines = { "foo", "bar", "baz" }
      assert.equals(util.hash(table.concat(lines, "\n")), util.hash_lines(lines))
    end)

    it("different lines produce different hashes", function()
      local a = util.hash_lines({ "a", "b" })
      local b = util.hash_lines({ "c", "d" })
      assert.is_not.equals(a, b)
    end)
  end)

  describe("clamp", function()
    it("returns value when in range", function()
      assert.equals(5, util.clamp(5, 1, 10))
    end)

    it("returns min when below", function()
      assert.equals(1, util.clamp(-5, 1, 10))
    end)

    it("returns max when above", function()
      assert.equals(10, util.clamp(99, 1, 10))
    end)

    it("handles equal min and max", function()
      assert.equals(5, util.clamp(99, 5, 5))
      assert.equals(5, util.clamp(-1, 5, 5))
      assert.equals(5, util.clamp(5, 5, 5))
    end)
  end)

  describe("shallow_copy", function()
    it("copies key/value pairs", function()
      local orig = { a = 1, b = "two" }
      local copy = util.shallow_copy(orig)
      assert.equals(1, copy.a)
      assert.equals("two", copy.b)
    end)

    it("returns a new reference", function()
      local orig = { x = 1 }
      local copy = util.shallow_copy(orig)
      assert.is_not.equals(orig, copy)
      copy.x = 99
      assert.equals(1, orig.x)
    end)

    it("does not deep-copy nested tables", function()
      local inner = { val = 42 }
      local orig = { nested = inner }
      local copy = util.shallow_copy(orig)
      assert.equals(inner, copy.nested) -- same reference
      copy.nested.val = 100
      assert.equals(100, orig.nested.val)
    end)
  end)
end)
