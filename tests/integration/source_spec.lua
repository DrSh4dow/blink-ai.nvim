local blink_ai = require("blink-ai")

local function make_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

describe("source integration", function()
  it("streams incremental and final completion callbacks", function()
    blink_ai.register_provider("test_stream", {
      name = "test_stream",
      setup = function() end,
      complete = function(_, on_chunk, on_done)
        on_chunk({ "print('hello')" })
        on_done()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_stream",
      debounce_ms = 0,
      stats = { enabled = true },
      providers = {
        test_stream = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "prin" })
    local calls = {}

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 4 },
      keyword = "prin",
    }, function(result)
      table.insert(calls, result)
    end)

    assert.truthy(vim.wait(200, function()
      return #calls >= 2
    end))
    assert.are.equal(true, calls[1].is_incomplete_forward)
    assert.are.equal(false, calls[#calls].is_incomplete_forward)
    assert.are.equal(1, #calls[#calls].items)
  end)

  it("cancels in-flight requests when superseded", function()
    local started = 0
    local cancel_count = 0

    blink_ai.register_provider("test_cancel", {
      name = "test_cancel",
      setup = function() end,
      complete = function()
        started = started + 1
        return function()
          cancel_count = cancel_count + 1
        end
      end,
    })

    blink_ai.setup({
      provider = "test_cancel",
      debounce_ms = 0,
      stats = { enabled = true },
      providers = {
        test_cancel = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "abc" })

    local cancel_second = source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function() end)

    assert.truthy(vim.wait(200, function()
      return started >= 1
    end))

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function() end)

    assert.truthy(vim.wait(200, function()
      return cancel_count >= 1
    end))

    cancel_second()
  end)
end)
