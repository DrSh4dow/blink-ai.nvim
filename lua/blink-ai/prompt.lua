local M = {}

local function default_system_prompt(ctx)
  local ft = ctx.filetype or "text"
  local name = ctx.filename or ""
  local parts = {
    "You are an AI code completion engine.",
    "Return only the completion text with no Markdown or explanation.",
    "The completion must fit at the <cursor> position.",
    ("Filetype: %s."):format(ft),
  }
  if name ~= "" then
    table.insert(parts, ("Filename: %s."):format(name))
  end
  if ctx.treesitter and ctx.treesitter.node_type then
    table.insert(parts, ("Current syntax node: %s."):format(ctx.treesitter.node_type))
  end
  return table.concat(parts, " ")
end

function M.system_prompt(ctx, cfg)
  if cfg and type(cfg.system_prompt) == "function" then
    return cfg.system_prompt(ctx)
  end
  if cfg and type(cfg.system_prompt) == "string" then
    return cfg.system_prompt
  end
  return default_system_prompt(ctx)
end

local function user_prompt(ctx)
  local before = ctx.context_before_cursor or ""
  local after = ctx.context_after_cursor or ""
  local sections = {
    "Complete code at <cursor>.",
  }
  if ctx.user_context and ctx.user_context ~= "" then
    table.insert(sections, "Additional project context:\n" .. ctx.user_context)
  end
  table.insert(sections, "Context before cursor:\n" .. before)
  table.insert(sections, "Context after cursor:\n" .. after)
  table.insert(sections, "Combined:\n" .. before .. "<cursor>" .. after)
  return table.concat(sections, "\n\n")
end

function M.chat_messages(ctx, cfg)
  local system = M.system_prompt(ctx, cfg)
  local user = user_prompt(ctx)
  return {
    { role = "system", content = system },
    { role = "user", content = user },
  }
end

function M.response_input(ctx)
  return user_prompt(ctx)
end

function M.anthropic_messages(ctx)
  local before = ctx.context_before_cursor or ""
  local after = ctx.context_after_cursor or ""
  local sections = {}
  if ctx.user_context and ctx.user_context ~= "" then
    table.insert(sections, "Additional project context:\n" .. ctx.user_context)
  end
  table.insert(sections, before .. "<cursor>" .. after)
  return {
    {
      role = "user",
      content = table.concat(sections, "\n\n"),
    },
  }
end

function M.fim_prompt(ctx, fim_tokens)
  local tokens = fim_tokens or { prefix = "<prefix>", suffix = "<suffix>", middle = "<middle>" }
  local before = ctx.context_before_cursor or ""
  local after = ctx.context_after_cursor or ""
  local prompt = table.concat({
    tokens.prefix,
    before,
    tokens.suffix,
    after,
    tokens.middle,
  }, "")
  if ctx.user_context and ctx.user_context ~= "" then
    return ctx.user_context .. "\n" .. prompt
  end
  return prompt
end

return M
