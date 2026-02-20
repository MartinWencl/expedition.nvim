local hooks = require("expedition.hooks")

describe("hooks", function()
  before_each(function()
    hooks.clear()
  end)

  describe("on", function()
    it("registers a callback", function()
      local called = false
      hooks.on("test.event", function() called = true end)
      hooks.dispatch("test.event")
      assert.is_true(called)
    end)

    it("returns an unregister function", function()
      local count = 0
      local unsub = hooks.on("test.event", function() count = count + 1 end)
      hooks.dispatch("test.event")
      assert.equals(1, count)

      unsub()
      hooks.dispatch("test.event")
      assert.equals(1, count) -- not called again
    end)

    it("unregister removes only that callback", function()
      local a_count = 0
      local b_count = 0
      local unsub_a = hooks.on("test.event", function() a_count = a_count + 1 end)
      hooks.on("test.event", function() b_count = b_count + 1 end)

      unsub_a()
      hooks.dispatch("test.event")
      assert.equals(0, a_count)
      assert.equals(1, b_count)
    end)

    it("supports multiple callbacks", function()
      local results = {}
      hooks.on("test.event", function() table.insert(results, "a") end)
      hooks.on("test.event", function() table.insert(results, "b") end)
      hooks.dispatch("test.event")
      assert.same({ "a", "b" }, results)
    end)

    it("accepts opts table", function()
      -- opts are stored on the entry; verify no error
      hooks.on("test.event", function() end, { priority = 10 })
      -- If we get here without error, opts are accepted
      assert.is_true(true)
    end)
  end)

  describe("dispatch", function()
    it("calls all callbacks with payload", function()
      local received = nil
      hooks.on("test.event", function(payload) received = payload end)
      hooks.dispatch("test.event", { key = "value" })
      assert.same({ key = "value" }, received)
    end)

    it("is no-op when no listeners registered", function()
      -- Should not error
      hooks.dispatch("nonexistent.event", { data = 1 })
      assert.is_true(true)
    end)

    it("passes empty table when payload is nil", function()
      local received = nil
      hooks.on("test.event", function(payload) received = payload end)
      hooks.dispatch("test.event")
      assert.same({}, received)
    end)

    it("continues after callback error", function()
      local second_called = false
      hooks.on("test.event", function() error("boom") end)
      hooks.on("test.event", function() second_called = true end)

      -- Stub vim.schedule to call immediately so we can check notification
      local orig_schedule = vim.schedule
      vim.schedule = function(fn) fn() end

      hooks.dispatch("test.event")
      assert.is_true(second_called)

      vim.schedule = orig_schedule
    end)

    it("notifies about errors", function()
      hooks.on("test.event", function() error("boom") end)

      local orig_schedule = vim.schedule
      local scheduled_fn = nil
      vim.schedule = function(fn) scheduled_fn = fn end

      hooks.dispatch("test.event")

      vim.schedule = orig_schedule

      assert.is_not_nil(scheduled_fn)
      -- Execute the scheduled function to trigger vim.notify
      _G._test_notifications = {}
      scheduled_fn()

      assert.is_true(#_test_notifications > 0)
      local msg = _test_notifications[1].msg
      assert.truthy(msg:find("hook error"))
      assert.truthy(msg:find("boom"))
    end)
  end)

  describe("clear", function()
    it("clears all when no arg", function()
      local called = false
      hooks.on("a", function() called = true end)
      hooks.on("b", function() called = true end)
      hooks.clear()
      hooks.dispatch("a")
      hooks.dispatch("b")
      assert.is_false(called)
    end)

    it("clears only specified event", function()
      local a_called = false
      local b_called = false
      hooks.on("a", function() a_called = true end)
      hooks.on("b", function() b_called = true end)
      hooks.clear("a")
      hooks.dispatch("a")
      hooks.dispatch("b")
      assert.is_false(a_called)
      assert.is_true(b_called)
    end)

    it("doesn't affect other events", function()
      local called = false
      hooks.on("keep", function() called = true end)
      hooks.clear("remove")
      hooks.dispatch("keep")
      assert.is_true(called)
    end)
  end)
end)
