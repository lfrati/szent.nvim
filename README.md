<p align="center">
<img width="300" height="300" alt="szent_round_400" src="https://github.com/user-attachments/assets/389f58cb-4c23-4ebc-86d0-295c22875252" />
  <p align="center">/sɛnt/ : holy [hu], past of send [en]</p>
<p>

# szent.nvim 
<code style="color:red">text</code>
A tiny Neovim bridge that sends code from your current buffer to a tmux REPL using safe bracketed paste.

<img width="920" height="305" alt="szent_example" src="https://github.com/user-attachments/assets/6606f689-1663-4d85-8e3b-88caf2930f32" />

## Features
- Target any tmux pane and paste via `load-buffer`/`paste-buffer -p`.
- Send from visual selection, paragraph or cell.
- Highlights the szent code (shoutout `vim.hl.range` for including a timeout)
- Checks that the target pane runs a known REPL command before sending.

## Requirements
- Neovim 0.10 or newer.
- A running tmux session with bracketed paste enabled.

## Installation
Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "lfrati/szent.nvim",
  config = function()
      local szent = require("szent")
      
      szent.setup {
        repl_commands = { "python", "ipython", "uv" },
      }
      -- keybindings are not set by default ♻️
      vim.keymap.set("x", "<leader><leader>p", "<Plug>(SzentVisual)")
      vim.keymap.set("n", "<leader><leader>p", "<Plug>(SzentParagraph)")
      vim.keymap.set("n", "<leader><leader>r", "<Plug>(SzentCellAndMove)")

  end
}
```

## Usage
- `:SzentConfig` prompts for a tmux pane to send text to (in case you changed your mind about `:.2`).
<img width="450" height="103" alt="image" src="https://github.com/user-attachments/assets/72ba1f6d-e291-4e05-bfe5-651608e4e2ea" />


- `send_visual()`, try to guess.
- `send_paragraph()`, another cryptic one.
- `send_cell({move = true})` sends the current delimited cell (defaults to `# %%`), and then moves the cursor to the next cell.
- `send_cell({move = false})` sends the current delimited cell (defaults to `# %%`), and then... nothing.

| Szent succesfully  | Error while szending |
| ------------- | ------------- |
| <img width="320" height="167" alt="success" src="https://github.com/user-attachments/assets/1817968e-5ce2-4c4a-85cf-fd9e9fa87a40" />  | <img width="319" height="171" alt="error" src="https://github.com/user-attachments/assets/e2dbf5d1-d497-4f83-99d7-512cfa7cda6e" />  |
| Code sent succesfully is highlighted with `Visual` | <pre> `Target tmux pane :.2 is running 'zsh'.` <br> &emsp; `Expected one of: python, ipython` </pre>|


Tip: use text objects for the cell content:
```lua
vim.keymap.set({"o","x"}, "ic", ":<C-u>lua require('szent').select_cell_inner()<CR>", { silent = true, desc = "inside cell" })
vim.keymap.set({"o","x"}, "ac", ":<C-u>lua require('szent').select_cell_around()<CR>", { silent = true, desc = "around cell" })
```


## Configuration
All options are optional (duh.) and are merged with the defaults below:

```lua
require("szent").setup({
  target_pane = ":.2",                     -- tmux pane target default (session:window.pane)
  cell_delimiter = [[^\s*#\s*%%]],         -- pattern that marks cell boundaries
  repl_commands = {},                      -- optional commands to assert before sending
  timeout = 200,                           -- highlight timeout in milliseconds
})
```

Customize the popup picker colors with the exposed namespace:
```
'SzentCmd'    : color pane command
'SzentActive' : color for the * marking the active pane
'FloatBorder' : color for the popup border
'FloatTitle'  : color for the popup title
'Normal'      : base text color in the popup
```
defining your own colors as follows:
```lua
local ns = require("szent").ui_namespace()
vim.api.nvim_set_hl(ns.popup, "FloatBorder", { fg = "#00ff00" })
```

## Thanks
- [slime](https://slime.common-lisp.dev/)
- [vim-slime](https://github.com/jpalardy/vim-slime)
