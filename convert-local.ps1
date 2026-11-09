#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Source = (Join-Path $PSScriptRoot 'wz/current'),
    [string]$Output = (Join-Path $PSScriptRoot 'nx-local'),
    [string]$ConverterPath,
    [ValidateSet('client', 'server')][string]$Mode = 'client',
    [ValidateRange(1, 64)][int]$Threads = 8,
    [switch]$Lz4HC
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-NoLinks([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Linked paths are not supported: $Path"
    }
    if ($item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force -Recurse) {
            if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked paths are not supported: $($child.FullName)"
            }
        }
    }
}

function Remove-ManagedDirectory([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Assert-NoLinks $Path
        foreach ($file in Get-ChildItem -LiteralPath $Path -Recurse -File -Force) {
            if ($file.Extension -ine '.nx' -and $file.Name -cne 'manifest.json') {
                throw "Unexpected file in managed NX output; it was not removed: $($file.FullName)"
            }
        }
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Get-Inputs {
    Assert-NoLinks $sourceRoot
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $files = @(Get-ChildItem -LiteralPath $sourceRoot -Recurse -File -Force |
        Where-Object { $_.Extension -in '.wz', '.img' } | Sort-Object FullName)
    if ($files.Count -eq 0) { throw "No WZ/IMG files found in $sourceRoot" }
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceRoot.Length + 1)
        $nx = [IO.Path]::ChangeExtension($relative, '.nx')
        if (-not $names.Add($nx)) { throw "Multiple inputs would produce $nx" }
        [pscustomobject]@{
            path = $relative
            nx = $nx
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
}

function Get-Outputs([string]$Directory, [object[]]$Inputs) {
    Assert-NoLinks $Directory
    $files = @(Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter '*.nx')
    if ($files.Count -ne $Inputs.Count) { throw 'The converter did not produce the complete NX set.' }
    foreach ($inputFile in $Inputs) {
        $path = Join-Path $Directory $inputFile.nx
        $file = Get-Item -LiteralPath $path
        if ($file.Length -lt 64) { throw "Incomplete NX file: $path" }
        $stream = [IO.File]::OpenRead($path)
        try {
            $magic = New-Object byte[] 4
            if ($stream.Read($magic, 0, 4) -ne 4 -or
                [Text.Encoding]::ASCII.GetString($magic) -cne 'PKG4') {
                throw "Invalid NX header: $path"
            }
        } finally { $stream.Dispose() }
        [pscustomobject]@{
            path = $inputFile.nx
            sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        }
    }
}

if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
    throw "Put only your active WZ/IMG files in '$Source', or use -Source to choose a folder."
}
$sourceRoot = [IO.Path]::GetFullPath((Get-Item -LiteralPath $Source).FullName).TrimEnd([char[]]'/\')
$outputRoot = [IO.Path]::GetFullPath($Output).TrimEnd([char[]]'/\')
$separator = [IO.Path]::DirectorySeparatorChar
if ($sourceRoot.Equals($outputRoot, [StringComparison]::OrdinalIgnoreCase) -or
    ($sourceRoot + $separator).StartsWith($outputRoot + $separator, [StringComparison]::OrdinalIgnoreCase) -or
    ($outputRoot + $separator).StartsWith($sourceRoot + $separator, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source and output folders must be separate and must not contain each other.'
}
if (-not $ConverterPath) {
    foreach ($candidate in 'x64/Release/NoLifeWzToNx.exe', 'x64/Debug/NoLifeWzToNx.exe', 'x64/NoLifeWzToNx.exe') {
        $path = Join-Path $PSScriptRoot $candidate
        if (Test-Path -LiteralPath $path -PathType Leaf) { $ConverterPath = $path; break }
    }
}
if (-not $ConverterPath -or -not (Test-Path -LiteralPath $ConverterPath -PathType Leaf)) {
    throw 'Build NoLifeWzToNx first, or specify -ConverterPath.'
}
$ConverterPath = (Get-Item -LiteralPath $ConverterPath).FullName
$global:LASTEXITCODE = 0
$capability = (& $ConverterPath '--output-version' | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $capability -cne 'NoLifeWzToNx-output-v1') {
    throw 'This converter does not support managed output. Rebuild it before using convert-local.'
}
if (-not (Test-Path -LiteralPath $outputRoot)) {
    New-Item -ItemType Directory -Path $outputRoot | Out-Null
}
Assert-NoLinks $outputRoot
$lock = $null
try {
    $lock = [IO.File]::Open((Join-Path $outputRoot '.lock'), [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $marker = Join-Path $outputRoot '.nx-local-managed'
    if (Test-Path -LiteralPath $marker) {
        if ((Get-Content -LiteralPath $marker -Raw).Trim() -cne 'NoLifeWzToNx-local-v1') {
            throw 'Unrecognized output folder marker; nothing was removed.'
        }
    } else {
        $existing = @(Get-ChildItem -LiteralPath $outputRoot -Force | Where-Object { $_.Name -ne '.lock' })
        if ($existing.Count -gt 0) { throw 'Output folder must be empty on first use; existing files were not removed.' }
        Set-Content -LiteralPath $marker -Value 'NoLifeWzToNx-local-v1' -Encoding ASCII
    }

    $current = Join-Path $outputRoot 'current'
    $previous = Join-Path $outputRoot 'previous'
    $pending = Join-Path $outputRoot '.pending'
    $retired = Join-Path $outputRoot '.retired'

    # Recover interrupted directory rotation before removing any temporary output.
    if (-not (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $previous)) {
        Move-Item -LiteralPath $previous -Destination $current
    }
    if ((Test-Path -LiteralPath $retired) -and -not (Test-Path -LiteralPath $previous)) {
        Move-Item -LiteralPath $retired -Destination $previous
    }
    if ((Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $previous)) {
        Remove-ManagedDirectory $retired
    }
    Remove-ManagedDirectory $pending
    $before = @(Get-Inputs)
    $inputJson = ConvertTo-Json -InputObject $before -Depth 5 -Compress
    $toolHash = (Get-FileHash -LiteralPath $ConverterPath -Algorithm SHA256).Hash
    New-Item -ItemType Directory -Path $pending | Out-Null
    $converterArgs = @($sourceRoot, "--$Mode", '--threads', "$Threads", '--output', $pending)
    if ($Lz4HC) { $converterArgs += '--lz4hc' }
    $global:LASTEXITCODE = 0
    & $ConverterPath @converterArgs
    if ($LASTEXITCODE -ne 0) { throw "Conversion failed (exit $LASTEXITCODE). Current and previous NX were preserved." }
    $afterJson = ConvertTo-Json -InputObject @(Get-Inputs) -Depth 5 -Compress
    if ($inputJson -cne $afterJson -or
        (Get-FileHash -LiteralPath $ConverterPath -Algorithm SHA256).Hash -cne $toolHash) {
        throw 'Inputs or converter changed during conversion. Current and previous NX were preserved.'
    }
    $nx = @(Get-Outputs $pending $before)
    $manifest = [ordered]@{
        schema = 1
        createdUtc = [DateTime]::UtcNow.ToString('o')
        source = $sourceRoot
        converterSha256 = $toolHash
        mode = $Mode
        lz4hc = [bool]$Lz4HC
        inputs = $before
        outputs = $nx
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $pending 'manifest.json') -Encoding UTF8
    if (Test-Path -LiteralPath $current) {
        try {
            $currentNx = @(Get-Outputs $current $before)
            $same = (ConvertTo-Json -InputObject $currentNx -Compress) -ceq (ConvertTo-Json -InputObject $nx -Compress)
        } catch { $same = $false }
        if ($same) {
            # Update provenance without consuming the previous distinct NX generation.
            Copy-Item -LiteralPath (Join-Path $pending 'manifest.json') -Destination (Join-Path $current 'manifest.json') -Force
            Remove-ManagedDirectory $pending
            Write-Host "NX content unchanged. Current: $current"
            return
        }
    }
    try {
        if (Test-Path -LiteralPath $previous) { Move-Item -LiteralPath $previous -Destination $retired }
        if (Test-Path -LiteralPath $current) { Move-Item -LiteralPath $current -Destination $previous }
        Move-Item -LiteralPath $pending -Destination $current
    } catch {
        if (-not (Test-Path -LiteralPath $current) -and (Test-Path -LiteralPath $previous)) {
            Move-Item -LiteralPath $previous -Destination $current
        }
        if ((Test-Path -LiteralPath $retired) -and -not (Test-Path -LiteralPath $previous)) {
            Move-Item -LiteralPath $retired -Destination $previous
        }
        throw
    }
    Remove-ManagedDirectory $retired
    Write-Host "Done. Latest NX: $current"
    Write-Host "Previous NX: $previous (available after the second distinct conversion)."
} finally {
    if ($lock) { $lock.Dispose() }
}
