local log = require("expedition.log")

describe("log", function()
  local exp

  before_each(function()
    test_reset()
    exp = test_create_expedition("log-test")
  end)

  describe("log_path", function()
    it("returns path ending in log.jsonl", function()
      local path = log.log_path(exp.id)
      assert.is_string(path)
      assert.truthy(path:find("log%.jsonl$"))
    end)
  end)

  describe("append", function()
    it("appends entry and returns true", function()
      local ok = log.append(exp.id, "test.event", { key = "val" })
      assert.is_true(ok)
    end)
  end)

  describe("read", function()
    it("returns entries", function()
      log.append(exp.id, "test.a", { n = 1 })
      log.append(exp.id, "test.b", { n = 2 })
      local entries = log.read(exp.id)
      -- expedition.created is already logged from test_create_expedition
      assert.is_true(#entries >= 2)
    end)

    it("entries have correct structure", function()
      log.append(exp.id, "test.structure", { foo = "bar" })
      local entries = log.read(exp.id)
      local last = entries[#entries]
      assert.is_string(last.timestamp)
      assert.equals("test.structure", last.event)
      assert.equals(exp.id, last.expedition_id)
      assert.equals("bar", last.data.foo)
    end)
  end)

  describe("tail", function()
    it("returns last n entries", function()
      -- Clear existing log by creating fresh entries
      for i = 1, 5 do
        log.append(exp.id, "test.seq", { i = i })
      end
      local all = log.read(exp.id)
      local last3 = log.tail(exp.id, 3)
      assert.equals(3, #last3)
      -- Should be the last 3 entries
      assert.same(all[#all], last3[3])
      assert.same(all[#all - 1], last3[2])
      assert.same(all[#all - 2], last3[1])
    end)

    it("returns all when n > count", function()
      local all = log.read(exp.id)
      local result = log.tail(exp.id, 9999)
      assert.equals(#all, #result)
    end)

    it("returns empty for n=0", function()
      local result = log.tail(exp.id, 0)
      assert.equals(0, #result)
    end)
  end)
end)
