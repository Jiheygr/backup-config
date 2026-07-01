return {
  "RRethy/base16-nvim",
  lazy = false,
  priority = 1000,
  config = function()
    local ok, matugen = pcall(require, "matugen")
    if ok then
      matugen.setup()
    else
      -- Fallback si matugen no está disponible
      vim.cmd("colorscheme base16-0x96f")
    end
  end,
}
