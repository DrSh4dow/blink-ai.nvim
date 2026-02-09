local function with_provider(module_name, fake_stream, run)
  local original_request = package.loaded["blink-ai.request"]
  local original_provider = package.loaded[module_name]

  package.loaded["blink-ai.request"] = { stream = fake_stream }
  package.loaded[module_name] = nil

  local provider = require(module_name)
  local ok, err = pcall(run, provider)

  package.loaded[module_name] = original_provider
  package.loaded["blink-ai.request"] = original_request

  if not ok then
    error(err)
  end
end

local function base_ctx()
  return {
    filetype = "lua",
    filename = "test.lua",
    context_before_cursor = "local value = ",
    context_after_cursor = "\nprint(value)",
  }
end

local function with_env(values, run)
  local previous = {}
  for name, value in pairs(values) do
    previous[name] = vim.fn.getenv(name)
    if value == nil then
      vim.fn.setenv(name, vim.NIL)
    else
      vim.fn.setenv(name, value)
    end
  end

  local ok, err = pcall(run)

  for name, value in pairs(previous) do
    if value == vim.NIL then
      vim.fn.setenv(name, vim.NIL)
    else
      vim.fn.setenv(name, value)
    end
  end

  if not ok then
    error(err)
  end
end

describe("providers", function()
  it("openai parses Responses API streaming chunks and request payload", function()
    with_provider("blink-ai.providers.openai", function(opts)
      assert.are.equal("POST", opts.method)
      assert.are.equal("sse", opts.stream_mode)
      local decoded = vim.json.decode(opts.body)
      assert.are.equal("gpt-test", decoded.model)
      assert.are.equal(true, decoded.stream)
      assert.are.equal(32, decoded.max_output_tokens)
      assert.are.equal("string", type(decoded.instructions))
      assert.are.equal("string", type(decoded.input))
      assert.is_nil(decoded.temperature)
      assert.is_nil(decoded.messages)
      assert.is_nil(decoded.max_tokens)
      assert.is_nil(decoded.n)
      opts.on_chunk(vim.json.encode({
        type = "response.output_text.delta",
        delta = "hel",
      }))
      opts.on_chunk(vim.json.encode({
        type = "response.output_text.delta",
        delta = "lo",
      }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        api_key = "test-openai-key",
        model = "gpt-test",
        endpoint = "https://example.invalid/openai",
      })

      local latest = {}
      local done = false
      local err = nil
      provider.complete(base_ctx(), function(chunk)
        latest = vim.deepcopy(chunk)
      end, function()
        done = true
      end, function(e)
        err = e
      end, {
        max_tokens = 32,
        n_completions = 1,
        timeout_ms = 5000,
        effective_provider = "openai",
        effective_provider_config = {
          api_key = "test-openai-key",
          model = "gpt-test",
          endpoint = "https://example.invalid/openai",
        },
      })

      assert.is_nil(err)
      assert.are.equal(true, done)
      assert.are.same({ "hello" }, latest)
    end)
  end)

  it("openai includes temperature only when explicitly configured", function()
    with_provider("blink-ai.providers.openai", function(opts)
      local decoded = vim.json.decode(opts.body)
      assert.are.equal(0.25, decoded.temperature)
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        api_key = "test-openai-key",
        model = "gpt-test",
        endpoint = "https://example.invalid/openai",
        temperature = 0.25,
      })

      provider.complete(base_ctx(), function() end, function() end, function()
        error("unexpected error callback")
      end, {
        max_tokens = 32,
        timeout_ms = 5000,
        effective_provider = "openai",
        effective_provider_config = {
          api_key = "test-openai-key",
          model = "gpt-test",
          endpoint = "https://example.invalid/openai",
          temperature = 0.25,
        },
      })
    end)
  end)

  it("openai sets completion-safe defaults for gpt-5 models", function()
    with_provider("blink-ai.providers.openai", function(opts)
      local decoded = vim.json.decode(opts.body)
      assert.are.equal("gpt-5-mini", decoded.model)
      assert.are.same({ effort = "minimal" }, decoded.reasoning)
      assert.are.same({ verbosity = "low" }, decoded.text)
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        api_key = "test-openai-key",
        model = "gpt-5-mini",
        endpoint = "https://example.invalid/openai",
      })

      provider.complete(base_ctx(), function() end, function() end, function()
        error("unexpected error callback")
      end, {
        max_tokens = 96,
        timeout_ms = 5000,
        effective_provider = "openai",
        effective_provider_config = {
          api_key = "test-openai-key",
          model = "gpt-5-mini",
          endpoint = "https://example.invalid/openai",
        },
      })
    end)
  end)

  it("openai falls back to OPENAI_API_KEY when BLINK key is unset", function()
    with_provider("blink-ai.providers.openai", function(opts)
      assert.are.equal("Bearer openai-env-key", opts.headers.Authorization)
      opts.on_done()
      return function() end
    end, function(provider)
      with_env({
        BLINK_OPENAI_API_KEY = nil,
        OPENAI_API_KEY = "openai-env-key",
      }, function()
        provider.setup({
          model = "gpt-test",
          endpoint = "https://example.invalid/openai",
        })

        provider.complete(base_ctx(), function() end, function() end, function()
          error("unexpected error callback")
        end, {
          max_tokens = 32,
          timeout_ms = 5000,
          effective_provider = "openai",
          effective_provider_config = {
            model = "gpt-test",
            endpoint = "https://example.invalid/openai",
          },
        })
      end)
    end)
  end)

  it("openai falls back to completed response output when no deltas stream", function()
    with_provider("blink-ai.providers.openai", function(opts)
      opts.on_chunk(vim.json.encode({
        type = "response.completed",
        response = {
          output = {
            {
              type = "message",
              content = {
                { type = "output_text", text = "print(value)" },
              },
            },
          },
        },
      }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        api_key = "test-openai-key",
        model = "gpt-test",
        endpoint = "https://example.invalid/openai",
      })

      local latest = {}
      provider.complete(base_ctx(), function(chunk)
        latest = vim.deepcopy(chunk)
      end, function() end, function()
        error("unexpected error callback")
      end, {
        max_tokens = 32,
        timeout_ms = 5000,
        effective_provider = "openai",
        effective_provider_config = {
          api_key = "test-openai-key",
          model = "gpt-test",
          endpoint = "https://example.invalid/openai",
        },
      })

      assert.are.same({ "print(value)" }, latest)
    end)
  end)

  it("openai propagates streamed API errors", function()
    with_provider("blink-ai.providers.openai", function(opts)
      opts.on_chunk(vim.json.encode({
        type = "response.error",
        message = "quota exceeded",
      }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        api_key = "test-openai-key",
        endpoint = "https://example.invalid/openai",
      })

      local err_message
      provider.complete(base_ctx(), function() end, function() end, function(err)
        err_message = err.message
      end, {
        max_tokens = 32,
        timeout_ms = 5000,
        effective_provider = "openai",
        effective_provider_config = {
          api_key = "test-openai-key",
          endpoint = "https://example.invalid/openai",
        },
      })

      assert.are.equal("quota exceeded", err_message)
    end)
  end)

  it("anthropic reads delta text and completion fallback", function()
    with_provider("blink-ai.providers.anthropic", function(opts)
      assert.are.equal("sse", opts.stream_mode)
      opts.on_chunk(vim.json.encode({
        type = "content_block_delta",
        delta = { text = "abc" },
      }))
      opts.on_chunk(vim.json.encode({ completion = "def" }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        api_key = "test-anthropic-key",
        endpoint = "https://example.invalid/anthropic",
      })

      local latest = {}
      provider.complete(base_ctx(), function(chunk)
        latest = vim.deepcopy(chunk)
      end, function() end, function()
        error("unexpected error callback")
      end, {
        max_tokens = 32,
        n_completions = 1,
        timeout_ms = 5000,
        effective_provider = "anthropic",
        effective_provider_config = {
          api_key = "test-anthropic-key",
          endpoint = "https://example.invalid/anthropic",
        },
      })

      assert.are.same({ "abcdef" }, latest)
    end)
  end)

  it("anthropic propagates structured API errors", function()
    with_provider("blink-ai.providers.anthropic", function(opts)
      opts.on_chunk(vim.json.encode({
        type = "error",
        error = { message = "quota exceeded" },
      }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        api_key = "test-anthropic-key",
        endpoint = "https://example.invalid/anthropic",
      })

      local err_message
      provider.complete(base_ctx(), function() end, function() end, function(err)
        err_message = err.message
      end, {
        max_tokens = 32,
        n_completions = 1,
        timeout_ms = 5000,
        effective_provider = "anthropic",
        effective_provider_config = {
          api_key = "test-anthropic-key",
          endpoint = "https://example.invalid/anthropic",
        },
      })

      assert.are.equal("quota exceeded", err_message)
    end)
  end)

  it("anthropic falls back to ANTHROPIC_API_KEY when BLINK key is unset", function()
    with_provider("blink-ai.providers.anthropic", function(opts)
      assert.are.equal("anthropic-env-key", opts.headers["x-api-key"])
      opts.on_done()
      return function() end
    end, function(provider)
      with_env({
        BLINK_ANTHROPIC_API_KEY = nil,
        ANTHROPIC_API_KEY = "anthropic-env-key",
      }, function()
        provider.setup({
          endpoint = "https://example.invalid/anthropic",
        })

        provider.complete(base_ctx(), function() end, function() end, function()
          error("unexpected error callback")
        end, {
          max_tokens = 32,
          timeout_ms = 5000,
          effective_provider = "anthropic",
          effective_provider_config = {
            endpoint = "https://example.invalid/anthropic",
          },
        })
      end)
    end)
  end)

  it("openai-compatible requires endpoint", function()
    with_provider("blink-ai.providers.openai_compatible", function()
      error("request.stream should not be called when endpoint is missing")
    end, function(provider)
      provider.setup({})

      local message
      local done = false
      provider.complete(base_ctx(), function() end, function()
        done = true
      end, function(err)
        message = err.message
      end, {
        max_tokens = 32,
        n_completions = 1,
        timeout_ms = 5000,
        effective_provider = "openai_compatible",
        effective_provider_config = {},
      })

      assert.are.equal(true, done)
      assert.truthy(message:find("endpoint is required", 1, true))
    end)
  end)

  it("openai-compatible parses streamed choices and uses auth header", function()
    with_provider("blink-ai.providers.openai_compatible", function(opts)
      assert.are.equal("Bearer compat-key", opts.headers.Authorization)
      opts.on_chunk(vim.json.encode({
        choices = {
          { index = 0, delta = { content = "abc" } },
          { index = 1, message = { content = "xyz" } },
        },
      }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        endpoint = "https://example.invalid/openai-compatible",
        api_key = "compat-key",
      })

      local latest = {}
      provider.complete(base_ctx(), function(chunk)
        latest = vim.deepcopy(chunk)
      end, function() end, function()
        error("unexpected error callback")
      end, {
        max_tokens = 32,
        n_completions = 2,
        timeout_ms = 5000,
        effective_provider = "openai_compatible",
        effective_provider_config = {
          endpoint = "https://example.invalid/openai-compatible",
          api_key = "compat-key",
        },
      })

      assert.are.same({ "abc", "xyz" }, latest)
    end)
  end)

  it("openai-compatible uses GEMINI_API_KEY for google openai endpoints", function()
    with_provider("blink-ai.providers.openai_compatible", function(opts)
      assert.are.equal("Bearer gemini-env-key", opts.headers.Authorization)
      opts.on_done()
      return function() end
    end, function(provider)
      with_env({
        BLINK_OPENAI_COMPATIBLE_API_KEY = nil,
        OPENAI_COMPATIBLE_API_KEY = nil,
        GEMINI_API_KEY = "gemini-env-key",
      }, function()
        provider.setup({
          endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
          model = "gemini-2.5-flash",
        })

        provider.complete(base_ctx(), function() end, function() end, function()
          error("unexpected error callback")
        end, {
          max_tokens = 32,
          timeout_ms = 5000,
          n_completions = 1,
          effective_provider = "openai_compatible",
          effective_provider_config = {
            endpoint = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
            model = "gemini-2.5-flash",
          },
        })
      end)
    end)
  end)

  it("ollama /api/generate uses FIM-style prompt field", function()
    with_provider("blink-ai.providers.ollama", function(opts)
      local decoded = vim.json.decode(opts.body)
      assert.truthy(decoded.prompt:find("<cursor>", 1, true))
      assert.is_nil(decoded.messages)
      opts.on_chunk(vim.json.encode({ response = "result" }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        endpoint = "http://localhost:11434/api/generate",
        model = "qwen2.5-coder:7b",
      })

      local latest = {}
      provider.complete(base_ctx(), function(chunk)
        latest = vim.deepcopy(chunk)
      end, function() end, function()
        error("unexpected error callback")
      end, {
        max_tokens = 32,
        n_completions = 1,
        timeout_ms = 5000,
        effective_provider = "ollama",
        effective_provider_config = {
          endpoint = "http://localhost:11434/api/generate",
          model = "qwen2.5-coder:7b",
        },
      })
      assert.are.same({ "result" }, latest)
    end)
  end)

  it("fim requires endpoint and parses choices", function()
    with_provider("blink-ai.providers.fim", function()
      error("request.stream should not be called when endpoint is missing")
    end, function(provider)
      provider.setup({})
      local message
      provider.complete(base_ctx(), function() end, function() end, function(err)
        message = err.message
      end, {
        max_tokens = 32,
        n_completions = 1,
        timeout_ms = 5000,
        effective_provider = "fim",
        effective_provider_config = {},
      })
      assert.truthy(message:find("endpoint is required", 1, true))
    end)

    with_provider("blink-ai.providers.fim", function(opts)
      opts.on_chunk(vim.json.encode({
        choices = {
          { index = 0, text = "chunk" },
          { index = 1, delta = { content = "other" } },
        },
      }))
      opts.on_done()
      return function() end
    end, function(provider)
      provider.setup({
        endpoint = "https://example.invalid/fim",
      })
      local latest = {}
      provider.complete(base_ctx(), function(chunk)
        latest = vim.deepcopy(chunk)
      end, function() end, function()
        error("unexpected error callback")
      end, {
        max_tokens = 32,
        n_completions = 2,
        timeout_ms = 5000,
        effective_provider = "fim",
        effective_provider_config = {
          endpoint = "https://example.invalid/fim",
        },
      })
      assert.are.same({ "chunk", "other" }, latest)
    end)
  end)
end)
