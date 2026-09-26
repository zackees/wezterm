# Replays clud's Kitty smoke against a locally built wezterm-gui, many times,
# and captures what a wedged GUI is doing (clud#1293: the seed GUI sometimes
# never exits after its panes finish, and its mux stops answering `cli list`).
param(
    [Parameter(Mandatory = $true)][string]$BinDir,
    [Parameter(Mandatory = $true)][string]$Config,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [int]$Iterations = 30
)

$ErrorActionPreference = 'Stop'
$gui = Join-Path $BinDir 'wezterm-gui.exe'
$cli = Join-Path $BinDir 'wezterm.exe'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$cdb = @(
    'C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe',
    'C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe'
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
Write-Host "cdb: $cdb"

function Invoke-Cli {
    param([string[]]$CliArgs, [string]$Socket, [int]$TimeoutMs = 5000)
    $start = [Diagnostics.ProcessStartInfo]::new($cli)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['WEZTERM_UNIX_SOCKET'] = $Socket
    [void]$start.ArgumentList.Add('cli')
    foreach ($a in $CliArgs) { [void]$start.ArgumentList.Add([string]$a) }
    $p = [Diagnostics.Process]::Start($start)
    try {
        $out = $p.StandardOutput.ReadToEndAsync()
        $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutMs)) {
            # Mirrors clud's Invoke-GuiCli: a timed-out client is killed,
            # which resets its connection on the server side (os error 10054).
            try { $p.Kill($true) } catch { }
            return "<timeout $($CliArgs -join ' ')>"
        }
        [void]$out.Wait(2000); [void]$err.Wait(2000)
        return ("$($out.Result)$($err.Result)").Trim()
    } finally { $p.Dispose() }
}

function Start-Gui {
    param([string]$Cwd, [string[]]$Prog)
    $start = [Diagnostics.ProcessStartInfo]::new($gui)
    $start.UseShellExecute = $false
    $start.Environment['CLUD_KITTYTERM_SOFTWARE_RENDERER'] = '1'
    $start.Environment['WEZTERM_LOG'] = 'info'
    foreach ($a in @('--config-file', $Config, 'start', '--no-auto-connect',
            '--return-initial-exit-code', '--cwd', $Cwd, '--') + $Prog) {
        [void]$start.ArgumentList.Add([string]$a)
    }
    return [Diagnostics.Process]::Start($start)
}

function Save-Screenshot {
    param([string]$Path)
    try {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $b = [Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = [Drawing.Bitmap]::new($b.Width, $b.Height)
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $bmp.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
    } catch { Write-Host "screenshot failed: $_" }
}

function Save-WedgeEvidence {
    param([Diagnostics.Process]$Seed, [string]$Socket, [string]$Dir)
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Save-Screenshot (Join-Path $Dir 'screen.png')
    $list = Invoke-Cli @('list', '--format', 'json') $Socket 30000
    Set-Content -LiteralPath (Join-Path $Dir 'cli-list.txt') -Value $list
    $threads = Get-Process -Id $Seed.Id | Select-Object -ExpandProperty Threads |
        Select-Object Id, ThreadState, WaitReason, TotalProcessorTime, PriorityLevel |
        Format-Table -AutoSize | Out-String -Width 200
    Set-Content -LiteralPath (Join-Path $Dir 'threads.txt') -Value $threads
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($Seed.Id)" |
        Select-Object ProcessId, Name, CommandLine | Format-List | Out-String -Width 400
    Set-Content -LiteralPath (Join-Path $Dir 'children.txt') -Value $children
    $windows = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } |
        Select-Object Id, ProcessName, MainWindowTitle | Format-Table -AutoSize | Out-String -Width 300
    Set-Content -LiteralPath (Join-Path $Dir 'windows.txt') -Value $windows
    if ($cdb) {
        $log = Join-Path $Dir 'stacks.txt'
        & $cdb -pv -p $Seed.Id -y "$BinDir;srv*" -lines -c '.lines -e; ~*kpn 60; q' *> $log
        Write-Host "stacks written: $((Get-Item $log).Length) bytes"
    }
}

$wedges = 0
$summary = [Collections.Generic.List[string]]::new()
for ($i = 1; $i -le $Iterations; $i++) {
    $dir = Join-Path $env:RUNNER_TEMP "wedge-$i"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $ready = Join-Path $dir 'seed-ready.txt'
    $release = Join-Path $dir 'release.txt'
    $seedScript = "`$env:WEZTERM_UNIX_SOCKET + '|' + `$env:WEZTERM_PANE | Set-Content -LiteralPath '$ready'; " +
        "while (-not (Test-Path -LiteralPath '$release')) { Start-Sleep -Milliseconds 100 }; exit 23"
    $seed = Start-Gui $dir @('powershell', '-NoProfile', '-Command', $seedScript)
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while (-not (Test-Path -LiteralPath $ready) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $ready)) {
        $summary.Add("iter ${i}: seed never ready (exited=$($seed.HasExited))")
        try { $seed.Kill($true) } catch { }
        continue
    }
    $socket, $seedPane = (Get-Content -LiteralPath $ready -Raw).Trim().Split('|')

    # A second `start` reuses the live GUI and waits for its pane's status.
    $reused = Start-Gui $dir @('cmd', '/c', 'exit 37')
    $reusedOk = $reused.WaitForExit(60000)
    $reusedCode = if ($reusedOk) { $reused.ExitCode } else { 'timeout' }

    # Probe panes split from the seed, like clud's terminal-semantics script.
    $heavy = Invoke-Cli @('split-pane', '--pane-id', $seedPane, '--cwd', $dir, '--',
        'powershell', '-NoProfile', '-Command',
        "1..20000 | ForEach-Object { 'heavy line ' + `$_ + ' ' + ('x' * 80) }; Start-Sleep -Seconds 1") $socket
    $idle = Invoke-Cli @('split-pane', '--pane-id', $seedPane, '--right', '--cwd', $dir, '--',
        'powershell', '-NoProfile', '-Command', 'Start-Sleep -Seconds 60') $socket
    [void](Invoke-Cli @('send-text', '--pane-id', $idle, 'PASTE_SENTINEL') $socket)
    [void](Invoke-Cli @('send-text', '--pane-id', $idle, '--no-paste', [string][char]3) $socket)
    [void](Invoke-Cli @('adjust-pane-size', '--pane-id', $idle, '--amount', '8', 'Left') $socket)
    [void](Invoke-Cli @('get-text', '--escapes', '--pane-id', $heavy) $socket)
    [void](Invoke-Cli @('list', '--format', 'json') $socket)
    # Some clients are killed mid-request, as a timed-out probe would be.
    [void](Invoke-Cli @('get-text', '--pane-id', $heavy) $socket 1)
    [void](Invoke-Cli @('list', '--format', 'json') $socket 1)
    Start-Sleep -Seconds 2
    [void](Invoke-Cli @('kill-pane', '--pane-id', $heavy) $socket 2000)
    [void](Invoke-Cli @('kill-pane', '--pane-id', $idle) $socket 2000)

    Set-Content -LiteralPath $release -Value 'go'
    $exited = $seed.WaitForExit(45000)
    if ($exited) {
        $summary.Add("iter ${i}: ok seed=$($seed.ExitCode) reused=$reusedCode")
    } else {
        $wedges++
        $summary.Add("iter ${i}: WEDGED reused=$reusedCode")
        Write-Host "iteration $i wedged; capturing evidence"
        Save-WedgeEvidence $seed $socket (Join-Path $OutDir "wedge-$i")
        try { $seed.Kill($true) } catch { }
        if ($wedges -ge 3) { break }
    }
    Get-Process wezterm-gui -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill($true) } catch { }
    }
}
$summary | Set-Content -LiteralPath (Join-Path $OutDir 'summary.txt')
$summary | ForEach-Object { Write-Host $_ }
Write-Host "wedges: $wedges"
