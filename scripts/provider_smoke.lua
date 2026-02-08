package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local config = require("blink-ai.config")

config.setup({
  max_tokens = 32,
  n_completions = 1,
})

local function smoke_provider(name, module_name, provider_opts)
  local provider = require(module_name)
  provider.setup(provider_opts)

  local done = false
  local streamed = false
  local err = nil

  local cancel = provider.complete({
    filetype = "lua",
    filename = "smoke.lua",
    context_before_cursor = "local function add(a, b)\n  return ",
    context_after_cursor = "\nend\n",
  }, function(chunk)
    if type(chunk) == "table" and next(chunk) ~= nil then
      streamed = true
    end
  end, function()
    done = true
  end, function(e)
    if type(e) == "table" then
      err = e.message or vim.inspect(e)
    else
      err = tostring(e)
    end
    done = true
  end, {
    max_tokens = 32,
    n_completions = 1,
    timeout_ms = 15000,
    effective_provider = name,
    effective_provider_config = provider_opts,
  })

  vim.wait(20000, function()
    return done
  end, 50)

  if not done then
    if type(cancel) == "function" then
      cancel()
    end
    return false, "timeout waiting for completion"
  end
  if err then
    return false, err
  end
  if not streamed then
    return false, "request finished but no streamed chunks received"
  end
  return true, "ok"
end

local checks = {
  {
    env = "BLINK_OPENAI_API_KEY",
    name = "openai",
    module = "blink-ai.providers.openai",
    opts = config.get().providers.openai,
  },
  {
    env = "BLINK_ANTHROPIC_API_KEY",
    name = "anthropic",
    module = "blink-ai.providers.anthropic",
    opts = config.get().providers.anthropic,
  },
}

local failures = {}
for _, check in ipairs(checks) do
  if (os.getenv(check.env) or "") == "" then
    print(string.format("%s: SKIP (%s missing)", check.name, check.env))
  else
    local ok, msg = smoke_provider(check.name, check.module, check.opts)
    if ok then
      print(string.format("%s: PASS (%s)", check.name, msg))
    else
      print(string.format("%s: FAIL (%s)", check.name, msg))
      table.insert(failures, check.name .. ": " .. msg)
    end
  end
end

assert(#failures == 0, table.concat(failures, "\n"))
