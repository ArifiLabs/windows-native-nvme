# Switch ONE NVMe controller to Windows' native NVMe stack (nvmedisk.sys) through storport's per-controller setting.
# Run in an elevated PowerShell 7. Nothing changes until you reboot.
#   List controllers : pwsh -File enable-native-nvme.ps1 -List
#   Status           : pwsh -File enable-native-nvme.ps1 -Status -Match 'VEN_1E4B&DEV_1602'
#   Enable           : pwsh -File enable-native-nvme.ps1 -Match 'VEN_1E4B&DEV_1602'
#   Undo             : pwsh -File enable-native-nvme.ps1 -Undo -Match 'VEN_1E4B&DEV_1602'
param([string]$Match, [switch]$List, [switch]$Status, [switch]$Undo, [switch]$AllowBootDisk)
$ErrorActionPreference = 'Stop'
$svc = 'HKLM:\SYSTEM\CurrentControlSet\Services\nvmedisk'

function Controllers { Get-PnpDevice -PresentOnly -Class SCSIAdapter | Where-Object { $_.InstanceId -like 'PCI\*' -and $_.FriendlyName -match 'NVM' } }
function DisksBehind($ctlId) {
    @(Get-CimInstance Win32_DiskDrive | Where-Object {
        (Get-PnpDeviceProperty -InstanceId $_.PNPDeviceID -KeyName DEVPKEY_Device_Parent).Data -eq $ctlId })
}
function KeyOf($ctlId) { "HKLM:\SYSTEM\CurrentControlSet\Enum\$ctlId\Device Parameters\StorPort" }
function Show {
    foreach ($c in Controllers) {
        $v = (Get-ItemProperty (KeyOf $c.InstanceId) -ErrorAction SilentlyContinue).EnableNativeNVMeUserSetting
        $d = DisksBehind $c.InstanceId | ForEach-Object { $g = Get-Disk -Number $_.Index; "$($g.FriendlyName)$(if ($g.IsBoot -or $g.IsSystem) { ' [BOOT/SYSTEM]' })" }
        '{0} | setting={1} | disks: {2}' -f ($c.InstanceId -split '\\')[1], $(if ($null -ne $v) { $v } else { 'unset' }), ($d -join ', ')
    }
    "nvmedisk service Start = $((Get-ItemProperty $svc).Start)  (0 = boot start, the stock value)"
    foreach ($cls in 'DiskDrive', 'NvmeDisk') {
        Get-PnpDevice -PresentOnly -Class $cls -ErrorAction SilentlyContinue | ForEach-Object {
            $s = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_Service).Data
            '  {0,-28} class={1,-9} driver={2}' -f $_.FriendlyName, $_.Class, $s
        }
    }
    $inc = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\StorPort' -ErrorAction SilentlyContinue
    if ($inc.IncompatibleFilterCount) { "WARNING: storport found $($inc.IncompatibleFilterCount) incompatible disk filter driver(s); native mode stays off." }
}

if ($List -or (-not $Match)) { Show; if (-not $Match) { "`nPass -Match with the VEN_xxxx&DEV_xxxx of the controller you want." }; exit 0 }
$ctl = @(Controllers | Where-Object InstanceId -like "PCI\$Match*")
if ($ctl.Count -ne 1) { throw "Expected exactly one NVMe controller matching '$Match', found $($ctl.Count). Use -List." }
$key = KeyOf $ctl[0].InstanceId
if ($Status) { Show; exit 0 }
if ($Undo) {
    Remove-ItemProperty -Path $key -Name EnableNativeNVMeUserSetting -ErrorAction SilentlyContinue
    "Removed the setting from $($ctl[0].InstanceId). Reboot to return it to stornvme + disk.sys."; exit 0
}
foreach ($d in DisksBehind $ctl[0].InstanceId) {
    $g = Get-Disk -Number $d.Index
    if (($g.IsBoot -or $g.IsSystem) -and -not $AllowBootDisk) {
        throw "Disk $($d.Index) ($($g.FriendlyName)) behind this controller is your boot/system disk. Test on a data drive first; pass -AllowBootDisk only with a recovery plan (see README)."
    }
}
if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
New-ItemProperty -Path $key -Name EnableNativeNVMeUserSetting -PropertyType DWord -Value 1 -Force | Out-Null
$start = (Get-ItemProperty $svc).Start
if ($start -ne 0) { Set-ItemProperty $svc -Name Start -Value 0 -Type DWord; "nvmedisk Start $start -> 0 (stock boot-start value)." }
"Enabled on $($ctl[0].InstanceId). Reboot, then run -Status: the disk should show class=NvmeDisk driver=nvmedisk."
