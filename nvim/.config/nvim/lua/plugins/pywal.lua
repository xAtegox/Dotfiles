return {
  "RedsXDD/neopywal.nvim",
  lazy = false,
  priority = 1000,
  config = function()
    vim.o.background = "dark"
    vim.cmd.colorscheme("neopywal-dark")
  end,
}
