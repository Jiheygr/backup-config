return {
  "nickjvandyke/opencode.nvim",
  version = "*",
  dependencies = {
    { "folke/snacks.nvim", optional = true },
  },
  config = function()
    vim.o.autoread = true
  end,
}
