return {
  "saghen/blink.cmp",
  event = "InsertEnter",
  lazy = true,
  dependencies = {
    "MeanderingProgrammer/render-markdown.nvim",
    "hrsh7th/nvim-cmp", -- Ensure nvim-cmp is loaded as a dependency
    "Kaiser-Yang/blink-cmp-avante",
  },
  opts = {
    sources = {
      default = { "lsp", "path", "snippets", "buffer", "markdown" },
      providers = {
        markdown = {
          name = "RenderMarkdown",
          module = "render-markdown.integ.blink",
          fallbacks = { "lsp" },
        },

        avante = {
          module = "blink-cmp-avante",
          name = "Avante",
        },
      },
    },
  },
}
