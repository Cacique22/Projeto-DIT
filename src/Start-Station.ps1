<#
.SYNOPSIS
    Script principal de inicialização da Estação de Ingestão DIT.
    Inicia o Servidor Web, o Daemon de Detecção e Ejeção Automática de Cartões.
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
Write-Host "Auto-Ejeção    : $(if ($cfg.AutoEject) { 'ATIVADA (Ejeta ao concluir)' } else { 'DESATIVADA' })" -ForegroundColor Green

# Inicia Servidor Web
$listener = Start-IngestHttpServer -ListenPort $cfg.Port

$url = "http://localhost:$($cfg.Port)/"
Start-Process $url

Write-Host "`n[✓] Painel de controle aberto no navegador: $url" -ForegroundColor Green
Write-Host "[✓] Também acessível por celulares na rede local: http://[IP-DESTA-MAQUINA]:$($cfg.Port)/" -ForegroundColor Gray
Write-Host "[✓] Monitorando inserção de cartões SD / Leitores USB..." -ForegroundColor Cyan
Write-Host "Pressione Ctrl+C para encerrar.`n" -ForegroundColor DarkGray

$publicFolder = Join-Path $PSScriptRoot "public"

# Monitor de USB
$knownDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
foreach ($d in $drives) { [void]$knownDrives.Add($d.Name) }

try {
    while ($listener.IsListening) {
        $contextTask = $listener.GetContextAsync()
        
        while (-not $contextTask.IsCompleted) {
            
            # 1. Processa fila de ingestão pendente (disparada via Web ou App)
            $pendingDrive = $null
            if ($script:PendingIngestQueue.TryDequeue([ref]$pendingDrive)) {
                Write-Host "`n[!] Ingestão manual recebida para: $pendingDrive" -ForegroundColor Cyan
                try {
                    $result = Start-StationIngestProcess -SourceDrive $pendingDrive -AutoEject $cfg.AutoEject
                    Write-Host "[✓] Ingestão concluída com status: $($result.Status)" -ForegroundColor Green
                    if ($result.Ejected) {
                        Write-Host "[⏏] Cartão $pendingDrive ejetado com segurança pelo sistema." -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "[-] Erro na ingestão: $_" -ForegroundColor Red
                }
            }
            
            # 2. Monitor de cartões plugados
            try {
                $currentReady = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
                $currentSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                
                foreach ($d in $currentReady) {
                    $driveName = $d.Name
                    [void]$currentSet.Add($driveName)
                    
                    if (-not $knownDrives.Contains($driveName)) {
                        Write-Host "`n[+] NOVO DISPOSITIVO DETECTADO: $driveName ($($d.VolumeLabel))" -ForegroundColor Cyan
                        Start-Sleep -Milliseconds 1200
                        
                        $isCandidate = $false
                        $dcim = Join-Path $driveName "DCIM"
                        $fotografoTxt = Join-Path $driveName "fotografo.txt"
                        $photos = Get-ChildItem -Path $driveName -File -ErrorAction SilentlyContinue | Where-Object {
                            $script:SUPPORTED_EXTENSIONS -contains $_.Extension.ToUpper()
                        }
                        
                        if ((Test-Path $dcim) -or (Test-Path $fotografoTxt) -or ($photos -and $photos.Count -gt 0)) {
                            Write-Host "[!] Cartão fotográfico reconhecido! Iniciando ingestão automática..." -ForegroundColor Green
                            $res = Start-StationIngestProcess -SourceDrive $driveName -AutoEject $cfg.AutoEject
                            if ($res.Ejected) {
                                Write-Host "[⏏] Cartão $driveName ejetado com segurança. Pode retirar." -ForegroundColor Yellow
                            }
                        }
                        
                        [void]$knownDrives.Add($driveName)
                    }
                }
                
                # Remoção de cartões
                $removed = [System.Collections.Generic.List[string]]::new()
                foreach ($k in $knownDrives) {
                    if (-not $currentSet.Contains($k)) { $removed.Add($k) }
                }
                foreach ($rem in $removed) {
                    Write-Host "[-] Dispositivo desconectado: $rem" -ForegroundColor DarkGray
                    [void]$knownDrives.Remove($rem)
                }
            } catch {}
            
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
