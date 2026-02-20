local parse = require("expedition.ai.parse")

describe("ai.parse", function()
  describe("extract_json", function()
    it("extracts from ```json fence", function()
      local text = 'Here is the result:\n```json\n{"key": "value"}\n```\nDone.'
      local result = parse.extract_json(text)
      assert.same({ key = "value" }, result)
    end)

    it("extracts from bare ``` fence", function()
      local text = 'Result:\n```\n{"key": "value"}\n```'
      local result = parse.extract_json(text)
      assert.same({ key = "value" }, result)
    end)

    it("extracts raw JSON object", function()
      local text = 'Some text before {"key": "value"} some text after'
      local result = parse.extract_json(text)
      assert.same({ key = "value" }, result)
    end)

    it("extracts raw JSON array", function()
      local text = 'Here: [1, 2, 3]'
      local result = parse.extract_json(text)
      assert.same({ 1, 2, 3 }, result)
    end)

    it("returns nil for no JSON", function()
      local result, err = parse.extract_json("just plain text with no json")
      assert.is_nil(result)
      assert.is_string(err)
    end)

    it("handles nested braces in strings", function()
      local text = '{"data": "value with {braces} inside"}'
      local result = parse.extract_json(text)
      assert.equals("value with {braces} inside", result.data)
    end)

    it("handles escaped quotes in strings", function()
      local text = '{"msg": "she said \\"hello\\""}'
      local result = parse.extract_json(text)
      assert.equals('she said "hello"', result.msg)
    end)
  end)

  describe("parse_proposal", function()
    it("parses valid proposal", function()
      local text = vim.json.encode({
        waypoints = {
          { title = "Step 1", description = "Do first thing", reasoning = "Because" },
          { title = "Step 2" },
        },
        summary = "A plan",
      })
      local proposal, err = parse.parse_proposal(text)
      assert.is_nil(err)
      assert.is_not_nil(proposal)
      assert.equals(2, #proposal.waypoints)
      assert.equals("Step 1", proposal.waypoints[1].title)
      assert.equals("Do first thing", proposal.waypoints[1].description)
      assert.equals("Because", proposal.waypoints[1].reasoning)
      assert.equals("A plan", proposal.summary)
    end)

    it("rejects missing waypoints", function()
      local text = vim.json.encode({ summary = "no waypoints" })
      local proposal, err = parse.parse_proposal(text)
      assert.is_nil(proposal)
      assert.truthy(err:find("waypoints"))
    end)

    it("rejects empty waypoints", function()
      local text = vim.json.encode({ waypoints = {} })
      local proposal, err = parse.parse_proposal(text)
      assert.is_nil(proposal)
      assert.truthy(err:find("waypoints"))
    end)

    it("rejects waypoint missing title", function()
      local text = vim.json.encode({
        waypoints = { { description = "no title here" } },
      })
      local proposal, err = parse.parse_proposal(text)
      assert.is_nil(proposal)
      assert.truthy(err:find("title"))
    end)

    it("fills default fields", function()
      local text = vim.json.encode({
        waypoints = { { title = "Minimal" } },
      })
      local proposal = parse.parse_proposal(text)
      assert.is_not_nil(proposal)
      local wp = proposal.waypoints[1]
      assert.equals("", wp.description)
      assert.equals("", wp.reasoning)
      assert.same({}, wp.depends_on_titles)
      assert.equals("", proposal.summary)
    end)

    it("falls back depends_on to depends_on_titles", function()
      local text = vim.json.encode({
        waypoints = {
          { title = "A", depends_on = { "Step 1" } },
        },
      })
      local proposal = parse.parse_proposal(text)
      assert.same({ "Step 1" }, proposal.waypoints[1].depends_on_titles)
    end)

    it("returns error for invalid JSON", function()
      local proposal, err = parse.parse_proposal("not json at all")
      assert.is_nil(proposal)
      assert.is_string(err)
    end)

    it("resets depends_on_titles when it is a string", function()
      local text = vim.json.encode({
        waypoints = {
          { title = "A", depends_on_titles = "not a table" },
        },
      })
      local proposal = parse.parse_proposal(text)
      assert.is_not_nil(proposal)
      assert.same({}, proposal.waypoints[1].depends_on_titles)
    end)
  end)

  describe("parse_summit_eval", function()
    it("parses valid evaluation", function()
      local text = vim.json.encode({
        ready = true,
        confidence = 0.85,
        reasoning = "All conditions met",
        remaining = { "Deploy to prod" },
      })
      local eval, err = parse.parse_summit_eval(text)
      assert.is_nil(err)
      assert.is_not_nil(eval)
      assert.is_true(eval.ready)
      assert.equals(0.85, eval.confidence)
      assert.equals("All conditions met", eval.reasoning)
      assert.same({ "Deploy to prod" }, eval.remaining)
    end)

    it("rejects missing ready field", function()
      local text = vim.json.encode({ confidence = 0.5 })
      local eval, err = parse.parse_summit_eval(text)
      assert.is_nil(eval)
      assert.truthy(err:find("ready"))
    end)

    it("parses with conditions array", function()
      local text = vim.json.encode({
        ready = false,
        conditions = {
          { id = "c-1", assessment = "met", reasoning = "Done" },
          { id = "c-2", assessment = "not_met", reasoning = "WIP" },
        },
      })
      local eval = parse.parse_summit_eval(text)
      assert.is_not_nil(eval)
      assert.is_not_nil(eval.conditions)
      assert.equals(2, #eval.conditions)
      assert.equals("c-1", eval.conditions[1].id)
      assert.equals("met", eval.conditions[1].assessment)
      assert.equals("Done", eval.conditions[1].reasoning)
    end)

    it("skips conditions missing id", function()
      local text = vim.json.encode({
        ready = true,
        conditions = {
          { id = "c-1", assessment = "met" },
          { assessment = "not_met" }, -- no id, should be skipped
        },
      })
      local eval = parse.parse_summit_eval(text)
      assert.equals(1, #eval.conditions)
      assert.equals("c-1", eval.conditions[1].id)
    end)

    it("defaults confidence, reasoning, remaining", function()
      local text = vim.json.encode({ ready = false })
      local eval = parse.parse_summit_eval(text)
      assert.equals(0, eval.confidence)
      assert.equals("", eval.reasoning)
      assert.same({}, eval.remaining)
    end)

    it("works without conditions (backwards compat)", function()
      local text = vim.json.encode({
        ready = true,
        confidence = 1.0,
        reasoning = "Ship it",
        remaining = {},
      })
      local eval = parse.parse_summit_eval(text)
      assert.is_nil(eval.conditions)
    end)

    it("returns error for invalid JSON", function()
      local eval, err = parse.parse_summit_eval("garbage")
      assert.is_nil(eval)
      assert.is_string(err)
    end)
  end)
end)
