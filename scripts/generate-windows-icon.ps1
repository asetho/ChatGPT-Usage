[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'CodexUsage\Assets.xcassets\AppIcon.appiconset\AppIcon-512@2x.png'
$smallSourcePath = Join-Path $repoRoot 'Windows\Assets\ChatGPTUsage-small.png'
if (!(Test-Path $sourcePath)) {
    throw "The macOS AppIcon source was not found: $sourcePath"
}
if (!(Test-Path $smallSourcePath)) {
    throw "The Windows small-icon source was not found: $smallSourcePath"
}

$source = [System.Drawing.Image]::FromFile($sourcePath)
$smallSource = [System.Drawing.Image]::FromFile($smallSourcePath)
try {
    function New-IconFrame([int]$pixelSize) {
        $frameSource = if ($pixelSize -le 64) { $smallSource } else { $source }
        $bitmap = [System.Drawing.Bitmap]::new(
            $pixelSize,
            $pixelSize,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $mask = [System.Drawing.Drawing2D.GraphicsPath]::new()
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            # Preserve the Orbit artwork's intentional inset at every size.
            $sourceInset = 0
            $sourceSize = [int][Math]::Min($frameSource.Width, $frameSource.Height) - ($sourceInset * 2)
            $inset = 0.0
            $cornerDiameter = $pixelSize * 0.38
            $mask.AddArc($inset, $inset, $cornerDiameter, $cornerDiameter, 180, 90)
            $mask.AddArc($pixelSize - $inset - $cornerDiameter, $inset, $cornerDiameter, $cornerDiameter, 270, 90)
            $mask.AddArc($pixelSize - $inset - $cornerDiameter, $pixelSize - $inset - $cornerDiameter, $cornerDiameter, $cornerDiameter, 0, 90)
            $mask.AddArc($inset, $pixelSize - $inset - $cornerDiameter, $cornerDiameter, $cornerDiameter, 90, 90)
            $mask.CloseFigure()
            $graphics.SetClip($mask)
            $graphics.DrawImage(
                $frameSource,
                [System.Drawing.Rectangle]::new(0, 0, $pixelSize, $pixelSize),
                $sourceInset,
                $sourceInset,
                $sourceSize,
                $sourceSize,
                [System.Drawing.GraphicsUnit]::Pixel)

            $stream = [System.IO.MemoryStream]::new()
            try {
                $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
                [PSCustomObject]@{ Size = $pixelSize; Data = $stream.ToArray() }
            }
            finally {
                $stream.Dispose()
            }
        }
        finally {
            $mask.Dispose()
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }

    $frames = @(16, 20, 24, 32, 40, 48, 64, 128, 256 | ForEach-Object { New-IconFrame $_ })
    $directory = Split-Path -Parent $OutputPath
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $file = [System.IO.File]::Create($OutputPath)
    $writer = [System.IO.BinaryWriter]::new($file)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$frames.Count)
        $offset = 6 + 16 * $frames.Count
        foreach ($frame in $frames) {
            [byte]$dimension = if ($frame.Size -eq 256) { 0 } else { $frame.Size }
            $writer.Write($dimension)
            $writer.Write($dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Data.Length)
            $writer.Write([uint32]$offset)
            $offset += $frame.Data.Length
        }
        foreach ($frame in $frames) {
            $writer.Write($frame.Data)
        }
    }
    finally {
        $writer.Dispose()
    }
}
finally {
    $smallSource.Dispose()
    $source.Dispose()
}
