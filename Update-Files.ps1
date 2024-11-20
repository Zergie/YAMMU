[cmdletbinding()]
param(
    [switch]
    $Force
)

function Get-Files {
    $scriptFu = $Global:scriptFu
    @{
        CAD = @{
            'Assembly *' = { Get-ChildItem | Compress-Archive -DestinationPath Assembly.zip -Force }
        }
        Images = @{
            render_1        = "Invoke-ScriptFu -Resize $($s=550; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_cw2      = "Invoke-ScriptFu -Resize $($s=550; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_ebay     = "Invoke-ScriptFu -Resize $($s=500; (($s/1024)*1280)),$s -Crop 400,400,112,0"
            render_feeder   = "Invoke-ScriptFu -Resize $($s=700; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_splitter = "Invoke-ScriptFu -Resize $($s=500; (($s/1024)*1280)),$s -CropCenter 400,400"
            render_heater   = "Invoke-ScriptFu -Resize $($s=550; (($s/1024)*1280)),$s -CropCenter 400,400"
        }
    }
}


$gimp = Get-ChildItem "$env:ProgramFiles\gimp*" -Directory |
        Get-ChildItem -Directory -Filter bin |
        Get-ChildItem -File -Filter gimp*console*.exe |
        ForEach-Object FullName

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
                        default {
                            throw "Not Implemented"
                        }
                    }

                    # check if output is outdated
                    if (!$Force) {
                        try {
                            if ((Get-Item $op.Input).LastWriteTime -lt (Get-Item $op.Output).LastWriteTime) {
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
                        Write-Host -ForegroundColor Cyan "$($op.Input) :"
                        $PSDefaultParameterValues['Get-ChildItem:Path'] = $op.Input
                        $Global:op = $op
                        Invoke-Command $op.Commands
                        $PSDefaultParameterValues.Remove('Get-ChildItem:Path')
                        Write-Host
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
