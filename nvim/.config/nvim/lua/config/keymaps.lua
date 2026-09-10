-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("n", "gf", function()
  if require("obsidian").util.cursor_on_markdown_link() then
    return "<cmd>ObsidianFollowLink<CR>"
  else
    return "gf"
  end
end, { noremap = false, expr = true })
vim.keymap.set("n", "Zu", "<Cmd>ZenMode<CR>", { silent = true })

vim.keymap.set("i", "<Tab>", function()
  if require("copilot.suggestion").is_visible() then
    require("copilot.suggestion").accept()
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Tab>", true, false, true), "n", false)
  end
end, {
  silent = true,
})

-- Aider keymaps
vim.keymap.set("n", "<leader>a/", "<cmd>AiderTerminalToggle<cr>", { desc = "Aider: Toggle Terminal" })
vim.keymap.set({ "n", "v" }, "<leader>as", "<cmd>AiderTerminalSend<cr>", { desc = "Aider: Send Selection/Line" })
vim.keymap.set("n", "<leader>ac", "<cmd>AiderQuickSendCommand<cr>", { desc = "Aider: Quick Send Command" })
vim.keymap.set("n", "<leader>ab", "<cmd>AiderQuickSendBuffer<cr>", { desc = "Aider: Quick Send Buffer" })
vim.keymap.set("n", "<leader>a+", "<cmd>AiderQuickAddFile<cr>", { desc = "Aider: Quick Add File" })
vim.keymap.set("n", "<leader>a-", "<cmd>AiderQuickDropFile<cr>", { desc = "Aider: Quick Drop File" })
vim.keymap.set("n", "<leader>ar", "<cmd>AiderQuickReadOnlyFile<cr>", { desc = "Aider: Quick Add File Read-Only" })

-- Go to normal mode from terminal with double escape
vim.keymap.set("t", "<Esc><Esc>", "<C-\\><C-n>", { noremap = true })
