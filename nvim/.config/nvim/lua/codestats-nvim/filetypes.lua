local M = {}

-- Using a set for faster lookups
local ignored_filetypes_set = {
  ["dap-repl"] = true,
  ["dapui_watches"] = true,
  ["dapui_stacks"] = true,
  ["dapui_breakpoints"] = true,
  ["dapui_scopes"] = true,
  ["dapui_console"] = true,
  ["qf"] = true,
  ["help"] = true,
  ["startify"] = true,
  ["TelescopePrompt"] = true,
  ["NvimTree"] = true,
  ["neo-tree"] = true,
  ["neo-tree-popup"] = true,
  ["snacks_dashboard"] = true,
  ["snacks_terminal"] = true,
  ["minifiles"] = true,
  ["lazy"] = true,
  ["AvanteInput"] = true,
  ["Avante"] = true,
  ["AvanteSelectedFiles"] = true,
  ["tsplayground"] = true,
  ["lspinfo"] = true,
}

function M.is_filetype_ignored(filetype)
  if not filetype or filetype == "" then
    return true -- Ignore empty or nil filetypes
  end
  return ignored_filetypes_set[filetype] == true
end

-- This function maps Neovim filetypes to language names that CodeStats expects.
-- You might need to expand this list or adjust the names based on CodeStats' requirements.
function M.get_language(filetype)
  local lang_map = {
    lua = "Lua",
    python = "Python",
    rust = "Rust",
    javascript = "JavaScript",
    typescript = "TypeScript",
    html = "HTML",
    css = "CSS",
    go = "Go",
    c = "C",
    cpp = "C++",
    java = "Java",
    -- Add more mappings here as needed
  }
  return lang_map[filetype] or filetype -- Return mapped name or original filetype if not found
end

return M
