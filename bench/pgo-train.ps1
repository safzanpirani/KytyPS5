<#
Train LLVM PGO on CPU-only synthetic workloads, then build the profile-use tree.
Run from an x64 clang-cl developer shell. Example on the swarm machine:
  . C:\astra\kyty-swarm\env.ps1
  ./bench/pgo-train.ps1 -CMakeArgs @('-DKYTY_ENABLE_LTO=ON')
Additional dependency/cache options can be supplied through -CMakeArgs.
The shared gate is mandatory here; pass -BuildGate on another machine.
#>
[CmdletBinding()]
param(
    [string]$BuildDirectory = "$PSScriptRoot/../_build/pgo",
    [string]$BuildGate = "$PSScriptRoot/../../buildgate.ps1",
    [string[]]$CMakeArgs = @(),
    [ValidateRange(1,10)][int]$Jobs = 3,
    [ValidateRange(1,100)][int]$TrainingRuns = 5
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path "$PSScriptRoot/..").Path
$build = [IO.Path]::GetFullPath($BuildDirectory)
if (-not (Test-Path -LiteralPath $BuildGate)) { throw "Build gate missing: $BuildGate" }
# A unique directory prevents stale profiles from previous source revisions.
$profiles = Join-Path $build ('profiles/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force $profiles | Out-Null
$profile = Join-Path $profiles 'kyty.profdata'
$targets = @('shader_recompiler_compute_tests','memory_tracker_tests','archive_file_tests',
    'page_manager_tests','ngs2_sampler_tests','resource_tracking_tests','shader_cfg_tests','kyty_emulator')
function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit $LASTEXITCODE" }
}
& $BuildGate -Label build-pgo-train -Command {
    $options = @('-S',$source,'-B',$build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',
        '-DCMAKE_C_COMPILER=clang-cl','-DCMAKE_CXX_COMPILER=clang-cl',
        '-DKYTY_BUILD_LAUNCHER=OFF','-DBUILD_TESTING=ON',
        '-DCMAKE_JOB_POOLS=kyty_pgo_link=1','-DCMAKE_JOB_POOL_LINK=kyty_pgo_link') + $CMakeArgs
    Run cmake ($options + @('-DKYTY_PGO_GENERATE=ON','-DKYTY_PGO_USE='))
    Run cmake (@('--build',$build,'--parallel',"$Jobs",'--target') + $targets)
    # Match llvm-profdata to the configured compiler, even if PATH differs.
    $compilerLine = Get-Content "$build/CMakeCache.txt" |
        Where-Object { $_ -match '^CMAKE_CXX_COMPILER:FILEPATH=' } | Select-Object -First 1
    if (-not $compilerLine) { throw 'Configured C++ compiler was not found in CMakeCache.txt' }
    $profdata = Join-Path (Split-Path ($compilerLine -split '=',2)[1]) 'llvm-profdata.exe'
    if (-not (Test-Path -LiteralPath $profdata)) { throw "Missing matching tool: $profdata" }
    $oldProfile = $env:LLVM_PROFILE_FILE
    Push-Location $profiles
    try {
        $env:LLVM_PROFILE_FILE = Join-Path $profiles '%m-%p.profraw'
        for ($run = 0; $run -lt $TrainingRuns; ++$run) {
            Run "$build/shader_recompiler_compute_tests.exe" @('--benchmark-shader-train')
            Run "$build/memory_tracker_tests.exe" @('--benchmark-clean-upload')
            Run "$build/archive_file_tests.exe" @()
        }
    } finally {
        Pop-Location
        $env:LLVM_PROFILE_FILE = $oldProfile
    }
    $raw = @(Get-ChildItem -LiteralPath $profiles -Filter '*.profraw' | ForEach-Object FullName)
    if (-not $raw.Count) { throw 'Training produced no LLVM profiles' }
    Run $profdata (@('merge','-o',$profile) + $raw)
    Run $profdata @('show',$profile)
    Run cmake ($options + @('-DKYTY_PGO_GENERATE=OFF',"-DKYTY_PGO_USE=$profile"))
    Run cmake (@('--build',$build,'--parallel',"$Jobs",'--target') + $targets)
    # Held-out workloads never execute while instrumentation is enabled.
    Run "$build/shader_recompiler_compute_tests.exe" @('--benchmark-shader-holdout')
    Run ctest @('--test-dir',$build,'--output-on-failure','--timeout','180','-j1',
        '-R','^(memory_tracker|page_manager|archive_file|ngs2_sampler|resource_tracking|shader_cfg)$')
}
if ($LASTEXITCODE -ne 0) { throw "PGO workflow failed: $LASTEXITCODE" }
Write-Host "Profile-use binaries: $build"
Write-Host "Training profile: $profile"
