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
$colorAmber = [System.Drawing.Color]::FromArgb(245, 158, 11)
$colorRed = [System.Drawing.Color]::FromArgb(239, 68, 68)

$script:IsIngesting = $false
$script:CancelRequested = $false

$form = New-Object System.Windows.Forms.Form
$form.Text = "Estacao de Ingestao DIT - Backup Seguro Multi-Cartao"
$form.Size = New-Object System.Drawing.Size(980, 840)
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
$lblSubTitle.Text = "Backup Seguro Multi-Cartao, Interrupcao Limpa e Validacao SHA-256"
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
$lblBadge.Size = New-Object System.Drawing.Size(240, 32)
$lblBadge.Location = New-Object System.Drawing.Point(700, 18)
$headerPanel.Controls.Add($lblBadge)

# Painel Central Scrollable
$scrollPanel = New-Object System.Windows.Forms.Panel
$scrollPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$scrollPanel.AutoScroll = $true
$scrollPanel.Padding = New-Object System.Windows.Forms.Padding(20)
$form.Controls.Add($scrollPanel)

# Grupo 1: Configuracoes Globais
$grpConfig = New-Object System.Windows.Forms.GroupBox
$grpConfig.Text = " Configuracoes Padrao "
$grpConfig.ForeColor = $colorCyan
$grpConfig.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpConfig.Location = New-Object System.Drawing.Point(20, 10)
$grpConfig.Size = New-Object System.Drawing.Size(920, 150)
$scrollPanel.Controls.Add($grpConfig)

$lblDest = New-Object System.Windows.Forms.Label
$lblDest.Text = "Destino Padrao (Quando o cartao nao tiver regra especifica):"
$lblDest.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblDest.ForeColor = $colorText
$lblDest.Location = New-Object System.Drawing.Point(15, 26)
$lblDest.AutoSize = $true
$grpConfig.Controls.Add($lblDest)

$txtDest = New-Object System.Windows.Forms.TextBox
$txtDest.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtDest.BackColor = $colorElevated
$txtDest.ForeColor = $colorText
$txtDest.Location = New-Object System.Drawing.Point(15, 48)
$txtDest.Size = New-Object System.Drawing.Size(740, 26)
$grpConfig.Controls.Add($txtDest)

$btnBrowseDest = New-Object System.Windows.Forms.Button
$btnBrowseDest.Text = "Procurar..."
$btnBrowseDest.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnBrowseDest.BackColor = $colorElevated
$btnBrowseDest.ForeColor = $colorText
$btnBrowseDest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseDest.Location = New-Object System.Drawing.Point(765, 46)
$btnBrowseDest.Size = New-Object System.Drawing.Size(140, 30)
$grpConfig.Controls.Add($btnBrowseDest)

$lblEvent = New-Object System.Windows.Forms.Label
$lblEvent.Text = "Nome do Evento:"
$lblEvent.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblEvent.ForeColor = $colorText
$lblEvent.Location = New-Object System.Drawing.Point(15, 84)
$lblEvent.AutoSize = $true
$grpConfig.Controls.Add($lblEvent)

$txtEvent = New-Object System.Windows.Forms.TextBox
$txtEvent.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$txtEvent.BackColor = $colorElevated
$txtEvent.ForeColor = $colorText
$txtEvent.Location = New-Object System.Drawing.Point(15, 106)
$txtEvent.Size = New-Object System.Drawing.Size(320, 26)
$grpConfig.Controls.Add($txtEvent)

$chkAutoEject = New-Object System.Windows.Forms.CheckBox
$chkAutoEject.Text = "Ejetar cartao automaticamente ao concluir backup com sucesso"
$chkAutoEject.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$chkAutoEject.ForeColor = $colorText
$chkAutoEject.Checked = $true
$chkAutoEject.Location = New-Object System.Drawing.Point(360, 106)
$chkAutoEject.Size = New-Object System.Drawing.Size(420, 26)
$grpConfig.Controls.Add($chkAutoEject)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "Salvar"
$btnSave.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnSave.BackColor = $colorCyan
$btnSave.ForeColor = [System.Drawing.Color]::Black
$btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSave.Location = New-Object System.Drawing.Point(805, 104)
$btnSave.Size = New-Object System.Drawing.Size(100, 30)
$grpConfig.Controls.Add($btnSave)

# Grupo 2: Mapeamento Multi-Cartao (Destinos Diferentes por Cartao)
$grpMappings = New-Object System.Windows.Forms.GroupBox
$grpMappings.Text = " Mapeamento de Cartoes & Destinos Personalizados "
$grpMappings.ForeColor = $colorCyan
$grpMappings.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpMappings.Location = New-Object System.Drawing.Point(20, 170)
$grpMappings.Size = New-Object System.Drawing.Size(920, 195)
$scrollPanel.Controls.Add($grpMappings)

$gridMappings = New-Object System.Windows.Forms.ListView
$gridMappings.View = [System.Windows.Forms.View]::Details
$gridMappings.FullRowSelect = $true
$gridMappings.GridLines = $true
$gridMappings.BackColor = $colorSurface
$gridMappings.ForeColor = $colorText
$gridMappings.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$gridMappings.Location = New-Object System.Drawing.Point(15, 25)
$gridMappings.Size = New-Object System.Drawing.Size(890, 95)

[void]$gridMappings.Columns.Add("Cartao / Drive", 160)
[void]$gridMappings.Columns.Add("Pasta de Destino Exclusiva", 500)
[void]$gridMappings.Columns.Add("Descricao / Fotografo", 210)
$grpMappings.Controls.Add($gridMappings)

# Inputs para adicionar novo mapeamento
$txtMapId = New-Object System.Windows.Forms.TextBox
$txtMapId.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtMapId.BackColor = $colorElevated
$txtMapId.ForeColor = $colorText
$txtMapId.Location = New-Object System.Drawing.Point(15, 130)
$txtMapId.Size = New-Object System.Drawing.Size(160, 24)
$grpMappings.Controls.Add($txtMapId)

$txtMapDest = New-Object System.Windows.Forms.TextBox
$txtMapDest.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtMapDest.BackColor = $colorElevated
$txtMapDest.ForeColor = $colorText
$txtMapDest.Location = New-Object System.Drawing.Point(185, 130)
$txtMapDest.Size = New-Object System.Drawing.Size(390, 24)
$grpMappings.Controls.Add($txtMapDest)

$btnBrowseMapDest = New-Object System.Windows.Forms.Button
$btnBrowseMapDest.Text = "Procurar..."
$btnBrowseMapDest.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnBrowseMapDest.BackColor = $colorElevated
$btnBrowseMapDest.ForeColor = $colorText
$btnBrowseMapDest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseMapDest.Location = New-Object System.Drawing.Point(585, 128)
$btnBrowseMapDest.Size = New-Object System.Drawing.Size(90, 28)
$grpMappings.Controls.Add($btnBrowseMapDest)

$txtMapDesc = New-Object System.Windows.Forms.TextBox
$txtMapDesc.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$txtMapDesc.BackColor = $colorElevated
$txtMapDesc.ForeColor = $colorText
$txtMapDesc.Location = New-Object System.Drawing.Point(685, 130)
$txtMapDesc.Size = New-Object System.Drawing.Size(120, 24)
$grpMappings.Controls.Add($txtMapDesc)

$btnAddMap = New-Object System.Windows.Forms.Button
$btnAddMap.Text = "+ Adicionar"
$btnAddMap.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
$btnAddMap.BackColor = $colorCyan
$btnAddMap.ForeColor = [System.Drawing.Color]::Black
$btnAddMap.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAddMap.Location = New-Object System.Drawing.Point(815, 128)
$btnAddMap.Size = New-Object System.Drawing.Size(90, 28)
$grpMappings.Controls.Add($btnAddMap)

$btnRemoveMap = New-Object System.Windows.Forms.Button
$btnRemoveMap.Text = "Remover Selecionado"
$btnRemoveMap.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$btnRemoveMap.BackColor = $colorElevated
$btnRemoveMap.ForeColor = $colorRed
$btnRemoveMap.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRemoveMap.Location = New-Object System.Drawing.Point(755, 160)
$btnRemoveMap.Size = New-Object System.Drawing.Size(150, 24)
$grpMappings.Controls.Add($btnRemoveMap)

# Dica de preenchimento
$lblMapTip = New-Object System.Windows.Forms.Label
$lblMapTip.Text = "Ex: Cartao/Drive: 'EOS_DIGITAL' ou 'E:' | Destino: 'D:\Backups_Eventos\Camera_Lucas' | Fotografo: 'Lucas'"
$lblMapTip.Font = New-Object System.Drawing.Font("Segoe UI", 8)
$lblMapTip.ForeColor = $colorTextMuted
$lblMapTip.Location = New-Object System.Drawing.Point(15, 162)
$lblMapTip.AutoSize = $true
$grpMappings.Controls.Add($lblMapTip)

# Grupo 3: Monitor de Ingestao e Botoes de Acao (Iniciar e Cancelar)
$grpMonitor = New-Object System.Windows.Forms.GroupBox
$grpMonitor.Text = " Monitor de Ingestao & Controles de Execucao "
$grpMonitor.ForeColor = $colorCyan
$grpMonitor.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpMonitor.Location = New-Object System.Drawing.Point(20, 375)
$grpMonitor.Size = New-Object System.Drawing.Size(920, 190)
$scrollPanel.Controls.Add($grpMonitor)

$lblManual = New-Object System.Windows.Forms.Label
$lblManual.Text = "Cartao ou Pasta de Fotos (Deteccao automatica, ou selecione manualmente):"
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
$txtSource.Size = New-Object System.Drawing.Size(470, 26)
$grpMonitor.Controls.Add($txtSource)

$btnBrowseSrc = New-Object System.Windows.Forms.Button
$btnBrowseSrc.Text = "Selecionar Cartao..."
$btnBrowseSrc.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnBrowseSrc.BackColor = $colorElevated
$btnBrowseSrc.ForeColor = $colorText
$btnBrowseSrc.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseSrc.Location = New-Object System.Drawing.Point(495, 46)
$btnBrowseSrc.Size = New-Object System.Drawing.Size(150, 30)
$grpMonitor.Controls.Add($btnBrowseSrc)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Ingerir Agora"
$btnStart.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnStart.BackColor = $colorGreen
$btnStart.ForeColor = [System.Drawing.Color]::Black
$btnStart.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnStart.Location = New-Object System.Drawing.Point(655, 46)
$btnStart.Size = New-Object System.Drawing.Size(120, 30)
$grpMonitor.Controls.Add($btnStart)

# BOTAO DE CANCELAMENTO SEGURO
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Parar com Seguranca"
$btnCancel.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnCancel.BackColor = $colorElevated
$btnCancel.ForeColor = $colorAmber
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.Location = New-Object System.Drawing.Point(785, 46)
$btnCancel.Size = New-Object System.Drawing.Size(125, 30)
$btnCancel.Enabled = $false
$grpMonitor.Controls.Add($btnCancel)

# Barra de Progresso
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(15, 90)
$progressBar.Size = New-Object System.Drawing.Size(890, 24)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$grpMonitor.Controls.Add($progressBar)

$lblStatusDetail = New-Object System.Windows.Forms.Label
$lblStatusDetail.Text = "Aguardando conexao de cartoes SD / Leitores USB..."
$lblStatusDetail.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatusDetail.ForeColor = $colorTextMuted
$lblStatusDetail.Location = New-Object System.Drawing.Point(15, 122)
$lblStatusDetail.Size = New-Object System.Drawing.Size(890, 20)
$grpMonitor.Controls.Add($lblStatusDetail)

$lblFileDetail = New-Object System.Windows.Forms.Label
$lblFileDetail.Text = ""
$lblFileDetail.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblFileDetail.ForeColor = $colorCyan
$lblFileDetail.Location = New-Object System.Drawing.Point(15, 144)
$lblFileDetail.Size = New-Object System.Drawing.Size(890, 20)
$grpMonitor.Controls.Add($lblFileDetail)

# Grupo 4: Historico de Auditoria
$grpHistory = New-Object System.Windows.Forms.GroupBox
$grpHistory.Text = " Historico de Auditoria da Sessao "
$grpHistory.ForeColor = $colorCyan
$grpHistory.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$grpHistory.Location = New-Object System.Drawing.Point(20, 575)
$grpHistory.Size = New-Object System.Drawing.Size(920, 210)
$scrollPanel.Controls.Add($grpHistory)

$gridHistory = New-Object System.Windows.Forms.ListView
$gridHistory.View = [System.Windows.Forms.View]::Details
$gridHistory.FullRowSelect = $true
$gridHistory.GridLines = $true
$gridHistory.BackColor = $colorSurface
$gridHistory.ForeColor = $colorText
$gridHistory.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$gridHistory.Location = New-Object System.Drawing.Point(15, 25)
$gridHistory.Size = New-Object System.Drawing.Size(890, 170)

[void]$gridHistory.Columns.Add("Horario", 90)
[void]$gridHistory.Columns.Add("Fotografo / Cartao", 200)
[void]$gridHistory.Columns.Add("Fotos Novas", 110)
[void]$gridHistory.Columns.Add("Ignoradas (Salvas)", 130)
[void]$gridHistory.Columns.Add("Volume", 100)
[void]$gridHistory.Columns.Add("Status / Ejecao", 240)
$grpHistory.Controls.Add($gridHistory)

# Funcoes de Carga e Atualizacao
function Refresh-MappingsGrid {
    $cfg = Get-StationConfig
    $gridMappings.Items.Clear()
    if ($cfg.CardMappings) {
        foreach ($m in $cfg.CardMappings) {
            $item = New-Object System.Windows.Forms.ListViewItem($m.Identifier.ToString())
            [void]$item.SubItems.Add($m.Destination.ToString())
            [void]$item.SubItems.Add($(if ($m.Description) { $m.Description.ToString() } else { "" }))
            $gridMappings.Items.Add($item)
        }
    }
}

function Load-FormConfig {
    $cfg = Get-StationConfig
    $txtDest.Text = $cfg.TargetRootPath
    $txtEvent.Text = $cfg.EventName
    $chkAutoEject.Checked = ($cfg.AutoEject -ne $false)
    Refresh-MappingsGrid
}

$btnBrowseDest.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a Pasta onde deseja salvar os backups padrao"
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

$btnBrowseMapDest.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a Pasta de Destino Exclusiva para este Cartao"
    $fbd.ShowNewFolderButton = $true
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtMapDest.Text = $fbd.SelectedPath
    }
})

$btnAddMap.Add_Click({
    $id = $txtMapId.Text.Trim()
    $dst = $txtMapDest.Text.Trim()
    $desc = $txtMapDesc.Text.Trim()
    
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($dst)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Preencha o Identificador do Cartao/Drive e a Pasta de Destino.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    Add-CardMappingRule -Identifier $id -Destination $dst -Description $desc
    $txtMapId.Text = ""
    $txtMapDest.Text = ""
    $txtMapDesc.Text = ""
    Refresh-MappingsGrid
    [System.Windows.Forms.MessageBox]::Show($form, "Regra de mapeamento adicionada com sucesso!", "Sucesso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
})

$btnRemoveMap.Add_Click({
    if ($gridMappings.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($form, "Selecione uma regra na tabela para remover.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    $selectedId = $gridMappings.SelectedItems[0].Text
    Remove-CardMappingRule -Identifier $selectedId
    Refresh-MappingsGrid
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

# ACAO DE CANCELAMENTO
$btnCancel.Add_Click({
    if ($script:IsIngesting) {
        $script:CancelRequested = $true
        $btnCancel.Enabled = $false
        $lblStatusDetail.Text = "Interrupcao solicitada. Finalizando foto atual e limpando arquivos temporarios com seguranca..."
        $form.Update()
    }
})

function Run-AppIngest {
    param([string]$SourcePath)
    
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or -not (Test-Path $SourcePath)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Caminho de origem nao encontrado: $SourcePath", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    $script:IsIngesting = $true
    $script:CancelRequested = $false
    
    $lblBadge.Text = "[*] INGESTAO EM ANDAMENTO"
    $lblBadge.ForeColor = $colorCyan
    $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(30, 6, 182, 212)
    $btnStart.Enabled = $false
    $btnCancel.Enabled = $true
    $progressBar.Value = 0
    $lblStatusDetail.Text = "Iniciando verificacao de integridade..."
    $lblFileDetail.Text = ""
    $form.Update()
    
    $cfg = Get-StationConfig
    $cardId = Get-CardIdentifier -DriveLetter $SourcePath
    $resolvedDest = Get-DestinationForCard -CardIdentifier $cardId -SourcePath $SourcePath -Config $cfg
    
    try {
        $res = Invoke-CardIngest -SourceDrive $SourcePath `
            -DestinationFolder $resolvedDest `
            -EventName $txtEvent.Text.Trim() `
            -AutoEject $chkAutoEject.Checked `
            -CancelCheck { $script:CancelRequested } `
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
        
        $mbTotalDone = [math]::Round($res.TotalBytesCopied / 1MB, 1)
        
        $item = New-Object System.Windows.Forms.ListViewItem((Get-Date -Format "HH:mm:ss"))
        [void]$item.SubItems.Add($res.CardIdentifier)
        [void]$item.SubItems.Add("+" + $res.CopiedCount + " fotos")
        [void]$item.SubItems.Add($res.SkippedCount.ToString() + " fotos")
        [void]$item.SubItems.Add($mbTotalDone.ToString() + " MB")
        
        $statusColText = if ($res.Status -eq "ABORTED_BY_USER") { 
            "[INTERROMPIDO]" 
        } elseif ($res.Ejected) { 
            "[OK] Ejetado" 
        } else { 
            "[OK] Salvo" 
        }
        [void]$item.SubItems.Add($statusColText)
        $gridHistory.Items.Insert(0, $item)
        
        if ($res.Status -eq "ABORTED_BY_USER") {
            $lblBadge.Text = "[!] INTERROMPIDO COM SEGURANCA"
            $lblBadge.ForeColor = $colorAmber
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
            $lblStatusDetail.Text = "Ingestao interrompida pelo usuario. Nenhum arquivo foi corrompido e o cartao esta intacto."
            $lblFileDetail.Text = ""
            [System.Windows.Forms.MessageBox]::Show($form, "Ingestao interrompida com total seguranca!`n`nNenhum arquivo corrompido foi gravado no destino.`nO cartao permanece 100% intacto.", "Interrupcao Segura", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        elseif ($res.Ejected) {
            $progressBar.Value = 100
            $lblBadge.Text = "[OK] CONCLUIDO & EJETADO"
            $lblBadge.ForeColor = $colorGreen
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
            $lblStatusDetail.Text = "Backup 100% verificado! Cartao ejetado com seguranca pelo Windows. Pode retira-lo."
            $lblFileDetail.Text = ""
            [System.Windows.Forms.MessageBox]::Show($form, "Backup concluido com sucesso e verificado com SHA-256!`n`nO cartao foi ejetado automaticamente pelo Windows.`nVoce pode retira-lo agora sem abrir o explorador.", "Sucesso DIT", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } else {
            $progressBar.Value = 100
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
        $script:IsIngesting = $false
        $script:CancelRequested = $false
        $btnStart.Enabled = $true
        $btnCancel.Enabled = $false
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
    if ($script:IsIngesting) { return }
    
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
