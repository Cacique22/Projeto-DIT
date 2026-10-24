# WebServer.ps1 - Servidor HTTP Local para Dashboard da Estação DIT

$cfgScript = Join-Path $PSScriptRoot "ConfigManager.ps1"
$engScript = Join-Path $PSScriptRoot "IngestEngine.ps1"
if (Test-Path $cfgScript) { . $cfgScript }
if (Test-Path $engScript) { . $engScript }

$script:StationState = "IDLE"
$script:ActiveCard = ""
$script:FilesDone = 0
$script:TotalFiles = 0
$script:BytesDone = [int64]0
$script:TotalBytes = [int64]0
$script:CurrentFile = ""
$script:StatusMessage = "Sistema Armado e Pronto"
$script:IngestHistory = [System.Collections.Generic.List[PSObject]]::new()
$script:IsProcessingIngest = $false
$script:PendingIngestQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:CancelRequested = $false

function Request-IngestCancellation {
    if ($script:IsProcessingIngest) {
        $script:CancelRequested = $true
        $script:StatusMessage = "Cancelamento solicitado. Finalizando com segurança..."
        Write-Host "[!] Solicitado cancelamento seguro da ingestão..." -ForegroundColor Yellow
        return $true
    }
    return $false
}

function Start-StationIngestProcess {
    param(
        [Parameter(Mandatory=$true)][string]$SourceDrive,
        [Parameter(Mandatory=$false)][bool]$AutoEject = $true,
        [string]$TargetFolderOverride = "",
        [string]$PhotoSubfolderOverride = "",
        [string]$PhotographerOverride = ""
    )
    
    if ($script:IsProcessingIngest) {
        Write-Warning "Ingestão já em andamento. Ignorando solicitação para $SourceDrive"
        return @{ Error = "Ingestão já em andamento" }
    }
    
    $script:IsProcessingIngest = $true
    $script:CancelRequested = $false
    $script:StationState = "INGESTING"
    $script:ActiveCard = Get-CardIdentifier -DriveLetter $SourceDrive
    $script:FilesDone = 0
    $script:TotalFiles = 0
    $script:BytesDone = [int64]0
    $script:TotalBytes = [int64]0
    $script:CurrentFile = "Analisando cartão..."
    $script:StatusMessage = "Processando $SourceDrive..."
    
    $cfg = Get-StationConfig
    $shouldEject = if ($null -ne $cfg.AutoEject) { [bool]$cfg.AutoEject } else { $true }
    $activeEvent = if (![string]::IsNullOrWhiteSpace($cfg.CurrentEvent)) { $cfg.CurrentEvent } else { $cfg.EventName }
    
    # 1. Se foi passado override de cadastro, registra o cartão imediatamente
    if (![string]::IsNullOrWhiteSpace($PhotographerOverride) -and ![string]::IsNullOrWhiteSpace($TargetFolderOverride)) {
        Register-CardForEvent -EventName $activeEvent `
            -CardIdentifier $script:ActiveCard `
            -Photographer $PhotographerOverride `
            -DestinationPath $TargetFolderOverride `
            -PhotoSubfolder $PhotoSubfolderOverride | Out-Null
    }
    
    # 2. Resolve destino e subpasta a partir do registro do cartão no evento
    $cardReg = Get-CardRegistration -EventName $activeEvent -CardIdentifier $script:ActiveCard -Config $cfg
    $resolvedDest = ""
    $resolvedSubfolder = ""
    
    if ($cardReg) {
        $resolvedDest = $cardReg.DestinationPath
        $resolvedSubfolder = $cardReg.PhotoSubfolder
    } elseif (![string]::IsNullOrWhiteSpace($TargetFolderOverride)) {
        $resolvedDest = $TargetFolderOverride
        $resolvedSubfolder = $PhotoSubfolderOverride
    } else {
        $resolvedDest = Get-DestinationForCard -CardIdentifier $script:ActiveCard -SourcePath $SourceDrive -Config $cfg -EventName $activeEvent
    }
    
    try {
        $result = Invoke-CardIngest -SourceDrive $SourceDrive `
            -DestinationFolder $resolvedDest `
            -EventName $activeEvent `
            -AutoEject $shouldEject `
            -CancelCheck { $script:CancelRequested } `
            -CardPhotoSubfolder $resolvedSubfolder `
            -ProgressCallback {
                param($p)
                $script:FilesDone = if ($null -ne $p.CurrentIndex) { $p.CurrentIndex } else { $p.FilesDone }
                $script:TotalFiles = $p.TotalFiles
                $script:BytesDone = $p.BytesCopied
                $script:TotalBytes = $p.TotalBytes
                $script:CurrentFile = $p.CurrentFile
                $script:StatusMessage = "$($p.CurrentFile) ($($script:FilesDone)/$($p.TotalFiles))"
            }
        
        $historyItem = [ordered]@{
            Timestamp      = [System.DateTime]::UtcNow.ToString("o")
            CardIdentifier = $result.CardIdentifier
            CopiedCount    = $result.CopiedCount
            SkippedCount   = $result.SkippedCount
            BytesCopied    = $result.TotalBytesCopied
            Duration       = $result.DurationSeconds
            Status         = $result.Status
            Destination    = $result.Destination
            Ejected        = $result.Ejected
            EventName      = $activeEvent
        }
        $script:IngestHistory.Insert(0, $historyItem)
        
        if ($result.Status -eq "ABORTED_BY_USER") {
            $script:StationState = "ABORTED"
            $script:StatusMessage = "Ingestão cancelada com segurança. Nenhum arquivo corrompido."
        }
        elseif ($result.Ejected) {
            $script:StationState = "COMPLETED_EJECTED"
            $script:StatusMessage = "Backup concluído! Cartão ejetado com segurança. Pode retirar."
        } else {
            $script:StationState = "IDLE"
            $script:StatusMessage = "Ingestão concluída com sucesso."
        }
        
        return $result
    }
    catch {
        $script:StationState = "ERROR"
        $script:StatusMessage = "Erro durante a ingestão: $_"
        Write-Host "Erro em Start-StationIngestProcess: $_" -ForegroundColor Red
        return @{ Error = $_.ToString() }
    }
    finally {
        $script:IsProcessingIngest = $false
        $script:CancelRequested = $false
        $script:CurrentFile = ""
    }
}

function Invoke-FolderPickerModal {
    param([string]$Title = "Selecione a Pasta")
    
    $selected = ""
    $scriptBlock = {
        param($modalTitle)
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $modalTitle
        $dialog.ShowNewFolderButton = $true
        
        $topForm = New-Object System.Windows.Forms.Form
        $topForm.TopMost = $true
        $topForm.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        
        $res = $dialog.ShowDialog($topForm)
        if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
            return $dialog.SelectedPath
        }
        return ""
    }
    
    try {
        $powerShellCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command `"$scriptBlock`" -modalTitle `"$Title`""
        $selected = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -Command $scriptBlock -modalTitle $Title
        if ($selected) {
            $selected = $selected.Trim()
        }
    }
    catch {
        Write-Host "Aviso ao abrir seletor: $_" -ForegroundColor DarkGray
    }
    
    return $selected
}

function Start-IngestHttpServer {
    param(
        [int]$ListenPort = 8080
    )
    
    $listener = New-Object System.Net.HttpListener
    $prefix = "http://*:$ListenPort/"
    
    try {
        $listener.Prefixes.Add($prefix)
        $listener.Start()
        Write-Host "Servidor Web iniciado em $prefix" -ForegroundColor Green
    }
    catch {
        $prefixLocal = "http://localhost:$ListenPort/"
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add($prefixLocal)
        $listener.Start()
        Write-Host "Servidor Web iniciado (modo local) em $prefixLocal" -ForegroundColor Green
    }
    
    return $listener
}

function Handle-HttpRequest {
    param(
        [Parameter(Mandatory=$true)]$Context,
        [string]$PublicFolder = ""
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    $response.AddHeader("Access-Control-Allow-Origin", "*")
    $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
    $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")
    
    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.Close()
        return
    }
    
    $path = $request.Url.AbsolutePath
    
    try {
        if ($path -eq "/api/status") {
            $cfg = Get-StationConfig
            $drives = @(Get-AvailableDrivesInfo)
            $isMonitoring = Get-MonitoringState
            $events = @(Get-StationEvents)
            $curCards = @(Get-EventCards -EventName $cfg.CurrentEvent)
            
            $statusObj = [ordered]@{
                State             = $script:StationState
                ActiveCard        = $script:ActiveCard
                FilesDone         = $script:FilesDone
                TotalFiles        = $script:TotalFiles
                BytesDone         = $script:BytesDone
                TotalBytes        = $script:TotalBytes
                CurrentFile       = $script:CurrentFile
                StatusMessage     = $script:StatusMessage
                IsIngesting       = $script:IsProcessingIngest
                MonitoringActive  = $isMonitoring
                CurrentEvent      = $cfg.CurrentEvent
                Events            = $events
                RegisteredCards   = $curCards
                Config            = $cfg
                Drives            = $drives
            }
            $json = $statusObj | ConvertTo-Json -Depth 5
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/events" -and $request.HttpMethod -eq "GET") {
            $events = @(Get-StationEvents)
            $cfg = Get-StationConfig
            $resObj = [ordered]@{
                CurrentEvent = $cfg.CurrentEvent
                Events       = $events
            }
            $json = $resObj | ConvertTo-Json -Depth 4
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/events" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $payload = $body | ConvertFrom-Json
            
            if ($payload.Name) {
                $created = New-StationEvent -EventName $payload.Name -DefaultDestination ($payload.Destination)
                $json = $created | ConvertTo-Json -Depth 3
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"O campo Name é obrigatório"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
        elseif ($path -eq "/api/events/select" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $payload = $body | ConvertFrom-Json
            
            if ($payload.Name) {
                Set-CurrentEvent -EventName $payload.Name | Out-Null
                $resObj = @{ Success = $true; CurrentEvent = $payload.Name }
                $json = $resObj | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"O campo Name é obrigatório"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
        elseif ($path -eq "/api/monitoring" -and $request.HttpMethod -eq "GET") {
            $active = Get-MonitoringState
            $json = @{ Active = $active } | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif (($path -eq "/api/monitoring/toggle" -or $path -eq "/api/monitoring") -and $request.HttpMethod -eq "POST") {
            $currentState = Get-MonitoringState
            $newState = -not $currentState
            
            # Checa se o usuário enviou um estado explícito no corpo
            if ($request.HasEntityBody) {
                try {
                    $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                    $body = $reader.ReadToEnd()
                    $payload = $body | ConvertFrom-Json
                    if ($null -ne $payload.Active) {
                        $newState = [bool]$payload.Active
                    }
                } catch {}
            }
            
            Set-MonitoringState -Active $newState | Out-Null
            $json = @{ Active = $newState; Message = if ($newState) { "Monitoramento ativado" } else { "Monitoramento pausado" } } | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/cancel" -and $request.HttpMethod -eq "POST") {
            $ok = Request-IngestCancellation
            $resObj = @{ Cancelled = $ok; Message = if ($ok) { "Cancelamento solicitado com sucesso" } else { "Nenhuma ingestão em andamento" } }
            $json = $resObj | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/cards" -and $request.HttpMethod -eq "GET") {
            $cfg = Get-StationConfig
            $evName = if ($request.QueryString["event"]) { $request.QueryString["event"] } else { $cfg.CurrentEvent }
            $cards = @(Get-EventCards -EventName $evName)
            $json = $cards | ConvertTo-Json -Depth 3
            if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }
            elseif (-not $json.Trim().StartsWith("[")) { $json = "[$json]" }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/card/detect" -and $request.HttpMethod -eq "GET") {
            $drive = $request.QueryString["drive"]
            if ([string]::IsNullOrWhiteSpace($drive)) {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Parâmetro drive ausente"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
                $response.Close()
                return
            }
            
            $cfg = Get-StationConfig
            $cardId = Get-CardIdentifier -DriveLetter $drive
            $folders = @(Get-CardPhotoFolders -DriveRoot $drive)
            $cardReg = Get-CardRegistration -EventName $cfg.CurrentEvent -CardIdentifier $cardId -Config $cfg
            $photogs = @(Get-EventPhotographers -EventName $cfg.CurrentEvent)
            
            $resObj = [ordered]@{
                DriveRoot            = $drive
                CardIdentifier       = $cardId
                IsRegistered         = ($null -ne $cardReg)
                Registration         = $cardReg
                PhotoFolders         = $folders
                ExistingPhotographers= $photogs
                SuggestedDestination = [System.IO.Path]::Combine($cfg.TargetRootPath, $cfg.CurrentEvent)
            }
            $json = $resObj | ConvertTo-Json -Depth 4
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/card" -and ($request.HttpMethod -eq "DELETE" -or ($request.HttpMethod -eq "POST" -and $request.QueryString["action"] -eq "delete"))) {
            $cfg = Get-StationConfig
            $evName = if ($request.QueryString["event"]) { $request.QueryString["event"] } else { $cfg.CurrentEvent }
            $id = $request.QueryString["id"]
            if ([string]::IsNullOrWhiteSpace($id) -and $request.HasEntityBody) {
                try {
                    $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
                    $payload = $reader.ReadToEnd() | ConvertFrom-Json
                    if ($payload.CardIdentifier) { $id = $payload.CardIdentifier }
                    if ($payload.EventName) { $evName = $payload.EventName }
                } catch {}
            }
            if ($id) {
                $removed = Remove-CardRegistration -EventName $evName -CardIdentifier $id
                $json = @{ Success = $removed; CardIdentifier = $id } | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Parametro id ou CardIdentifier obrigatorio"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
        elseif ($path -eq "/api/event/destination" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $payload = $reader.ReadToEnd() | ConvertFrom-Json
            $cfg = Get-StationConfig
            $evName = if ($payload.EventName) { $payload.EventName } else { $cfg.CurrentEvent }
            if ($payload.Destination) {
                $newDest = Set-EventDestination -EventName $evName -NewDestination $payload.Destination -UpdateRegisteredCards $true
                $json = @{ Success = $true; Destination = $newDest } | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Campo Destination obrigatorio"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
        elseif ($path -eq "/api/card/register" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $payload = $body | ConvertFrom-Json
            
            $cfg = Get-StationConfig
            $evName = if ($payload.EventName) { $payload.EventName } else { $cfg.CurrentEvent }
            
            if ($payload.CardIdentifier -and $payload.Photographer -and $payload.DestinationPath) {
                $saved = Register-CardForEvent -EventName $evName `
                    -CardIdentifier $payload.CardIdentifier `
                    -Photographer $payload.Photographer `
                    -DestinationPath $payload.DestinationPath `
                    -PhotoSubfolder ($payload.PhotoSubfolder)
                
                $json = $saved | ConvertTo-Json -Depth 3
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"CardIdentifier, Photographer e DestinationPath são obrigatórios"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
        elseif ($path -eq "/api/photographers" -and $request.HttpMethod -eq "GET") {
            $cfg = Get-StationConfig
            $evName = if ($request.QueryString["event"]) { $request.QueryString["event"] } else { $cfg.CurrentEvent }
            $list = @(Get-EventPhotographers -EventName $evName)
            $json = $list | ConvertTo-Json
            if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }
            elseif (-not $json.Trim().StartsWith("[")) { $json = "[$json]" }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/mappings" -and $request.HttpMethod -eq "GET") {
            $cfg = Get-StationConfig
            $mappings = if ($cfg.CardMappings) { @($cfg.CardMappings) } else { @() }
            $json = $mappings | ConvertTo-Json -Depth 3
            if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }
            elseif (-not $json.Trim().StartsWith("[")) { $json = "[$json]" }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/mappings" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $payload = $body | ConvertFrom-Json
            
            if ($payload.Identifier -and $payload.Destination) {
                $savedRule = Add-CardMappingRule -Identifier $payload.Identifier -Destination $payload.Destination -Description ($payload.Description)
                $json = $savedRule | ConvertTo-Json
                $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Identifier e Destination sao obrigatorios"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
        elseif ($path -eq "/api/mappings" -and $request.HttpMethod -eq "DELETE") {
            $ident = $request.QueryString["identifier"]
            if ($ident) {
                Remove-CardMappingRule -Identifier $ident | Out-Null
                $buffer = [System.Text.Encoding]::UTF8.GetBytes('{"Status":"DELETED"}')
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $buffer.Length
                $response.OutputStream.Write($buffer, 0, $buffer.Length)
            } else {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Parâmetro identifier ausente"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
        elseif ($path -eq "/api/drives") {
            $drives = @(Get-AvailableDrivesInfo)
            $json = $drives | ConvertTo-Json -Depth 3
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/browse-folder") {
            $title = if ($request.QueryString["type"] -eq "source") { 
                "Selecione o Cartao ou Pasta de Fotos (Origem)" 
            } else { 
                "Selecione a Pasta onde deseja Salvar os Backups" 
            }
            
            $picked = Invoke-FolderPickerModal -Title $title
            
            $resPayload = @{ SelectedPath = $picked }
            $json = $resPayload | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/config" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $updates = $body | ConvertFrom-Json
            
            $cfg = Get-StationConfig
            $ht = @{}
            foreach ($k in $cfg.Keys) { $ht[$k] = $cfg[$k] }
            
            if ($null -ne $updates.TargetRootPath) { $ht["TargetRootPath"] = $updates.TargetRootPath.ToString() }
            if ($null -ne $updates.EventName) { 
                $ht["EventName"] = $updates.EventName.ToString() 
                $ht["CurrentEvent"] = $updates.EventName.ToString() 
            }
            if ($null -ne $updates.CurrentEvent) { 
                $ht["CurrentEvent"] = $updates.CurrentEvent.ToString() 
                $ht["EventName"] = $updates.CurrentEvent.ToString() 
            }
            if ($null -ne $updates.SafeSpaceBufferGB) { $ht["SafeSpaceBufferGB"] = [int]$updates.SafeSpaceBufferGB }
            if ($null -ne $updates.BuzzerEnabled) { $ht["BuzzerEnabled"] = [bool]$updates.BuzzerEnabled }
            if ($null -ne $updates.AutoEject) { $ht["AutoEject"] = [bool]$updates.AutoEject }
            if ($null -ne $updates.MonitoringActive) { $ht["MonitoringActive"] = [bool]$updates.MonitoringActive }
            if ($null -ne $updates.CardMappings) { $ht["CardMappings"] = @($updates.CardMappings) }
            
            $saved = Set-StationConfig -Config $ht
            $json = $saved | ConvertTo-Json -Depth 5
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/manual-ingest" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $payload = $body | ConvertFrom-Json
            
            if ($null -eq $payload -or [string]::IsNullOrWhiteSpace($payload.SourceDrive)) {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Campo SourceDrive obrigatorio"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
                $response.Close()
                return
            }
            
            if (!(Test-Path $payload.SourceDrive)) {
                $response.StatusCode = 400
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Caminho de origem nao encontrado"}')
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
                $response.Close()
                return
            }
            
            [System.Threading.ThreadPool]::QueueUserWorkItem({
                param($src)
                Start-StationIngestProcess -SourceDrive $src
            }, $payload.SourceDrive) | Out-Null
            
            $resObj = @{ Status = "ENQUEUED"; Message = "Ingestao manual enfileirada para $($payload.SourceDrive)" }
            $json = $resObj | ConvertTo-Json
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/history") {
            $json = $script:IngestHistory | ConvertTo-Json -Depth 3
            if ([string]::IsNullOrWhiteSpace($json)) { $json = "[]" }
            elseif (-not $json.Trim().StartsWith("[")) { $json = "[$json]" }
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/beep" -and $request.HttpMethod -eq "POST") {
            Emit-IngestSound -Type "Success"
            $buffer = [System.Text.Encoding]::UTF8.GetBytes('{"Status":"OK"}')
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        else {
            # Servir arquivos estáticos (Dashboard Web)
            $reqFile = if ($path -eq "/" -or [string]::IsNullOrWhiteSpace($path)) { "index.html" } else { $path.TrimStart('/') }
            $localFile = [System.IO.Path]::Combine($PublicFolder, $reqFile)
            
            if (Test-Path $localFile) {
                $bytes = [System.IO.File]::ReadAllBytes($localFile)
                $ext = [System.IO.Path]::GetExtension($localFile).ToLower()
                switch ($ext) {
                    ".html" { $response.ContentType = "text/html; charset=utf-8" }
                    ".css"  { $response.ContentType = "text/css; charset=utf-8" }
                    ".js"   { $response.ContentType = "application/javascript; charset=utf-8" }
                    ".png"  { $response.ContentType = "image/png" }
                    default { $response.ContentType = "application/octet-stream" }
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $response.StatusCode = 404
                $err = [System.Text.Encoding]::UTF8.GetBytes("404 Nao Encontrado")
                $response.OutputStream.Write($err, 0, $err.Length)
            }
        }
    }
    catch {
        $response.StatusCode = 500
        $errMsg = @{ Error = $_.ToString() } | ConvertTo-Json
        $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
        $response.ContentType = "application/json; charset=utf-8"
        try { $response.OutputStream.Write($errBytes, 0, $errBytes.Length) } catch {}
    }
    finally {
        try { $response.Close() } catch {}
    }
}
