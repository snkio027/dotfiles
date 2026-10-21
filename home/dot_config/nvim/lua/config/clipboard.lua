local M = {}

function M.setup()
  -- Native providers remain responsible for macOS, Linux desktops and SSH.
  -- Never replace a user-selected provider or use a remote WSL host's clipboard.
  if
    vim.fn.has("wsl") ~= 1
    or vim.g.clipboard ~= nil
    or (vim.env.SSH_CONNECTION or "") ~= ""
    or (vim.env.SSH_TTY or "") ~= ""
  then
    return
  end

  local name, copy, paste
  if vim.fn.executable("win32yank.exe") == 1 then
    -- WSL interop needs the Windows executable, not a Linux symlink to it.
    local executable = vim.fn.resolve(vim.fn.exepath("win32yank.exe"))
    name = "win32yank (WSL)"
    copy = { executable, "-i", "--crlf" }
    paste = { executable, "-o", "--lf" }
  elseif vim.fn.executable("powershell.exe") == 1 then
    -- Windows PowerShell is an existing OS component, not a new dependency.
    -- Pass clipboard data on stdin, never interpolate it into PowerShell code.
    local command = { "powershell.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-STA", "-Command" }
    name = "Windows PowerShell (WSL)"
    copy = vim.list_extend(vim.deepcopy(command), {
      [[$ErrorActionPreference='Stop'; [Console]::InputEncoding=[Text.UTF8Encoding]::new($false); Set-Clipboard -Value ([Console]::In.ReadToEnd())]],
    })
    paste = vim.list_extend(vim.deepcopy(command), {
      [[$ErrorActionPreference='Stop'; [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::Write(((Get-Clipboard -Raw) -replace "`r`n", "`n"))]],
    })
  else
    -- Interop may be disabled, or the Windows PATH deliberately omitted.
    -- Keep native WSLg/terminal detection; do not install or guess a C: path.
    return
  end

  vim.g.clipboard = {
    name = name,
    copy = { ["+"] = copy, ["*"] = copy },
    paste = { ["+"] = paste, ["*"] = paste },
    cache_enabled = 0,
  }
end

return M
