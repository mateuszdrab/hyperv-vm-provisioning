param(
    [string]$UserName = "root",
    [string]$VMName = $null
)

if ($VMName -eq $null) {
    Write-Error "Please provide a VM name"
    exit
}

# Copy the GPU driver files to the VM
$TargetHost = (Get-VM -Name $VMName).NetworkAdapters[0].IPAddresses[0]

# Create a destination folder.
ssh ${UserName}@${TargetHost} "mkdir -p ~/wsl/drivers ~/wsl/lib"

# Copy driver files
# https://github.com/brokeDude2901/dxgkrnl_ubuntu/blob/main/README.md#3-copy-windows-host-gpu-driver-to-ubuntu-vm

(Get-CimInstance -ClassName Win32_VideoController -Property *).InstalledDisplayDrivers | Select-String "C:\\Windows\\System32\\DriverStore\\FileRepository\\[a-zA-Z0-9\\._]+\\" | foreach {
    $l = $_.Matches.Value.Substring(0, $_.Matches.Value.Length - 1)
    scp -r $l ${UserName}@${TargetHost}:~/wsl/drivers/
}

scp -r C:\Windows\System32\lxss\lib ${UserName}@${TargetHost}:~/wsl/
scp -r "C:\Program Files\WSL\lib" ${UserName}@${TargetHost}:~/wsl/

scp .\install-gpu.sh ${UserName}@${TargetHost}:/tmp/

ssh ${UserName}@${TargetHost} 'chmod +x /tmp/install-gpu.sh && /tmp/install-gpu.sh'