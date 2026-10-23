<#
.SYNOPSIS
    Suíte de Testes Automatizados de Missão Crítica para auto-ingest-station.
    Valida todas as Invariantes do motor, persistência de configurações e API web.
#>

$ErrorActionPreference = "Stop"

# Carrega os módulos
$enginePath = Join-Path $PSScriptRoot "..\src\IngestEngine.ps1"
$configPath = Join-Path $PSScriptRoot "..\src\ConfigManager.ps1"
$serverPath = Join-Path $PSScriptRoot "..\src\WebServer.ps1"

if (!(Test-Path $enginePath)) { throw "Motor não encontrado em: $enginePath" }
. $enginePath

if (!(Test-Path $configPath)) { throw "ConfigManager não encontrado em: $configPath" }
. $configPath

$script:passedCount = 0
$script:failedCount = 0

function Assert-Equal($actual, $expected, $testName) {
    if ($actual -eq $expected) {
        Write-Host "  [PASS] $testName" -ForegroundColor Green
        $script:passedCount++
    } else {
        Write-Host "  [FAIL] $testName" -ForegroundColor Red
        Write-Host "         Esperado: '$expected' | Obtido: '$actual'" -ForegroundColor Yellow
        $script:failedCount++
    }
}

function Assert-True($condition, $testName) {
    if ($condition) {
        Write-Host "  [PASS] $testName" -ForegroundColor Green
        $script:passedCount++
    } else {
        Write-Host "  [FAIL] $testName (Condição falsa)" -ForegroundColor Red
        $script:failedCount++
    }
}

Write-Host "
========================================================" -ForegroundColor Cyan
Write-Host " INICIANDO SUÍTE DE TESTES: auto-ingest-station " -ForegroundColor Cyan
Write-Host "========================================================
" -ForegroundColor Cyan

# Cria diretórios temporários para os testes
$testSandbox = Join-Path ([System.IO.Path]::GetTempPath()) "auto_ingest_test_sandbox_$([System.Guid]::NewGuid().ToString('N'))"
$mockCard = Join-Path $testSandbox "MockCard"
$mockBackup = Join-Path $testSandbox "MockBackup"
$mockConfigFile = Join-Path $testSandbox "test_config.json"

New-Item -ItemType Directory -Path $mockCard -Force | Out-Null
New-Item -ItemType Directory -Path $mockBackup -Force | Out-Null

try {
    # -------------------------------------------------------------------------
    # TESTE 1: Integridade Criptográfica SHA-256
    # -------------------------------------------------------------------------
    Write-Host "[1/8] Testando Cálculo de Hash SHA-256..." -ForegroundColor White
    $sampleFile = Join-Path $testSandbox "sample.txt"
    Set-Content -Path $sampleFile -Value "Teste de Integridade Fotografica DIT" -Encoding UTF8 -NoNewline
    $hash1 = Get-FileSha256 -FilePath $sampleFile
    $hash2 = Get-FileSha256 -FilePath $sampleFile
    Assert-Equal $hash1 $hash2 "Hash determinístico repetível"
    Assert-Equal $hash1.Length 64 "Hash possui exatamente 64 caracteres hexadecimais"

    # -------------------------------------------------------------------------
    # TESTE 2: Identificação de Fotógrafo / Cartão
    # -------------------------------------------------------------------------
    Write-Host "
[2/8] Testando Identificação de Fotógrafo..." -ForegroundColor White
    $fotografoTxt = Join-Path $mockCard "fotografo.txt"
    Set-Content -Path $fotografoTxt -Value "Lucas Fotografia" -Encoding UTF8
    $detectedName = Get-CardIdentifier -DriveLetter $mockCard
    Assert-Equal $detectedName "Lucas Fotografia" "Nome do fotógrafo extraído com sucesso de fotografo.txt"
    Remove-Item -Path $fotografoTxt -Force

    # -------------------------------------------------------------------------
    # TESTE 3: Pre-Flight Check de Espaço em Disco
    # -------------------------------------------------------------------------
    Write-Host "
[3/8] Testando Pre-Flight Check de Espaço em Disco..." -ForegroundColor White
    $passCheck = Test-PreFlightDiskSpace -TargetPath $mockBackup -RequiredBytes 1000000
    Assert-True $passCheck.IsSufficient "Aprova quando espaço é abundante"

    $hugeBytes = [int64]99999999999999999 # 99 Petabytes
    $failCheck = Test-PreFlightDiskSpace -TargetPath $mockBackup -RequiredBytes $hugeBytes
    Assert-True (-not $failCheck.IsSufficient) "Rejeita preventivamente quando disco for insuficiente"

    # -------------------------------------------------------------------------
    # TESTE 4: Ciclo Completo de Ingestão Atômica com Staging
    # -------------------------------------------------------------------------
    Write-Host "
[4/8] Testando Cópia Atômica com Staging e Validação..." -ForegroundColor White
    $raw1 = Join-Path $mockCard "DCIM\100EOSR6\IMG_0001.CR3"
    $raw2 = Join-Path $mockCard "DCIM\100EOSR6\IMG_0002.CR3"
    New-Item -ItemType Directory -Path (Split-Path $raw1) -Force | Out-Null
    [System.IO.File]::WriteAllBytes($raw1, (1..2048 | ForEach-Object { [byte]($_ % 256) }))
    [System.IO.File]::WriteAllBytes($raw2, (1..4096 | ForEach-Object { [byte]($_ % 256) }))

    $result = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste"
    Assert-Equal $result.Status "SUCCESS_ALL_VERIFIED" "Status final é SUCCESS_ALL_VERIFIED"
    Assert-Equal $result.CopiedCount 2 "Exatamente 2 arquivos foram copiados"
    Assert-Equal $result.Errors.Count 0 "Zero erros registrados"

    $destCardFolder = $result.Destination
    $destFile1 = Join-Path $destCardFolder "DCIM\100EOSR6\IMG_0001.CR3"
    $destFile2 = Join-Path $destCardFolder "DCIM\100EOSR6\IMG_0002.CR3"
    Assert-True (Test-Path $destFile1) "Arquivo 1 final existe no destino"
    Assert-True (Test-Path $destFile2) "Arquivo 2 final existe no destino"

    $leftoverStaging = Get-ChildItem -Path $destCardFolder -Recurse -Filter "*.staging.tmp"
    Assert-Equal $leftoverStaging.Count 0 "Nenhum arquivo .staging.tmp órfão sobrou no destino"

    $srcHash1 = Get-FileSha256 -FilePath $raw1
    $destHash1 = Get-FileSha256 -FilePath $destFile1
    Assert-Equal $destHash1 $srcHash1 "Hash do arquivo 1 copiado confere byte a byte com o cartão"

    $manifestPath = Join-Path $destCardFolder "manifest.jsonl"
    Assert-True (Test-Path $manifestPath) "Manifesto de auditoria foi criado"
    $manifestLines = Get-Content $manifestPath -Encoding UTF8
    Assert-Equal $manifestLines.Count 2 "Manifesto possui exatamente 2 registros de auditoria"

    # -------------------------------------------------------------------------
    # TESTE 5: Idempotência Determinística (Re-inserção do Cartão)
    # -------------------------------------------------------------------------
    Write-Host "
[5/8] Testando Idempotência em Re-inserção de Cartão..." -ForegroundColor White
    $repeatResult = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste"
    Assert-Equal $repeatResult.CopiedCount 0 "Zero arquivos novos foram copiados em repetição"
    Assert-Equal $repeatResult.SkippedCount 2 "Ambos os arquivos já existentes foram pulados"
    Assert-Equal $repeatResult.Status "IDLE_NO_NEW_FILES" "Status de retorno é IDLE_NO_NEW_FILES"

    $raw3 = Join-Path $mockCard "DCIM\100EOSR6\IMG_0003.CR3"
    [System.IO.File]::WriteAllBytes($raw3, (1..1024 | ForEach-Object { [byte]($_ % 256) }))
    $newResult = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste"
    Assert-Equal $newResult.CopiedCount 1 "Apenas a foto 3 (nova) foi copiada na segunda sessão"
    Assert-Equal $newResult.SkippedCount 2 "As fotos 1 e 2 anteriores foram ignoradas"

    # -------------------------------------------------------------------------
    # TESTE 6: Imutabilidade do Cartão de Origem (Read-Only)
    # -------------------------------------------------------------------------
    Write-Host "
[6/8] Testando Imutabilidade do Cartão de Origem..." -ForegroundColor White
    Assert-True (Test-Path $raw1) "Foto 1 original permanece intacta no cartão"
    Assert-True (Test-Path $raw2) "Foto 2 original permanece intacta no cartão"
    Assert-True (Test-Path $raw3) "Foto 3 original permanece intacta no cartão"
    $raw1Length = (Get-Item $raw1).Length
    Assert-Equal $raw1Length 2048 "Bytes do cartão de origem não foram modificados"

    # -------------------------------------------------------------------------
    # TESTE 7: Gerenciador de Configurações (ConfigManager)
    # -------------------------------------------------------------------------
    Write-Host "
[7/8] Testando ConfigManager e Descoberta de Armazenamento..." -ForegroundColor White
    $initialCfg = Get-StationConfig -ConfigPath $mockConfigFile
    Assert-True (Test-Path $mockConfigFile) "Arquivo config.json foi gerado automaticamente"
    Assert-True (![string]::IsNullOrWhiteSpace($initialCfg.TargetRootPath)) "TargetRootPath padrão foi preenchido"

    # Atualiza configuração e verifica sanitização
    $newFolder = Join-Path $testSandbox "DestinoPersonalizado"
    $updateHt = @{
        TargetRootPath = $newFolder
        EventName = 'Aniversário/15_Anos:Especial*São_Paulo'
        SafeSpaceBufferGB = 15
    }
    Set-StationConfig -Config $updateHt -ConfigPath $mockConfigFile | Out-Null
    
    $reloadedCfg = Get-StationConfig -ConfigPath $mockConfigFile
    Assert-Equal $reloadedCfg.TargetRootPath $newFolder "Caminho de destino personalizado persistido"
    Assert-Equal $reloadedCfg.EventName 'Aniversário_15_Anos_Especial_São_Paulo' "Caracteres proibidos sanitizados em EventName"
    Assert-Equal $reloadedCfg.SafeSpaceBufferGB 15 "Buffer de segurança persistido"
    Assert-True (Test-Path $newFolder) "Pasta de destino foi criada automaticamente pelo ConfigManager"

    # Valida descoberta de discos
    $drivesInfo = @(Get-AvailableDrivesInfo)
    Assert-True ($drivesInfo.Count -gt 0) "Descobriu ao menos 1 unidade de disco pronta no sistema"
    Assert-True ($drivesInfo[0].FreeGB -ge 0) "Espaço livre em GB foi calculado corretamente"

    # -------------------------------------------------------------------------
    # TESTE 8: Servidor Web e Endpoints REST (API e Dashboard)
    # -------------------------------------------------------------------------
    Write-Host "
[8/8] Testando Servidor Web e Endpoints REST..." -ForegroundColor White
    $testPort = 8095
    $publicDir = (Resolve-Path (Join-Path $PSScriptRoot "..\src\public")).Path
    $resolvedServerPath = (Resolve-Path $serverPath).Path

    $serverProc = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"& { . '$resolvedServerPath'; `$l = Start-IngestHttpServer -ListenPort $testPort; while (`$l.IsListening) { try { `$ctx = `$l.GetContext(); Handle-HttpRequest -Context `$ctx -PublicFolder '$publicDir' } catch { break } } }`"" -PassThru -WindowStyle Hidden
    
    Start-Sleep -Seconds 2

    try {
        # Teste 8.1: GET / (Dashboard HTML)
        $htmlRes = Invoke-WebRequest -Uri "http://localhost:$testPort/" -UseBasicParsing
        Assert-Equal $htmlRes.StatusCode 200 "GET / retorna HTTP 200 OK"
        Assert-True ($htmlRes.Content.Contains("INGEST") -and $htmlRes.Content.Contains("DIT")) "Dashboard HTML servido com sucesso em /"

        # Teste 8.2: GET /api/status
        $statusRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/status"
        Assert-Equal $statusRes.State "IDLE" "Status inicial da estação reportado como IDLE"
        $statusDrives = @($statusRes.Drives)
        Assert-True ($statusDrives.Count -gt 0) "API /api/status lista unidades de disco ativas"

        # Teste 8.3: POST /api/config
        $bodyJson = @{ EventName = "Formatura_Medicina_2026"; TargetRootPath = $newFolder } | ConvertTo-Json
        $savedRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/config" -Method Post -Body $bodyJson -ContentType "application/json"
        Assert-Equal $savedRes.EventName "Formatura_Medicina_2026" "POST /api/config atualizou nome do evento via API"

        # Teste 8.4: GET /api/history
        $historyRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/history"
        Assert-True ($historyRes -is [System.Array] -or $null -eq $historyRes) "GET /api/history responde formato válido"

        # Teste 8.5: POST /api/beep
        $beepRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/beep" -Method Post -Body "{}" -ContentType "application/json"
        Assert-Equal $beepRes.Status "OK" "POST /api/beep responde com sucesso"
    }
    finally {
        if ($serverProc -and -not $serverProc.HasExited) {
            Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
        }
    }

}
finally {
    # Limpa a sandbox de testes
    if (Test-Path $testSandbox) {
        Remove-Item -Path $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "
========================================================" -ForegroundColor Cyan
Write-Host " RESULTADO FINAL DOS TESTES " -ForegroundColor Cyan
Write-Host " Passaram: $script:passedCount | Falharam: $script:failedCount" -ForegroundColor $(if ($script:failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "========================================================
" -ForegroundColor Cyan

if ($script:failedCount -gt 0) {
    exit 1
}
exit 0
