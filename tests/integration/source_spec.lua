local blink_ai = require("blink-ai")
local transform = require("blink-ai.transform")

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

  it("shapes streamed candidates into paired suggestions", function()
    blink_ai.register_provider("test_paired", {
      name = "test_paired",
      setup = function() end,
      complete = function(_, on_chunk, on_done)
        on_chunk({
          "if condition then",
          "if condition then\n  print('value')\nend",
          "third choice",
        })
        on_done()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_paired",
      debounce_ms = 0,
      suggestion_mode = "paired",
      stats = { enabled = true },
      providers = {
        test_paired = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "if condition" })
    local calls = {}

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 12 },
      keyword = "condition",
    }, function(result)
      table.insert(calls, result)
    end)

    assert.truthy(vim.wait(200, function()
      return #calls >= 2
    end))

    local last = calls[#calls]
    assert.are.equal(2, #last.items)
    assert.are.equal("if condition then", last.items[1].textEdit.newText)
    assert.truthy(last.items[2].textEdit.newText:find("\n", 1, true))
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

  it("coalesces rapid typing via debounce", function()
    local started = 0

    blink_ai.register_provider("test_debounce", {
      name = "test_debounce",
      setup = function() end,
      complete = function(_, on_chunk, on_done)
        started = started + 1
        on_chunk({ "debounced" })
        on_done()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_debounce",
      debounce_ms = 80,
      stats = { enabled = true },
      providers = {
        test_debounce = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "abc" })

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 1 },
      keyword = "a",
    }, function() end)
    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 2 },
      keyword = "ab",
    }, function() end)
    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function() end)

    assert.truthy(vim.wait(300, function()
      return started >= 1
    end))
    assert.are.equal(1, started)
  end)

  it("suppresses stale callbacks after cancellation", function()
    local request_id = 0
    blink_ai.register_provider("test_stale", {
      name = "test_stale",
      setup = function() end,
      complete = function(_, on_chunk, on_done)
        request_id = request_id + 1
        local current_id = request_id
        local cancelled = false

        local delay = current_id == 1 and 120 or 10
        vim.defer_fn(function()
          if cancelled then
            return
          end
          on_chunk({ "response-" .. tostring(current_id) })
          on_done()
        end, delay)

        return function()
          cancelled = true
        end
      end,
    })

    blink_ai.setup({
      provider = "test_stale",
      debounce_ms = 0,
      stats = { enabled = true },
      providers = {
        test_stale = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "abc" })
    local seen = {}

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 2 },
      keyword = "ab",
    }, function(result)
      if result.items and result.items[1] and result.items[1].textEdit then
        table.insert(seen, result.items[1].textEdit.newText)
      end
    end)

    vim.wait(20)

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function(result)
      if result.items and result.items[1] and result.items[1].textEdit then
        table.insert(seen, result.items[1].textEdit.newText)
      end
    end)

    assert.truthy(vim.wait(300, function()
      for _, text in ipairs(seen) do
        if text == "response-2" then
          return true
        end
      end
      return false
    end))

    for _, text in ipairs(seen) do
      assert.are_not.equal("response-1", text)
    end
  end)

  it("precomputes completion range once for streaming callbacks", function()
    blink_ai.register_provider("test_fixed_range", {
      name = "test_fixed_range",
      setup = function() end,
      complete = function(_, on_chunk, on_done)
        on_chunk({ "first" })
        on_chunk({ "second" })
        on_done()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_fixed_range",
      debounce_ms = 0,
      stats = { enabled = true },
      providers = {
        test_fixed_range = { model = "test-model" },
      },
    })

    local original_range = transform.lsp_range_from_ctx
    local original_items = transform.items_from_output
    local range_calls = 0
    local missing_fixed_range = false

    transform.lsp_range_from_ctx = function(ctx)
      range_calls = range_calls + 1
      return original_range(ctx)
    end
    transform.items_from_output = function(output, ctx, cfg, fixed_range)
      if fixed_range == nil then
        missing_fixed_range = true
      end
      return original_items(output, ctx, cfg, fixed_range)
    end

    local ok, err = pcall(function()
      local source = blink_ai.new({}, { timeout_ms = 1000 })
      local bufnr = make_buffer({ "prin" })
      local calls = {}

      source:get_completions({
        bufnr = bufnr,
        cursor = { 1, 4 },
        line_before_cursor = "prin",
        line_after_cursor = "",
      }, function(result)
        table.insert(calls, result)
      end)

      assert.truthy(vim.wait(200, function()
        return #calls >= 3
      end))
      assert.are.equal(1, range_calls)
      assert.is_false(missing_fixed_range)
    end)

    transform.lsp_range_from_ctx = original_range
    transform.items_from_output = original_items

    assert.is_true(ok, tostring(err))
  end)
end)
