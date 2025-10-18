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
      vim.keymap.set("x", "<leader><leader>p", szent.send_visual, { desc = "szent: send selection", silent = true })
      vim.keymap.set("n", "<leader><leader>p", szent.send_paragraph, { desc = "szent: send paragraph", silent = true })
      vim.keymap.set("n", "<leader><leader>r", szent.send_cell, { desc = "szent: send cell and advance", silent = true })
  end
}
```

## Usage
- `:SzentConfig` prompts for a tmux pane to send text to (in case you changed your mind about `:.2`).
<img width="463" height="108" alt="szent_select" src="https://github.com/user-attachments/assets/e68618db-917a-48aa-9d15-3dd945993f85" />

- `send_visual()`, try to guess.
- `send_paragraph()`, another cryptic one.
- `send_cell()` sends the current delimited cell (defaults to `# %%`), and moves the cursor to the next cell.

Tip: use a text object for the cell content:
`vim.keymap.set({"o","x"}, "ic", ":<C-u>lua require('szent').select_cell_inner()<CR>", { silent = true, desc = "inside cell" })` 


## Configuration
All options are optional (duh.) and are merged with the defaults below:

```lua
require("szent").setup({
  target_pane = ":.2",                     -- tmux pane target default (session:window.pane)
  move_to_next_cell = true,                -- jump to the next cell after sending
  cell_delimiter = [[^\s*#\s*%%]],         -- pattern that marks cell boundaries
  repl_commands = {},                      -- optional commands to assert before sending
  timeout = 200,                           -- highlight timeout in milliseconds
})
```

## Thanks
- [slime](https://slime.common-lisp.dev/)
- [vim-slime](https://github.com/jpalardy/vim-slime)
