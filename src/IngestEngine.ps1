# Suporte a extensões fotográficas e de vídeo profissionais
$script:SUPPORTED_EXTENSIONS = @(
    ".CR2", ".CR3",        # Canon RAW
    ".ARW",                # Sony RAW
    ".NEF",                # Nikon RAW
    ".DNG",                # Adobe Digital Negative / Leica / Drones
    ".RAF",                # Fujifilm RAW
    ".RW2",                # Panasonic RAW
    ".ORF",                # Olympus RAW
    ".JPG", ".JPEG",       # JPEGs de alta resolução
    ".HEIC", ".HIF",       # High Efficiency Images
    ".MP4", ".MOV"         # Vídeos do evento
)

function Get-FileSha256 {
    param([Parameter(Mandatory=$true)][string]$FilePath)
    
    if (!(Test-Path $FilePath)) {
        throw "Arquivo não encontrado para cálculo de hash: $FilePath"
    }

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    
    try {
        $hashBytes = $sha256.ComputeHash($stream)
        $sb = New-Object System.Text.StringBuilder
        foreach ($b in $hashBytes) {
            [void]$sb.Append($b.ToString("x2"))
        }
        return $sb.ToString()
    }
    finally {
        $stream.Close()
        $stream.Dispose()
        $sha256.Dispose()
    }
}

function Get-CardIdentifier {
    param([Parameter(Mandatory=$true)][string]$DriveLetter)
    
    $cleanPath = $DriveLetter.TrimEnd("\")
    
    # 1. Checa se o fotógrafo colocou um arquivo com o nome dele na raiz
    $nameFiles = @(
        (Join-Path $cleanPath "fotografo.txt"),
        (Join-Path $cleanPath "photographer.txt"),
        (Join-Path $cleanPath "camera.txt")
    )
    foreach ($nf in $nameFiles) {
        if (Test-Path $nf) {
            $name = (Get-Content $nf -TotalCount 1).Trim()
            if (![string]::IsNullOrWhiteSpace($name)) {
                return ($name -replace '[\\/:*?"<>|]', '_')
            }
        }
    }
    
    # Se for uma letra de drive (ex: "E:" ou "E")
    if ($cleanPath -match '^[A-Za-z]:?$') {
        $cleanLetter = $cleanPath.TrimEnd(":")
        $vol = Get-Volume -DriveLetter $cleanLetter -ErrorAction SilentlyContinue
        
        if ($vol -and ![string]::IsNullOrWhiteSpace($vol.FileSystemLabel) -and $vol.FileSystemLabel -notmatch "^(NO_NAME|EOS_DIGITAL|UNTITLED|VOLUME)$") {
            return ($vol.FileSystemLabel -replace '[\\/:*?"<>|]', '_')
        }
        
        if ($vol -and ![string]::IsNullOrWhiteSpace($vol.SerialNumber)) {
            return "Cartao_$($vol.SerialNumber)"
        }
        return "Cartao_Drive_$cleanLetter"
    }
    
    # Se for uma pasta (em testes ou em rede)
    $folderName = [System.IO.Path]::GetFileName($cleanPath)
    if (![string]::IsNullOrWhiteSpace($folderName)) {
        return $folderName
    }
    
    return "Cartao_Desconhecido"
}

function Test-PreFlightDiskSpace {
    param(
        [Parameter(Mandatory=$true)][string]$TargetPath,
        [Parameter(Mandatory=$true)][int64]$RequiredBytes
    )
    
    if (!(Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }
    
    $driveRoot = [System.IO.Path]::GetPathRoot([System.IO.Path]::GetFullPath($TargetPath))
    $driveInfo = [System.IO.DriveInfo]::new($driveRoot)
    $freeBytes = $driveInfo.AvailableFreeSpace
    
    $safetyThreshold = [int64]($RequiredBytes * 1.10)
    
    if ($freeBytes -lt $safetyThreshold) {
        $freeGb = [math]::Round($freeBytes / 1GB, 2)
        $reqGb = [math]::Round($safetyThreshold / 1GB, 2)
        return @{
            IsSufficient = $false
            FreeBytes = $freeBytes
            RequiredBytesWithMargin = $safetyThreshold
            Message = "Espaço insuficiente em $driveRoot. Disponível: $freeGb GB | Necessário: $reqGb GB"
        }
    }
    
    return @{
        IsSufficient = $true
        FreeBytes = $freeBytes
        RequiredBytesWithMargin = $safetyThreshold
        Message = "Espaço em disco validado com sucesso."
    }
}

function Emit-IngestSound {
    param([ValidateSet("Start", "Success", "Error")][string]$Type)
    
    try {
        switch ($Type) {
            "Start" {
                [Console]::Beep(523, 150)
            }
            "Success" {
                [Console]::Beep(523, 120)
                [Console]::Beep(659, 120)
                [Console]::Beep(784, 300)
            }
            "Error" {
                [Console]::Beep(220, 400)
                Start-Sleep -Milliseconds 100
                [Console]::Beep(220, 600)
            }
        }
    } catch {}
}

function Invoke-CardIngest {
    param(
        [Parameter(Mandatory=$true)][string]$SourceDrive,
        [Parameter(Mandatory=$true)][string]$DestinationFolder,
        [Parameter(Mandatory=$false)][string]$EventName = "Evento_Geral",
        [Parameter(Mandatory=$false)][scriptblock]$ProgressCallback = $null
    )
    
    $startTime = [System.DateTime]::UtcNow
    $cleanSource = $SourceDrive.TrimEnd("\") + "\"
    
    if (!(Test-Path $cleanSource)) {
        throw "Drive de origem não encontrado ou indisponível: $cleanSource"
    }
    
    $cardId = Get-CardIdentifier -DriveLetter $cleanSource
    $finalDestination = [System.IO.Path]::Combine($DestinationFolder, $EventName, $cardId)
    $manifestPath = [System.IO.Path]::Combine($finalDestination, "manifest.jsonl")
    
    if (!(Test-Path $finalDestination)) {
        New-Item -ItemType Directory -Path $finalDestination -Force | Out-Null
    }
    
    $idempotencyMap = @{}
    if (Test-Path $manifestPath) {
        Get-Content $manifestPath -Encoding UTF8 | ForEach-Object {
            if (![string]::IsNullOrWhiteSpace($_)) {
                try {
                    $entry = $_ | ConvertFrom-Json
                    if ($entry.status -eq "VERIFIED_OK") {
                        $idempotencyMap[$entry.relative_path] = $entry.sha256
                    }
                } catch {}
            }
        }
    }
    
    $allFiles = Get-ChildItem -Path $cleanSource -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $script:SUPPORTED_EXTENSIONS -contains $_.Extension.ToUpper()
    }
    
    $filesToCopy = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $totalNewBytes = [int64]0
    $skippedCount = 0
    
    foreach ($file in $allFiles) {
        $relPath = $file.FullName.Substring($cleanSource.Length)
        $destCandidate = [System.IO.Path]::Combine($finalDestination, $relPath)
        
        if ($idempotencyMap.ContainsKey($relPath) -and (Test-Path $destCandidate)) {
            $destItem = Get-Item $destCandidate
            if ($destItem.Length -eq $file.Length) {
                $skippedCount++
                continue
            }
        }
        
        $filesToCopy.Add($file)
        $totalNewBytes += $file.Length
    }
    
    if ($filesToCopy.Count -eq 0) {
        Emit-IngestSound -Type "Success"
        return @{
            Status = "IDLE_NO_NEW_FILES"
            TotalFound = $allFiles.Count
            CopiedCount = 0
            SkippedCount = $skippedCount
            TotalBytesCopied = 0
            CardIdentifier = $cardId
            Destination = $finalDestination
            DurationSeconds = 0
            Errors = @()
        }
    }
    
    $spaceCheck = Test-PreFlightDiskSpace -TargetPath $finalDestination -RequiredBytes $totalNewBytes
    if (-not $spaceCheck.IsSufficient) {
        Emit-IngestSound -Type "Error"
        throw "ABORTADO POR SEGURANÇA: $($spaceCheck.Message)"
    }
    
    Emit-IngestSound -Type "Start"
    
    $copiedCount = 0
    $bytesTransferred = [int64]0
    $errors = [System.Collections.Generic.List[string]]::new()
    
    for ($i = 0; $i -lt $filesToCopy.Count; $i++) {
        $srcFile = $filesToCopy[$i]
        $relPath = $srcFile.FullName.Substring($cleanSource.Length)
        $targetFile = [System.IO.Path]::Combine($finalDestination, $relPath)
        $targetDir = [System.IO.Path]::GetDirectoryName($targetFile)
        $stagingFile = $targetFile + ".staging.tmp"
        
        if (!(Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        if (Test-Path $stagingFile) {
            Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue
        }
        
        try {
            [System.IO.File]::Copy($srcFile.FullName, $stagingFile, $true)
            
            $stagingItem = Get-Item $stagingFile
            if ($stagingItem.Length -ne $srcFile.Length) {
                throw "Tamanho divergente: Esperado $($srcFile.Length) bytes, obtido $($stagingItem.Length) bytes"
            }
            
            $srcHash = Get-FileSha256 -FilePath $srcFile.FullName
            $destHash = Get-FileSha256 -FilePath $stagingFile
            
            if ($srcHash -ne $destHash) {
                throw "CORRUPÇÃO DE DADOS: Hash SHA-256 não confere!"
            }
            
            if (Test-Path $targetFile) {
                Remove-Item -Path $targetFile -Force
            }
            [System.IO.File]::Move($stagingFile, $targetFile)
            
            $ledgerEntry = [ordered]@{
                timestamp_utc = [System.DateTime]::UtcNow.ToString("o")
                card_identifier = $cardId
                relative_path = $relPath
                bytes = $srcFile.Length
                sha256 = $srcHash
                status = "VERIFIED_OK"
            }
            $jsonLine = $ledgerEntry | ConvertTo-Json -Compress
            [System.IO.File]::AppendAllLines($manifestPath, [string[]]@($jsonLine), [System.Text.Encoding]::UTF8)
            
            $copiedCount++
            $bytesTransferred += $srcFile.Length
            
            if ($ProgressCallback) {
                & $ProgressCallback @{
                    CurrentIndex = $i + 1
                    TotalFiles = $filesToCopy.Count
                    CurrentFile = $srcFile.Name
                    BytesCopied = $bytesTransferred
                    TotalBytes = $totalNewBytes
                }
            }
        }
        catch {
            $errMessage = "Falha no arquivo $relPath : $_"
            $errors.Add($errMessage)
            
            if (Test-Path $stagingFile) {
                Remove-Item -Path $stagingFile -Force -ErrorAction SilentlyContinue
            }
            
            $failEntry = [ordered]@{
                timestamp_utc = [System.DateTime]::UtcNow.ToString("o")
                card_identifier = $cardId
                relative_path = $relPath
                bytes = $srcFile.Length
                error = "$_"
                status = "FAILED"
            }
            $jsonLine = $failEntry | ConvertTo-Json -Compress
            [System.IO.File]::AppendAllLines($manifestPath, [string[]]@($jsonLine), [System.Text.Encoding]::UTF8)
        }
    }
    
    $endTime = [System.DateTime]::UtcNow
    $duration = [math]::Round(($endTime - $startTime).TotalSeconds, 2)
    
    if ($errors.Count -eq 0) {
        Emit-IngestSound -Type "Success"
        $status = "SUCCESS_ALL_VERIFIED"
    } else {
        Emit-IngestSound -Type "Error"
        $status = "COMPLETED_WITH_ERRORS"
    }
    
    return @{
        Status = $status
        TotalFound = $allFiles.Count
        CopiedCount = $copiedCount
        SkippedCount = $skippedCount
        TotalBytesCopied = $bytesTransferred
        CardIdentifier = $cardId
        Destination = $finalDestination
        DurationSeconds = $duration
        Errors = $errors
    }
}
