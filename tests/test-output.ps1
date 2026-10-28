#requires -Version 5.1
param([Parameter(Mandatory = $true)][string]$ConverterPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ConverterPath = (Get-Item -LiteralPath $ConverterPath).FullName
$root = Join-Path ([IO.Path]::GetTempPath()) ('nx-output-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Encode-WzString([string]$Value) {
    $bytes = [Collections.Generic.List[byte]]::new()
    $bytes.Add([byte](256 - $Value.Length))
    $mask = 0xAA
    foreach ($b in [Text.Encoding]::ASCII.GetBytes($Value)) {
        $bytes.Add([byte]($b -bxor $mask))
        $mask++
    }
    return ,$bytes.ToArray()
}
function Write-Img([string]$Path, [byte]$Value) {
    # BMS, Property with one compressed integer property. No game assets required.
    [byte[]]$bytes = @([byte]0x73) + (Encode-WzString 'Property') +
        @([byte]0, [byte]0, [byte]1, [byte]0) + (Encode-WzString 'value') + @([byte]3, $Value)
    [IO.File]::WriteAllBytes($Path, $bytes)
}
function Run-Converter([string[]]$Arguments) {
    & $ConverterPath @Arguments
    Assert ($LASTEXITCODE -eq 0) 'Converter failed.'
}
function Check-Nx([string]$Path) {
    $data = [IO.File]::ReadAllBytes($Path)
    Assert ($data.Length -ge 64) 'NX is truncated.'
    Assert ([Text.Encoding]::ASCII.GetString($data, 0, 4) -ceq 'PKG4') 'NX magic is wrong.'
    Assert ([BitConverter]::ToUInt32($data, 4) -eq 2) 'Fixture properties were not converted.'
    # Root occupies the first 20-byte node, followed by our integer property.
    $nodes = [BitConverter]::ToUInt64($data, 8)
    Assert ([BitConverter]::ToInt64($data, [int]$nodes + 20 + 12) -eq 42) 'Fixture value was not preserved.'
}
try {
    $source = Join-Path $root 'source with spaces'
    $output = Join-Path $root 'output with spaces'
    New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
    $img = Join-Path $source 'nested/Map.IMG'
    Write-Img $img 42
    Run-Converter @($source, '--client', '--output', $output)
    $nx = Join-Path $output 'nested/Map.nx'
    Check-Nx $nx
    Assert (-not (Test-Path -LiteralPath (Join-Path $source 'nested/Map.nx'))) 'Explicit output wrote into source.'
    $hash = (Get-FileHash -LiteralPath $nx).Hash
    Run-Converter @($source, '--client', '--output', $output)
    Assert ((Get-FileHash -LiteralPath $nx).Hash -eq $hash) 'Existing explicit output was overwritten.'

    $single = Join-Path $root 'single'
    Run-Converter @($img, '--server', '--output', $single)
    Check-Nx (Join-Path $single 'Map.nx')
    Run-Converter @($img, '--server')
    Check-Nx (Join-Path $source 'nested/Map.nx')

    & $ConverterPath $img '--output'
    Assert ($LASTEXITCODE -ne 0) 'Missing output argument was accepted.'
    & $ConverterPath $img $img '--output' $output
    Assert ($LASTEXITCODE -ne 0) 'Ambiguous multiple inputs with output were accepted.'

    # End-to-end wrapper with the actual converter, including its new CLI option.
    $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'convert-local.ps1'
    $managed = Join-Path $root 'managed'
    $sourceBefore = (Get-FileHash -LiteralPath $img).Hash
    & $scriptPath -Source $source -Output $managed -ConverterPath $ConverterPath
    Check-Nx (Join-Path $managed 'current/nested/Map.nx')
    Assert ((Get-FileHash -LiteralPath $img).Hash -eq $sourceBefore) 'Source IMG changed.'
    & $scriptPath -Source $source -Output $managed -ConverterPath $ConverterPath
    Assert (-not (Test-Path -LiteralPath (Join-Path $managed 'previous'))) 'Identical real conversion consumed history.'
    Write-Img $img 43
    & $scriptPath -Source $source -Output $managed -ConverterPath $ConverterPath
    Check-Nx (Join-Path $managed 'previous/nested/Map.nx')
    Assert ((Get-FileHash -LiteralPath (Join-Path $managed 'current/nested/Map.nx')).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $managed 'previous/nested/Map.nx')).Hash) 'Changed real conversion was not promoted.'
    Write-Host 'PASS: real converter output routing, fixture value, legacy output, argument validation and managed retention.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
