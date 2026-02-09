local prompt = require("blink-ai.prompt")

describe("prompt builders", function()
  it("builds chat messages with user context", function()
    local ctx = {
      filetype = "lua",
      filename = "init.lua",
      context_before_cursor = "local x = ",
      context_after_cursor = "1",
      user_context = "project conventions",
    }
    local messages = prompt.chat_messages(ctx, {})

    assert.are.equal("system", messages[1].role)
    assert.truthy(messages[1].content:find("Filetype: lua", 1, true))
    assert.are.equal("user", messages[2].role)
    assert.truthy(messages[2].content:find("project conventions", 1, true))
    assert.truthy(messages[2].content:find("<cursor>", 1, true))
  end)

  it("builds anthropic message content", function()
    local ctx = {
      context_before_cursor = "print(",
      context_after_cursor = ")",
      user_context = "python style",
    }
    local messages = prompt.anthropic_messages(ctx)

    assert.are.equal(1, #messages)
    assert.are.equal("user", messages[1].role)
    assert.truthy(messages[1].content:find("python style", 1, true))
    assert.truthy(messages[1].content:find("print(<cursor>)", 1, true))
  end)

  it("builds responses input text", function()
    local ctx = {
      context_before_cursor = "foo = ",
      context_after_cursor = "bar",
      user_context = "prefer short completions",
      repo_context = "File: lua/a.lua\nreturn M",
    }
    local input = prompt.response_input(ctx)

    assert.truthy(input:find("prefer short completions", 1, true))
    assert.truthy(input:find("Related project files (truncated):", 1, true))
    assert.truthy(input:find("Context before cursor:\nfoo = ", 1, true))
    assert.truthy(input:find("Context after cursor:\nbar", 1, true))
    assert.falsy(input:find("Combined:", 1, true))
  end)

  it("builds fim prompt with tokens", function()
    local ctx = {
      context_before_cursor = "foo",
      context_after_cursor = "bar",
    }
    local text = prompt.fim_prompt(ctx, {
      prefix = "<PRE>",
      suffix = "<SUF>",
      middle = "<MID>",
    })

    assert.are.equal("<PRE>foo<SUF>bar<MID>", text)
  end)
end)
