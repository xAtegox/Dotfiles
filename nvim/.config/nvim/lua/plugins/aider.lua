return {
  "GeorgesAlkhouri/nvim-aider",
  event = "VeryLazy",
  opts = {
    cmd = {
      "AiderTerminalToggle",
      "AiderHealth",
    },
    -- General keys moved to lua/config/keymaps.lua
    dependencies = {
      "folke/snacks.nvim",
      --- The below dependencies are optional
      "nvim-tree/nvim-tree.lua",
      --- Neo-tree integration
      {
        "nvim-neo-tree/neo-tree.nvim",
        opts = function(_, opts)
          --   }
          require("nvim_aider.neo_tree").setup(opts)
        end,
      },
    },
  },
}
