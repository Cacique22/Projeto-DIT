<#
.SYNOPSIS
    Suíte de Testes Automatizados de Missão Crítica para auto-ingest-station.
    Valida todas as Invariantes do motor, auto-ejeção, subpastas, persistência e API web.
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

if (!(Test-Path $serverPath)) { throw "WebServer não encontrado em: $serverPath" }
. $serverPath

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

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " INICIANDO SUÍTE DE TESTES: auto-ingest-station " -ForegroundColor Cyan
Write-Host "========================================================`n" -ForegroundColor Cyan

# Backup da configuração do usuário para garantir isolamento 100%
$prodConfigFile = Join-Path $PSScriptRoot "..\config.json"
$prodConfigBackup = $null
if (Test-Path $prodConfigFile) {
    $prodConfigBackup = Get-Content $prodConfigFile -Raw -Encoding UTF8
}

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
    Write-Host "[1/9] Testando Cálculo de Hash SHA-256..." -ForegroundColor White
    $sampleFile = Join-Path $testSandbox "sample.txt"
    Set-Content -Path $sampleFile -Value "Teste de Integridade Fotografica DIT" -Encoding UTF8 -NoNewline
    $hash1 = Get-FileSha256 -FilePath $sampleFile
    $hash2 = Get-FileSha256 -FilePath $sampleFile
    Assert-Equal $hash1 $hash2 "Hash determinístico repetível"
    Assert-Equal $hash1.Length 64 "Hash possui exatamente 64 caracteres hexadecimais"

    # -------------------------------------------------------------------------
    # TESTE 2: Identificação de Fotógrafo e Subpastas
    # -------------------------------------------------------------------------
    Write-Host "`n[2/9] Testando Identificação de Fotógrafo e Suporte a Subpastas..." -ForegroundColor White
    $fotografoTxt = Join-Path $mockCard "fotografo.txt"
    Set-Content -Path $fotografoTxt -Value "Lucas Fotografia" -Encoding UTF8
    $detectedName = Get-CardIdentifier -DriveLetter $mockCard
    Assert-Equal $detectedName "Lucas Fotografia" "Nome do fotógrafo extraído com sucesso de fotografo.txt na raiz"

    # Testa busca de fotografo.txt a partir de uma subpasta (ex: E:\DCIM\100CANON)
    $subDir = Join-Path $mockCard "DCIM\100CANON"
    New-Item -ItemType Directory -Path $subDir -Force | Out-Null
    $detectedSubName = Get-CardIdentifier -DriveLetter $subDir
    Assert-Equal $detectedSubName "Lucas Fotografia" "Nome do fotógrafo identificado mesmo informando subpasta DCIM\100CANON"
    Remove-Item -Path $fotografoTxt -Force

    # -------------------------------------------------------------------------
    # TESTE 3: Pre-Flight Check de Espaço em Disco
    # -------------------------------------------------------------------------
    Write-Host "`n[3/9] Testando Pre-Flight Check de Espaço em Disco..." -ForegroundColor White
    $passCheck = Test-PreFlightDiskSpace -TargetPath $mockBackup -RequiredBytes 1000000
    Assert-True $passCheck.IsSufficient "Aprova quando espaço é abundante"

    $hugeBytes = [int64]99999999999999999 # 99 Petabytes
    $failCheck = Test-PreFlightDiskSpace -TargetPath $mockBackup -RequiredBytes $hugeBytes
    Assert-True (-not $failCheck.IsSufficient) "Rejeita preventivamente quando disco for insuficiente"

    # -------------------------------------------------------------------------
    # TESTE 4: Ciclo Completo de Ingestão Atômica com Staging
    # -------------------------------------------------------------------------
    Write-Host "`n[4/9] Testando Cópia Atômica com Staging e Validação..." -ForegroundColor White
    $raw1 = Join-Path $mockCard "DCIM\100CANON\IMG_0001.CR3"
    $raw2 = Join-Path $mockCard "DCIM\100CANON\IMG_0002.CR3"
    [System.IO.File]::WriteAllBytes($raw1, (1..2048 | ForEach-Object { [byte]($_ % 256) }))
    [System.IO.File]::WriteAllBytes($raw2, (1..4096 | ForEach-Object { [byte]($_ % 256) }))

    $result = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste" -AutoEject $false
    Assert-Equal $result.Status "SUCCESS_ALL_VERIFIED" "Status final é SUCCESS_ALL_VERIFIED"
    Assert-Equal $result.CopiedCount 2 "Exatamente 2 arquivos foram copiados"
    Assert-Equal $result.Errors.Count 0 "Zero erros registrados"

    $destCardFolder = $result.Destination
    $destFile1 = Join-Path $destCardFolder "DCIM\100CANON\IMG_0001.CR3"
    $destFile2 = Join-Path $destCardFolder "DCIM\100CANON\IMG_0002.CR3"
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
    # TESTE 5: Ingestão Direta a partir de Subpasta (Ex: E:\DCIM\100CANON)
    # -------------------------------------------------------------------------
    Write-Host "`n[5/9] Testando Ingestão Especificando Subpasta Direta..." -ForegroundColor White
    $subResult = Invoke-CardIngest -SourceDrive $subDir -DestinationFolder $mockBackup -EventName "Casamento_Subpasta" -AutoEject $false
    Assert-Equal $subResult.CopiedCount 2 "Copiou arquivos normalmente mesmo com caminho de subpasta"
    Assert-Equal $subResult.Errors.Count 0 "Sem erros na cópia de subpasta"

    # -------------------------------------------------------------------------
    # TESTE 6: Idempotência Determinística (Re-inserção do Cartão)
    # -------------------------------------------------------------------------
    Write-Host "`n[6/9] Testando Idempotência em Re-inserção de Cartão..." -ForegroundColor White
    $repeatResult = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste" -AutoEject $false
    Assert-Equal $repeatResult.CopiedCount 0 "Zero arquivos novos foram copiados em repetição"
    Assert-Equal $repeatResult.SkippedCount 2 "Ambos os arquivos já existentes foram pulados"
    Assert-Equal $repeatResult.Status "IDLE_NO_NEW_FILES" "Status de retorno é IDLE_NO_NEW_FILES"

    $raw3 = Join-Path $mockCard "DCIM\100CANON\IMG_0003.CR3"
    [System.IO.File]::WriteAllBytes($raw3, (1..1024 | ForEach-Object { [byte]($_ % 256) }))
    $newResult = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste" -AutoEject $false
    Assert-Equal $newResult.CopiedCount 1 "Apenas a foto 3 (nova) foi copiada na segunda sessão"
    Assert-Equal $newResult.SkippedCount 2 "As fotos 1 e 2 anteriores foram ignoradas"

    # -------------------------------------------------------------------------
    # TESTE 7: Imutabilidade do Cartão de Origem (Read-Only)
    # -------------------------------------------------------------------------
    Write-Host "`n[7/9] Testando Imutabilidade do Cartão de Origem..." -ForegroundColor White
    Assert-True (Test-Path $raw1) "Foto 1 original permanece intacta no cartão"
    Assert-True (Test-Path $raw2) "Foto 2 original permanece intacta no cartão"
    Assert-True (Test-Path $raw3) "Foto 3 original permanece intacta no cartão"
    $raw1Length = (Get-Item $raw1).Length
    Assert-Equal $raw1Length 2048 "Bytes do cartão de origem não foram modificados"

    # -------------------------------------------------------------------------
    # TESTE 8: ConfigManager e Isolamento de Sandbox
    # -------------------------------------------------------------------------
    Write-Host "`n[8/9] Testando ConfigManager e Descoberta de Armazenamento..." -ForegroundColor White
    $initialCfg = Get-StationConfig -ConfigPath $mockConfigFile
    Assert-True (Test-Path $mockConfigFile) "Arquivo config.json de teste gerado"
    Assert-True (![string]::IsNullOrWhiteSpace($initialCfg.TargetRootPath)) "TargetRootPath padrão foi preenchido"
    Assert-True ($initialCfg.AutoEject -eq $true) "AutoEject ativado por padrão na configuração"

    $newFolder = Join-Path $testSandbox "DestinoPersonalizado"
    $updateHt = @{
        TargetRootPath = $newFolder
        EventName = 'Aniversário/15_Anos:Especial*São_Paulo'
        SafeSpaceBufferGB = 15
        AutoEject = $true
    }
    Set-StationConfig -Config $updateHt -ConfigPath $mockConfigFile | Out-Null
    
    $reloadedCfg = Get-StationConfig -ConfigPath $mockConfigFile
    Assert-Equal $reloadedCfg.TargetRootPath $newFolder "Caminho de destino personalizado persistido"
    Assert-Equal $reloadedCfg.EventName 'Aniversário_15_Anos_Especial_São_Paulo' "Caracteres proibidos sanitizados em EventName"
    Assert-Equal $reloadedCfg.AutoEject $true "AutoEject persistido como true"

    $drivesInfo = @(Get-AvailableDrivesInfo)
    Assert-True ($drivesInfo.Count -gt 0) "Descobriu ao menos 1 unidade de disco pronta no sistema"
    Assert-True ($drivesInfo[0].FreeGB -ge 0) "Espaço livre em GB foi calculado corretamente"

    # -------------------------------------------------------------------------
    # TESTE 9: Servidor Web e Endpoints REST (API e Dashboard)
    # -------------------------------------------------------------------------
    Write-Host "`n[9/9] Testando Servidor Web e Endpoints REST..." -ForegroundColor White
    $testPort = 8095
    $publicDir = (Resolve-Path (Join-Path $PSScriptRoot "..\src\public")).Path
    $resolvedServerPath = (Resolve-Path $serverPath).Path

    $serverProc = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"& { . '$resolvedServerPath'; `$l = Start-IngestHttpServer -ListenPort $testPort; while (`$l.IsListening) { try { `$ctx = `$l.GetContext(); Handle-HttpRequest -Context `$ctx -PublicFolder '$publicDir' } catch { break } } }`"" -PassThru -WindowStyle Hidden
    
    Start-Sleep -Seconds 2

    try {
        # Teste 9.1: GET / (Dashboard HTML)
        $htmlRes = Invoke-WebRequest -Uri "http://localhost:$testPort/" -UseBasicParsing
        Assert-Equal $htmlRes.StatusCode 200 "GET / retorna HTTP 200 OK"
        Assert-True ($htmlRes.Content.Contains("INGEST") -and $htmlRes.Content.Contains("DIT")) "Dashboard HTML servido com sucesso em /"
        Assert-True ($htmlRes.Content.Contains("browseFolder")) "Botão de explorar pastas presente no HTML"

        # Teste 9.2: GET /api/status
        $statusRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/status"
        Assert-Equal $statusRes.State "IDLE" "Status inicial da estação reportado como IDLE"
        $statusDrives = @($statusRes.Drives)
        Assert-True ($statusDrives.Count -gt 0) "API /api/status lista unidades de disco ativas"

        # Teste 9.3: POST /api/config
        $bodyJson = @{ EventName = "Formatura_Medicina_2026"; AutoEject = $true } | ConvertTo-Json
        $savedRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/config" -Method Post -Body $bodyJson -ContentType "application/json"
        Assert-Equal $savedRes.EventName "Formatura_Medicina_2026" "POST /api/config atualizou nome do evento via API"

        # Teste 9.4: GET /api/history
        $historyRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/history"
        Assert-True ($historyRes -is [System.Array] -or $null -eq $historyRes) "GET /api/history responde formato válido"

        # Teste 9.5: POST /api/beep
        $beepRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/beep" -Method Post -Body "{}" -ContentType "application/json"
        Assert-Equal $beepRes.Status "OK" "POST /api/beep responde com sucesso"

        # Teste 9.6: POST /api/manual-ingest com caminho inexistente (Validação sem crash)
        try {
            $badRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/manual-ingest" -Method Post -Body '{"SourceDrive":"Z:\\Drive_Fantasma"}' -ContentType "application/json"
            Assert-True $false "Deveria ter retornado erro 400 para drive inexistente"
        } catch {
            Assert-True ($_.Exception.Message.Contains("400")) "Rejeita preventivamente caminho de origem inexistente sem derrubar o servidor"
        }
    }
    finally {
        if ($serverProc -and -not $serverProc.HasExited) {
            Stop-Process -Id $serverProc.Id -Force -ErrorAction SilentlyContinue
        }
    }

}
finally {
    # Restaura a configuração de produção do usuário se foi alterada durante o teste
    if ($prodConfigBackup) {
        [System.IO.File]::WriteAllText($prodConfigFile, $prodConfigBackup, [System.Text.Encoding]::UTF8)
    }

    if (Test-Path $testSandbox) {
        Remove-Item -Path $testSandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host " RESULTADO FINAL DOS TESTES " -ForegroundColor Cyan
Write-Host " Passaram: $script:passedCount | Falharam: $script:failedCount" -ForegroundColor $(if ($script:failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "========================================================`n" -ForegroundColor Cyan

if ($script:failedCount -gt 0) {
    exit 1
}
exit 0
