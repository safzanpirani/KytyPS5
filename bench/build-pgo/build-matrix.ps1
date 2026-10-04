# Machine-local experiment driver. All configure/build work stays inside the gate.
[CmdletBinding()]
param(
    [ValidateSet('dev','thin','v3','raptor','o3','whole','inline','sections','link')]
    [string]$Variant = 'dev',
    [ValidateRange(1,5)][int]$Jobs = 3
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path "$PSScriptRoot/../..").Path
$swarm = Split-Path $source
if (-not (Test-Path "$swarm/READY.txt")) { throw 'Wait for swarm READY.txt before building' }
. "$swarm/env.ps1"
$env:CCACHE_DIR = 'C:\astra\ccache'
$env:CCACHE_CONFIGPATH = 'C:\astra\ccache\ccache.conf'
$build = "$source/_build/pgo-$Variant"
$output = "$source/bench/build-pgo/runs/$Variant"
New-Item -ItemType Directory -Force $output | Out-Null
$options = @('-S',$source,'-B',$build,'-G','Ninja','-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_C_COMPILER=clang-cl','-DCMAKE_CXX_COMPILER=clang-cl',
    '-DCMAKE_C_COMPILER_LAUNCHER=ccache','-DCMAKE_CXX_COMPILER_LAUNCHER=ccache',
    '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON','-DKYTY_BUILD_LAUNCHER=OFF','-DBUILD_TESTING=ON',
    '-DCMAKE_JOB_POOLS=link_pool=1','-DCMAKE_JOB_POOL_LINK=link_pool',
    '-DCMAKE_EXE_LINKER_FLAGS=/threads:3 /time',
    '-DKYTY_PGO_GENERATE=OFF','-DKYTY_PGO_USE=','-DKYTY_CPU_TARGET=',
    '-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF')
foreach ($dep in 'opus','xbyak','zydis','zstd','zarchive_source') {
    $options += "-DFETCHCONTENT_SOURCE_DIR_$($dep.ToUpper())=C:/astra/kyty/build/baseline/_deps/$dep-src"
}
$options += '-DFFMPEG_PREBUILT_DIR=C:/astra/kyty/build/baseline/externals/ffmpeg-9ac4cfd195f1'
if ($Variant -in 'dev','link') { $options += '-DKYTY_ENABLE_LTO=OFF' }
else { $options += '-DKYTY_ENABLE_LTO=ON' }
switch ($Variant) {
    'v3' { $options += '-DKYTY_CPU_TARGET=x86-64-v3' }
    'raptor' { $options += '-DKYTY_CPU_TARGET=raptorlake' }
    'o3' {
        $options += '-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /clang:-O3'
        $options += '-DCMAKE_C_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /clang:-O3'
    }
    'whole' { $options += '-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /clang:-flto=thin /clang:-fwhole-program-vtables' }
    'inline' { $options += '-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /clang:-mllvm /clang:-inline-threshold=400' }
    'sections' {
        $options += '-DCMAKE_CXX_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /Gw /Gy'
        $options += '-DCMAKE_C_FLAGS_RELEASE=/O2 /Ob2 /DNDEBUG /Gw /Gy'
        $options += '-DCMAKE_EXE_LINKER_FLAGS=/threads:3 /time /OPT:REF,ICF'
    }
    'link' {
        $options += "-DCMAKE_LINKER=$((Get-Command link.exe).Source)"
        $options += '-DCMAKE_EXE_LINKER_FLAGS=/time'
    }
}
$targets = @('shader_recompiler_compute_tests','shader_cfg_tests','memory_tracker_tests',
    'page_manager_tests','archive_file_tests','ngs2_sampler_tests','resource_tracking_tests','kyty_emulator')
if ($Variant -eq 'link') { $targets = $targets | Where-Object { $_ -ne 'kyty_emulator' } }
& "$swarm/buildgate.ps1" -Label "build-pgo-$Variant" -Command {
    & cmake @options *> "$output/configure.log"
    if ($LASTEXITCODE -ne 0) { Get-Content "$output/configure.log" -Tail 60; throw 'Configure failed' }
    $command = @('cmake','--build',$build,'--parallel',"$Jobs",'--target') + $targets
    & python "$PSScriptRoot/monitor-build.py" --output $output @command
    if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
}
if ($LASTEXITCODE -ne 0) { throw "Gate failed: $LASTEXITCODE" }
Get-ChildItem $build -Filter '*.exe' | Select-Object Name,Length |
    ConvertTo-Json | Set-Content "$output/sizes.json"
