# Watch-UsbCards.ps1 - Daemon de Detecção Automática de Cartões de Memória
param(
    [int]$PollIntervalMs = 1500
)

$enginePath = Join-Path $PSScriptRoot "IngestEngine.ps1"
$configPath = Join-Path $PSScriptRoot "ConfigManager.ps1"
$serverPath = Join-Path $PSScriptRoot "WebServer.ps1"

if (Test-Path $enginePath) { . $enginePath }
if (Test-Path $configPath) { . $configPath }
if (Test-Path $serverPath) { . $serverPath }

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " DAEMON DE INGESTÃO AUTOMÁTICA DIT: ATIVO E MONITORANDO   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Aguardando conexão de cartões SD / CFexpress / Leitores USB...`n" -ForegroundColor Gray

# Inicializa conjunto de drives conhecidos no boot
$knownDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
foreach ($d in $drives) {
    [void]$knownDrives.Add($d.Name)
}

function Test-IsCardCandidate {
    param([Parameter(Mandatory=$true)][string]$DriveRoot)
    
    # 1. Checa se tem pasta DCIM clássica de câmeras
    $dcim = Join-Path $DriveRoot "DCIM"
    if (Test-Path $dcim) { return $true }
    
    # 2. Checa se tem identificador de fotógrafo
    $fotografoTxt = Join-Path $DriveRoot "fotografo.txt"
    if (Test-Path $fotografoTxt) { return $true }
    
    # 3. Checa se tem arquivos com extensões fotográficas na raiz ou subpastas imediatas
    $photos = Get-ChildItem -Path $DriveRoot -File -ErrorAction SilentlyContinue | Where-Object {
        $script:SUPPORTED_EXTENSIONS -contains $_.Extension.ToUpper()
    }
    if ($photos -and $photos.Count -gt 0) { return $true }
    
    return $false
}

function Watch-Loop {
    while ($true) {
        try {
            $currentReady = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
            $currentSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            
            foreach ($d in $currentReady) {
                $driveName = $d.Name
                [void]$currentSet.Add($driveName)
                
                # Se for um drive novo que não estava presente
                if (-not $knownDrives.Contains($driveName)) {
                    Write-Host "`n[+] NOVO DISPOSITIVO DETECTADO: $driveName ($($d.VolumeLabel))" -ForegroundColor Cyan
                    
                    # Aguarda 1.5s para estabilização de montagem do Windows
                    Start-Sleep -Milliseconds 1500
                    
                    if (Test-IsCardCandidate -DriveRoot $driveName) {
                        Write-Host "[!] Cartão fotográfico validado! Disparando ingestão segura..." -ForegroundColor Green
                        
                        try {
                            Start-StationIngestProcess -SourceDrive $driveName
                        }
                        catch {
                            Write-Host "[-] Erro durante ingestão: $_" -ForegroundColor Red
                        }
                    } else {
                        Write-Host "[i] Dispositivo $driveName não contém padrão fotográfico conhecido (ignorado)." -ForegroundColor DarkGray
                    }
                    
                    [void]$knownDrives.Add($driveName)
                }
            }
            
            # Detecta remoção de cartões para permitir re-inserção
            $removed = [System.Collections.Generic.List[string]]::new()
            foreach ($k in $knownDrives) {
                if (-not $currentSet.Contains($k)) {
                    $removed.Add($k)
                }
            }
            foreach ($rem in $removed) {
                Write-Host "[-] Dispositivo removido: $rem" -ForegroundColor Yellow
                [void]$knownDrives.Remove($rem)
            }
        }
        catch {
            Write-Host "Aviso no monitor de discos: $_" -ForegroundColor DarkGray
        }
        
        Start-Sleep -Milliseconds $PollIntervalMs
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Watch-Loop
}
