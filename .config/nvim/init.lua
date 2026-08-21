-- Theme
vim.pack.add({
    "https://github.com/ellisonleao/gruvbox.nvim",
})

vim.o.background = "dark"
vim.cmd.colorscheme("gruvbox")

vim.g.mapleader = " "

vim.pack.add({
  "https://github.com/nvim-tree/nvim-tree.lua",
})

require("nvim-tree").setup()

vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeToggle<cr>")

vim.opt.number = true
