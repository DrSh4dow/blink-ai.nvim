local blink_ai = require("blink-ai")
local transform = require("blink-ai.transform")

local function make_buffer(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

describe("source integration", function()
  it("emits only the final completion callback by default", function()
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
      return #calls >= 1
    end))
    assert.are.equal(1, #calls)
    assert.are.equal(false, calls[1].is_incomplete_forward)
    assert.are.equal(1, #calls[1].items)
    assert.are.equal("󰚩", calls[1].items[1].kind_icon)
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
      completion_scope = "block",
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
      return #calls >= 1
    end))

    local final = calls[#calls]
    assert.are.equal(1, #calls)
    assert.are.equal(2, #final.items)
    assert.are.equal("if condition then", final.items[1].textEdit.newText)
    assert.truthy(final.items[2].textEdit.newText:find("\n", 1, true))
  end)

  it("returns a single same-line suggestion in line scope", function()
    blink_ai.register_provider("test_line_scope", {
      name = "test_line_scope",
      setup = function() end,
      complete = function(_, on_chunk, on_done)
        on_chunk({
          "if condition then\n  print('value')\nend",
          "fallback",
        })
        on_done()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_line_scope",
      debounce_ms = 0,
      completion_scope = "line",
      stats = { enabled = true },
      providers = {
        test_line_scope = { model = "test-model" },
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
      return #calls >= 1
    end))

    local final = calls[#calls]
    assert.are.equal(1, #final.items)
    assert.are.equal("if condition then", final.items[1].textEdit.newText)
    assert.falsy(final.items[1].textEdit.newText:find("\n", 1, true))
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

  it("clears loading placeholder on explicit source cancel", function()
    blink_ai.register_provider("test_cancel_clear", {
      name = "test_cancel_clear",
      setup = function() end,
      complete = function()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_cancel_clear",
      debounce_ms = 0,
      ui = {
        loading_placeholder = {
          enabled = true,
          watchdog_ms = 1200,
        },
      },
      stats = { enabled = true },
      providers = {
        test_cancel_clear = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "abc" })
    local calls = {}

    local cancel = source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function(result)
      table.insert(calls, result)
    end)

    assert.truthy(vim.wait(200, function()
      return #calls >= 1
    end))
    cancel()

    assert.truthy(vim.wait(200, function()
      return #calls >= 2
    end))
    assert.are.equal(true, calls[1].is_incomplete_forward)
    assert.are.equal("AI (thinking...)", calls[1].items[1].label)
    assert.are.equal(false, calls[2].is_incomplete_forward)
    assert.are.equal(0, #calls[2].items)
  end)

  it("clears loading placeholder when provider returns error", function()
    blink_ai.register_provider("test_error_clear", {
      name = "test_error_clear",
      setup = function() end,
      complete = function(_, _, _, on_error)
        vim.defer_fn(function()
          on_error({ key = "test:error", message = "boom" })
        end, 20)
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_error_clear",
      debounce_ms = 0,
      ui = {
        loading_placeholder = {
          enabled = true,
          watchdog_ms = 1200,
        },
      },
      notify_on_error = false,
      stats = { enabled = true },
      providers = {
        test_error_clear = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "abc" })
    local calls = {}

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function(result)
      table.insert(calls, result)
    end)

    assert.truthy(vim.wait(300, function()
      return #calls >= 2
    end))
    assert.are.equal(true, calls[1].is_incomplete_forward)
    assert.are.equal(false, calls[2].is_incomplete_forward)
    assert.are.equal(0, #calls[2].items)
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
        local text = result.items[1].textEdit.newText
        if text and text ~= "" then
          table.insert(seen, text)
        end
      end
    end)

    vim.wait(20)

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function(result)
      if result.items and result.items[1] and result.items[1].textEdit then
        local text = result.items[1].textEdit.newText
        if text and text ~= "" then
          table.insert(seen, text)
        end
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

  it("auto-clears loading placeholder via watchdog and suppresses late final completion", function()
    blink_ai.register_provider("test_watchdog", {
      name = "test_watchdog",
      setup = function() end,
      complete = function(_, on_chunk, on_done)
        vim.defer_fn(function()
          on_chunk({ "watchdog-final" })
          on_done()
        end, 120)
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_watchdog",
      debounce_ms = 0,
      ui = {
        loading_placeholder = {
          enabled = true,
          watchdog_ms = 30,
        },
      },
      stats = { enabled = true },
      providers = {
        test_watchdog = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "abc" })
    local calls = {}

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 3 },
      keyword = "abc",
    }, function(result)
      table.insert(calls, result)
    end)

    assert.truthy(vim.wait(500, function()
      return #calls >= 2
    end))

    assert.are.equal("AI (thinking...)", calls[1].items[1].label)
    assert.are.equal(false, calls[2].is_incomplete_forward)
    assert.are.equal(0, #calls[2].items)
    assert.are.equal(2, #calls)
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
        return #calls >= 1
      end))
      assert.are.equal(1, range_calls)
      assert.is_false(missing_fixed_range)
    end)

    transform.lsp_range_from_ctx = original_range
    transform.items_from_output = original_items

    assert.is_true(ok, tostring(err))
  end)

  it("uses the fast model for openai completion strategy", function()
    local seen_model = nil

    blink_ai.register_provider("openai", {
      name = "openai",
      setup = function() end,
      complete = function(_, on_chunk, on_done, _, runtime_cfg)
        seen_model = runtime_cfg.effective_provider_config.model
        on_chunk({ "print('ok')" })
        on_done()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "openai",
      debounce_ms = 0,
      providers = {
        openai = {
          model = "gpt-5.2-codex",
          fast_model = "gpt-5-mini",
          model_strategy = "fast_for_completion",
        },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "prin" })

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 4 },
      keyword = "prin",
    }, function() end)

    assert.truthy(vim.wait(200, function()
      return seen_model ~= nil
    end))
    assert.are.equal("gpt-5-mini", seen_model)
  end)

  it("caps max_tokens in line completion scope", function()
    local seen_max_tokens = nil

    blink_ai.register_provider("test_line_tokens", {
      name = "test_line_tokens",
      setup = function() end,
      complete = function(_, on_chunk, on_done, _, runtime_cfg)
        seen_max_tokens = runtime_cfg.max_tokens
        on_chunk({ "print('ok')" })
        on_done()
        return function() end
      end,
    })

    blink_ai.setup({
      provider = "test_line_tokens",
      debounce_ms = 0,
      completion_scope = "line",
      max_tokens = 160,
      line_max_tokens = 48,
      providers = {
        test_line_tokens = { model = "test-model" },
      },
    })

    local source = blink_ai.new({}, { timeout_ms = 1000 })
    local bufnr = make_buffer({ "prin" })

    source:get_completions({
      bufnr = bufnr,
      cursor = { 1, 4 },
      keyword = "prin",
    }, function() end)

    assert.truthy(vim.wait(200, function()
      return seen_max_tokens ~= nil
    end))
    assert.are.equal(48, seen_max_tokens)
  end)
end)
