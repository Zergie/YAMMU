[cmdletbinding()]
param(
    [switch]
    $Force
)

function Get-Files {
    $scriptFu = $Global:scriptFu
    @{
        CAD = @{
            'Assembly *' = {
                Get-ChildItem | Compress-Archive -DestinationPath Assembly.zip -Force
                Remove-Item Assembly* -Exclude Assembly.zip
            }
        }
        Images = @{
            render_1        = "Invoke-ScriptFu -Resize $($s=550; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_cw2      = "Invoke-ScriptFu -Resize $($s=550; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_ebay     = "Invoke-ScriptFu -Resize $($s=500; (($s/1024)*1280)),$s -Crop 400,400,112,0"
            render_feeder   = "Invoke-ScriptFu -Resize $($s=700; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_splitter = "Invoke-ScriptFu -Resize $($s=500; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_heater   = "Invoke-ScriptFu -Resize $($s=550; (($s/1024)*1280)),$s -CropCenter 400,400"
        }
        STLs = @{
            '**/*.stl' = { Get-ChildItem | Update-Stl }
        }
    }
}


# programms
$gimp = Get-ChildItem "$env:ProgramFiles\gimp*" -Directory |
        Get-ChildItem -Directory -Filter bin |
        Get-ChildItem -File -Filter gimp*console*.exe |
        ForEach-Object FullName # see: https://www.gimp.org/downloads/
. $gimp --help | Out-Null; if ($LASTEXITCODE -ne 0) { throw "gimp is not installed" }

$stl_transform = "wsl stl_transform" # see: https://github.com/AllwineDesigns/stl_cmd
$stl_bbox = "wsl stl_bbox"

function Update-Stl {
    param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [System.IO.FileSystemInfo[]]
    $file
    )
begin {
    Set-Content -Path $Global:op.Output -Value (Get-Date)
}
process {
    Push-Location $file.DirectoryName
    try {
        Write-Host -ForegroundColor Green $file.Name
        @(
            '_x1.stl$'
            '\s'
        ) | ForEach-Object {
            if ($file.Name -match $_) {
                Write-Host -ForegroundColor Red " => Illegal file name ($_)"
            }
        }
        $bbox = Invoke-Expression "$stl_bbox $($file.Name)" |
            Select-String -Pattern "\(([^,]+),\s*([^,]+),\s*([^,]+)\)" -AllMatches |
            ForEach-Object { $_.Matches } |
            ForEach-Object { [pscustomobject]@{x=[decimal]$_.Groups[1].value;y=[decimal]$_.Groups[2].value;z=[decimal]$_.Groups[3].value}}
        $center = [pscustomobject]@{
            x=[Math]::Round($bbox[2].x / 2 + $bbox[0].x, 4)
            y=[Math]::Round($bbox[2].y / 2 + $bbox[0].y, 4)
        }
        # $center | ConvertTo-Json -Compress | Write-Host
        $cmd = ""
        if ($center.x -ne 0) { $cmd  += " -tx $(-$center.x)" }
        if ($center.y -ne 0) { $cmd  += " -ty $(-$center.y)" }
        if ($bbox[0].z -ne 0) { $cmd += " -tz $(-$bbox[0].z)" }
        if ($cmd.Length -gt 0) {
            $cmd = "$stl_transform $cmd $($file.Name)"
            Write-Host -ForegroundColor Cyan $cmd
            Invoke-Expression "$cmd out.stl"
            Move-Item out.stl $file.Name -Force
        }
    } catch {
        Remove-Item -Path $Global:op.Output
    } finally {
        Pop-Location
    }
}
end {}
}

function Invoke-ScriptFu {
    param(
        [int[]] $Crop, # width, height, x, y
        [int[]] $CropCenter, # width, height
    [int[]] $Resize, # width, height
        [int]   $Contrast, # -127 .. 127
        [int]   $Bightness # -127 .. 127
    )

    $script = '(let* ((image (car (gimp-file-load RUN-NONINTERACTIVE "input.png" "input.png"))) (drawable (car (gimp-image-get-active-layer image)))) __script__(gimp-file-save RUN-NONINTERACTIVE image drawable "output.png" "output.png") (gimp-image-delete image))'

    if ($Resize) {
        $script = $script.Replace("__script__", "(gimp-image-scale image {0} {1}) __script__" -f $($Resize))
    }

    if ($Crop) {
        $script = $script.Replace("__script__", "(gimp-image-crop image {0} {1} {2} {3}) __script__" -f $($Crop))
    }

    if ($CropCenter) {
        $script = $script.Replace("__script__", "(gimp-image-crop image {0} {1} (/ (- (car (gimp-image-width image)) {0}) 2) (/ (- (car (gimp-image-height image)) {1}) 2)) __script__" -f $($CropCenter))
    }

    if ($Contrast -or $Bightness) {
        $script = $script.Replace("__script__", "(gimp-brightness-contrast drawable {0} {1}) __script__" -f ($Bightness, $Contrast))
    }

    $script = $script.Replace("__script__", "")
    $script = $script.Replace("input.png", $Global:op.Input)
    $script = $script.Replace("output.png", $Global:op.Output)

    Write-Debug $script
    Invoke-Expression ". `"$gimp`" -i -b '$script' -b '(gimp-quit 0)'"
}

function Invoke-Command {
    param ([object] $command)

    switch ( $command.GetType().FullName ){
        System.Object[] {
            foreach ($item in $command) {
                Invoke-Command $item
            }
        }
        System.String {
            Write-Host -ForegroundColor Cyan $command.ToString().Trim()
            Invoke-Expression $command
        }
        System.Management.Automation.ScriptBlock {
            Write-Host -ForegroundColor Cyan $command.ToString().Trim()
            $item.Invoke()
        }
        default {
            throw $command.GetType().FullName
        }
    }
}


try {
    Push-Location $PSScriptRoot
    (Get-Files).GetEnumerator() |
        ForEach-Object {
            try {
                Push-Location $_.Name
                foreach ($item in $_.Value.GetEnumerator()) {
                    $op = [pscustomobject]@{
                        Input = $item.Name
                        Output = $null
                        Commands = @( $item.Value )
                    }

                    # determine what is todo
                    switch ($_.Name){
                        Images {
                            $op.Output = $op.Input + "_processed.png"
                            $op.Input  = $op.Input + ".png"
                            $op.Commands += "Invoke-Item $($op.Output)"
                        }
                        CAD {
                            $op.Output = $op.Input + ".zip"
                            $op.Input  = $op.Input + ".step"
                        }
                        STLs {
                            $op.Output = $env:Temp + "\yammu.txt"
                        }
                        default {
                            throw "$($_.Name) is not implemented"
                        }
                    }

                    # check if output is outdated
                    if (!$Force) {
                        try {
                            if ((
                                    Get-ChildItem $op.Input |
                                        Sort-Object LastWriteTime |
                                        Select-Object -Last 1
                                ).LastWriteTime -lt (Get-Item $op.Output).LastWriteTime) {
                                $op.Output = $null
                            }
                        } catch {
                        }
                    }

                    # do or do not (there is no try)
                    if (!(Test-Path $op.Input)) {
                        Write-Host -ForegroundColor Cyan "$($op.Input) : Nothing to do. (no input file present)"
                    } elseif ($null -eq $op.output -and !$Force) {
                        Write-Host -ForegroundColor Cyan "$($op.Input) : Nothing to do. (output is newer than input)"
                    } else {
                        try {
                            Write-Host -ForegroundColor Cyan "$($op.Input) :"
                            $PSDefaultParameterValues['Get-ChildItem:Path'] = $op.Input
                            if ($PSDefaultParameterValues['Get-ChildItem:Path'].StartsWith("**")) {
                                $PSDefaultParameterValues['Get-ChildItem:Path'] = $PSDefaultParameterValues['Get-ChildItem:Path'].SubString(3)
                                $PSDefaultParameterValues['Get-ChildItem:Recurse'] = $true
                            }
                            if ((!$Force) -and (Test-Path $op.Output)) {
                                $PSDefaultParameterValues['Get-ChildItem:Path'] = Get-ChildItem |
                                    Where-Object LastWriteTime -gt (Get-Item $op.Output).LastWriteTime |
                                    ForEach-Object FullName
                            }
                            $Global:op = $op
                            Invoke-Command $op.Commands
                            Write-Host
                        } finally {
                            $PSDefaultParameterValues.Remove('Get-ChildItem:Path')
                            $PSDefaultParameterValues.Remove('Get-ChildItem:Recurse')
                        }
                    }
                }
            } finally {
                Remove-Variable op -ErrorAction SilentlyContinue
                Pop-Location
            }
        }
} finally {
    Pop-Location
}
