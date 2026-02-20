local storage = require("expedition.storage")

describe("storage", function()
  local tmpdir

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  describe("read_json", function()
    it("returns nil for missing file", function()
      local data, err = storage.read_json(tmpdir .. "/missing.json")
      assert.is_nil(data)
      assert.is_string(err)
    end)

    it("returns nil for empty file", function()
      local path = tmpdir .. "/empty.json"
      local f = io.open(path, "w")
      f:write("")
      f:close()
      local data, err = storage.read_json(path)
      assert.is_nil(data)
      assert.equals("empty file", err)
    end)

    it("returns nil for bad JSON", function()
      local path = tmpdir .. "/bad.json"
      local f = io.open(path, "w")
      f:write("not json at all {{{")
      f:close()
      local data, err = storage.read_json(path)
      assert.is_nil(data)
      assert.truthy(err:find("json decode error"))
    end)

    it("decodes valid JSON", function()
      local path = tmpdir .. "/valid.json"
      local f = io.open(path, "w")
      f:write('{"key":"value","num":42}')
      f:close()
      local data = storage.read_json(path)
      assert.is_not_nil(data)
      assert.equals("value", data.key)
      assert.equals(42, data.num)
    end)
  end)

  describe("write_json", function()
    it("write + read roundtrip", function()
      local path = tmpdir .. "/roundtrip.json"
      local original = { name = "test", items = { 1, 2, 3 } }
      local ok = storage.write_json(path, original)
      assert.is_true(ok)
      local loaded = storage.read_json(path)
      assert.same(original, loaded)
    end)

    it("atomic write (no .tmp left behind)", function()
      local path = tmpdir .. "/atomic.json"
      storage.write_json(path, { ok = true })
      -- .tmp should not exist
      local f = io.open(path .. ".tmp", "r")
      assert.is_nil(f)
    end)
  end)

  describe("append_jsonl / read_jsonl", function()
    it("append + read roundtrip", function()
      local path = tmpdir .. "/test.jsonl"
      storage.append_jsonl(path, { event = "a", n = 1 })
      storage.append_jsonl(path, { event = "b", n = 2 })
      local entries = storage.read_jsonl(path)
      assert.equals(2, #entries)
      assert.equals("a", entries[1].event)
      assert.equals("b", entries[2].event)
    end)

    it("skips invalid lines", function()
      local path = tmpdir .. "/mixed.jsonl"
      local f = io.open(path, "w")
      f:write('{"valid":true}\n')
      f:write('not json\n')
      f:write('{"also_valid":true}\n')
      f:close()
      local entries = storage.read_jsonl(path)
      assert.equals(2, #entries)
      assert.is_true(entries[1].valid)
      assert.is_true(entries[2].also_valid)
    end)
  end)
end)
