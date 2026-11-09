#requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'convert-local.ps1'
$root = Join-Path ([IO.Path]::GetTempPath()) ('nx-retention-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$passed = 0

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function New-Case([string]$Name) {
    $script:caseRoot = Join-Path $root $Name
    $script:source = Join-Path $caseRoot 'WZ sources'
    $script:output = Join-Path $caseRoot 'NX output'
    $script:mock = Join-Path $caseRoot 'mock converter.ps1'
    New-Item -ItemType Directory -Path (Join-Path $source 'nested') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $source 'Map.wz') -Value 'version1'
    Set-Content -LiteralPath (Join-Path $source 'nested/UI.IMG') -Value 'ui1'
    Set-Content -LiteralPath (Join-Path $caseRoot 'mode') -Value 'ok'
    @'
if ($args.Count -eq 1 -and $args[0] -eq '--output-version') {
    Write-Output 'NoLifeWzToNx-output-v1'
    exit 0
}
$source = $args[0]
$destination = $args[[Array]::IndexOf($args, '--output') + 1]
$mode = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'mode') -Raw).Trim()
$files = @(Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object { $_.Extension -in '.wz', '.img' })
foreach ($file in $files) {
    if ($mode -eq 'missing' -and $file.Name -eq 'Map.wz') { continue }
    $relative = [IO.Path]::ChangeExtension($file.FullName.Substring($source.Length + 1), '.nx')
    $path = Join-Path $destination $relative
    New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
    $payload = [IO.File]::ReadAllBytes($file.FullName)
    $bytes = New-Object byte[] (64 + $payload.Length)
    [Text.Encoding]::ASCII.GetBytes('PKG4').CopyTo($bytes, 0)
    $payload.CopyTo($bytes, 64)
    if ($mode -eq 'invalid') { $bytes[0] = 0 }
    [IO.File]::WriteAllBytes($path, $bytes)
}
if ($mode -eq 'change-source') { Add-Content -LiteralPath (Join-Path $source 'Map.wz') -Value 'changed' }
if ($mode -eq 'fail') { exit 7 }
exit 0
'@ | Set-Content -LiteralPath $mock -Encoding UTF8
}
function Run-Conversion {
    & $scriptPath -Source $source -Output $output -ConverterPath $mock -Threads 1
}
function Expect-Failure([scriptblock]$Action) {
    $failed = $false
    try { & $Action } catch { $failed = $true }
    Assert $failed 'Expected failure did not occur.'
}
function Current-Hash {
    (Get-FileHash -LiteralPath (Join-Path $output 'current/Map.nx') -Algorithm SHA256).Hash
}

try {
    New-Case 'rotation'
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $source 'Map.wz')).Hash
    Run-Conversion
    $first = Current-Hash
    Assert (Test-Path -LiteralPath (Join-Path $output 'current/nested/UI.nx')) 'Nested uppercase input was lost.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $source 'Map.nx'))) 'NX was written alongside WZ.'
    Assert ((Get-FileHash -LiteralPath (Join-Path $source 'Map.wz')).Hash -eq $sourceHash) 'Source WZ changed.'
    Run-Conversion
    Assert (-not (Test-Path -LiteralPath (Join-Path $output 'previous'))) 'Identical NX consumed a generation.'
    Set-Content -LiteralPath (Join-Path $source 'Map.wz') -Value 'version2'
    Run-Conversion
    $second = Current-Hash
    Assert ($second -ne $first) 'New content was not promoted.'
    Assert ((Get-FileHash -LiteralPath (Join-Path $output 'previous/Map.nx')).Hash -eq $first) 'Previous generation is wrong.'
    Set-Content -LiteralPath (Join-Path $source 'Map.wz') -Value 'version3'
    Run-Conversion
    $third = Current-Hash
    Assert ((Get-FileHash -LiteralPath (Join-Path $output 'previous/Map.nx')).Hash -eq $second) 'Oldest NX was not rotated out.'
    Assert (@(Get-ChildItem -LiteralPath $output -Directory -Force).Count -eq 2) 'Extra generations accumulated.'
    $passed++

    foreach ($mode in 'fail', 'missing', 'invalid', 'change-source') {
        Set-Content -LiteralPath (Join-Path $caseRoot 'mode') -Value $mode
        Expect-Failure { Run-Conversion }
        Assert ((Current-Hash) -eq $third) "Failure '$mode' replaced current NX."
        Assert ((Get-FileHash -LiteralPath (Join-Path $output 'previous/Map.nx')).Hash -eq $second) "Failure '$mode' replaced previous NX."
        $passed++
    }
    Set-Content -LiteralPath (Join-Path $caseRoot 'mode') -Value 'ok'
    Set-Content -LiteralPath (Join-Path $source 'Map.wz') -Value 'version3'
    Run-Conversion
    Assert (-not (Test-Path -LiteralPath (Join-Path $output '.pending'))) 'Temporary output was not cleaned.'

    # Simulate termination after current moved, but before pending was promoted.
    Move-Item -LiteralPath (Join-Path $output 'previous') -Destination (Join-Path $output '.retired')
    Move-Item -LiteralPath (Join-Path $output 'current') -Destination (Join-Path $output 'previous')
    Set-Content -LiteralPath (Join-Path $caseRoot 'mode') -Value 'fail'
    Expect-Failure { Run-Conversion }
    Assert ((Current-Hash) -eq $third) 'Interrupted rotation did not restore current.'
    Assert ((Get-FileHash -LiteralPath (Join-Path $output 'previous/Map.nx')).Hash -eq $second) 'Interrupted rotation lost previous.'
    $passed++

    # Simulate termination after promotion, before retired output was removed.
    New-Item -ItemType Directory -Path (Join-Path $output '.retired') | Out-Null
    Expect-Failure { Run-Conversion }
    Assert (-not (Test-Path -LiteralPath (Join-Path $output '.retired'))) 'Committed rotation left obsolete output.'
    Assert ((Current-Hash) -eq $third) 'Committed rotation changed current during recovery.'
    $passed++

    $handle = [IO.File]::Open((Join-Path $output '.lock'), 'Open', 'ReadWrite', 'None')
    try { Expect-Failure { Run-Conversion } } finally { $handle.Dispose() }
    Assert ((Current-Hash) -eq $third) 'Concurrent invocation changed current.'
    $passed++

    New-Case 'protect-existing'
    New-Item -ItemType Directory -Path $output | Out-Null
    Set-Content -LiteralPath (Join-Path $output 'precious.wz') -Value 'keep'
    Expect-Failure { Run-Conversion }
    Assert ((Get-Content -LiteralPath (Join-Path $output 'precious.wz') -Raw).Trim() -eq 'keep') 'Unmanaged file was removed.'
    $passed++

    New-Case 'collision'
    Set-Content -LiteralPath (Join-Path $source 'Map.img') -Value 'collision'
    Expect-Failure { Run-Conversion }
    Assert (-not (Test-Path -LiteralPath (Join-Path $output 'current'))) 'Colliding inputs were promoted.'
    $passed++

    New-Case 'overlap'
    Expect-Failure { & $scriptPath -Source $source -Output (Join-Path $source 'nx') -ConverterPath $mock }
    Expect-Failure { & $scriptPath -Source $source -Output $caseRoot -ConverterPath $mock }
    Assert (Test-Path -LiteralPath (Join-Path $source 'Map.wz')) 'Overlapping output removed source.'
    $passed++

    New-Case 'protect-wz-in-output'
    Run-Conversion
    New-Item -ItemType Directory -Path (Join-Path $output '.pending') | Out-Null
    $precious = Join-Path $output '.pending/precious.wz'
    Set-Content -LiteralPath $precious -Value 'keep'
    Expect-Failure { Run-Conversion }
    Assert ((Get-Content -LiteralPath $precious -Raw).Trim() -eq 'keep') 'WZ in output was deleted.'
    $passed++

    New-Case 'reject-old-converter'
    @'
if ($args.Count -ne 1 -or $args[0] -ne '--output-version') {
    Set-Content -LiteralPath (Join-Path $PSScriptRoot 'unexpected-input') -Value 'bad'
}
Write-Output 'Old converter without output routing'
exit 0
'@ | Set-Content -LiteralPath $mock -Encoding UTF8
    Expect-Failure { Run-Conversion }
    Assert (-not (Test-Path -LiteralPath (Join-Path $caseRoot 'unexpected-input'))) 'Legacy converter received source inputs.'
    Assert (-not (Test-Path -LiteralPath $output)) 'Legacy converter initialized managed output.'
    $passed++

    Write-Host "PASS: $passed local-retention scenarios (mock converter; not a real WZ conversion)."
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force
}
