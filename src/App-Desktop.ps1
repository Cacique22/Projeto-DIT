# App-Desktop.ps1 - Aplicativo Desktop Nativo da Estacao de Ingestao DIT
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$enginePath = Join-Path $PSScriptRoot "IngestEngine.ps1"
$configPath = Join-Path $PSScriptRoot "ConfigManager.ps1"

if (Test-Path $enginePath) { . $enginePath }
if (Test-Path $configPath) { . $configPath }

[System.Windows.Forms.Application]::EnableVisualStyles()

# Paleta Dark Mode DIT
$colorBg = [System.Drawing.Color]::FromArgb(11, 15, 25)
$colorSurface = [System.Drawing.Color]::FromArgb(17, 24, 39)
$colorElevated = [System.Drawing.Color]::FromArgb(31, 41, 55)
$colorText = [System.Drawing.Color]::FromArgb(248, 250, 252)
$colorTextMuted = [System.Drawing.Color]::FromArgb(148, 163, 184)
$colorCyan = [System.Drawing.Color]::FromArgb(6, 182, 212)
$colorGreen = [System.Drawing.Color]::FromArgb(16, 185, 129)
$colorRed = [System.Drawing.Color]::FromArgb(239, 68, 68)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Estacao de Ingestao DIT - Backup Seguro"
$form.Size = New-Object System.Drawing.Size(940, 720)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $colorBg
$form.ForeColor = $colorText
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

# Header
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height = 70
$headerPanel.BackColor = $colorSurface
$form.Controls.Add($headerPanel)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "ESTACAO DE INGESTAO DIT"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 13, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $colorText
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.AutoSize = $true
$headerPanel.Controls.Add($lblTitle)

$lblSubTitle = New-Object System.Windows.Forms.Label
$lblSubTitle.Text = "Backup Seguro de Alta Confiabilidade para Eventos Fotograficos"
$lblSubTitle.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblSubTitle.ForeColor = $colorTextMuted
$lblSubTitle.Location = New-Object System.Drawing.Point(22, 38)
$lblSubTitle.AutoSize = $true
$headerPanel.Controls.Add($lblSubTitle)

$lblBadge = New-Object System.Windows.Forms.Label
$lblBadge.Text = "[*] SISTEMA ARMADO"
$lblBadge.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblBadge.ForeColor = $colorGreen
$lblBadge.BackColor = [System.Drawing.Color]::FromArgb(20, 16, 185, 129)
$lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblBadge.Size = New-Object System.Drawing.Size(220, 32)
$lblBadge.Location = New-Object System.Drawing.Point(680, 18)
$headerPanel.Controls.Add($lblBadge)

# Painel Central
$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainPanel.Padding = New-Object System.Windows.Forms.Padding(20)
$form.Controls.Add($mainPanel)

# Grupo 1: Configuracoes
$grpConfig = New-Object System.Windows.Forms.GroupBox
$grpConfig.Text = " Configuracoes de Armazenamento "
$grpConfig.ForeColor = $colorCyan
$grpConfig.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpConfig.Location = New-Object System.Drawing.Point(20, 85)
$grpConfig.Size = New-Object System.Drawing.Size(880, 155)
$mainPanel.Controls.Add($grpConfig)

$lblDest = New-Object System.Windows.Forms.Label
$lblDest.Text = "Onde Deseja Salvar os Arquivos (Destino):"
$lblDest.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblDest.ForeColor = $colorText
$lblDest.Location = New-Object System.Drawing.Point(15, 28)
$lblDest.AutoSize = $true
$grpConfig.Controls.Add($lblDest)

$txtDest = New-Object System.Windows.Forms.TextBox
$txtDest.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtDest.BackColor = $colorElevated
$txtDest.ForeColor = $colorText
$txtDest.Location = New-Object System.Drawing.Point(15, 50)
$txtDest.Size = New-Object System.Drawing.Size(700, 26)
$grpConfig.Controls.Add($txtDest)

$btnBrowseDest = New-Object System.Windows.Forms.Button
$btnBrowseDest.Text = "Procurar Pasta..."
$btnBrowseDest.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnBrowseDest.BackColor = $colorElevated
$btnBrowseDest.ForeColor = $colorText
$btnBrowseDest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseDest.Location = New-Object System.Drawing.Point(725, 48)
$btnBrowseDest.Size = New-Object System.Drawing.Size(140, 30)
$grpConfig.Controls.Add($btnBrowseDest)

$lblEvent = New-Object System.Windows.Forms.Label
$lblEvent.Text = "Nome do Evento:"
$lblEvent.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblEvent.ForeColor = $colorText
$lblEvent.Location = New-Object System.Drawing.Point(15, 88)
$lblEvent.AutoSize = $true
$grpConfig.Controls.Add($lblEvent)

$txtEvent = New-Object System.Windows.Forms.TextBox
$txtEvent.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtEvent.BackColor = $colorElevated
$txtEvent.ForeColor = $colorText
$txtEvent.Location = New-Object System.Drawing.Point(15, 110)
$txtEvent.Size = New-Object System.Drawing.Size(320, 26)
$grpConfig.Controls.Add($txtEvent)

$chkAutoEject = New-Object System.Windows.Forms.CheckBox
$chkAutoEject.Text = "Ejetar o cartao automaticamente apos concluir o backup com seguranca"
$chkAutoEject.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkAutoEject.ForeColor = $colorText
$chkAutoEject.Checked = $true
$chkAutoEject.Location = New-Object System.Drawing.Point(360, 110)
$chkAutoEject.Size = New-Object System.Drawing.Size(400, 26)
$grpConfig.Controls.Add($chkAutoEject)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Salvar"
$btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnSave.BackColor = $colorCyan
$btnSave.ForeColor = [System.Drawing.Color]::Black
$btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSave.Location = New-Object System.Drawing.Point(765, 108)
$btnSave.Size = New-Object System.Drawing.Size(100, 30)
$grpConfig.Controls.Add($btnSave)

# Grupo 2: Monitor de Ingestao e Disparo
$grpMonitor = New-Object System.Windows.Forms.GroupBox
$grpMonitor.Text = " Monitor de Ingestao & Disparo Manual "
$grpMonitor.ForeColor = $colorCyan
$grpMonitor.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpMonitor.Location = New-Object System.Drawing.Point(20, 250)
$grpMonitor.Size = New-Object System.Drawing.Size(880, 175)
$mainPanel.Controls.Add($grpMonitor)

$lblManual = New-Object System.Windows.Forms.Label
$lblManual.Text = "Cartao ou Pasta de Fotos (Deteccao automatica ao plugar, ou selecione manualmente):"
$lblManual.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblManual.ForeColor = $colorText
$lblManual.Location = New-Object System.Drawing.Point(15, 25)
$lblManual.AutoSize = $true
$grpMonitor.Controls.Add($lblManual)

$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtSource.BackColor = $colorElevated
$txtSource.ForeColor = $colorText
$txtSource.Location = New-Object System.Drawing.Point(15, 48)
$txtSource.Size = New-Object System.Drawing.Size(560, 26)
$grpMonitor.Controls.Add($txtSource)

$btnBrowseSrc = New-Object System.Windows.Forms.Button
$btnBrowseSrc.Text = "Selecionar Cartao..."
$btnBrowseSrc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnBrowseSrc.BackColor = $colorElevated
$btnBrowseSrc.ForeColor = $colorText
$btnBrowseSrc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseSrc.Location = New-Object System.Drawing.Point(585, 46)
$btnBrowseSrc.Size = New-Object System.Drawing.Size(150, 30)
$grpMonitor.Controls.Add($btnBrowseSrc)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Ingerir Agora"
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnStart.BackColor = $colorGreen
$btnStart.ForeColor = [System.Drawing.Color]::Black
$btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStart.Location = New-Object System.Drawing.Point(745, 46)
$btnStart.Size = New-Object System.Drawing.Size(120, 30)
$grpMonitor.Controls.Add($btnStart)

# Barra de Progresso
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 90)
$progressBar.Size = New-Object System.Drawing.Size(850, 24)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$grpMonitor.Controls.Add($progressBar)

$lblStatusDetail = New-Object System.Windows.Forms.Label
$lblStatusDetail.Text = "Aguardando conexao de cartoes SD / Leitores USB..."
$lblStatusDetail.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatusDetail.ForeColor = $colorTextMuted
$lblStatusDetail.Location = New-Object System.Drawing.Point(15, 122)
$lblStatusDetail.Size = New-Object System.Drawing.Size(850, 20)
$grpMonitor.Controls.Add($lblStatusDetail)

$lblFileDetail = New-Object System.Windows.Forms.Label
$lblFileDetail.Text = ""
$lblFileDetail.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFileDetail.ForeColor = $colorCyan
$lblFileDetail.Location = New-Object System.Drawing.Point(15, 144)
$lblFileDetail.Size = New-Object System.Drawing.Size(850, 20)
$grpMonitor.Controls.Add($lblFileDetail)

# Grupo 3: Historico de Auditoria
$grpHistory = New-Object System.Windows.Forms.GroupBox
$grpHistory.Text = " Historico de Auditoria da Sessao "
$grpHistory.ForeColor = $colorCyan
$grpHistory.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpHistory.Location = New-Object System.Drawing.Point(20, 435)
$grpHistory.Size = New-Object System.Drawing.Size(880, 220)
$mainPanel.Controls.Add($grpHistory)

$gridHistory = New-Object System.Windows.Forms.ListView
$gridHistory.View = [System.Windows.Forms.View]::Details
$gridHistory.FullRowSelect = $true
$gridHistory.GridLines = $true
$gridHistory.BackColor = $colorSurface
$gridHistory.ForeColor = $colorText
$gridHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$gridHistory.Location = New-Object System.Drawing.Point(15, 25)
$gridHistory.Size = New-Object System.Drawing.Size(850, 180)

[void]$gridHistory.Columns.Add("Horario", 100)
[void]$gridHistory.Columns.Add("Fotografo / Cartao", 240)
[void]$gridHistory.Columns.Add("Fotos Novas", 120)
[void]$gridHistory.Columns.Add("Ignoradas (Salvas)", 140)
[void]$gridHistory.Columns.Add("Volume", 110)
[void]$gridHistory.Columns.Add("Ejecao", 120)
$grpHistory.Controls.Add($gridHistory)

function Load-FormConfig {
    $cfg = Get-StationConfig
    $txtDest.Text = $cfg.TargetRootPath
    $txtEvent.Text = $cfg.EventName
    $chkAutoEject.Checked = ($cfg.AutoEject -ne $false)
}

$btnBrowseDest.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a Pasta onde deseja salvar os backups"
    $fbd.SelectedPath = $txtDest.Text
    $fbd.ShowNewFolderButton = $true
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtDest.Text = $fbd.SelectedPath
    }
})

$btnBrowseSrc.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione o Cartao SD ou Pasta de Fotos de Origem"
    $fbd.ShowNewFolderButton = $false
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSource.Text = $fbd.SelectedPath
    }
})

$btnSave.Add_Click({
    $ht = @{
        TargetRootPath = $txtDest.Text.Trim()
        EventName = $txtEvent.Text.Trim()
        AutoEject = $chkAutoEject.Checked
    }
    Set-StationConfig -Config $ht | Out-Null
    [System.Windows.Forms.MessageBox]::Show($form, "Configuracoes salvas com sucesso!", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

function Run-AppIngest {
    param([string]$SourcePath)
    
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path $SourcePath)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Caminho de origem nao encontrado: $SourcePath", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $lblBadge.Text = "[*] INGESTAO EM ANDAMENTO"
    $lblBadge.ForeColor = $colorCyan
    $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(30, 6, 182, 212)
    $btnStart.Enabled = $false
    $progressBar.Value = 0
    $lblStatusDetail.Text = "Iniciando verificacao de integridade..."
    $lblFileDetail.Text = ""
    $form.Update()
    
    try {
        $res = Invoke-CardIngest -SourceDrive $SourcePath `
            -DestinationFolder $txtDest.Text.Trim() `
            -EventName $txtEvent.Text.Trim() `
            -AutoEject $chkAutoEject.Checked `
            -ProgressCallback {
                param($p)
                $pct = if ($p.TotalFiles -gt 0) { [math]::Round(($p.CurrentIndex / $p.TotalFiles) * 100) } else { 0 }
                $progressBar.Value = [math]::Min(100, [math]::Max(0, $pct))
                $mbCopied = [math]::Round($p.BytesCopied / 1MB, 1)
                $mbTotal = [math]::Round($p.TotalBytes / 1MB, 1)
                $lblStatusDetail.Text = "Copiando e validando SHA-256: " + $p.CurrentIndex + " / " + $p.TotalFiles + " fotos (" + $mbCopied + " MB de " + $mbTotal + " MB)"
                $lblFileDetail.Text = "Foto: " + $p.CurrentFile
                $form.Update()
            }
        
        $progressBar.Value = 100
        $mbTotalDone = [math]::Round($res.TotalBytesCopied / 1MB, 1)
        
        $item = New-Object System.Windows.Forms.ListViewItem((Get-Date -Format "HH:mm:ss"))
        [void]$item.SubItems.Add($res.CardIdentifier)
        [void]$item.SubItems.Add("+" + $res.CopiedCount + " fotos")
        [void]$item.SubItems.Add($res.SkippedCount.ToString() + " fotos")
        [void]$item.SubItems.Add($mbTotalDone.ToString() + " MB")
        [void]$item.SubItems.Add($(if ($res.Ejected) { "[OK] Ejetado" } else { "-" }))
        $gridHistory.Items.Insert(0, $item)
        
        if ($res.Ejected) {
            $lblBadge.Text = "[OK] CONCLUIDO & EJETADO"
            $lblBadge.ForeColor = $colorGreen
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
            $lblStatusDetail.Text = "Backup 100% verificado! Cartao ejetado com seguranca pelo Windows. Pode retira-lo."
            $lblFileDetail.Text = ""
            [System.Windows.Forms.MessageBox]::Show($form, "Backup concluido com sucesso e verificado com SHA-256!`n`nO cartao foi ejetado automaticamente pelo Windows.`nVoce pode retira-lo agora sem abrir o explorador.", "Sucesso DIT", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            $lblBadge.Text = "[*] SISTEMA ARMADO"
            $lblBadge.ForeColor = $colorGreen
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(20, 16, 185, 129)
            $lblStatusDetail.Text = "Backup concluido com sucesso."
        }
    }
    catch {
        $lblBadge.Text = "[X] ERRO NA INGESTAO"
        $lblBadge.ForeColor = $colorRed
        $lblStatusDetail.Text = "Erro: $_"
        [System.Windows.Forms.MessageBox]::Show($form, "Erro durante a ingestao: $_", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        $btnStart.Enabled = $true
        $form.Update()
    }
}

$btnStart.Add_Click({
    Run-AppIngest -SourcePath $txtSource.Text.Trim()
})

$knownDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$drives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
foreach ($d in $drives) { [void]$knownDrives.Add($d.Name) }

$usbTimer = New-Object System.Windows.Forms.Timer
$usbTimer.Interval = 1500
$usbTimer.Add_Tick({
    try {
        $currentReady = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
        $currentSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        
        foreach ($d in $currentReady) {
            $driveName = $d.Name
            [void]$currentSet.Add($driveName)
            
            if (-not $knownDrives.Contains($driveName)) {
                Start-Sleep -Milliseconds 1000
                $dcim = Join-Path $driveName "DCIM"
                $fotografoTxt = Join-Path $driveName "fotografo.txt"
                $photos = Get-ChildItem -Path $driveName -File -ErrorAction SilentlyContinue | Where-Object {
                    $script:SUPPORTED_EXTENSIONS -contains $_.Extension.ToUpper()
                }
                
                if ((Test-Path $dcim) -or (Test-Path $fotografoTxt) -or ($photos -and $photos.Count -gt 0)) {
                    $txtSource.Text = $driveName
                    Run-AppIngest -SourcePath $driveName
                }
                
                [void]$knownDrives.Add($driveName)
            }
        }
        
        $removed = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $knownDrives) {
            if (-not $currentSet.Contains($k)) { $removed.Add($k) }
        }
        foreach ($rem in $removed) {
            [void]$knownDrives.Remove($rem)
        }
    } catch {}
})

Load-FormConfig
$usbTimer.Start()

[void]$form.ShowDialog()
$usbTimer.Stop()
$usbTimer.Dispose()
$form.Dispose()
