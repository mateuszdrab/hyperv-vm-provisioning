param(
    [string]$VMName = $null,
    [switch]$EnableGPU,
    [System.Collections.Hashtable] $VMCreationParams = @{},
    [string]$GpuInstallScriptArgs = "",
    [switch]$ShowVmConnectWindow,
    [switch]$SkipGPUDriverProvisioning,
    [switch]$WaitForVmCloudInit,
    [string]$VMCreationParamsDefaultFile = ".\VMCreationParamsDefault.json"
)

$VMCreationParamsDefault = @{}

# Auto load defaults from json file VMCreationParamsDefault.json
if (Test-Path $VMCreationParamsDefaultFile) {
    Write-Verbose "Loading default VM creation parameters from $VMCreationParamsDefaultFile"
    $VMCreationParamsDefault = Get-Content -Path $VMCreationParamsDefaultFile | ConvertFrom-Json
}
else {
    Write-Warning "No default VM creation parameters file found at $VMCreationParamsDefaultFile"
}

# Remove duplicate params from $VMCreationParamsDefault
$VMCreationParams.Keys | ForEach-Object {
    if ($VMCreationParamsDefault.ContainsKey($_)) {
        Write-Verbose "Removing duplicate parameter $_"
        $VMCreationParamsDefault.Remove($_)
    }
}

# Merge the default and provided parameters, with the provided parameters taking precedence
$VMCreationParams = $VMCreationParamsDefault + $VMCreationParams

# If VMName is provided, set it in the $VMCreationParams
if ($VMName) {
    $VMCreationParams.VMName = $VMName
}

# Set the VM name if not provided
if (!$VMCreationParams.ContainsKey("VMName")) {
    $VMCreationParams.VMName = "Ubuntu-$($VMCreationParams.ImageVersion.replace('.', ''))-$(get-random)"
    write-verbose "Setting VM name to '$($VMCreationParams.VMName)' as it was not provided"
}

# If the VM is to be GPU enabled
if ($EnableGPU) {
    Write-Verbose "GPU VM requested, disabling autostart"
    $VMCreationParams["AutoStart"] = $false
}

# ShowVmConnectWindow switch to VMCreationParams
if ($ShowVmConnectWindow) {
    $VMCreationParams["ShowVmConnectWindow"] = $true
}

$waitForVmReady = ($EnableGPU -and (-not $SkipGPUDriverProvisioning)) -or $WaitForVmCloudInit
$vmConnectDelay = $waitForVmReady -and $VMCreationParams["ShowVmConnectWindow"]

if ($vmConnectDelay) {
    Write-Verbose "Delaying VM connect window"
    $VMCreationParams.ShowVmConnectWindow = $false
}

$createdVmObject = .\New-HyperVCloudImageVM.ps1  @VMCreationParams

if ($EnableGPU) {
    Write-Verbose "Setting up GPU VM settings"
    # Enable VM features required for this to work
    $GPUVmParams = @{
        GuestControlledCacheTypes = $true
        LowMemoryMappedIoSpace    = 1Gb
        HighMemoryMappedIoSpace   = 32GB
        AutomaticStopAction       = 'ShutDown'
        # CheckpointType            = 'Disabled'
    }

    Set-VM @GPUVmParams -VMName $VMCreationParams.VMName

    # Add GPU-P adapter
    Write-Verbose "Adding GPU-P adapter"
    Add-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName

    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MinPartitionVRAM 1
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MaxPartitionVRAM 11
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -OptimalPartitionVRAM 10
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MinPartitionEncode 1
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MaxPartitionEncode 11
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -OptimalPartitionEncode 10
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MinPartitionDecode 1
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MaxPartitionDecode 11
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -OptimalPartitionDecode 10
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MinPartitionCompute 1
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -MaxPartitionCompute 11
    # Set-VMGpuPartitionAdapter -VMName $VMCreationParams.VMName -OptimalPartitionCompute 10

    # If not skipping GPU driver provisioning, start the VM
    if (-not $SkipGPUDriverProvisioning) {
        Write-Verbose "Starting VM"   
        Start-VM -VMName $VMCreationParams.VMName
    }
}

if ($waitForVmReady) {
    # Wait until the VM has an IP address
    Write-Verbose "Waiting to VM provisioning to complete"

    $startWaitTimestamp = Get-Date

    $cloudInitComplete = $false
    while (!$cloudInitComplete) {       
        $VMIP = (Get-VM -VMName $VMCreationParams.VMName).NetworkAdapters[0].IPAddresses[0]

        if (!$VMIP) {
            Write-Verbose "VM does not have an IP address yet, waited for $([uint32]((Get-Date) - $startWaitTimestamp).TotalSeconds) seconds"
            Start-Sleep -Seconds 30
            continue
        }
        else {
            write-verbose "VM IP: $VMIP"
        }

        $cloudInitStatus = ssh root@$VMIP cloud-init status --format json 
        Write-Verbose "Cloud-init status: $cloudInitStatus"
        $cloudInitComplete = (($cloudInitStatus | ConvertFrom-Json).Status -eq "disabled")
        write-verbose "Cloud-init complete: $cloudInitComplete, waited for $([uint32]((Get-Date) - $startWaitTimestamp).TotalSeconds) seconds"

        if (!$cloudInitComplete) {
            Write-Verbose "Waiting for cloud-init to complete"
            Start-Sleep -Seconds 30
            continue
        }

        [uint32]$uptime = 0
        $timeToWaitSeconds = 120

        # Checking VM uptime
        while ($uptime -lt $timeToWaitSeconds) {
            $uptime = (Get-VM -Name $VMCreationParams.VMName).Uptime.TotalSeconds
            Write-Verbose "VM uptime is $uptime seconds, waiting until it's at least $timeToWaitSeconds seconds"
            Start-Sleep -Seconds 30
        }

        Write-Verbose "VM uptime is $uptime seconds, waited for $([uint32]((Get-Date) - $startWaitTimestamp).TotalSeconds) seconds total"
    } 

    if ($vmConnectDelay) {
        $copyParams["ShowVmConnectWindow"] = $true        
    }
}

if ($EnableGPU -and (-not $SkipGPUDriverProvisioning)) {  
    # Copy the GPU driver files to the VM and install them
    $copyParams = @{
        VMName               = $VMCreationParams.VMName
        GpuInstallScriptArgs = $GpuInstallScriptArgs
    }

    .\Copy-HostGPUDriverToUbuntu.ps1 @copyParams
}

$createdVmObject