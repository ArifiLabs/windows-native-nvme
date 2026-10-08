# DiskSpd tests behind every number in the README. Needs DiskSpd (winget install Microsoft.DiskSpd).
# Read tests run on -Target (any large existing file, never modified). Write tests run on a separate scratch file
# that this script creates on the same drive (-Scratch) and deletes at the end.
#   pwsh -File bench.ps1 -Target 'E:\models\big.gguf' -Out .\before -Rounds 2
#   pwsh -File bench.ps1 -Target 'C:\bench\read.dat' -Out .\before -Rounds 2 -CreateTargetGB 32
param([Parameter(Mandatory)][string]$Target, [string]$Out = '.\bench-out', [int]$Rounds = 2,
      [int]$CreateTargetGB = 0, [string]$Scratch, [switch]$NoWrites)
New-Item -ItemType Directory -Force $Out | Out-Null
if ($CreateTargetGB -and -not (Test-Path $Target)) { & diskspd "-c$($CreateTargetGB)G" -w100 -b1M -o8 -t1 -si -d1 -Sh $Target | Out-Null }
if (-not $Scratch) { $Scratch = Join-Path (Split-Path $Target -Qualifier) 'diskspd-scratch.dat' }
$reads = [ordered]@{
    'rand-4M-qd8-full'    = @('-b4M', '-o8', '-t1', '-r')
    'rand-4M-qd8-span8G'  = @('-b4M', '-o8', '-t1', '-r', '-f8G')
    'rand-4M-qd8-span1G'  = @('-b4M', '-o8', '-t1', '-r', '-f1G')
    'rand-4K-qd32x4-full' = @('-b4K', '-o32', '-t4', '-r')
    'rand-4K-qd1-full'    = @('-b4K', '-o1', '-t1', '-r')
    'seq-1M-qd8'          = @('-b1M', '-o8', '-t1', '-si')
    'rand-128K-qd8'       = @('-b128K', '-o8', '-t1', '-r')
}
$writes = [ordered]@{
    'write-seq-1M-qd8'      = @('-b1M', '-o8', '-t1', '-si')
    'write-rand-4K-qd32x4'  = @('-b4K', '-o32', '-t4', '-r')
}
function Run($name, $a, $file, $w, $r) {
    $f = Join-Path $Out "$name-r$r.txt"
    & diskspd @($a + @("-w$w", '-Sh', '-d20')) $file > $f
    $t = Get-Content $f
    $tot = (($t | Select-String '^total:' | Select-Object -First 1).Line) -split '\|'
    $cpu = (($t | Select-String '^\s*avg\.' | Select-Object -First 1).Line) -split '\|'
    '{0,-22} r{1}  MiB/s {2,9}  IOPS {3,10}  CPU {4}' -f $name, $r, $tot[2].Trim(), $tot[3].Trim(), $cpu[1].Trim()
}
if (-not $NoWrites) { & diskspd -c16G -w100 -b1M -o8 -t1 -si -d1 -Sh $Scratch | Out-Null }
foreach ($r in 1..$Rounds) {
    foreach ($n in $reads.Keys) { Run $n $reads[$n] $Target 0 $r }
    if (-not $NoWrites) { foreach ($n in $writes.Keys) { Run $n $writes[$n] $Scratch 100 $r } }
}
if (-not $NoWrites) { Remove-Item $Scratch -ErrorAction SilentlyContinue }
