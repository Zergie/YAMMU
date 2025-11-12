[CmdletBinding()]
param()
$klipper_url = "trident.local"
$klipper_user = "biqu"
$gcode = @(
    "QUERY_BE"
)

Write-Host
Write-Host -ForegroundColor Cyan "Installing on ${klipper_url}"
scp $PSScriptRoot\multi_material_unit.py ${klipper_user}@${klipper_url}:klipper/klippy/extras/multi_material_unit.py
scp ${klipper_user}@${klipper_url}:printer_data/config/mmu.cfg "$PSScriptRoot\mmu-$((Get-Date).ToString('yyyyMMdd_HHmmss')).cfg.bak"
scp $PSScriptRoot\mmu.cfg ${klipper_user}@${klipper_url}:printer_data/config/mmu.cfg

Write-Host -ForegroundColor Cyan "Restarting klipper on ${klipper_url} " -NoNewline
ssh ${klipper_user}@${klipper_url} systemctl restart klipper

$success = $false
0..30 | ForEach-Object {
    if (!$success) {
        Write-Host -ForegroundColor Cyan -NoNewline "."
        Start-Sleep -Seconds 1
        try {
            $response = Invoke-RestMethod -Uri http://${klipper_url}:7125/printer/info -TimeoutSec 1
            if ($response -and $response.result.state -eq "ready") {
                Write-Host -ForegroundColor Green " $($response.result.state_message)"
                $success = $true
            }
        } catch {
            # Ignore exceptions and continue waiting
        }
    }
}
if (-not $success) {
    Write-Host -ForegroundColor Red " $($response.result.state_message)"
    exit 1
}

$last_message = (Invoke-RestMethod -Uri http://${klipper_url}:7125/server/gcode_store?count=10).result.gcode_store |
                    Select-Object -Last 1

$gcode |
    ForEach-Object {
        Write-Host -ForegroundColor Cyan -NoNewline "Running gcode '$_' .. "
        "http://${klipper_url}:7125/printer/gcode/script?script=$_"
    } |
    ForEach-Object {
        $uri = $_
        Invoke-RestMethod -Method Post -Uri $uri -SkipHttpErrorCheck |
            ForEach-Object {
                Write-Host -NoNewline ' '
                if ($null -eq $_.error) {
                    Write-Host -ForegroundColor Green $_.result
                } elseif ($_.error.message) {
                    Write-Host -ForegroundColor Red ($_.error.message | ConvertFrom-Json).message
                }
                (Invoke-RestMethod -Uri http://${klipper_url}:7125/server/gcode_store?count=10).result.gcode_store |
                    Where-Object time -gt $last_message.time -OutVariable messages |
                    ForEach-Object message |
                    Write-Host -ForegroundColor Yellow
                $last_message = $messages | Select-Object -Last 1
            }
    }
