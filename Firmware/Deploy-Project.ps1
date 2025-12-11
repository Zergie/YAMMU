[CmdletBinding()]
param()
$klipper_url = "trident.local"
$klipper_user = "biqu"
$gcode = $(try { Get-Content $PSScriptRoot\startup.gcode -Encoding utf8 } catch { @() })

#region Helper Functions
function ➡️ () { Write-Host -ForegroundColor Cyan "`n$args" }
function ➡️➡️ () { Write-Host -NoNewline -ForegroundColor Cyan $args }
function 🔴 () { Write-Host -ForegroundColor Red $args }
function 🟡 () { Write-Host -NoNewline -ForegroundColor Yellow $args }
function 🟢 () { Write-Host -ForegroundColor Green $args }
function 🔵 () { Write-Host -ForegroundColor Blue $args }

function Invoke-SCP {
    $p = Start-Process -NoNewWindow -PassThru -FilePath "scp" -ArgumentList $args
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        🔴 "scp $command"
        🔴 "SCP command failed with exit code $($p.ExitCode | ConvertTo-Json)"
        exit 1
    }
}

function Invoke-SSH {
    $p = Start-Process -NoNewWindow -PassThru -FilePath "ssh" -ArgumentList $args
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) {
        🔴 "ssh $command"
        🔴 "SSH command failed with exit code $($p.ExitCode | ConvertTo-Json)"
        exit 1
    }
}

#endregion

➡️ "Installing on ${klipper_url}"
Invoke-SCP $PSScriptRoot\*.py ${klipper_user}@${klipper_url}:klipper/klippy/extras/
Invoke-SCP $PSScriptRoot\mmu.cfg ${klipper_user}@${klipper_url}:printer_data/config/mmu.cfg

➡️➡️ "Clearing klippy log on ${klipper_url} "
Invoke-SSH ${klipper_user}@${klipper_url} touch printer_data/logs/klippy.log
Write-Host -ForegroundColor Cyan -NoNewline "."
Invoke-SSH ${klipper_user}@${klipper_url} rm printer_data/logs/klippy.log
🟢 " ok"

➡️➡️ "Restarting klipper on ${klipper_url} "
Invoke-SSH ${klipper_user}@${klipper_url} systemctl restart klipper

$finished = $false
$firmware_restart_count = 0
0..30 | ForEach-Object {
    if (!$finished) {
        Write-Host -ForegroundColor Cyan -NoNewline "."
        Start-Sleep -Seconds 1
        try {
            $response = Invoke-RestMethod -Uri http://${klipper_url}:7125/printer/info -TimeoutSec 1
            if ($response -and $response.result.state -eq "ready") {
                🟢 " $($response.result.state)"
                $finished = $true
            } elseif ($response -and $response.result.state -ne "startup") {
                🔴 " $($response.result.state) "
                🔴 "$($response.result.state_message.Trim())"
                🔴 ""

                if ($response.result.state -in @("error", "shutdown") -and $response.result.state_message -like '*"FIRMWARE_RESTART"*') {
                    if ($firmware_restart_count -lt 1) {
                        ➡️➡️ "Firmware restart detected, waiting for klipper to recover "
                        $firmware_restart_count += 1
                        Invoke-RestMethod `
                            -Method Post `
                            -Uri "http://${klipper_url}:7125/printer/gcode/script?script=FIRMWARE_RESTART" `
                            -SkipHttpErrorCheck `
                            -ErrorAction SilentlyContinue | Out-Null

                        $response = Invoke-RestMethod -Uri http://${klipper_url}:7125/printer/info -TimeoutSec 1
                        if ($response -and $response.result.state -eq "ready") {
                            🟢 " $($response.result.state)"
                            $finished = $true
                        } else {
                            🔴 " $($response.result.state) "
                        }
                    }
                    else {
                        🔴 " $($response.result.state) "
                        ssh ${klipper_user}@${klipper_url} "cat printer_data/logs/klippy.log" |
                            Select-String "Traceback" -Context 5,20 |
                            Select-Object -First 1
                        exit 1
                    }
                }

            }
        } catch {
            # Ignore exceptions and continue waiting
        }
    }
}
if (!$finished) {
    🔴 " Timeout: $($response.result.state)"
    🔴 ""
    # ssh mks@10.0.0.17 "cat printer_data/logs/klippy.log | sed -n '/=======================/,`$p'"
    exit 1
}


$last_message = (Invoke-RestMethod -Uri http://${klipper_url}:7125/server/gcode_store?count=10).result.gcode_store |
                    Select-Object -Last 1

➡️➡️ "Sending startup G-Code to ${klipper_url} "
$gcode |
    Where-Object { $_.Trim().Length -gt 0 } |
    ForEach-Object {
        Write-Host -ForegroundColor Cyan -NoNewline "."
        "http://${klipper_url}:7125/printer/gcode/script?script=$_"
    } |
    ForEach-Object {
        Invoke-RestMethod -Method Post -Uri $_ -SkipHttpErrorCheck -ErrorAction SilentlyContinue | Out-Null
    }
🟢 " ok"

(Invoke-RestMethod -Uri http://${klipper_url}:7125/server/gcode_store?count=10).result.gcode_store |
    Where-Object time -ge $last_message.time -OutVariable messages |
    ForEach-Object { $_.message.Trim() } |
    ForEach-Object {
        if ($_.StartsWith("!!")) {
            🔴 $_
        } elseif ($_.StartsWith("//") -or $_.StartsWith("echo:")) {
            Write-Host $_
        } else {
            🔵 $_
        }
    }

(Invoke-RestMethod "http://${klipper_url}:7125/printer/objects/query?multi_material_unit").result.status |
        ForEach-Object multi_material_unit

# ➡️ "Tailing klippy log on ${klipper_url} "
# ssh ${klipper_user}@${klipper_url} tail -f printer_data/logs/klippy.log