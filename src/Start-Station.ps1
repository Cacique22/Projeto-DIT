<#
.SYNOPSIS
    Script principal de inicialização da Estação de Ingestão DIT.
    Inicia o Servidor Web e o Daemon de Detecção Automática de Cartões USB.
#>

$ErrorActionPreference = "Continue"

$enginePath = Join-Path $PSScriptRoot "IngestEngine.ps1"
$configPath = Join-Path $PSScriptRoot "ConfigManager.ps1"
$serverPath = Join-Path $PSScriptRoot "WebServer.ps1"

if (Test-Path $enginePath) { . $enginePath }
if (Test-Path $configPath) { . $configPath }
if (Test-Path $serverPath) { . $serverPath }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " ESTAÇÃO DE INGESTÃO AUTOMÁTICA DIT - INICIALIZANDO       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$cfg = Get-StationConfig
Write-Host "Destino Atual  : $($cfg.TargetRootPath)" -ForegroundColor White
Write-Host "Evento Atual   : $($cfg.EventName)" -ForegroundColor White
Write-Host "Porta Web      : $($cfg.Port)" -ForegroundColor White

# Inicia Servidor Web
$listener = Start-IngestHttpServer -ListenPort $cfg.Port

# Abre a interface no navegador padrão
$url = "http://localhost:$($cfg.Port)/"
Start-Process $url

Write-Host "`nPainel de controle aberto no navegador: $url" -ForegroundColor Green
Write-Host "Também acessível na rede local pelo IP desta máquina (Porta $($cfg.Port))." -ForegroundColor Gray
Write-Host "Pressione Ctrl+C para encerrar a estação.`n" -ForegroundColor DarkGray

# Inicia thread/loop de atendimento HTTP e monitoramento de cartões
$publicFolder = Join-Path $PSScriptRoot "public"

# Monitor de USB em background ou loop cooperativo
$knownDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
foreach ($d in $drives) { [void]$knownDrives.Add($d.Name) }

try {
    while ($listener.IsListening) {
        # Atendimento de requisições HTTP assíncronas / não bloqueantes
        $contextTask = $listener.GetContextAsync()
        
        while (-not $contextTask.IsCompleted) {
            # Durante a espera de requisições HTTP, verifica se novos discos foram plugados
            try {
                $currentReady = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
                $currentSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                
                foreach ($d in $currentReady) {
                    $driveName = $d.Name
                    [void]$currentSet.Add($driveName)
                    
                    if (-not $knownDrives.Contains($driveName)) {
                        Write-Host "`n[+] NOVO DISPOSITIVO DETECTADO: $driveName ($($d.VolumeLabel))" -ForegroundColor Cyan
                        Start-Sleep -Milliseconds 1500
                        
                        $isCandidate = $false
                        $dcim = Join-Path $driveName "DCIM"
                        $fotografoTxt = Join-Path $driveName "fotografo.txt"
                        $photos = Get-ChildItem -Path $driveName -File -ErrorAction SilentlyContinue | Where-Object {
                            $script:SUPPORTED_EXTENSIONS -contains $_.Extension.ToUpper()
                        }
                        
                        if ((Test-Path $dcim) -or (Test-Path $fotografoTxt) -or ($photos -and $photos.Count -gt 0)) {
                            Write-Host "[!] Cartão fotográfico reconhecido! Iniciando ingestão..." -ForegroundColor Green
                            [System.Threading.ThreadPool]::QueueUserWorkItem({
                                param($src)
                                Start-StationIngestProcess -SourceDrive $src
                            }, $driveName) | Out-Null
                        }
                        
                        [void]$knownDrives.Add($driveName)
                    }
                }
                
                # Dispositivos removidos
                $removed = [System.Collections.Generic.List[string]]::new()
                foreach ($k in $knownDrives) {
                    if (-not $currentSet.Contains($k)) { $removed.Add($k) }
                }
                foreach ($rem in $removed) {
                    Write-Host "[-] Dispositivo desconectado: $rem" -ForegroundColor Yellow
                    [void]$knownDrives.Remove($rem)
                }
            } catch {}
            
            # Pequena pausa para evitar 100% de CPU
            Start-Sleep -Milliseconds 250
        }
        
        $context = $contextTask.Result
        Handle-HttpRequest -Context $context -PublicFolder $publicFolder
    }
}
finally {
    if ($listener) {
        $listener.Stop()
        $listener.Close()
    }
}
