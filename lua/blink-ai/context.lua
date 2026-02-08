local M = {}

local function get_treesitter_scope(bufnr, line, col)
  if not vim.treesitter or not vim.treesitter.get_node then
    return nil
  end

  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { line - 1, col } })
  if not ok or not node then
    return nil
  end

  local scope = {
    node_type = node:type(),
  }

  local parent = node:parent()
  if parent then
    scope.parent_type = parent:type()
  end

  return scope
end

function M.get(ctx, cfg)
  local config = cfg or require("blink-ai.config").get()
  local bufnr = (ctx and ctx.bufnr) or vim.api.nvim_get_current_buf()
  local cursor = (ctx and ctx.cursor) or vim.api.nvim_win_get_cursor(0)
  local line = cursor[1]
  local col = cursor[2]

  local before_lines = config.context.before_cursor_lines
  local after_lines = config.context.after_cursor_lines
  local start_line = math.max(1, line - before_lines)
  local end_line = line + after_lines

  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local current_index = line - start_line + 1
  local current_line = lines[current_index] or ""

  local before_parts = {}
  for i = 1, current_index - 1 do
    table.insert(before_parts, lines[i])
  end
  local before = table.concat(before_parts, "\n")
  local current_before = current_line:sub(1, col)
  if before ~= "" then
    before = before .. "\n" .. current_before
  else
    before = current_before
  end

  local after_parts = {}
  local current_after = current_line:sub(col + 1)
  if current_after ~= "" then
    table.insert(after_parts, current_after)
  end
  for i = current_index + 1, #lines do
    table.insert(after_parts, lines[i])
  end
  local after = table.concat(after_parts, "\n")

  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename ~= "" then
    filename = vim.fn.fnamemodify(filename, ":t")
  end

  local result = {
    bufnr = bufnr,
    cursor = cursor,
    filetype = vim.bo[bufnr].filetype,
    filename = filename,
    context_before_cursor = before,
    context_after_cursor = after,
  }

  if config.context.enable_treesitter then
    result.treesitter = get_treesitter_scope(bufnr, line, col)
  end

  if type(config.context.user_context) == "function" then
    local ok, user_context = pcall(config.context.user_context, result)
    if ok and type(user_context) == "string" and user_context ~= "" then
      result.user_context = user_context
    end
  end

  return result
end

return M
