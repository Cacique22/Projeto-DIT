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
        AutoEject          = $true
        Port               = 8080
        CardMappings       = @()
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
            if ($null -ne $loaded.AutoEject) { $defaultConfig.AutoEject = [bool]$loaded.AutoEject }
            if ($loaded.Port) { $defaultConfig.Port = [int]$loaded.Port }
            if ($loaded.CardMappings) { $defaultConfig.CardMappings = @($loaded.CardMappings) }
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
    
    if ($Config.ContainsKey("CardMappings")) {
        $Config["CardMappings"] = @($Config["CardMappings"])
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

function Get-DestinationForCard {
    param(
        [Parameter(Mandatory=$true)][string]$CardIdentifier,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)]$Config
    )
    
    $driveRoot = [System.IO.Path]::GetPathRoot($SourcePath).TrimEnd('\')
    
    # 1. Checa se existe mapeamento customizado habilitado para este cartão ou letra de drive
    if ($Config.CardMappings) {
        foreach ($map in $Config.CardMappings) {
            $isEnabled = if ($null -ne $map.Enabled) { [bool]$map.Enabled } else { $true }
            if ($isEnabled -and !([string]::IsNullOrWhiteSpace($map.Identifier))) {
                if ($map.Identifier.Equals($CardIdentifier, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $map.Identifier.Equals($driveRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    
                    if (![string]::IsNullOrWhiteSpace($map.Destination)) {
                        return [System.IO.Path]::Combine($map.Destination, $Config.EventName, $CardIdentifier)
                    }
                }
            }
        }
    }
    
    # 2. Destino padrão da estação
    return [System.IO.Path]::Combine($Config.TargetRootPath, $Config.EventName, $CardIdentifier)
}

function Add-CardMappingRule {
    param(
        [Parameter(Mandatory=$true)][string]$Identifier,
        [Parameter(Mandatory=$true)][string]$Destination,
        [string]$Description = "",
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $list = [System.Collections.Generic.List[PSObject]]::new()
    
    if ($cfg.CardMappings) {
        foreach ($m in $cfg.CardMappings) {
            if (-not $m.Identifier.Equals($Identifier, [System.StringComparison]::OrdinalIgnoreCase)) {
                $list.Add($m)
            }
        }
    }
    
    $newRule = [PSCustomObject]@{
        Identifier  = $Identifier.Trim()
        Destination = $Destination.Trim()
        Description = $Description.Trim()
        Enabled     = $true
    }
    $list.Add($newRule)
    
    $ht = @{}
    foreach ($k in $cfg.Keys) { $ht[$k] = $cfg[$k] }
    $ht["CardMappings"] = $list.ToArray()
    
    Set-StationConfig -Config $ht -ConfigPath $ConfigPath | Out-Null
    return $newRule
}

function Remove-CardMappingRule {
    param(
        [Parameter(Mandatory=$true)][string]$Identifier,
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $list = [System.Collections.Generic.List[PSObject]]::new()
    
    if ($cfg.CardMappings) {
        foreach ($m in $cfg.CardMappings) {
            if (-not $m.Identifier.Equals($Identifier, [System.StringComparison]::OrdinalIgnoreCase)) {
                $list.Add($m)
            }
        }
    }
    
    $ht = @{}
    foreach ($k in $cfg.Keys) { $ht[$k] = $cfg[$k] }
    $ht["CardMappings"] = $list.ToArray()
    
    Set-StationConfig -Config $ht -ConfigPath $ConfigPath | Out-Null
    return $true
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
