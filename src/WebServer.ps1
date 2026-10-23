# WebServer.ps1 - Servidor HTTP e API da Estação de Ingestão DIT
param(
    [int]$Port = 8080,
    [string]$PublicDir = (Join-Path $PSScriptRoot "public")
)

$enginePath = Join-Path $PSScriptRoot "IngestEngine.ps1"
$configPath = Join-Path $PSScriptRoot "ConfigManager.ps1"

if (Test-Path $enginePath) { . $enginePath }
if (Test-Path $configPath) { . $configPath }

# Estado Global da Estação
$script:StationState = "IDLE" # "IDLE" | "INGESTING" | "COMPLETED_EJECTED" | "ABORTED" | "ERROR"
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
        [Parameter(Mandatory=$false)][bool]$AutoEject = $true
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
    
    # Resolve destino (customizado por cartão ou padrão da estação)
    $resolvedDest = Get-DestinationForCard -CardIdentifier $script:ActiveCard -SourcePath $SourceDrive -Config $cfg
    
    try {
        $result = Invoke-CardIngest -SourceDrive $SourceDrive `
            -DestinationFolder $resolvedDest `
            -EventName $cfg.EventName `
            -AutoEject $shouldEject `
            -CancelCheck { $script:CancelRequested } `
            -ProgressCallback {
                param($p)
                $script:FilesDone = $p.CurrentIndex
                $script:TotalFiles = $p.TotalFiles
                $script:CurrentFile = $p.CurrentFile
                $script:BytesDone = $p.BytesCopied
                $script:TotalBytes = $p.TotalBytes
            }
        
        $historyItem = [PSCustomObject]@{
            Timestamp       = (Get-Date -Format "o")
            CardIdentifier  = $result.CardIdentifier
            CopiedCount     = $result.CopiedCount
            SkippedCount    = $result.SkippedCount
            BytesCopied     = $result.TotalBytesCopied
            Status          = $result.Status
            Ejected         = $result.Ejected
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

function Start-IngestHttpServer {
    param([int]$ListenPort = 8080)
    
    $listener = New-Object System.Net.HttpListener
    
    try {
        $listener.Prefixes.Add("http://+:$ListenPort/")
        $listener.Start()
        Write-Host "Servidor Web Ativo em: http://+:$ListenPort/ (Rede Local)" -ForegroundColor Green
        return $listener
    }
    catch {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://127.0.0.1:$ListenPort/")
        $listener.Prefixes.Add("http://localhost:$ListenPort/")
        $listener.Start()
        Write-Host "Servidor Web Ativo em: http://localhost:$ListenPort/" -ForegroundColor Yellow
        return $listener
    }
}

function Invoke-FolderPickerModal {
    param([string]$Title = "Selecione uma Pasta")
    
    $selected = ""
    $thread = [System.Threading.Thread]::new([System.Threading.ThreadStart]{
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = $Title
        $dialog.ShowNewFolderButton = $true
        
        $f = New-Object System.Windows.Forms.Form
        $f.TopMost = $true
        $f.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
        $f.Show()
        $f.BringToFront()
        
        if ($dialog.ShowDialog($f) -eq [System.Windows.Forms.DialogResult]::OK) {
            $selected = $dialog.SelectedPath
        }
        $f.Close()
        $f.Dispose()
        $dialog.Dispose()
    })
    $thread.SetApartmentState([System.Threading.ApartmentState]::STA)
    $thread.Start()
    $thread.Join()
    
    return $selected
}

function Handle-HttpRequest {
    param(
        [Parameter(Mandatory=$true)][System.Net.HttpListenerContext]$Context,
        [Parameter(Mandatory=$true)][string]$PublicFolder
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
            
            $payload = [ordered]@{
                State         = $script:StationState
                ActiveCard    = $script:ActiveCard
                FilesDone     = $script:FilesDone
                TotalFiles    = $script:TotalFiles
                BytesDone     = $script:BytesDone
                TotalBytes    = $script:TotalBytes
                CurrentFile   = $script:CurrentFile
                StatusMessage = $script:StatusMessage
                IsIngesting   = $script:IsProcessingIngest
                Config        = $cfg
                Drives        = @($drives)
            }
            
            $json = $payload | ConvertTo-Json -Depth 5
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
            foreach ($prop in $cfg.Keys) { $ht[$prop] = $cfg[$prop] }
            
            if ($updates.TargetRootPath) { $ht["TargetRootPath"] = $updates.TargetRootPath }
            if ($updates.EventName) { $ht["EventName"] = $updates.EventName }
            if ($null -ne $updates.SafeSpaceBufferGB) { $ht["SafeSpaceBufferGB"] = [int]$updates.SafeSpaceBufferGB }
            if ($null -ne $updates.BuzzerEnabled) { $ht["BuzzerEnabled"] = [bool]$updates.BuzzerEnabled }
            if ($null -ne $updates.AutoEject) { $ht["AutoEject"] = [bool]$updates.AutoEject }
            if ($null -ne $updates.CardMappings) { $ht["CardMappings"] = @($updates.CardMappings) }
            
            $saved = Set-StationConfig -Config $ht
            $json = $saved | ConvertTo-Json -Depth 4
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
        elseif ($path -eq "/api/manual-ingest" -and $request.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $payload = $body | ConvertFrom-Json
            
            if (!$payload.SourceDrive) {
                $errObj = @{ Error = "Drive ou pasta de origem nao especificado." }
                $errJson = $errObj | ConvertTo-Json
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errJson)
                $response.StatusCode = 400
                $response.ContentType = "application/json; charset=utf-8"
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
            elseif (!(Test-Path $payload.SourceDrive)) {
                $errObj = @{ Error = "O caminho especificado nao existe ou nao esta acessivel: $($payload.SourceDrive)" }
                $errJson = $errObj | ConvertTo-Json
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errJson)
                $response.StatusCode = 400
                $response.ContentType = "application/json; charset=utf-8"
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
            else {
                $script:PendingIngestQueue.Enqueue($payload.SourceDrive)
                
                $okBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Status":"INGEST_STARTED","Message":"Ingestao colocada na fila com sucesso"}')
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $okBytes.Length
                $response.OutputStream.Write($okBytes, 0, $okBytes.Length)
            }
        }
        else {
            $reqFile = if ($path -eq "/" -or [string]::IsNullOrWhiteSpace($path)) { "index.html" } else { $path.TrimStart("/") }
            $fullFilePath = [System.IO.Path]::Combine($PublicFolder, $reqFile)
            
            if (Test-Path $fullFilePath) {
                $bytes = [System.IO.File]::ReadAllBytes($fullFilePath)
                if ($fullFilePath.EndsWith(".html")) { $response.ContentType = "text/html; charset=utf-8" }
                elseif ($fullFilePath.EndsWith(".css")) { $response.ContentType = "text/css" }
                elseif ($fullFilePath.EndsWith(".js")) { $response.ContentType = "application/javascript" }
                elseif ($fullFilePath.EndsWith(".svg")) { $response.ContentType = "image/svg+xml" }
                
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $response.StatusCode = 404
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
        }
    }
    catch {
        $response.StatusCode = 500
        $errMsg = "500 Internal Error: $_"
        $errBytes = [System.Text.Encoding]::UTF8.GetBytes($errMsg)
        $response.ContentType = "text/plain; charset=utf-8"
        $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
    }
    finally {
        $response.Close()
    }
}
