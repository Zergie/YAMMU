[cmdletbinding()]
param(
)

$gimp = Get-ChildItem "$env:ProgramFiles\gimp*" -Directory |
        Get-ChildItem -Directory -Filter bin |
        Get-ChildItem -File -Filter gimp*console*.exe |
        ForEach-Object FullName

$scriptFu = [pscustomobject]@{
    crop = '(let* ((image (car (gimp-file-load RUN-NONINTERACTIVE "input.png" "input.png"))) (drawable (car (gimp-image-get-active-layer image)))) (gimp-image-crop image {0} {1} {2} {3}) (gimp-file-save RUN-NONINTERACTIVE image drawable "output.png" "output.png") (gimp-image-delete image))' # width,height,x,y
}

try {
    Push-Location $PSScriptRoot
    @{
        render_1 = $scriptFu.crop -f @(800, 800, $((1280-800)/2), $((1024-800)/2))
    }.GetEnumerator() |
        ForEach-Object {
            $file  = $_.Name + ".png" #(Get-ChildItem "$($_.Name).png").FullName
            $output = [System.IO.Path]::GetFileNameWithoutExtension($file) + "_processed.png"
            $cmd  = ". `"$gimp`" -i -b '$($_.Value.Replace("input.png", $file).Replace("output.png", $output))' -b '(gimp-quit 0)'"
            Write-Host -ForegroundColor Cyan $cmd
            Invoke-Expression $cmd

            Invoke-Item $output
        }

} finally {
    Pop-Location
}
