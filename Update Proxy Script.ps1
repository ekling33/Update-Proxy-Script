<#
.SYNOPSIS
    Queries the installed Google Chrome version on remote Windows machines and generates an HTML report.

.DESCRIPTION
    Reads a list of machine names from machines.txt, connects to each remotely using
    Invoke-Command (WinRM), retrieves the Chrome version from the registry, and
    exports a styled HTML report.

.NOTES
    - Run this script as a user with admin rights on the target machines.
    - WinRM must be enabled on target machines (Enable-PSRemoting).
    - machines.txt should have one hostname or IP per line.
#>

[CmdletBinding()]
param(
    [string]$MachineListPath = ".\machines.txt",
    [string]$ReportOutputPath = ".\ChromeVersionReport.html"
)

# ── Validate input file ──────────────────────────────────────────────────────
if (-not (Test-Path $MachineListPath)) {
    Write-Error "Machine list file not found: $MachineListPath"
    exit 1
}

$machines = Get-Content $MachineListPath | Where-Object { $_ -match '\S' }

if ($machines.Count -eq 0) {
    Write-Error "No machines found in $MachineListPath"
    exit 1
}

Write-Host "Found $($machines.Count) machine(s) to query..." -ForegroundColor Cyan

# ── Remote scriptblock to fetch Chrome version ───────────────────────────────
$chromeScriptBlock = {
    $registryPaths = @(
        "HKLM:\SOFTWARE\Google\Chrome\BLBeacon",
        "HKLM:\SOFTWARE\WOW6432Node\Google\Chrome\BLBeacon",
        "HKCU:\SOFTWARE\Google\Chrome\BLBeacon"
    )

    $version = $null
    foreach ($path in $registryPaths) {
        try {
            $val = Get-ItemProperty -Path $path -Name "version" -ErrorAction SilentlyContinue
            if ($val) {
                $version = $val.version
                break
            }
        } catch { }
    }

    # Fallback: read from the EXE directly if registry misses
    if (-not $version) {
        $exePaths = @(
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
        )
        foreach ($exe in $exePaths) {
            if (Test-Path $exe) {
                $version = (Get-Item $exe).VersionInfo.ProductVersion
                break
            }
        }
    }

    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        ChromeVersion = if ($version) { $version } else { "Not Installed" }
        OSCaption     = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
        QueryTime     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

# ── Query each machine ────────────────────────────────────────────────────────
$results = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($machine in $machines) {
    $machine = $machine.Trim()
    Write-Host "  Querying: $machine" -NoNewline

    try {
        $data = Invoke-Command -ComputerName $machine `
                               -ScriptBlock $chromeScriptBlock `
                               -ErrorAction Stop

        $result = [PSCustomObject]@{
            ComputerName  = $machine
            ReportedName  = $data.ComputerName
            ChromeVersion = $data.ChromeVersion
            OSCaption     = $data.OSCaption
            QueryTime     = $data.QueryTime
            Status        = "Success"
        }
        Write-Host "  ✓  Chrome: $($data.ChromeVersion)" -ForegroundColor Green

    } catch {
        $result = [PSCustomObject]@{
            ComputerName  = $machine
            ReportedName  = "N/A"
            ChromeVersion = "N/A"
            OSCaption     = "N/A"
            QueryTime     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Status        = "Error: $($_.Exception.Message)"
        }
        Write-Host "  ✗  Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    $results.Add($result)
}

# ── Build HTML report ─────────────────────────────────────────────────────────
$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
$errorCount   = ($results | Where-Object { $_.Status -ne "Success" }).Count
$notInstalled = ($results | Where-Object { $_.ChromeVersion -eq "Not Installed" }).Count
$reportDate   = Get-Date -Format "dddd, MMMM dd yyyy  HH:mm:ss"

# Build table rows
$tableRows = foreach ($r in $results) {
    $statusClass  = if ($r.Status -eq "Success") { "success" } else { "error" }
    $versionClass = switch -Wildcard ($r.ChromeVersion) {
        "Not Installed" { "not-installed" }
        "N/A"           { "na" }
        default         { "installed" }
    }
    @"
        <tr class="$statusClass">
            <td>$([System.Web.HttpUtility]::HtmlEncode($r.ComputerName))</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($r.ReportedName))</td>
            <td class="$versionClass">$([System.Web.HttpUtility]::HtmlEncode($r.ChromeVersion))</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($r.OSCaption))</td>
            <td>$([System.Web.HttpUtility]::HtmlEncode($r.QueryTime))</td>
            <td><span class="badge badge-$statusClass">$([System.Web.HttpUtility]::HtmlEncode($r.Status))</span></td>
        </tr>
"@
}

$html = @"
<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Chrome Version Report</title>
<style>
  :root, [data-theme="light"] {
    --color-bg: #f7f6f2; --color-surface: #f9f8f5; --color-surface-2: #fbfbf9;
    --color-border: #d4d1ca; --color-divider: #dcd9d5;
    --color-text: #28251d; --color-text-muted: #7a7974; --color-text-faint: #bab9b4;
    --color-primary: #01696f; --color-primary-highlight: #cedcd8;
    --color-success: #437a22; --color-success-highlight: #d4dfcc;
    --color-error: #a12c7b; --color-error-highlight: #e0ced7;
    --color-warning: #964219; --color-warning-highlight: #ddcfc6;
    --shadow-md: 0 4px 12px oklch(0.2 0.01 80 / 0.08);
    --radius-md: 0.5rem; --radius-lg: 0.75rem; --radius-full: 9999px;
    --font-body: 'Inter', system-ui, sans-serif;
    --font-mono: 'JetBrains Mono', 'Consolas', monospace;
  }
  [data-theme="dark"] {
    --color-bg: #171614; --color-surface: #1c1b19; --color-surface-2: #201f1d;
    --color-border: #393836; --color-divider: #262523;
    --color-text: #cdccca; --color-text-muted: #797876; --color-text-faint: #5a5957;
    --color-primary: #4f98a3; --color-primary-highlight: #313b3b;
    --color-success: #6daa45; --color-success-highlight: #3a4435;
    --color-error: #d163a7; --color-error-highlight: #4c3d46;
    --color-warning: #bb653b; --color-warning-highlight: #564942;
    --shadow-md: 0 4px 12px oklch(0 0 0 / 0.3);
  }
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  html { -webkit-font-smoothing: antialiased; }
  body { font-family: var(--font-body); font-size: 14px; background: var(--color-bg); color: var(--color-text); line-height: 1.5; }

  /* ── Header ── */
  .header {
    background: var(--color-surface);
    border-bottom: 1px solid var(--color-divider);
    padding: 20px 32px;
    display: flex; align-items: center; justify-content: space-between; gap: 16px;
    position: sticky; top: 0; z-index: 100;
  }
  .header-left { display: flex; align-items: center; gap: 12px; }
  .logo-icon svg { display: block; }
  .header h1 { font-size: 18px; font-weight: 600; letter-spacing: -0.01em; }
  .header .subtitle { font-size: 12px; color: var(--color-text-muted); margin-top: 2px; }
  .theme-btn {
    background: none; border: 1px solid var(--color-border); color: var(--color-text-muted);
    padding: 6px 10px; border-radius: var(--radius-md); cursor: pointer; font-size: 13px;
    transition: all 150ms ease;
  }
  .theme-btn:hover { background: var(--color-surface-2); color: var(--color-text); }

  /* ── Main layout ── */
  .main { max-width: 1200px; margin: 0 auto; padding: 28px 32px; }

  /* ── KPI Cards ── */
  .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin-bottom: 28px; }
  .kpi-card {
    background: var(--color-surface); border: 1px solid var(--color-border);
    border-radius: var(--radius-lg); padding: 16px 20px;
    box-shadow: var(--shadow-md);
  }
  .kpi-label { font-size: 11px; font-weight: 500; text-transform: uppercase; letter-spacing: 0.06em; color: var(--color-text-muted); margin-bottom: 6px; }
  .kpi-value { font-size: 28px; font-weight: 700; letter-spacing: -0.02em; font-family: var(--font-mono); }
  .kpi-value.total   { color: var(--color-primary); }
  .kpi-value.ok      { color: var(--color-success); }
  .kpi-value.fail    { color: var(--color-error); }
  .kpi-value.missing { color: var(--color-warning); }

  /* ── Table card ── */
  .table-card {
    background: var(--color-surface); border: 1px solid var(--color-border);
    border-radius: var(--radius-lg); box-shadow: var(--shadow-md); overflow: hidden;
  }
  .table-card-header {
    padding: 14px 20px; border-bottom: 1px solid var(--color-divider);
    display: flex; align-items: center; justify-content: space-between;
  }
  .table-card-header h2 { font-size: 14px; font-weight: 600; }
  .table-card-header .count { font-size: 12px; color: var(--color-text-muted); }

  /* ── Table ── */
  .table-wrap { overflow-x: auto; }
  table { width: 100%; border-collapse: collapse; }
  thead th {
    padding: 10px 16px; font-size: 11px; font-weight: 600; text-transform: uppercase;
    letter-spacing: 0.05em; color: var(--color-text-muted); text-align: left;
    background: var(--color-surface-2); border-bottom: 1px solid var(--color-divider);
    white-space: nowrap;
  }
  tbody td {
    padding: 10px 16px; font-size: 13px; border-bottom: 1px solid var(--color-divider);
    vertical-align: middle;
  }
  tbody tr:last-child td { border-bottom: none; }
  tbody tr:hover td { background: var(--color-surface-2); }
  tbody tr.error td { opacity: 0.75; }

  /* Version styling */
  .installed { font-family: var(--font-mono); font-size: 12px; font-weight: 500; color: var(--color-success); }
  .not-installed { font-weight: 500; color: var(--color-warning); }
  .na { color: var(--color-text-faint); }

  /* Badges */
  .badge {
    display: inline-flex; align-items: center; padding: 2px 8px;
    border-radius: var(--radius-full); font-size: 11px; font-weight: 500; white-space: nowrap;
  }
  .badge-Success      { background: var(--color-success-highlight); color: var(--color-success); }
  .badge-error        { background: var(--color-error-highlight);   color: var(--color-error); font-size: 10px; max-width: 260px; overflow: hidden; text-overflow: ellipsis; display: block; }

  /* Footer */
  .footer { text-align: center; padding: 24px; font-size: 12px; color: var(--color-text-faint); }

  /* Search */
  .search-input {
    background: var(--color-surface-2); border: 1px solid var(--color-border);
    border-radius: var(--radius-md); padding: 6px 12px; font-size: 13px; color: var(--color-text);
    outline: none; width: 220px;
    transition: border-color 150ms ease, box-shadow 150ms ease;
  }
  .search-input:focus { border-color: var(--color-primary); box-shadow: 0 0 0 3px oklch(from var(--color-primary) l c h / 0.15); }
  .search-input::placeholder { color: var(--color-text-faint); }
</style>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
</head>
<body>

<header class="header">
  <div class="header-left">
    <div class="logo-icon">
      <svg width="32" height="32" viewBox="0 0 32 32" fill="none" aria-label="Chrome Report Logo">
        <rect width="32" height="32" rx="8" fill="var(--color-primary)" opacity="0.15"/>
        <circle cx="16" cy="16" r="7" stroke="var(--color-primary)" stroke-width="2" fill="none"/>
        <circle cx="16" cy="16" r="3" fill="var(--color-primary)"/>
        <line x1="16" y1="9" x2="16" y2="5" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round"/>
        <line x1="22.2" y1="12.5" x2="25.6" y2="10.5" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round"/>
        <line x1="22.2" y1="19.5" x2="25.6" y2="21.5" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round"/>
        <line x1="16" y1="23" x2="16" y2="27" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round"/>
        <line x1="9.8" y1="19.5" x2="6.4" y2="21.5" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round"/>
        <line x1="9.8" y1="12.5" x2="6.4" y2="10.5" stroke="var(--color-primary)" stroke-width="2" stroke-linecap="round"/>
      </svg>
    </div>
    <div>
      <h1>Google Chrome Version Report</h1>
      <div class="subtitle">Generated: $reportDate</div>
    </div>
  </div>
  <button class="theme-btn" onclick="toggleTheme()" id="themeBtn">☀ Light</button>
</header>

<main class="main">

  <div class="kpi-grid">
    <div class="kpi-card">
      <div class="kpi-label">Total Machines</div>
      <div class="kpi-value total">$($results.Count)</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Queried Successfully</div>
      <div class="kpi-value ok">$successCount</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Query Errors</div>
      <div class="kpi-value fail">$errorCount</div>
    </div>
    <div class="kpi-card">
      <div class="kpi-label">Chrome Not Installed</div>
      <div class="kpi-value missing">$notInstalled</div>
    </div>
  </div>

  <div class="table-card">
    <div class="table-card-header">
      <h2>Machine Details</h2>
      <div style="display:flex;align-items:center;gap:12px;">
        <span class="count" id="rowCount">$($results.Count) machines</span>
        <input type="search" class="search-input" placeholder="Filter machines…" oninput="filterTable(this.value)" id="searchBox">
      </div>
    </div>
    <div class="table-wrap">
      <table id="reportTable">
        <thead>
          <tr>
            <th>Target Name</th>
            <th>Reported Hostname</th>
            <th>Chrome Version</th>
            <th>Operating System</th>
            <th>Query Time</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody id="tableBody">
          $($tableRows -join "`n")
        </tbody>
      </table>
    </div>
  </div>

</main>

<footer class="footer">Chrome Version Report &mdash; Generated by Get-ChromeVersionReport.ps1</footer>

<script>
  // Theme toggle
  function toggleTheme() {
    const html = document.documentElement;
    const btn  = document.getElementById('themeBtn');
    if (html.getAttribute('data-theme') === 'dark') {
      html.setAttribute('data-theme', 'light');
      btn.textContent = '☾ Dark';
    } else {
      html.setAttribute('data-theme', 'dark');
      btn.textContent = '☀ Light';
    }
  }

  // Live search / filter
  function filterTable(query) {
    const q    = query.toLowerCase();
    const rows = document.querySelectorAll('#tableBody tr');
    let   vis  = 0;
    rows.forEach(row => {
      const match = row.textContent.toLowerCase().includes(q);
      row.style.display = match ? '' : 'none';
      if (match) vis++;
    });
    document.getElementById('rowCount').textContent = vis + ' machine' + (vis !== 1 ? 's' : '');
  }

  // Click-to-sort columns
  document.querySelectorAll('thead th').forEach((th, i) => {
    th.style.cursor = 'pointer';
    th.title = 'Click to sort';
    let asc = true;
    th.addEventListener('click', () => {
      const tbody = document.getElementById('tableBody');
      const rows  = Array.from(tbody.querySelectorAll('tr'));
      rows.sort((a, b) => {
        const va = a.cells[i]?.textContent.trim() ?? '';
        const vb = b.cells[i]?.textContent.trim() ?? '';
        return asc ? va.localeCompare(vb, undefined, {numeric: true}) : vb.localeCompare(va, undefined, {numeric: true});
      });
      asc = !asc;
      rows.forEach(r => tbody.appendChild(r));
    });
  });
</script>
</body>
</html>
"@

$html | Out-File -FilePath $ReportOutputPath -Encoding UTF8
Write-Host "`nReport saved to: $ReportOutputPath" -ForegroundColor Cyan

# Also export CSV for reference
$csvPath = $ReportOutputPath -replace '\.html$', '.csv'
$results | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "CSV  saved to:   $csvPath" -ForegroundColor Cyan

Write-Host "`n=== Summary ===" -ForegroundColor Yellow
Write-Host "  Total machines queried : $($results.Count)"
Write-Host "  Successful             : $successCount"
Write-Host "  Errors                 : $errorCount"
Write-Host "  Chrome not installed   : $notInstalled"
