param([string]$BuildGate = "$PSScriptRoot/../../../buildgate.ps1")
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path "$PSScriptRoot/../../tests/perf/build-pgo").Path
$build = [IO.Path]::GetFullPath("$PSScriptRoot/../../_build/pgo-smoke")
$profiles = "$build/profile with spaces"
New-Item -ItemType Directory -Force $profiles | Out-Null
function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed: $LASTEXITCODE" }
}
& $BuildGate -Label build-pgo-smoke -Command {
    $options = @('-S',$source,'-B',$build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',
        '-DCMAKE_C_COMPILER=clang-cl','-DCMAKE_CXX_COMPILER=clang-cl',
        '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON')
    Run cmake ($options + @('-DKYTY_ENABLE_LTO=OFF','-DKYTY_PGO_GENERATE=OFF','-DKYTY_PGO_USE='))
    Run cmake @('--build',$build,'--parallel','3')
    Run "$build/smoke.exe" @()
    if ((Get-Content "$build/compile_commands.json" -Raw) -match 'flto|fprofile|march=') {
        throw 'Default configuration added optimization flags'
    }
    Run cmake ($options + @('-DKYTY_ENABLE_LTO=ON','-DKYTY_PGO_GENERATE=ON'))
    Run cmake @('--build',$build,'--parallel','3')
    $oldProfile = $env:LLVM_PROFILE_FILE
    try {
        $env:LLVM_PROFILE_FILE = "$profiles/smoke-%p.profraw"
        Run "$build/smoke.exe" @()
    } finally { $env:LLVM_PROFILE_FILE = $oldProfile }
    $raw = @(Get-ChildItem $profiles -Filter '*.profraw' | ForEach-Object FullName)
    if (-not $raw.Count) { throw 'No profiling data was written' }
    Run llvm-profdata (@('merge','-o',"$profiles/smoke.profdata") + $raw)
    Run cmake ($options + @('-DKYTY_PGO_GENERATE=OFF',"-DKYTY_PGO_USE=$profiles/smoke.profdata"))
    Run cmake @('--build',$build,'--parallel','3')
    Run "$build/smoke.exe" @()
    (Get-Item "$profiles/smoke.profdata").LastWriteTime = Get-Date
    $rebuild = & cmake --build $build --parallel 3 2>&1
    if ($LASTEXITCODE -ne 0 -or ($rebuild -join "`n") -notmatch 'library.cpp.obj' -or
        ($rebuild -join "`n") -notmatch 'main.cpp.obj') { throw 'Replacing a profile did not rebuild both objects' }
    $rebuild
    & cmake @options '-DKYTY_PGO_GENERATE=ON' 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { throw 'Conflicting PGO options were accepted' }
    Run cmake ($options + @('-DKYTY_PGO_GENERATE=OFF','-DKYTY_PGO_USE='))
    Write-Host 'Optimization smoke checks passed (defaults, ThinLTO, PGO, spaces, profile invalidation, conflicting options)'
}
if ($LASTEXITCODE -ne 0) { throw "Smoke verification failed: $LASTEXITCODE" }
