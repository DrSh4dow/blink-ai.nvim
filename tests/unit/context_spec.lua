local context = require("blink-ai.context")

describe("context.get", function()
  it("extracts before/after context and user hook output", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "local foo = 1",
      "return foo",
    })

    local result = context.get({
      bufnr = bufnr,
      cursor = { 2, 6 },
    }, {
      context = {
        before_cursor_lines = 5,
        after_cursor_lines = 5,
        enable_treesitter = false,
        user_context = function()
          return "test-hook"
        end,
      },
    })

    assert.truthy(result.context_before_cursor:find("local foo = 1", 1, true))
    assert.truthy(result.context_before_cursor:find("return", 1, true))
    assert.are.equal(" foo", result.context_after_cursor)
    assert.are.equal("test-hook", result.user_context)
  end)

  it("collects import-aware repo context snippets", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/.git", "p")
    vim.fn.mkdir(root .. "/lua/foo", "p")
    vim.fn.writefile({ "return { value = 42 }" }, root .. "/lua/foo/bar.lua")

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_name(bufnr, root .. "/lua/main.lua")
    vim.bo[bufnr].filetype = "lua"
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "local mod = require(\"foo.bar\")",
      "return mod.value",
    })

    local result = context.get({
      bufnr = bufnr,
      cursor = { 2, 6 },
    }, {
      context = {
        before_cursor_lines = 5,
        after_cursor_lines = 5,
        enable_treesitter = false,
        repo = {
          enabled = true,
          max_files = 2,
          max_lines_per_file = 20,
          max_chars_total = 1000,
          include_current_dir = true,
        },
      },
    })

    assert.truthy(result.repo_context)
    assert.truthy(result.repo_context:find("File: lua/foo/bar.lua", 1, true))
    assert.truthy(result.repo_context:find("value = 42", 1, true))
  end)
end)
