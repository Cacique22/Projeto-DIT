# ConfigManager.ps1 - Gerenciador de Configurações e Eventos da Estação de Ingestão DIT

$script:DefaultConfigFile = [System.IO.Path]::Combine((Split-Path -Parent $PSScriptRoot), "config.json")

function Convert-PSObjectToHashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject }
    
    $ht = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $val = $prop.Value
        if ($val -is [PSCustomObject]) {
            $ht[$prop.Name] = Convert-PSObjectToHashtable -InputObject $val
        } else {
            $ht[$prop.Name] = $val
        }
    }
    return $ht
}

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
    
    $defaultEventName = "Evento_" + (Get-Date -Format "yyyy-MM-dd")
    $defaultTarget = Get-DefaultTargetDirectory
    
    $defaultConfig = [ordered]@{
        TargetRootPath     = $defaultTarget
        EventName          = $defaultEventName
        CurrentEvent       = $defaultEventName
        SafeSpaceBufferGB  = 10
        BuzzerEnabled      = $true
        AutoEject          = $true
        MonitoringActive   = $true
        Port               = 8080
        Events             = @{}
        CardMappings       = @()
        LastUpdated        = (Get-Date -Format "o")
    }
    
    if (Test-Path $ConfigPath) {
        try {
            $rawJson = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
            $loaded = $rawJson | ConvertFrom-Json
            
            if ($loaded.TargetRootPath) { $defaultConfig.TargetRootPath = $loaded.TargetRootPath }
            if ($loaded.EventName) { $defaultConfig.EventName = $loaded.EventName }
            if ($loaded.CurrentEvent) { $defaultConfig.CurrentEvent = $loaded.CurrentEvent }
            else { $defaultConfig.CurrentEvent = $defaultConfig.EventName }
            
            if ($null -ne $loaded.SafeSpaceBufferGB) { $defaultConfig.SafeSpaceBufferGB = [int]$loaded.SafeSpaceBufferGB }
            if ($null -ne $loaded.BuzzerEnabled) { $defaultConfig.BuzzerEnabled = [bool]$loaded.BuzzerEnabled }
            if ($null -ne $loaded.AutoEject) { $defaultConfig.AutoEject = [bool]$loaded.AutoEject }
            if ($null -ne $loaded.MonitoringActive) { $defaultConfig.MonitoringActive = [bool]$loaded.MonitoringActive }
            if ($loaded.Port) { $defaultConfig.Port = [int]$loaded.Port }
            
            if ($loaded.Events) {
                $defaultConfig.Events = Convert-PSObjectToHashtable -InputObject $loaded.Events
            }
            if ($loaded.CardMappings) { $defaultConfig.CardMappings = @($loaded.CardMappings) }
            if ($loaded.LastUpdated) { $defaultConfig.LastUpdated = $loaded.LastUpdated }
            
            # Garante que o evento atual esteja inicializado no dicionário de Eventos
            $curName = $defaultConfig.CurrentEvent
            if (-not $defaultConfig.Events.ContainsKey($curName)) {
                $defaultConfig.Events[$curName] = @{
                    Name               = $curName
                    CreatedAt          = (Get-Date -Format "o")
                    DefaultDestination = [System.IO.Path]::Combine($defaultConfig.TargetRootPath, $curName)
                    Cards              = @{}
                }
            }
            
            return $defaultConfig
        } catch {
            Write-Warning "Falha ao ler $ConfigPath. Recriando configuração padrão..."
        }
    }
    
    # Inicializa primeiro evento padrão
    $defaultConfig.Events[$defaultEventName] = @{
        Name               = $defaultEventName
        CreatedAt          = (Get-Date -Format "o")
        DefaultDestination = [System.IO.Path]::Combine($defaultTarget, $defaultEventName)
        Cards              = @{}
    }
    
    Set-StationConfig -Config $defaultConfig -ConfigPath $ConfigPath
    return $defaultConfig
}

function Set-StationConfig {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Config,
        [Parameter(Mandatory=$false)][string]$ConfigPath = $script:DefaultConfigFile
    )
    
    if ($Config.ContainsKey("CurrentEvent")) {
        $cleanEvent = $Config["CurrentEvent"] -replace '[\\/:*?"<>|]', '_'
        if ([string]::IsNullOrWhiteSpace($cleanEvent)) {
            $cleanEvent = "Evento_" + (Get-Date -Format "yyyy-MM-dd")
        }
        $Config["CurrentEvent"] = $cleanEvent
        $Config["EventName"] = $cleanEvent
    }
    elseif ($Config.ContainsKey("EventName")) {
        $cleanEvent = $Config["EventName"] -replace '[\\/:*?"<>|]', '_'
        if ([string]::IsNullOrWhiteSpace($cleanEvent)) {
            $cleanEvent = "Evento_" + (Get-Date -Format "yyyy-MM-dd")
        }
        $Config["EventName"] = $cleanEvent
        $Config["CurrentEvent"] = $cleanEvent
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
    
    if ($null -eq $Config["Events"]) {
        $Config["Events"] = @{}
    }
    
    if ($Config.ContainsKey("CardMappings")) {
        $Config["CardMappings"] = @($Config["CardMappings"])
    }
    
    $Config["LastUpdated"] = (Get-Date -Format "o")
    
    $dir = Split-Path -Parent $ConfigPath
    if ($dir -and !(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    $jsonContent = $Config | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($ConfigPath, $jsonContent, [System.Text.Encoding]::UTF8)
    
    return $Config
}

# -----------------------------------------------------------------------------
# GERENCIAMENTO DE EVENTOS
# -----------------------------------------------------------------------------

function Get-StationEvents {
    param([string]$ConfigPath = $script:DefaultConfigFile)
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $eventsList = [System.Collections.Generic.List[PSObject]]::new()
    
    if ($cfg.Events) {
        foreach ($k in $cfg.Events.Keys) {
            $ev = $cfg.Events[$k]
            $evName = if ($ev["Name"]) { $ev["Name"] } else { $k }
            $createdAt = if ($ev["CreatedAt"]) { $ev["CreatedAt"] } else { "" }
            $defaultDest = if ($ev["DefaultDestination"]) { $ev["DefaultDestination"] } else { "" }
            
            $cardsCount = 0
            $photographersSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            
            if ($ev["Cards"]) {
                $cardsCount = $ev["Cards"].Keys.Count
                foreach ($cKey in $ev["Cards"].Keys) {
                    $cardObj = $ev["Cards"][$cKey]
                    if ($cardObj["Photographer"]) {
                        [void]$photographersSet.Add($cardObj["Photographer"])
                    }
                }
            }
            
            $eventsList.Add([PSCustomObject]@{
                Name               = $evName
                CreatedAt          = $createdAt
                DefaultDestination = $defaultDest
                CardCount          = $cardsCount
                Photographers      = @($photographersSet)
                IsCurrent          = ($evName -eq $cfg.CurrentEvent)
            })
        }
    }
    
    return @($eventsList | Sort-Object CreatedAt -Descending)
}

function New-StationEvent {
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [string]$DefaultDestination = "",
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cleanName = $EventName -replace '[\\/:*?"<>|]', '_'
    if ([string]::IsNullOrWhiteSpace($cleanName)) {
        throw "Nome de evento inválido."
    }
    
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $dest = if (![string]::IsNullOrWhiteSpace($DefaultDestination)) {
        $DefaultDestination.Trim()
    } else {
        [System.IO.Path]::Combine($cfg.TargetRootPath, $cleanName)
    }
    
    if (!(Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
    }
    
    $evObj = @{
        Name               = $cleanName
        CreatedAt          = (Get-Date -Format "o")
        DefaultDestination = $dest
        Cards              = @{}
    }
    
    $ht = @{}
    foreach ($k in $cfg.Keys) { $ht[$k] = $cfg[$k] }
    $ht.Events[$cleanName] = $evObj
    $ht["CurrentEvent"] = $cleanName
    $ht["EventName"] = $cleanName
    
    Set-StationConfig -Config $ht -ConfigPath $ConfigPath | Out-Null
    
    return [PSCustomObject]@{
        Name               = $cleanName
        CreatedAt          = $evObj.CreatedAt
        DefaultDestination = $dest
        CardCount          = 0
        Photographers      = @()
        IsCurrent          = $true
    }
}

function Set-CurrentEvent {
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cleanName = $EventName -replace '[\\/:*?"<>|]', '_'
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    
    $ht = @{}
    foreach ($k in $cfg.Keys) { $ht[$k] = $cfg[$k] }
    
    if (-not $ht.Events.ContainsKey($cleanName)) {
        $dest = [System.IO.Path]::Combine($cfg.TargetRootPath, $cleanName)
        $ht.Events[$cleanName] = @{
            Name               = $cleanName
            CreatedAt          = (Get-Date -Format "o")
            DefaultDestination = $dest
            Cards              = @{}
        }
    }
    
    $ht["CurrentEvent"] = $cleanName
    $ht["EventName"] = $cleanName
    
    Set-StationConfig -Config $ht -ConfigPath $ConfigPath | Out-Null
    return $cleanName
}

function Get-CurrentEvent {
    param([string]$ConfigPath = $script:DefaultConfigFile)
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $curName = $cfg.CurrentEvent
    if ($cfg.Events -and $cfg.Events.ContainsKey($curName)) {
        $ev = $cfg.Events[$curName]
        return [PSCustomObject]@{
            Name               = $curName
            CreatedAt          = $ev["CreatedAt"]
            DefaultDestination = $ev["DefaultDestination"]
            Cards              = $ev["Cards"]
        }
    }
    return [PSCustomObject]@{
        Name               = $curName
        CreatedAt          = (Get-Date -Format "o")
        DefaultDestination = [System.IO.Path]::Combine($cfg.TargetRootPath, $curName)
        Cards              = @{}
    }
}

# -----------------------------------------------------------------------------
# CADASTRO E MAPEAMENTO DE CARTÕES POR EVENTO
# -----------------------------------------------------------------------------

function Get-EventCards {
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $cardsList = [System.Collections.Generic.List[PSObject]]::new()
    
    if ($cfg.Events -and $cfg.Events.ContainsKey($EventName)) {
        $ev = $cfg.Events[$EventName]
        if ($ev["Cards"]) {
            foreach ($k in $ev["Cards"].Keys) {
                $c = $ev["Cards"][$k]
                $cardsList.Add([PSCustomObject]@{
                    CardIdentifier  = $c["CardIdentifier"]
                    Photographer    = $c["Photographer"]
                    DestinationPath = $c["DestinationPath"]
                    PhotoSubfolder  = if ($c["PhotoSubfolder"]) { $c["PhotoSubfolder"] } else { "" }
                    RegisteredAt    = if ($c["RegisteredAt"]) { $c["RegisteredAt"] } else { "" }
                })
            }
        }
    }
    
    return @($cardsList)
}

function Get-CardRegistration {
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [Parameter(Mandatory=$true)][string]$CardIdentifier,
        $Config = $null,
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cfg = if ($null -ne $Config) { $Config } else { Get-StationConfig -ConfigPath $ConfigPath }
    
    if ($cfg.Events) {
        $evObj = $null
        if ($cfg.Events -is [System.Collections.IDictionary] -and $cfg.Events.ContainsKey($EventName)) {
            $evObj = $cfg.Events[$EventName]
        } elseif ($cfg.Events.PSObject -and $cfg.Events.PSObject.Properties[$EventName]) {
            $evObj = $cfg.Events.PSObject.Properties[$EventName].Value
        }
        
        if ($evObj) {
            $cards = if ($evObj -is [System.Collections.IDictionary]) { $evObj["Cards"] } else { $evObj.Cards }
            if ($cards) {
                $c = $null
                if ($cards -is [System.Collections.IDictionary] -and $cards.ContainsKey($CardIdentifier)) {
                    $c = $cards[$CardIdentifier]
                } elseif ($cards.PSObject -and $cards.PSObject.Properties[$CardIdentifier]) {
                    $c = $cards.PSObject.Properties[$CardIdentifier].Value
                }
                
                if ($c) {
                    $ident = if ($c["CardIdentifier"]) { $c["CardIdentifier"] } else { $c.CardIdentifier }
                    $photog = if ($c["Photographer"]) { $c["Photographer"] } else { $c.Photographer }
                    $dest = if ($c["DestinationPath"]) { $c["DestinationPath"] } else { $c.DestinationPath }
                    $subf = if ($c["PhotoSubfolder"]) { $c["PhotoSubfolder"] } else { $c.PhotoSubfolder }
                    $regAt = if ($c["RegisteredAt"]) { $c["RegisteredAt"] } else { $c.RegisteredAt }
                    
                    return [PSCustomObject]@{
                        CardIdentifier  = $ident
                        Photographer    = $photog
                        DestinationPath = $dest
                        PhotoSubfolder  = if ($subf) { $subf } else { "" }
                        RegisteredAt    = if ($regAt) { $regAt } else { "" }
                    }
                }
            }
        }
    }
    
    return $null
}

function Register-CardForEvent {
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [Parameter(Mandatory=$true)][string]$CardIdentifier,
        [Parameter(Mandatory=$true)][string]$Photographer,
        [Parameter(Mandatory=$true)][string]$DestinationPath,
        [string]$PhotoSubfolder = "",
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $cleanIdent = $CardIdentifier.Trim()
    $cleanPhotog = $Photographer.Trim()
    $cleanDest = $DestinationPath.Trim()
    $cleanSubf = $PhotoSubfolder.Trim()
    
    if (!(Test-Path $cleanDest)) {
        New-Item -ItemType Directory -Path $cleanDest -Force | Out-Null
    }
    
    $ht = @{}
    foreach ($k in $cfg.Keys) { $ht[$k] = $cfg[$k] }
    
    if (-not $ht.Events.ContainsKey($EventName)) {
        $ht.Events[$EventName] = @{
            Name               = $EventName
            CreatedAt          = (Get-Date -Format "o")
            DefaultDestination = [System.IO.Path]::Combine($cfg.TargetRootPath, $EventName)
            Cards              = @{}
        }
    }
    
    if (-not $ht.Events[$EventName].ContainsKey("Cards") -or $null -eq $ht.Events[$EventName]["Cards"]) {
        $ht.Events[$EventName]["Cards"] = @{}
    }
    
    $cardEntry = @{
        CardIdentifier  = $cleanIdent
        Photographer    = $cleanPhotog
        DestinationPath = $cleanDest
        PhotoSubfolder  = $cleanSubf
        RegisteredAt    = (Get-Date -Format "o")
    }
    
    $ht.Events[$EventName]["Cards"][$cleanIdent] = $cardEntry
    
    Set-StationConfig -Config $ht -ConfigPath $ConfigPath | Out-Null
    
    return [PSCustomObject]@{
        CardIdentifier  = $cleanIdent
        Photographer    = $cleanPhotog
        DestinationPath = $cleanDest
        PhotoSubfolder  = $cleanSubf
        RegisteredAt    = $cardEntry.RegisteredAt
    }
}

function Get-EventPhotographers {
    param(
        [Parameter(Mandatory=$true)][string]$EventName,
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    
    $cards = Get-EventCards -EventName $EventName -ConfigPath $ConfigPath
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($c in $cards) {
        if (![string]::IsNullOrWhiteSpace($c.Photographer)) {
            [void]$set.Add($c.Photographer.Trim())
        }
    }
    return @($set)
}

function Get-CardPhotoFolders {
    param([Parameter(Mandatory=$true)][string]$DriveRoot)
    
    $cleanRoot = $DriveRoot.TrimEnd('\') + '\'
    $candidates = [System.Collections.Generic.List[string]]::new()
    
    if (Test-Path $cleanRoot) {
        # 1. Procura subpastas dentro de DCIM (padrão Canon, Nikon, Sony, Fuji)
        $dcim = Join-Path $cleanRoot "DCIM"
        if (Test-Path $dcim) {
            $sub = Get-ChildItem -Path $dcim -Directory -ErrorAction SilentlyContinue
            foreach ($s in $sub) {
                $candidates.Add("DCIM\" + $s.Name)
            }
            if ($candidates.Count -eq 0) {
                $candidates.Add("DCIM")
            }
        }
        
        # 2. Procura padrão Sony Video (PRIVATE\M4ROOT\CLIP)
        $sonyClip = Join-Path $cleanRoot "PRIVATE\M4ROOT\CLIP"
        if (Test-Path $sonyClip) {
            $candidates.Add("PRIVATE\M4ROOT\CLIP")
        }
        
        # 3. Procura outras pastas no 1º nível que contenham fotos/vídeos
        $topDirs = Get-ChildItem -Path $cleanRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("DCIM", "MISC", "PRIVATE") }
        foreach ($td in $topDirs) {
            $hasMedia = Get-ChildItem -Path $td.FullName -File -ErrorAction SilentlyContinue | Where-Object {
                $script:SUPPORTED_EXTENSIONS -contains $_.Extension.ToUpper()
            }
            if ($hasMedia -and $hasMedia.Count -gt 0) {
                $candidates.Add($td.Name)
            }
        }
    }
    
    # 4. Raiz do cartão como opção
    $candidates.Add("\ (Raiz do Cartão)")
    
    return $candidates.ToArray()
}

# -----------------------------------------------------------------------------
# ESTADO DE MONITORAMENTO (ATIVO / PAUSADO)
# -----------------------------------------------------------------------------

function Get-MonitoringState {
    param([string]$ConfigPath = $script:DefaultConfigFile)
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    if ($null -ne $cfg.MonitoringActive) {
        return [bool]$cfg.MonitoringActive
    }
    return $true
}

function Set-MonitoringState {
    param(
        [Parameter(Mandatory=$true)][bool]$Active,
        [string]$ConfigPath = $script:DefaultConfigFile
    )
    $cfg = Get-StationConfig -ConfigPath $ConfigPath
    $ht = @{}
    foreach ($k in $cfg.Keys) { $ht[$k] = $cfg[$k] }
    $ht["MonitoringActive"] = $Active
    Set-StationConfig -Config $ht -ConfigPath $ConfigPath | Out-Null
    return $Active
}

# -----------------------------------------------------------------------------
# RESOLUÇÃO DE DESTINO (COM SUPORTE A EVENTO E CARTÕES REGISTRADOS)
# -----------------------------------------------------------------------------

function Get-DestinationForCard {
    param(
        [Parameter(Mandatory=$true)][string]$CardIdentifier,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)]$Config,
        [string]$EventName = ""
    )
    
    $activeEvent = if (![string]::IsNullOrWhiteSpace($EventName)) { $EventName } else { $Config.EventName }
    
    # 1. Checa cadastro específico do cartão no evento ativo
    $cardReg = Get-CardRegistration -EventName $activeEvent -CardIdentifier $CardIdentifier -Config $Config
    if ($cardReg -and ![string]::IsNullOrWhiteSpace($cardReg.DestinationPath)) {
        return $cardReg.DestinationPath
    }
    
    # 2. Checa regras legadas de CardMappings (para retrocompatibilidade)
    $driveRoot = [System.IO.Path]::GetPathRoot($SourcePath).TrimEnd('\')
    if ($Config.CardMappings) {
        foreach ($map in $Config.CardMappings) {
            $isEnabled = if ($null -ne $map.Enabled) { [bool]$map.Enabled } else { $true }
            if ($isEnabled -and !([string]::IsNullOrWhiteSpace($map.Identifier))) {
                if ($map.Identifier.Equals($CardIdentifier, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $map.Identifier.Equals($driveRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    
                    if (![string]::IsNullOrWhiteSpace($map.Destination)) {
                        return [System.IO.Path]::Combine($map.Destination, $activeEvent, $CardIdentifier)
                    }
                }
            }
        }
    }
    
    # 3. Destino padrão da estação: [DestinoRoot]\[Evento]\[Identificador]
    return [System.IO.Path]::Combine($Config.TargetRootPath, $activeEvent, $CardIdentifier)
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
