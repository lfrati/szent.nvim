if vim.g.loaded_szent_plugin then
    return
end
vim.g.loaded_szent_plugin = true

local szent = require("szent")

-- Expose minimal commands so users can reconfigure targets without reloading Neovim.
vim.api.nvim_create_user_command("SzentConfig", function()
    szent.configure()
end, {})


vim.keymap.set("x", "<Plug>(szentvisual)", function()
    szent.send_visual()
end, { desc = "szent: send selection", silent = true })

vim.keymap.set("n", "<Plug>(szentparagraph)", function()
    szent.send_paragraph()
end, { desc = "szent: send paragraph", silent = true })

vim.keymap.set("n", "<Plug>(szentcellandmove)", function()
    szent.send_cell({ move = true })
end, { desc = "szent: send cell and advance", silent = true })

vim.keymap.set("n", "<Plug>(szentcell)", function()
    szent.send_cell({ move = false })
end, { desc = "szent: send cell and remain in current cell", silent = true })

