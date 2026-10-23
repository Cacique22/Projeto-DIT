# WebServer.ps1 - Servidor HTTP e API da Estação de Ingestão DIT
param(
    [int]$Port = 8080,
    [string]$PublicDir = (Join-Path $PSScriptRoot "public")
)

$enginePath = Join-Path $PSScriptRoot "IngestEngine.ps1"
$configPath = Join-Path $PSScriptRoot "ConfigManager.ps1"

if (Test-Path $enginePath) { . $enginePath }
if (Test-Path $configPath) { . $configPath }

# Estado Global em Memória
$script:StationState = "IDLE"
$script:ActiveCard = ""
$script:FilesDone = 0
$script:TotalFiles = 0
$script:BytesDone = [int64]0
$script:TotalBytes = [int64]0
$script:CurrentFile = ""
$script:IngestHistory = [System.Collections.Generic.List[PSObject]]::new()
$script:IsProcessingIngest = $false

function Start-StationIngestProcess {
    param(
        [Parameter(Mandatory=$true)][string]$SourceDrive
    )
    
    if ($script:IsProcessingIngest) {
        Write-Warning "Ingestão já em andamento. Ignorando solicitação duplicada para $SourceDrive"
        return @{ Error = "Ingestão já em andamento" }
    }
    
    $script:IsProcessingIngest = $true
    $script:StationState = "INGESTING"
    $script:ActiveCard = Get-CardIdentifier -DriveLetter $SourceDrive
    $script:FilesDone = 0
    $script:TotalFiles = 0
    $script:BytesDone = [int64]0
    $script:TotalBytes = [int64]0
    $script:CurrentFile = "Iniciando análise do cartão..."
    
    $cfg = Get-StationConfig
    
    try {
        $result = Invoke-CardIngest -SourceDrive $SourceDrive `
            -DestinationFolder $cfg.TargetRootPath `
            -EventName $cfg.EventName `
            -ProgressCallback {
                param($p)
                $script:FilesDone = $p.CurrentIndex
                $script:TotalFiles = $p.TotalFiles
                $script:CurrentFile = $p.CurrentFile
                $script:BytesDone = $p.BytesCopied
                $script:TotalBytes = $p.TotalBytes
            }
        
        # Registra no histórico da sessão
        $historyItem = [PSCustomObject]@{
            Timestamp       = (Get-Date -Format "o")
            CardIdentifier  = $result.CardIdentifier
            CopiedCount     = $result.CopiedCount
            SkippedCount    = $result.SkippedCount
            BytesCopied     = $result.TotalBytesCopied
            Status          = $result.Status
        }
        $script:IngestHistory.Insert(0, $historyItem)
        return $result
    }
    finally {
        $script:StationState = "IDLE"
        $script:IsProcessingIngest = $false
        $script:CurrentFile = ""
    }
}

function Start-IngestHttpServer {
    param([int]$ListenPort = 8080)
    
    $listener = New-Object System.Net.HttpListener
    
    # Tenta bind global (+). Se não for admin, usa localhost
    $prefixAdded = $false
    try {
        $listener.Prefixes.Add("http://+:$ListenPort/")
        $listener.Start()
        $prefixAdded = $true
        Write-Host "Servidor Web Ativo em: http://+:$ListenPort/ (Acessível na rede local)" -ForegroundColor Green
    }
    catch {
        $listener = New-Object System.Net.HttpListener
        $listener.Prefixes.Add("http://localhost:$ListenPort/")
        $listener.Start()
        Write-Host "Servidor Web Ativo em: http://localhost:$ListenPort/" -ForegroundColor Yellow
    }
    
    return $listener
}

function Handle-HttpRequest {
    param(
        [Parameter(Mandatory=$true)][System.Net.HttpListenerContext]$Context,
        [Parameter(Mandatory=$true)][string]$PublicFolder
    )
    
    $request = $Context.Request
    $response = $Context.Response
    
    # Habilita CORS para facilidade de testes e integrações
    $response.AddHeader("Access-Control-Allow-Origin", "*")
    $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")
    
    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.Close()
        return
    }
    
    $path = $request.Url.AbsolutePath
    
    try {
        # Rotas da API
        if ($path -eq "/api/status") {
            $cfg = Get-StationConfig
            $drives = @(Get-AvailableDrivesInfo)
            
            $payload = [ordered]@{
                State       = $script:StationState
                ActiveCard  = $script:ActiveCard
                FilesDone   = $script:FilesDone
                TotalFiles  = $script:TotalFiles
                BytesDone   = $script:BytesDone
                TotalBytes  = $script:TotalBytes
                CurrentFile = $script:CurrentFile
                Config      = $cfg
                Drives      = @($drives)
            }
            
            $json = $payload | ConvertTo-Json -Depth 5
            $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
            $response.ContentType = "application/json; charset=utf-8"
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
        elseif ($path -eq "/api/drives") {
            $drives = @(Get-AvailableDrivesInfo)
            $json = $drives | ConvertTo-Json -Depth 3
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
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Error":"Drive de origem não especificado"}')
                $response.StatusCode = 400
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            } else {
                # Executa a ingestão em background ou thread separada
                [System.Threading.ThreadPool]::QueueUserWorkItem({
                    param($src)
                    Start-StationIngestProcess -SourceDrive $src
                }, $payload.SourceDrive) | Out-Null
                
                $okBytes = [System.Text.Encoding]::UTF8.GetBytes('{"Status":"INGEST_STARTED"}')
                $response.ContentType = "application/json; charset=utf-8"
                $response.ContentLength64 = $okBytes.Length
                $response.OutputStream.Write($okBytes, 0, $okBytes.Length)
            }
        }
        else {
            # Arquivos estáticos
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
        $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
    }
    finally {
        $response.Close()
    }
}
