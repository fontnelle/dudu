# PowerShell completion for dudu. Enable it in your profile:
#   Add-Content $PROFILE 'dudu completion powershell | Out-String | Invoke-Expression'

Register-ArgumentCompleter -Native -CommandName dudu, dudu.cmd -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
  $words = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
  $commands = 'backup', 'restore', 'status', 'outdated', 'secrets', 'schedule', 'config', 'doctor', 'update', 'uninstall', 'completion', '--help', '--version'
  $collectors = 'winget', 'scoop', 'choco', 'brew', 'shell', 'git', 'terminal', 'node', 'npm', 'pnpm', 'yarn', 'bun', 'python', 'ruby', 'cargo', 'go', 'vscode', 'cursor'
  $sub = @{
    backup = '--dry-run', '--only'
    status = '--dry-run', '--only'
    secrets = '--dry-run', '--only'
    restore = '--dry-run', '--only', '--from', '--file', '--yes'
    config = 'show', 'gdrive', 'set'
    schedule = 'on', 'off', 'status'
    uninstall = '--yes', '--purge'
    completion = 'zsh', 'bash', 'powershell', 'highlight'
  }
  # The word being typed is the last element when there is one; the command is the second.
  $typing = if ($wordToComplete) { 1 } else { 0 }
  $list = @()
  if ($words.Count - $typing -le 1) { $list = $commands }
  elseif ($words[$words.Count - 1 - $typing] -eq '--only') { $list = $collectors }
  elseif ($sub.ContainsKey($words[1])) { $list = $sub[$words[1]] }
  $list | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
  }
}
