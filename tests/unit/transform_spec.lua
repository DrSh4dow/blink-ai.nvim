local transform = require("blink-ai.transform")

describe("transform.items_from_output", function()
  it("maps streamed outputs to completion items", function()
    local items = transform.items_from_output({ "one", "two" }, {
      cursor = { 1, 3 },
      keyword = "abc",
    }, {
      effective_provider = "openai",
    })

    assert.are.equal(2, #items)
    assert.are.equal("one", items[1].label)
    assert.are.equal("two", items[2].label)
    assert.are.equal("blink-ai", items[1].data.source)
    assert.are.equal("openai", items[1].data.provider)
    assert.are.equal(0, items[1].textEdit.range.start.line)
    assert.are.equal(0, items[1].textEdit.range.start.character)
    assert.are.equal(3, items[1].textEdit.range["end"].character)
  end)

  it("applies transform_items hook when provided", function()
    local items = transform.items_from_output("one", { cursor = { 1, 1 } }, {
      transform_items = function(current_items)
        current_items[1].label = "custom"
        return current_items
      end,
    })

    assert.are.equal(1, #items)
    assert.are.equal("custom", items[1].label)
  end)

  it("derives keyword start without Vimscript regex calls", function()
    local original_matchstrpos = vim.fn.matchstrpos
    vim.fn.matchstrpos = function()
      error("matchstrpos should not be called")
    end

    local ok, items_or_err = pcall(function()
      return transform.items_from_output("hello", {
        cursor = { 1, 5 },
        line_before_cursor = "print",
        line_after_cursor = "",
      }, {})
    end)

    vim.fn.matchstrpos = original_matchstrpos

    assert.is_true(ok, tostring(items_or_err))
    assert.are.equal(1, #items_or_err)
    assert.are.equal(0, items_or_err[1].textEdit.range.start.character)
    assert.are.equal(5, items_or_err[1].textEdit.range["end"].character)
  end)

  it("supports a fixed textEdit range for streaming updates", function()
    local range = {
      start = { line = 0, character = 2 },
      ["end"] = { line = 0, character = 6 },
    }
    local items = transform.items_from_output({ "one", "two" }, nil, {}, range)

    assert.are.equal(2, #items)
    assert.are.equal(2, items[1].textEdit.range.start.character)
    assert.are.equal(6, items[1].textEdit.range["end"].character)
    assert.are.equal(2, items[2].textEdit.range.start.character)
    assert.are.equal(6, items[2].textEdit.range["end"].character)
  end)
end)
