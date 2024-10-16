[cmdletbinding()]
param(
)

$gimp = Get-ChildItem "$env:ProgramFiles\gimp*" -Directory |
        Get-ChildItem -Directory -Filter bin |
        Get-ChildItem -File -Filter gimp*console*.exe |
        ForEach-Object FullName

$scriptFu = [pscustomobject]@{
    crop = '(let* ((image (car (gimp-file-load RUN-NONINTERACTIVE "input.png" "input.png"))) (drawable (car (gimp-image-get-active-layer image)))) (gimp-image-crop image {0} {1} {2} {3}) (gimp-file-save RUN-NONINTERACTIVE image drawable "output.png" "output.png") (gimp-image-delete image))' # width,height,x,y
    crop_resize = '(let* ((image (car (gimp-file-load RUN-NONINTERACTIVE "input.png" "input.png"))) (drawable (car (gimp-image-get-active-layer image)))) (gimp-image-crop image {0} {1} {2} {3}) (gimp-image-scale image {4} {5}) (gimp-file-save RUN-NONINTERACTIVE image drawable "output.png" "output.png") (gimp-image-delete image))' # width,height,x,y,new_width,new_height
}

function Invoke-Command {
    param ([string] $cmd)
    Write-Host -ForegroundColor Cyan $cmd
    Invoke-Expression $cmd
}

function Invoke-ScriptFu {
    param ([string] $script)
    Invoke-Command ". `"$gimp`" -i -b '$($script.Replace("input.png", $file).Replace("output.png", $output))' -b '(gimp-quit 0)'"
}

try {
    Push-Location $PSScriptRoot
    @{
        render_1 = $scriptFu.crop_resize -f @(800, 800, $((1280-800)/2), $((1024-800)/2), 400, 400)
    }.GetEnumerator() |
        ForEach-Object {
            $file  = $_.Name + ".png" #(Get-ChildItem "$($_.Name).png").FullName
            $output = [System.IO.Path]::GetFileNameWithoutExtension($file) + "_processed.png"

            Invoke-ScriptFu $_.Value

            Invoke-Item $output
        }

    Invoke-Command "git add *_processed.png"
    Invoke-Command "git status"
} finally {
    Pop-Location
}
