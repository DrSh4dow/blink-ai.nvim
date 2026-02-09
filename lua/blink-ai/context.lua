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

local function path_is_file(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local stat = vim.loop.fs_stat(path)
  return stat and stat.type == "file" or false
end

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return vim.fs.normalize(path)
end

local function add_unique(list, seen, value)
  if type(value) ~= "string" or value == "" then
    return
  end
  if seen[value] then
    return
  end
  seen[value] = true
  table.insert(list, value)
end

local function add_module_specs_from_python(line, list, seen)
  local import_line = line:match("^%s*import%s+(.+)$")
  if import_line then
    for chunk in import_line:gmatch("[^,]+") do
      local module = vim.trim(chunk):match("([%w_%.]+)")
      if module then
        add_unique(list, seen, module)
      end
    end
  end

  local from_line = line:match("^%s*from%s+([%w_%.]+)%s+import%s+")
  if from_line then
    add_unique(list, seen, from_line)
  end
end

local function import_specs(filetype, lines)
  local specs = {}
  local seen = {}

  for _, line in ipairs(lines) do
    if filetype == "lua" then
      for module in line:gmatch("require%s*%(%s*['\"]([%w%._/-]+)['\"]%s*%)") do
        add_unique(specs, seen, module)
      end
      for module in line:gmatch("require%s+['\"]([%w%._/-]+)['\"]") do
        add_unique(specs, seen, module)
      end
    elseif
      filetype == "javascript"
      or filetype == "javascriptreact"
      or filetype == "typescript"
      or filetype == "typescriptreact"
      or filetype == "tsx"
      or filetype == "jsx"
    then
      for module in line:gmatch("from%s*['\"]([^'\"]+)['\"]") do
        add_unique(specs, seen, module)
      end
      for module in line:gmatch("import%s*['\"]([^'\"]+)['\"]") do
        add_unique(specs, seen, module)
      end
    elseif filetype == "python" then
      add_module_specs_from_python(line, specs, seen)
    end
  end

  return specs
end

local function add_js_candidates(base_path, list, seen)
  if base_path:match("%.[%w]+$") then
    add_unique(list, seen, base_path)
    return
  end

  local extensions = { ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".json" }
  for _, ext in ipairs(extensions) do
    add_unique(list, seen, base_path .. ext)
  end

  local indexes = {
    "index.ts",
    "index.tsx",
    "index.js",
    "index.jsx",
    "index.mjs",
    "index.cjs",
  }
  for _, name in ipairs(indexes) do
    add_unique(list, seen, base_path .. "/" .. name)
  end
end

local function resolved_candidates(filetype, specs, current_path, root, include_current_dir)
  local candidates = {}
  local seen = {}
  local current_dir = vim.fs.dirname(current_path)

  for _, spec in ipairs(specs) do
    if filetype == "lua" then
      local module = spec:gsub("%.", "/"):gsub("^/+", "")
      local bases = {
        root .. "/lua/" .. module,
        root .. "/" .. module,
      }
      if include_current_dir then
        table.insert(bases, current_dir .. "/" .. module)
      end
      for _, base in ipairs(bases) do
        add_unique(candidates, seen, base .. ".lua")
        add_unique(candidates, seen, base .. "/init.lua")
      end
    elseif
      filetype == "javascript"
      or filetype == "javascriptreact"
      or filetype == "typescript"
      or filetype == "typescriptreact"
      or filetype == "tsx"
      or filetype == "jsx"
    then
      local is_relative = spec:sub(1, 2) == "./" or spec:sub(1, 3) == "../"
      local is_rooted = spec:sub(1, 1) == "/"
      local base = nil
      if is_relative then
        base = current_dir .. "/" .. spec
      elseif is_rooted then
        base = root .. spec
      end
      if base then
        add_js_candidates(base, candidates, seen)
      end
    elseif filetype == "python" then
      if spec:sub(1, 1) ~= "." then
        local module = spec:gsub("%.", "/")
        local bases = {
          root .. "/" .. module,
        }
        if include_current_dir then
          table.insert(bases, current_dir .. "/" .. module)
        end
        for _, base in ipairs(bases) do
          add_unique(candidates, seen, base .. ".py")
          add_unique(candidates, seen, base .. "/__init__.py")
        end
      end
    end
  end

  return candidates
end

local function read_snippet(path, max_lines, max_chars)
  local file = io.open(path, "r")
  if not file then
    return nil
  end

  local lines = {}
  local used = 0
  for line in file:lines() do
    if #lines >= max_lines then
      break
    end

    local next_cost = #line + 1
    if used + next_cost > max_chars then
      local remaining = math.max(0, max_chars - used)
      if remaining > 0 then
        table.insert(lines, line:sub(1, remaining))
      end
      break
    end

    table.insert(lines, line)
    used = used + next_cost
  end

  file:close()

  if #lines == 0 then
    return nil
  end
  return table.concat(lines, "\n")
end

local function repo_context(bufnr, filetype, current_path, cfg)
  local repo_cfg = ((cfg or {}).context or {}).repo or {}
  if not repo_cfg.enabled then
    return nil
  end

  local max_files = tonumber(repo_cfg.max_files) or 3
  local max_lines = tonumber(repo_cfg.max_lines_per_file) or 80
  local max_chars_total = tonumber(repo_cfg.max_chars_total) or 6000
  local include_current_dir = repo_cfg.include_current_dir ~= false
  if max_files <= 0 or max_lines <= 0 or max_chars_total <= 0 then
    return nil
  end

  local root = vim.fs.root(
    current_path,
    { ".git", "package.json", "pyproject.toml", "stylua.toml" }
  ) or vim.fs.dirname(current_path)
  if not root or root == "" then
    return nil
  end
  root = normalize_path(root)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local scan_until = math.min(line_count, 400)
  local source_lines = vim.api.nvim_buf_get_lines(bufnr, 0, scan_until, false)
  local specs = import_specs(filetype, source_lines)
  if #specs == 0 then
    return nil
  end

  local candidates = resolved_candidates(filetype, specs, current_path, root, include_current_dir)
  if #candidates == 0 then
    return nil
  end

  local sections = {}
  local used_chars = 0
  local included_files = 0
  local seen_paths = {}
  local normalized_current = normalize_path(current_path)

  for _, raw_path in ipairs(candidates) do
    if included_files >= max_files or used_chars >= max_chars_total then
      break
    end

    local normalized = normalize_path(raw_path)
    if normalized and not seen_paths[normalized] and normalized ~= normalized_current then
      seen_paths[normalized] = true
      if path_is_file(normalized) then
        local remaining = max_chars_total - used_chars
        if remaining <= 24 then
          break
        end

        local display = normalized
        if root and normalized:sub(1, #root) == root then
          display = normalized:sub(#root + 2)
        end

        local header = "File: " .. display .. "\n"
        local content = read_snippet(normalized, max_lines, remaining - #header)
        if content and content ~= "" then
          local section = header .. content
          table.insert(sections, section)
          used_chars = used_chars + #section + 2
          included_files = included_files + 1
        end
      end
    end
  end

  if #sections == 0 then
    return nil
  end
  return table.concat(sections, "\n\n")
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

  local full_path = vim.api.nvim_buf_get_name(bufnr)
  if full_path ~= "" then
    local repo_snippets = repo_context(bufnr, result.filetype, full_path, config)
    if repo_snippets and repo_snippets ~= "" then
      result.repo_context = repo_snippets
    end
  end

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
