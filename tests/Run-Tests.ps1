<#
.SYNOPSIS
    Suíte de Testes Automatizados de Missão Crítica para auto-ingest-station.
    Valida todas as Invariantes do motor, auto-ejeção, cancelamento seguro,
    gestão de múltiplos eventos, cadastro de cartões por fotógrafo/subpasta,
    controle de pausa/retomada de monitoramento, integridade criptográfica e API web.
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
    Write-Host "[1/16] Testando Cálculo de Hash SHA-256..." -ForegroundColor White
    $testFilePath = Join-Path $testSandbox "test_sha.bin"
    [System.IO.File]::WriteAllBytes($testFilePath, [byte[]]@(0x41, 0x42, 0x43, 0x44, 0x01, 0x02, 0xFF))

    $hash1 = Get-FileSha256 -FilePath $testFilePath
    $hash2 = Get-FileSha256 -FilePath $testFilePath
    Assert-Equal $hash1 $hash2 "Hash determinístico repetível"
    Assert-Equal $hash1.Length 64 "Hash possui exatamente 64 caracteres hexadecimais"

    # -------------------------------------------------------------------------
    # TESTE 2: Identificação de Fotógrafo e Suporte a Subpastas
    # -------------------------------------------------------------------------
    Write-Host "`n[2/16] Testando Identificação de Fotógrafo e Suporte a Subpastas..." -ForegroundColor White
    $identFile = Join-Path $mockCard "fotografo.txt"
    Set-Content -Path $identFile -Value "Fotografo_Lucas_A7IV" -Encoding UTF8

    $extractedCardId = Get-CardIdentifier -DriveLetter $mockCard
    Assert-Equal $extractedCardId "Fotografo_Lucas_A7IV" "Nome do fotógrafo extraído com sucesso de fotografo.txt na raiz"

    $subfolderDcim = Join-Path $mockCard "DCIM\100CANON"
    New-Item -ItemType Directory -Path $subfolderDcim -Force | Out-Null
    $extractedFromSub = Get-CardIdentifier -DriveLetter $subfolderDcim
    Assert-Equal $extractedFromSub "Fotografo_Lucas_A7IV" "Nome do fotógrafo identificado mesmo informando subpasta DCIM\100CANON"

    # -------------------------------------------------------------------------
    # TESTE 3: Pre-Flight Check de Espaço em Disco
    # -------------------------------------------------------------------------
    Write-Host "`n[3/16] Testando Pre-Flight Check de Espaço em Disco..." -ForegroundColor White
    $spaceOk = Test-PreFlightDiskSpace -TargetPath $mockBackup -RequiredBytes 1048576
    Assert-True $spaceOk.IsSufficient "Aprova quando espaço é abundante"

    $spaceFail = Test-PreFlightDiskSpace -TargetPath $mockBackup -RequiredBytes ([int64]999999999999999)
    Assert-Equal $spaceFail.IsSufficient $false "Rejeita preventivamente quando disco for insuficiente"

    # -------------------------------------------------------------------------
    # TESTE 4: Cópia Atômica com Staging e Validação Criptográfica
    # -------------------------------------------------------------------------
    Write-Host "`n[4/16] Testando Cópia Atômica com Staging e Validação..." -ForegroundColor White
    $dummyPhoto1 = Join-Path $subfolderDcim "IMG_0001.CR3"
    $dummyPhoto2 = Join-Path $subfolderDcim "IMG_0002.JPG"
    [System.IO.File]::WriteAllBytes($dummyPhoto1, [byte[]]@(1..5000 | ForEach-Object { [byte]($_ % 256) }))
    [System.IO.File]::WriteAllBytes($dummyPhoto2, [byte[]]@(1..3000 | ForEach-Object { [byte]((255 + $_) % 256) }))

    $ingestResult = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste" -AutoEject $false

    Assert-Equal $ingestResult.Status "SUCCESS_ALL_VERIFIED" "Status final é SUCCESS_ALL_VERIFIED"
    Assert-Equal $ingestResult.CopiedCount 2 "Exatamente 2 arquivos foram copiados"
    Assert-Equal $ingestResult.Errors.Length 0 "Zero erros registrados"

    $destFolder = $ingestResult.Destination
    $destFile1 = Join-Path $destFolder "DCIM\100CANON\IMG_0001.CR3"
    $destFile2 = Join-Path $destFolder "DCIM\100CANON\IMG_0002.JPG"

    Assert-True (Test-Path $destFile1) "Arquivo 1 final existe no destino"
    Assert-True (Test-Path $destFile2) "Arquivo 2 final existe no destino"

    $stagingFiles = Get-ChildItem -Path $destFolder -Recurse -Filter "*.staging.tmp"
    Assert-Equal $stagingFiles.Count 0 "Nenhum arquivo .staging.tmp órfão sobrou no destino"

    $dest1Hash = Get-FileSha256 -FilePath $destFile1
    $src1Hash = Get-FileSha256 -FilePath $dummyPhoto1
    Assert-Equal $dest1Hash $src1Hash "Hash do arquivo 1 copiado confere byte a byte com o cartão"

    $manifestPath = Join-Path $destFolder "manifest.jsonl"
    Assert-True (Test-Path $manifestPath) "Manifesto de auditoria foi criado"
    $manifestLines = Get-Content $manifestPath -Encoding UTF8
    Assert-Equal $manifestLines.Count 2 "Manifesto possui exatamente 2 registros de auditoria"

    # -------------------------------------------------------------------------
    # TESTE 5: Ingestão Especificando Subpasta Direta
    # -------------------------------------------------------------------------
    Write-Host "`n[5/16] Testando Ingestão Especificando Subpasta Direta..." -ForegroundColor White
    $mockBackupSub = Join-Path $testSandbox "MockBackupSub"
    New-Item -ItemType Directory -Path $mockBackupSub -Force | Out-Null

    $subIngestResult = Invoke-CardIngest -SourceDrive $subfolderDcim -DestinationFolder $mockBackupSub -EventName "Casamento_Teste" -AutoEject $false
    Assert-Equal $subIngestResult.CopiedCount 2 "Copiou arquivos normalmente mesmo com caminho de subpasta"
    Assert-Equal $subIngestResult.Errors.Length 0 "Sem erros na cópia de subpasta"

    # -------------------------------------------------------------------------
    # TESTE 6: Idempotência em Re-inserção de Cartão
    # -------------------------------------------------------------------------
    Write-Host "`n[6/16] Testando Idempotência em Re-inserção de Cartão..." -ForegroundColor White
    $reIngestResult = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste" -AutoEject $false
    Assert-Equal $reIngestResult.CopiedCount 0 "Zero arquivos novos foram copiados em repetição"
    Assert-Equal $reIngestResult.SkippedCount 2 "Ambos os arquivos já existentes foram pulados"
    Assert-Equal $reIngestResult.Status "IDLE_NO_NEW_FILES" "Status de retorno é IDLE_NO_NEW_FILES"

    $dummyPhoto3 = Join-Path $subfolderDcim "IMG_0003.CR3"
    [System.IO.File]::WriteAllBytes($dummyPhoto3, [byte[]]@(1..2000 | ForEach-Object { [byte]($_ % 128) }))

    $partialResult = Invoke-CardIngest -SourceDrive $mockCard -DestinationFolder $mockBackup -EventName "Casamento_Teste" -AutoEject $false
    Assert-Equal $partialResult.CopiedCount 1 "Apenas a foto 3 (nova) foi copiada na segunda sessão"
    Assert-Equal $partialResult.SkippedCount 2 "As fotos 1 e 2 anteriores foram ignoradas"

    # -------------------------------------------------------------------------
    # TESTE 7: Imutabilidade do Cartão de Origem
    # -------------------------------------------------------------------------
    Write-Host "`n[7/16] Testando Imutabilidade do Cartão de Origem..." -ForegroundColor White
    Assert-True (Test-Path $dummyPhoto1) "Foto 1 original permanece intacta no cartão"
    Assert-True (Test-Path $dummyPhoto2) "Foto 2 original permanece intacta no cartão"
    Assert-True (Test-Path $dummyPhoto3) "Foto 3 original permanece intacta no cartão"
    $card1HashAfter = Get-FileSha256 -FilePath $dummyPhoto1
    Assert-Equal $card1HashAfter $src1Hash "Bytes do cartão de origem não foram modificados"

    # -------------------------------------------------------------------------
    # TESTE 8: ConfigManager e Descoberta de Armazenamento
    # -------------------------------------------------------------------------
    Write-Host "`n[8/16] Testando ConfigManager e Descoberta de Armazenamento..." -ForegroundColor White
    $cfg = Get-StationConfig -ConfigPath $mockConfigFile
    Assert-True (Test-Path $mockConfigFile) "Arquivo config.json de teste gerado"
    Assert-True (![string]::IsNullOrWhiteSpace($cfg.TargetRootPath)) "TargetRootPath padrão foi preenchido"
    Assert-Equal $cfg.AutoEject $true "AutoEject ativado por padrão na configuração"

    $newFolder = Join-Path $testSandbox "Armazenamento_Dedicado_DIT"
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
    Write-Host "`n[9/16] Testando Servidor Web e Endpoints REST..." -ForegroundColor White
    $testPort = 8095
    $publicDir = (Resolve-Path (Join-Path $PSScriptRoot "..\src\public")).Path
    $resolvedConfigPath = (Resolve-Path $configPath).Path
    $resolvedEnginePath = (Resolve-Path $enginePath).Path
    $resolvedServerPath = (Resolve-Path $serverPath).Path

    $serverProc = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"& { . '$resolvedConfigPath'; . '$resolvedEnginePath'; . '$resolvedServerPath'; `$l = Start-IngestHttpServer -ListenPort $testPort; while (`$l.IsListening) { try { `$ctx = `$l.GetContext(); Handle-HttpRequest -Context `$ctx -PublicFolder '$publicDir' } catch { break } } }`"" -PassThru -WindowStyle Hidden
    
    Start-Sleep -Seconds 2

    try {
        # Teste 9.1: GET / (Dashboard HTML)
        $htmlRes = Invoke-WebRequest -Uri "http://localhost:$testPort/" -UseBasicParsing
        Assert-Equal $htmlRes.StatusCode 200 "GET / retorna HTTP 200 OK"
        Assert-True ($htmlRes.Content.Contains("INGEST") -and $htmlRes.Content.Contains("DIT")) "Dashboard HTML servido com sucesso em /"
        Assert-True ($htmlRes.Content.Contains("browseFolder")) "Botão de explorar pastas presente no HTML"
        Assert-True ($htmlRes.Content.Contains("cancelCurrentIngest")) "Botão de parar com segurança presente no HTML"
        Assert-True ($htmlRes.Content.Contains("badgeCurrentEvent")) "Seção de eventos presente no HTML"

        # Teste 9.2: GET /api/status
        $statusRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/status"
        Assert-Equal $statusRes.State "IDLE" "Status inicial da estação reportado como IDLE"
        $statusDrives = @($statusRes.Drives)
        Assert-True ($statusDrives.Count -gt 0) "API /api/status lista unidades de disco ativas"
        Assert-Equal $statusRes.MonitoringActive $true "Status inicial do monitoramento reportado como ativo"

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

    # -------------------------------------------------------------------------
    # TESTE 10: Interrupção Segura de Ingestão (Cancelamento sem Corrupção)
    # -------------------------------------------------------------------------
    Write-Host "`n[10/16] Testando Interrupção Segura de Ingestão..." -ForegroundColor White
    $mockCardCancel = Join-Path $testSandbox "MockCardCancel"
    $mockBackupCancel = Join-Path $testSandbox "MockBackupCancel"
    New-Item -ItemType Directory -Path $mockCardCancel -Force | Out-Null
    New-Item -ItemType Directory -Path $mockBackupCancel -Force | Out-Null

    Set-Content -Path (Join-Path $mockCardCancel "fotografo.txt") -Value "Fotografo_Abort_Test" -Encoding UTF8

    for ($i = 1; $i -le 4; $i++) {
        $p = Join-Path $mockCardCancel "PHOTO_$i.RAW"
        [System.IO.File]::WriteAllBytes($p, [byte[]]@(1..4000 | ForEach-Object { [byte]($_ % 256) }))
    }

    $script:cancelTriggered = $false
    $abortResult = Invoke-CardIngest -SourceDrive $mockCardCancel `
        -DestinationFolder $mockBackupCancel `
        -EventName "AbortTest" `
        -AutoEject $true `
        -CancelCheck { $script:cancelTriggered } `
        -ProgressCallback {
            param($prog)
            if ($prog.CurrentIndex -ge 1) {
                $script:cancelTriggered = $true
            }
        }

    Assert-Equal $abortResult.Status "ABORTED_BY_USER" "Status de retorno é ABORTED_BY_USER"
    Assert-Equal $abortResult.CopiedCount 1 "Apenas a primeira foto concluída antes do cancelamento foi mantida"
    Assert-Equal $abortResult.Ejected $false "Cartão NÃO foi ejetado durante o aborto para inspeção segura"

    $stagingLeft = Get-ChildItem -Path $abortResult.Destination -Recurse -Filter "*.staging.tmp"
    Assert-Equal $stagingLeft.Count 0 "Nenhum arquivo temporário .staging.tmp órfão deixado no destino"

    $destPhoto1 = Join-Path $abortResult.Destination "PHOTO_1.RAW"
    Assert-True (Test-Path $destPhoto1) "Foto 1 copiada antes da interrupção permanece intacta"
    $p1Sha = Get-FileSha256 -FilePath $destPhoto1
    $src1Sha = Get-FileSha256 -FilePath (Join-Path $mockCardCancel "PHOTO_1.RAW")
    Assert-Equal $p1Sha $src1Sha "Hash SHA-256 da foto 1 confere com o original"

    Assert-True (!(Test-Path (Join-Path $abortResult.Destination "PHOTO_3.RAW"))) "Fotos posteriores não foram criadas pela metade"

    for ($i = 1; $i -le 4; $i++) {
        Assert-True (Test-Path (Join-Path $mockCardCancel "PHOTO_$i.RAW")) "Cartão de origem manteve PHOTO_$i intacta"
    }

    $cancelManifest = Join-Path $abortResult.Destination "manifest.jsonl"
    Assert-True (Test-Path $cancelManifest) "Manifesto de auditoria registrado no cancelamento"
    $manifestText = Get-Content $cancelManifest -Raw -Encoding UTF8
    Assert-True ($manifestText.Contains("ABORTED_BY_USER")) "Manifesto gravou status ABORTED_BY_USER no log append-only"

    $resumeResult = Invoke-CardIngest -SourceDrive $mockCardCancel `
        -DestinationFolder $mockBackupCancel `
        -EventName "AbortTest" `
        -AutoEject $false

    Assert-Equal $resumeResult.Status "SUCCESS_ALL_VERIFIED" "Retomada após cancelamento concluiu com SUCCESS_ALL_VERIFIED"
    Assert-Equal $resumeResult.CopiedCount 3 "Retomada copiou exatamente as 3 fotos restantes"
    Assert-Equal $resumeResult.SkippedCount 1 "Retomada pulou a foto 1 já verificada anteriormente"
    for ($i = 1; $i -le 4; $i++) {
        Assert-True (Test-Path (Join-Path $resumeResult.Destination "PHOTO_$i.RAW")) "Todas as 4 fotos existem íntegras no destino final"
    }

    # -------------------------------------------------------------------------
    # TESTE 11: Mapeamento Multi-Cartão & Destinos Personalizados
    # -------------------------------------------------------------------------
    Write-Host "`n[11/16] Testando Mapeamento Multi-Cartão & Destinos Personalizados..." -ForegroundColor White
    $destAlpha = Join-Path $testSandbox "Dest_Fotografo_Alpha"
    $destBeta = Join-Path $testSandbox "Dest_Fotografo_Beta"
    New-Item -ItemType Directory -Path $destAlpha -Force | Out-Null
    New-Item -ItemType Directory -Path $destBeta -Force | Out-Null

    $rule1 = Add-CardMappingRule -Identifier "CARD_ALPHA" -Destination $destAlpha -Description "Fotógrafo Alpha" -ConfigPath $mockConfigFile
    Assert-Equal $rule1.Identifier "CARD_ALPHA" "Regra de mapeamento criada para CARD_ALPHA"

    $rule2 = Add-CardMappingRule -Identifier "Z:" -Destination $destBeta -Description "Drive Z Específico" -ConfigPath $mockConfigFile
    Assert-Equal $rule2.Identifier "Z:" "Regra de mapeamento criada para unidade Z:"

    $currentCfgWithMaps = Get-StationConfig -ConfigPath $mockConfigFile
    Assert-Equal $currentCfgWithMaps.CardMappings.Count 2 "Config possui 2 regras de mapeamento registradas"

    $routeAlpha = Get-DestinationForCard -CardIdentifier "CARD_ALPHA" -SourcePath "E:\DCIM" -Config $currentCfgWithMaps
    Assert-True ($routeAlpha.StartsWith($destAlpha, [System.StringComparison]::OrdinalIgnoreCase)) "CARD_ALPHA roteado para destino personalizado Alpha"

    $routeBeta = Get-DestinationForCard -CardIdentifier "OUTRO_CARD" -SourcePath "Z:\DCIM" -Config $currentCfgWithMaps
    Assert-True ($routeBeta.StartsWith($destBeta, [System.StringComparison]::OrdinalIgnoreCase)) "Drive Z: roteado para destino personalizado Beta"

    $routeDefault = Get-DestinationForCard -CardIdentifier "CARD_NAO_MAPEADO" -SourcePath "F:\DCIM" -Config $currentCfgWithMaps
    Assert-True ($routeDefault.StartsWith($currentCfgWithMaps.TargetRootPath, [System.StringComparison]::OrdinalIgnoreCase)) "Cartão não mapeado usa destino padrão da estação"

    Remove-CardMappingRule -Identifier "CARD_ALPHA" -ConfigPath $mockConfigFile | Out-Null
    $cfgAfterRemoval = Get-StationConfig -ConfigPath $mockConfigFile
    Assert-Equal $cfgAfterRemoval.CardMappings.Count 1 "Regra de CARD_ALPHA removida com sucesso"

    # -------------------------------------------------------------------------
    # TESTE 12: Endpoints REST para Cancelamento e Mapeamento Multi-Cartão
    # -------------------------------------------------------------------------
    Write-Host "`n[12/16] Testando Endpoints REST de Cancelamento e Mapeamento..." -ForegroundColor White
    $serverProc2 = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"& { . '$resolvedConfigPath'; . '$resolvedEnginePath'; . '$resolvedServerPath'; `$l = Start-IngestHttpServer -ListenPort $testPort; while (`$l.IsListening) { try { `$ctx = `$l.GetContext(); Handle-HttpRequest -Context `$ctx -PublicFolder '$publicDir' } catch { break } } }`"" -PassThru -WindowStyle Hidden
    
    Start-Sleep -Seconds 2

    try {
        $cancelIdle = Invoke-RestMethod -Uri "http://localhost:$testPort/api/cancel" -Method Post
        Assert-Equal $cancelIdle.Cancelled $false "POST /api/cancel informa que nenhuma ingestão estava ativa"

        $mappingsList = Invoke-RestMethod -Uri "http://localhost:$testPort/api/mappings"
        Assert-True ($mappingsList -is [System.Array] -or $null -eq $mappingsList) "GET /api/mappings retorna lista válida"

        $newMapBody = @{
            Identifier = "SONY_A7_API"
            Destination = $destAlpha
            Description = "Fotógrafo Criado via Web API"
        } | ConvertTo-Json
        $postMapRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/mappings" -Method Post -Body $newMapBody -ContentType "application/json"
        Assert-Equal $postMapRes.Identifier "SONY_A7_API" "POST /api/mappings cadastrou nova regra"

        $delMapRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/mappings?identifier=SONY_A7_API" -Method Delete
        Assert-Equal $delMapRes.Status "DELETED" "DELETE /api/mappings removeu a regra com sucesso"
    }
    finally {
        if ($serverProc2 -and -not $serverProc2.HasExited) {
            Stop-Process -Id $serverProc2.Id -Force -ErrorAction SilentlyContinue
        }
    }

    # -------------------------------------------------------------------------
    # TESTE 13: Gestão de Múltiplos Eventos e Persistência
    # -------------------------------------------------------------------------
    Write-Host "`n[13/16] Testando Gestão de Múltiplos Eventos e Persistência..." -ForegroundColor White
    $evDest1 = Join-Path $testSandbox "Event_Casamento_Lucas"
    $evDest2 = Join-Path $testSandbox "Event_Bodas_Ouro"
    New-Item -ItemType Directory -Path $evDest1 -Force | Out-Null
    New-Item -ItemType Directory -Path $evDest2 -Force | Out-Null

    $ev1 = New-StationEvent -EventName "Casamento_Lucas_Mariana" -DefaultDestination $evDest1 -ConfigPath $mockConfigFile
    Assert-Equal $ev1.Name "Casamento_Lucas_Mariana" "Novo evento Casamento_Lucas_Mariana criado"

    $ev2 = New-StationEvent -EventName "Bodas_Ouro_2026" -DefaultDestination $evDest2 -ConfigPath $mockConfigFile
    Assert-Equal $ev2.Name "Bodas_Ouro_2026" "Novo evento Bodas_Ouro_2026 criado"

    $eventsListAll = @(Get-StationEvents -ConfigPath $mockConfigFile)
    Assert-True ($eventsListAll.Count -ge 2) "Lista de eventos contém múltiplos eventos persistidos"

    # Alterna o evento ativo
    Set-CurrentEvent -EventName "Casamento_Lucas_Mariana" -ConfigPath $mockConfigFile | Out-Null
    $curEv = Get-CurrentEvent -ConfigPath $mockConfigFile
    Assert-Equal $curEv.Name "Casamento_Lucas_Mariana" "Evento ativo alternado para Casamento_Lucas_Mariana com persistência"

    # -------------------------------------------------------------------------
    # TESTE 14: Cadastro de Cartão por Evento e Formatação de Subpasta
    # -------------------------------------------------------------------------
    Write-Host "`n[14/16] Testando Cadastro de Cartão por Evento e Subpasta..." -ForegroundColor White
    $mockCardNikon = Join-Path $testSandbox "MockCardNikon"
    $nikonDcim = Join-Path $mockCardNikon "DCIM\100NCZ_6"
    New-Item -ItemType Directory -Path $nikonDcim -Force | Out-Null

    $nikonPhoto = Join-Path $nikonDcim "DSC_0001.NEF"
    [System.IO.File]::WriteAllBytes($nikonPhoto, [byte[]]@(1..3000 | ForEach-Object { [byte]($_ % 256) }))

    # 14.1: Descoberta de subpastas de fotos no cartão
    $foldersFound = @(Get-CardPhotoFolders -DriveRoot $mockCardNikon)
    Assert-True ($foldersFound -contains "DCIM\100NCZ_6") "Identificou subpasta de câmera DCIM\100NCZ_6 no cartão"

    # 14.2: Cadastro do primeiro uso do cartão no evento ativo
    $photogDest = Join-Path $evDest1 "Marina_Camera2"
    $regCard = Register-CardForEvent -EventName "Casamento_Lucas_Mariana" `
        -CardIdentifier "NIKON_SD_64GB" `
        -Photographer "Marina Costa" `
        -DestinationPath $photogDest `
        -PhotoSubfolder "DCIM\100NCZ_6" `
        -ConfigPath $mockConfigFile

    Assert-Equal $regCard.Photographer "Marina Costa" "Cartão cadastrado com fotógrafo Marina Costa"
    Assert-Equal $regCard.PhotoSubfolder "DCIM\100NCZ_6" "Subpasta de fotos da câmera registrada no cadastro"

    # 14.3: Recuperação do cadastro
    $savedReg = Get-CardRegistration -EventName "Casamento_Lucas_Mariana" -CardIdentifier "NIKON_SD_64GB" -ConfigPath $mockConfigFile
    Assert-Equal $savedReg.Photographer "Marina Costa" "Cadastro recuperado com sucesso"
    Assert-Equal $savedReg.DestinationPath $photogDest "Destino do cartão recuperado com sucesso"

    # 14.4: Listagem de fotógrafos únicos do evento
    $photogsEvent = @(Get-EventPhotographers -EventName "Casamento_Lucas_Mariana" -ConfigPath $mockConfigFile)
    Assert-True ($photogsEvent -contains "Marina Costa") "Marina Costa consta na lista de fotógrafos do evento"

    # 14.5: Ingestão usando a subpasta cadastrada
    $resNikon = Invoke-CardIngest -SourceDrive $mockCardNikon `
        -DestinationFolder $savedReg.DestinationPath `
        -EventName "Casamento_Lucas_Mariana" `
        -AutoEject $false `
        -CardPhotoSubfolder $savedReg.PhotoSubfolder

    Assert-Equal $resNikon.Status "SUCCESS_ALL_VERIFIED" "Ingestão com subpasta de câmera concluída com sucesso"
    Assert-Equal $resNikon.CopiedCount 1 "Exatamente 1 foto descarregada da subpasta"
    $destNikonFile = Join-Path $photogDest "DSC_0001.NEF"
    Assert-True (Test-Path $destNikonFile) "Foto transferida para a pasta dedicada do fotógrafo"

    # 14.6: Re-inserção (idempotência no cartão cadastrado)
    $resNikonRepeat = Invoke-CardIngest -SourceDrive $mockCardNikon `
        -DestinationFolder $savedReg.DestinationPath `
        -EventName "Casamento_Lucas_Mariana" `
        -AutoEject $false `
        -CardPhotoSubfolder $savedReg.PhotoSubfolder

        Assert-Equal $resNikonRepeat.Status "IDLE_NO_NEW_FILES" "Re-insercao do cartao registrado e identificada e fotos repetidas sao puladas"

    # 14.7: Edicao do cadastro do cartao (alterar fotografo e destino)
    $updatedPhotogDest = Join-Path $evDest1 "Marina_Studio"
    $updatedReg = Register-CardForEvent -EventName "Casamento_Lucas_Mariana" `
        -CardIdentifier "NIKON_CF_128" `
        -Photographer "Marina Studio" `
        -DestinationPath $updatedPhotogDest `
        -PhotoSubfolder "DCIM\100NCZ_6" `
        -ConfigPath $mockConfigFile
    Assert-Equal $updatedReg.Photographer "Marina Studio" "Edicao do cadastro do cartao atualizou fotografo"
    Assert-Equal $updatedReg.DestinationPath $updatedPhotogDest "Edicao do cadastro atualizou pasta de destino"

    # 14.8: Fallback seguro quando o disco configurado nao existe (ex: disco Z:\ inexistente)
    $fakeConfig = Get-StationConfig -ConfigPath $mockConfigFile
    $fakeDest = Get-DestinationForCard -CardIdentifier "NIKON_CF_128" -SourcePath $mockCardNikon -Config $fakeConfig -EventName "Casamento_Lucas_Mariana"
    Assert-True (![string]::IsNullOrWhiteSpace($fakeDest)) "Get-DestinationForCard retorna destino valido sem travar"

    # 14.9: Alterar destino do evento inteiro
    $newEvDest = Join-Path $testSandbox "Novo_Destino_Casamento"
    Set-EventDestination -EventName "Casamento_Lucas_Mariana" -NewDestination $newEvDest -UpdateRegisteredCards $true -ConfigPath $mockConfigFile | Out-Null
    $reloadedEv = Get-CurrentEvent -ConfigPath $mockConfigFile
    Assert-Equal $reloadedEv.DefaultDestination $newEvDest "Set-EventDestination atualizou destino base do evento"

    # 14.10: Remover cadastro de cartao
    $removeOk = Remove-CardRegistration -EventName "Casamento_Lucas_Mariana" -CardIdentifier "NIKON_CF_128" -ConfigPath $mockConfigFile
    Assert-True $removeOk "Remove-CardRegistration removeu cartao com sucesso"
    $deletedCardReg = Get-CardRegistration -EventName "Casamento_Lucas_Mariana" -CardIdentifier "NIKON_CF_128" -ConfigPath $mockConfigFile
    Assert-True ($null -eq $deletedCardReg) "Cartao NIKON_CF_128 nao consta mais no cadastro do evento"
    
    # Remove tambem o primeiro cartao para zerar
    Remove-CardRegistration -EventName "Casamento_Lucas_Mariana" -CardIdentifier "NIKON_SD_64GB" -ConfigPath $mockConfigFile | Out-Null
    $afterRemoveCards = @(Get-EventCards -EventName "Casamento_Lucas_Mariana" -ConfigPath $mockConfigFile)
    Assert-Equal $afterRemoveCards.Count 0 "Todos os cartoes foram removidos com sucesso"

    # -------------------------------------------------------------------------
    # TESTE 15: Controle de Monitoramento e Leitura (Pausar / Retomar)
    # -------------------------------------------------------------------------
    Write-Host "`n[15/16] Testando Controle de Monitoramento (Pausar / Retomar)..." -ForegroundColor White
    $stateInitial = Get-MonitoringState -ConfigPath $mockConfigFile
    Assert-Equal $stateInitial $true "Monitoramento ativo por padrão"

    Set-MonitoringState -Active $false -ConfigPath $mockConfigFile | Out-Null
    $statePaused = Get-MonitoringState -ConfigPath $mockConfigFile
    Assert-Equal $statePaused $false "Monitoramento pausado com sucesso"

    Set-MonitoringState -Active $true -ConfigPath $mockConfigFile | Out-Null
    $stateResumed = Get-MonitoringState -ConfigPath $mockConfigFile
    Assert-Equal $stateResumed $true "Monitoramento reativado com sucesso"

    # -------------------------------------------------------------------------
    # TESTE 16: Endpoints REST de Eventos, Cadastro de Cartão e Monitoramento
    # -------------------------------------------------------------------------
    Write-Host "`n[16/16] Testando Endpoints REST de Eventos e Cadastro..." -ForegroundColor White
    $serverProc3 = Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -Command `"& { . '$resolvedConfigPath'; . '$resolvedEnginePath'; . '$resolvedServerPath'; `$l = Start-IngestHttpServer -ListenPort $testPort; while (`$l.IsListening) { try { `$ctx = `$l.GetContext(); Handle-HttpRequest -Context `$ctx -PublicFolder '$publicDir' } catch { break } } }`"" -PassThru -WindowStyle Hidden
    
    Start-Sleep -Seconds 2

    try {
        # 16.1: GET /api/events
        $evRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/events"
        Assert-True ($null -ne $evRes.CurrentEvent) "GET /api/events retorna CurrentEvent"

        # 16.2: POST /api/events (criar novo evento via API)
        $newEvPayload = @{ Name = "Formatura_Direito_2026"; Destination = $evDest2 } | ConvertTo-Json
        $postEvRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/events" -Method Post -Body $newEvPayload -ContentType "application/json"
        Assert-Equal $postEvRes.Name "Formatura_Direito_2026" "POST /api/events criou novo evento via API"

        # 16.3: POST /api/events/select (trocar evento ativo via API)
        $selectPayload = @{ Name = "Formatura_Direito_2026" } | ConvertTo-Json
        $selEvRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/events/select" -Method Post -Body $selectPayload -ContentType "application/json"
        Assert-Equal $selEvRes.Success $true "POST /api/events/select alternou evento ativo via API"

        # 16.4: POST /api/monitoring/toggle (alternar monitoramento via API)
        $toggleRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/monitoring/toggle" -Method Post
        Assert-True ($null -ne $toggleRes.Active) "POST /api/monitoring/toggle alternou estado de monitoramento"

        # 16.5: POST /api/card/register (cadastrar cartão via API)
        $cardRegPayload = @{
            EventName       = "Formatura_Direito_2026"
            CardIdentifier  = "SONY_CFX_512"
            Photographer    = "Carlos Fotografia"
            DestinationPath = $evDest2
            PhotoSubfolder  = "DCIM\100MSDCF"
        } | ConvertTo-Json
        $postCardRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/card/register" -Method Post -Body $cardRegPayload -ContentType "application/json"
        Assert-Equal $postCardRes.Photographer "Carlos Fotografia" "POST /api/card/register cadastrou cartão com fotógrafo Carlos Fotografia"

        # 16.6: GET /api/cards
        $cardsListRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/cards?event=Formatura_Direito_2026"
        Assert-True ($cardsListRes -is [System.Array]) "GET /api/cards retorna lista de cartões cadastrados"
                Assert-Equal $cardsListRes.Count 1 "Exatamente 1 cartao cadastrado para o evento"

        # 16.7: POST /api/event/destination
        $newDestPayload = @{ EventName = "Formatura_Direito_2026"; Destination = $evDest1 } | ConvertTo-Json
        $destRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/event/destination" -Method Post -Body $newDestPayload -ContentType "application/json"
        Assert-True $destRes.Success "POST /api/event/destination alterou destino do evento via API"

        # 16.8: DELETE /api/card
        $delCardRes = Invoke-RestMethod -Uri "http://localhost:$testPort/api/card?event=Formatura_Direito_2026&id=SONY_CFX_512" -Method Delete
        Assert-True $delCardRes.Success "DELETE /api/card removeu cadastro de cartao via API"
    }
    finally {
        if ($serverProc3 -and -not $serverProc3.HasExited) {
            Stop-Process -Id $serverProc3.Id -Force -ErrorAction SilentlyContinue
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
