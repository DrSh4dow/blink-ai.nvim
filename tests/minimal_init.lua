vim.opt.runtimepath:append(vim.fn.getcwd())

local plenary_path = vim.fn.getcwd() .. "/.tests/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:append(plenary_path)
end
