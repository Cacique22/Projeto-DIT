# ConfigManager.ps1 - Gerenciador de Configurações da Estação de Ingestão DIT

$script:DefaultConfigFile = [System.IO.Path]::Combine((Split-Path -Parent $PSScriptRoot), "config.json")

function Get-DefaultTargetDirectory {
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { 
        $_.IsReady -and ($_.DriveType -eq 'Fixed' -or $_.DriveType -eq 'Removable') -and $_.Name -ne 'C:\' 
    } | Sort-Object AvailableFreeSpace -Descending
    
    if ($drives -and $drives.Count -gt 0) {
        return [System.IO.Path]::Combine($drives[0].RootDirectory.FullName, "Backups_Eventos")
    }
    
    return "C:\Backups_Eventos"
}

function Get-StationConfig {
    param(
        [Parameter(Mandatory=$false)][string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $defaultConfig = [ordered]@{
        TargetRootPath     = (Get-DefaultTargetDirectory)
        EventName          = "Evento_" + (Get-Date -Format "yyyy-MM-dd")
        SafeSpaceBufferGB  = 10
        BuzzerEnabled      = $true
        Port               = 8080
        LastUpdated        = (Get-Date -Format "o")
    }
    
    if (Test-Path $ConfigPath) {
        try {
            $rawJson = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
            $loaded = $rawJson | ConvertFrom-Json
            
            if ($loaded.TargetRootPath) { $defaultConfig.TargetRootPath = $loaded.TargetRootPath }
            if ($loaded.EventName) { $defaultConfig.EventName = $loaded.EventName }
            if ($null -ne $loaded.SafeSpaceBufferGB) { $defaultConfig.SafeSpaceBufferGB = [int]$loaded.SafeSpaceBufferGB }
            if ($null -ne $loaded.BuzzerEnabled) { $defaultConfig.BuzzerEnabled = [bool]$loaded.BuzzerEnabled }
            if ($loaded.Port) { $defaultConfig.Port = [int]$loaded.Port }
            if ($loaded.LastUpdated) { $defaultConfig.LastUpdated = $loaded.LastUpdated }
            
            return $defaultConfig
        } catch {
            Write-Warning "Falha ao ler $ConfigPath. Recriando configuração padrão..."
        }
    }
    
    Set-StationConfig -Config $defaultConfig -ConfigPath $ConfigPath
    return $defaultConfig
}

function Set-StationConfig {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Config,
        [Parameter(Mandatory=$false)][string]$ConfigPath = $script:DefaultConfigFile
    )
    
    if ($Config.ContainsKey("EventName")) {
        $cleanEvent = $Config["EventName"] -replace '[\\/:*?"<>|]', '_'
        if ([string]::IsNullOrWhiteSpace($cleanEvent)) {
            $cleanEvent = "Evento_" + (Get-Date -Format "yyyy-MM-dd")
        }
        $Config["EventName"] = $cleanEvent
    }
    
    if ($Config.ContainsKey("TargetRootPath")) {
        $dest = $Config["TargetRootPath"].Trim()
        if ([string]::IsNullOrWhiteSpace($dest)) {
            $dest = Get-DefaultTargetDirectory
        }
        $Config["TargetRootPath"] = $dest
        if (!(Test-Path $dest)) {
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
        }
    }
    
    $Config["LastUpdated"] = (Get-Date -Format "o")
    
    $dir = Split-Path -Parent $ConfigPath
    if ($dir -and !(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    $jsonContent = $Config | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($ConfigPath, $jsonContent, [System.Text.Encoding]::UTF8)
    
    return $Config
}

function Get-AvailableDrivesInfo {
    $drivesList = [System.Collections.Generic.List[PSObject]]::new()
    
    $drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
    foreach ($d in $drives) {
        $totalGb = [math]::Round($d.TotalSize / 1GB, 1)
        $freeGb = [math]::Round($d.AvailableFreeSpace / 1GB, 1)
        $usedGb = [math]::Round(($d.TotalSize - $d.AvailableFreeSpace) / 1GB, 1)
        $percentFree = [math]::Round(($d.AvailableFreeSpace / $d.TotalSize) * 100, 1)
        
        $label = if ([string]::IsNullOrWhiteSpace($d.VolumeLabel)) { "Disco Local" } else { $d.VolumeLabel }
        
        $drivesList.Add([PSCustomObject]@{
            RootDirectory = $d.RootDirectory.FullName
            DriveLetter   = $d.Name.TrimEnd("\")
            Label         = $label
            DriveType     = $d.DriveType.ToString()
            TotalGB       = $totalGb
            FreeGB        = $freeGb
            UsedGB        = $usedGb
            PercentFree   = $percentFree
            IsSystem      = ($d.Name -eq "C:\")
        })
    }
    
    return ,$drivesList.ToArray()
}
