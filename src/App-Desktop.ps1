# App-Desktop.ps1 - Aplicativo Gráfico Nativo da Estação de Ingestão DIT
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$enginePath = Join-Path $PSScriptRoot "IngestEngine.ps1"
$configPath = Join-Path $PSScriptRoot "ConfigManager.ps1"

if (Test-Path $enginePath) { . $enginePath }
if (Test-Path $configPath) { . $configPath }

[System.Windows.Forms.Application]::EnableVisualStyles()

# -----------------------------------------------------------------------------
# PALETA DE CORES E FONTES DIT
# -----------------------------------------------------------------------------
$colorBg       = [System.Drawing.Color]::FromArgb(11, 15, 25)
$colorSurface  = [System.Drawing.Color]::FromArgb(17, 24, 39)
$colorElevated = [System.Drawing.Color]::FromArgb(31, 41, 55)
$colorBorder   = [System.Drawing.Color]::FromArgb(55, 65, 81)
$colorText     = [System.Drawing.Color]::FromArgb(248, 250, 252)
$colorMuted    = [System.Drawing.Color]::FromArgb(148, 163, 184)
$colorCyan     = [System.Drawing.Color]::FromArgb(6, 182, 212)
$colorGreen    = [System.Drawing.Color]::FromArgb(16, 185, 129)
$colorAmber    = [System.Drawing.Color]::FromArgb(245, 158, 11)
$colorRed      = [System.Drawing.Color]::FromArgb(239, 68, 68)

$fontTitle   = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$fontHeader  = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fontRegular = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$fontBold    = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$fontSmall   = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
$fontMono    = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)

# -----------------------------------------------------------------------------
# ESTADO GLOBAL DA APLICAÇÃO
# -----------------------------------------------------------------------------
$script:CurrentConfig = Get-StationConfig
$script:CurrentEvent = if ($script:CurrentConfig.CurrentEvent) { $script:CurrentConfig.CurrentEvent } else { $script:CurrentConfig.EventName }
$script:MonitoringActive = Get-MonitoringState
$script:IsIngesting = $false
$script:CancelRequested = $false

# -----------------------------------------------------------------------------
# MODAL: SELEÇÃO / CRIAÇÃO DE EVENTO
# -----------------------------------------------------------------------------
function Show-EventSelectionModal {
    param([bool]$IsInitial = $false)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = "Estação DIT - Seleção de Evento"
    $modal.Size = New-Object System.Drawing.Size(720, 560)
    $modal.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $modal.BackColor = $colorBg
    $modal.ForeColor = $colorText
    $modal.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $modal.MaximizeBox = $false
    $modal.MinimizeBox = $false
    $modal.TopMost = $true
    
    # Cabeçalho do modal
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlHeader.Height = 70
    $pnlHeader.BackColor = $colorSurface
    $pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
    $modal.Controls.Add($pnlHeader)
    
    $lblMTitle = New-Object System.Windows.Forms.Label
    $lblMTitle.Text = "ORGANIZAÇÃO DE EVENTOS DIT"
    $lblMTitle.Font = $fontTitle
    $lblMTitle.ForeColor = $colorCyan
    $lblMTitle.AutoSize = $true
    $pnlHeader.Controls.Add($lblMTitle)
    
    $lblMSub = New-Object System.Windows.Forms.Label
    $lblMSub.Text = "Escolha um evento anterior para consultar auditoria/continuar ou crie um novo evento."
    $lblMSub.Font = $fontSmall
    $lblMSub.ForeColor = $colorMuted
    $lblMSub.Location = New-Object System.Drawing.Point(20, 38)
    $lblMSub.AutoSize = $true
    $pnlHeader.Controls.Add($lblMSub)
    
    # Painel Esquerdo: Eventos Anteriores
    $grpExisting = New-Object System.Windows.Forms.GroupBox
    $grpExisting.Text = "  Eventos Anteriores (Histórico & Auditoria)  "
    $grpExisting.Font = $fontBold
    $grpExisting.ForeColor = $colorText
    $grpExisting.Location = New-Object System.Drawing.Point(20, 85)
    $grpExisting.Size = New-Object System.Drawing.Size(360, 360)
    $modal.Controls.Add($grpExisting)
    
    $listEvents = New-Object System.Windows.Forms.ListView
    $listEvents.Location = New-Object System.Drawing.Point(12, 24)
    $listEvents.Size = New-Object System.Drawing.Size(336, 275)
    $listEvents.View = [System.Windows.Forms.View]::Details
    $listEvents.FullRowSelect = $true
    $listEvents.GridLines = $true
    $listEvents.MultiSelect = $false
    $listEvents.BackColor = $colorElevated
    $listEvents.ForeColor = $colorText
    $listEvents.Font = $fontRegular
    [void]$listEvents.Columns.Add("Nome do Evento", 200)
    [void]$listEvents.Columns.Add("Cartões", 60)
    [void]$listEvents.Columns.Add("Criado em", 70)
    $grpExisting.Controls.Add($listEvents)
    
    $allEvents = @(Get-StationEvents)
    foreach ($ev in $allEvents) {
        $item = New-Object System.Windows.Forms.ListViewItem($ev.Name)
        [void]$item.SubItems.Add($ev.CardCount.ToString())
        $dtStr = if ($ev.CreatedAt) {
            try { ([System.DateTime]::Parse($ev.CreatedAt)).ToString("dd/MM/yy") } catch { "-" }
        } else { "-" }
        [void]$item.SubItems.Add($dtStr)
        if ($ev.Name -eq $script:CurrentEvent) {
            $item.BackColor = [System.Drawing.Color]::FromArgb(40, 6, 182, 212)
            $item.ForeColor = $colorCyan
            $item.Selected = $true
        }
        $listEvents.Items.Add($item)
    }
    
    $btnOpenSelected = New-Object System.Windows.Forms.Button
    $btnOpenSelected.Text = "Abrir Evento Selecionado"
    $btnOpenSelected.Font = $fontBold
    $btnOpenSelected.BackColor = $colorCyan
    $btnOpenSelected.ForeColor = [System.Drawing.Color]::Black
    $btnOpenSelected.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOpenSelected.Location = New-Object System.Drawing.Point(12, 310)
    $btnOpenSelected.Size = New-Object System.Drawing.Size(336, 36)
    $grpExisting.Controls.Add($btnOpenSelected)
    
    # Painel Direito: Criar Novo Evento
    $grpNew = New-Object System.Windows.Forms.GroupBox
    $grpNew.Text = "  Criar Novo Evento  "
    $grpNew.Font = $fontBold
    $grpNew.ForeColor = $colorText
    $grpNew.Location = New-Object System.Drawing.Point(395, 85)
    $grpNew.Size = New-Object System.Drawing.Size(295, 360)
    $modal.Controls.Add($grpNew)
    
    $lblNewName = New-Object System.Windows.Forms.Label
    $lblNewName.Text = "Nome do Evento:"
    $lblNewName.Font = $fontRegular
    $lblNewName.Location = New-Object System.Drawing.Point(15, 30)
    $lblNewName.AutoSize = $true
    $grpNew.Controls.Add($lblNewName)
    
    $txtNewEventName = New-Object System.Windows.Forms.TextBox
    $txtNewEventName.Location = New-Object System.Drawing.Point(15, 52)
    $txtNewEventName.Size = New-Object System.Drawing.Size(265, 25)
    $txtNewEventName.BackColor = $colorElevated
    $txtNewEventName.ForeColor = $colorText
    $txtNewEventName.Font = $fontRegular
    $txtNewEventName.Text = "Evento_" + (Get-Date -Format "yyyy-MM-dd")
    $grpNew.Controls.Add($txtNewEventName)
    
    $lblNewDest = New-Object System.Windows.Forms.Label
    $lblNewDest.Text = "Pasta Base de Armazenamento:"
    $lblNewDest.Font = $fontRegular
    $lblNewDest.Location = New-Object System.Drawing.Point(15, 95)
    $lblNewDest.AutoSize = $true
    $grpNew.Controls.Add($lblNewDest)
    
    $txtNewEventDest = New-Object System.Windows.Forms.TextBox
    $txtNewEventDest.Location = New-Object System.Drawing.Point(15, 117)
    $txtNewEventDest.Size = New-Object System.Drawing.Size(185, 25)
    $txtNewEventDest.BackColor = $colorElevated
    $txtNewEventDest.ForeColor = $colorText
    $txtNewEventDest.Font = $fontMono
    $txtNewEventDest.Text = $script:CurrentConfig.TargetRootPath
    $grpNew.Controls.Add($txtNewEventDest)
    
    $btnBrowseDest = New-Object System.Windows.Forms.Button
    $btnBrowseDest.Text = "Procurar..."
    $btnBrowseDest.Font = $fontRegular
    $btnBrowseDest.BackColor = $colorElevated
    $btnBrowseDest.ForeColor = $colorText
    $btnBrowseDest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBrowseDest.Location = New-Object System.Drawing.Point(205, 115)
    $btnBrowseDest.Size = New-Object System.Drawing.Size(75, 27)
    $grpNew.Controls.Add($btnBrowseDest)
    
    $btnBrowseDest.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione a Pasta Base de Armazenamento para os Eventos"
        if ($fbd.ShowDialog($modal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtNewEventDest.Text = $fbd.SelectedPath
        }
    })
    
    $lblEventExpl = New-Object System.Windows.Forms.Label
    $lblEventExpl.Text = "As fotos de cada fotógrafo serão organizadas automaticamente nesta pasta:`n[Pasta Base]\[Evento]\[Fotógrafo]\..."
    $lblEventExpl.Font = $fontSmall
    $lblEventExpl.ForeColor = $colorMuted
    $lblEventExpl.Location = New-Object System.Drawing.Point(15, 160)
    $lblEventExpl.Size = New-Object System.Drawing.Size(265, 80)
    $grpNew.Controls.Add($lblEventExpl)
    
    $btnCreateEvent = New-Object System.Windows.Forms.Button
    $btnCreateEvent.Text = "+ Criar e Iniciar Evento"
    $btnCreateEvent.Font = $fontBold
    $btnCreateEvent.BackColor = $colorGreen
    $btnCreateEvent.ForeColor = [System.Drawing.Color]::Black
    $btnCreateEvent.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCreateEvent.Location = New-Object System.Drawing.Point(15, 310)
    $btnCreateEvent.Size = New-Object System.Drawing.Size(265, 36)
    $grpNew.Controls.Add($btnCreateEvent)
    
    # Rodapé do modal
    $btnCancelModal = New-Object System.Windows.Forms.Button
    $btnCancelModal.Text = "Fechar"
    $btnCancelModal.Font = $fontRegular
    $btnCancelModal.BackColor = $colorElevated
    $btnCancelModal.ForeColor = $colorText
    $btnCancelModal.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancelModal.Location = New-Object System.Drawing.Point(590, 465)
    $btnCancelModal.Size = New-Object System.Drawing.Size(100, 32)
    $modal.Controls.Add($btnCancelModal)
    
    $btnCancelModal.Add_Click({
        $modal.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $modal.Close()
    })
    
    $btnOpenSelected.Add_Click({
        if ($listEvents.SelectedItems.Count -gt 0) {
            $chosen = $listEvents.SelectedItems[0].Text
            Set-CurrentEvent -EventName $chosen | Out-Null
            $script:CurrentEvent = $chosen
            $script:CurrentConfig = Get-StationConfig
            $modal.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $modal.Close()
        } else {
            [System.Windows.Forms.MessageBox]::Show($modal, "Selecione um evento da lista para abrir.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
    
    $btnCreateEvent.Add_Click({
        $evName = $txtNewEventName.Text.Trim()
        $destPath = $txtNewEventDest.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($evName)) {
            [System.Windows.Forms.MessageBox]::Show($modal, "Por favor informe o nome do evento.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        try {
            $created = New-StationEvent -EventName $evName -DefaultDestination $destPath
            $script:CurrentEvent = $created.Name
            $script:CurrentConfig = Get-StationConfig
            $modal.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $modal.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($modal, "Erro ao criar evento: $_", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })
    
    $res = $modal.ShowDialog()
    $modal.Dispose()
    return $res
}

# -----------------------------------------------------------------------------
# MODAL: CADASTRO DO PRIMEIRO USO DO CARTÃO NO EVENTO ATIVO
# -----------------------------------------------------------------------------
function Show-CardSetupModal {
    param(
        [Parameter(Mandatory=$true)][string]$DriveLetter,
        [Parameter(Mandatory=$true)][string]$CardIdentifier,
        [Parameter(Mandatory=$true)][string]$EventName
    )
    
    $setupModal = New-Object System.Windows.Forms.Form
    $setupModal.Text = "Configurar Novo Cartão para o Evento: $EventName"
    $setupModal.Size = New-Object System.Drawing.Size(640, 500)
    $setupModal.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $setupModal.BackColor = $colorBg
    $setupModal.ForeColor = $colorText
    $setupModal.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $setupModal.MaximizeBox = $false
    $setupModal.MinimizeBox = $false
    $setupModal.TopMost = $true
    
    # Cabeçalho
    $pnlTop = New-Object System.Windows.Forms.Panel
    $pnlTop.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlTop.Height = 70
    $pnlTop.BackColor = $colorSurface
    $pnlTop.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
    $setupModal.Controls.Add($pnlTop)
    
    $lblTop1 = New-Object System.Windows.Forms.Label
    $lblTop1.Text = "NOVO CARTÃO DETECTADO - CONFIGURAÇÃO OBRIGATÓRIA"
    $lblTop1.Font = $fontTitle
    $lblTop1.ForeColor = $colorAmber
    $lblTop1.AutoSize = $true
    $pnlTop.Controls.Add($lblTop1)
    
    $lblTop2 = New-Object System.Windows.Forms.Label
    $lblTop2.Text = "Unidade: $DriveLetter  |  ID: $CardIdentifier  |  Evento: $EventName"
    $lblTop2.Font = $fontMono
    $lblTop2.ForeColor = $colorCyan
    $lblTop2.Location = New-Object System.Drawing.Point(20, 40)
    $lblTop2.AutoSize = $true
    $pnlTop.Controls.Add($lblTop2)
    
    # Corpo do formulário
    $pnlBody = New-Object System.Windows.Forms.Panel
    $pnlBody.Location = New-Object System.Drawing.Point(20, 85)
    $pnlBody.Size = New-Object System.Drawing.Size(585, 320)
    $setupModal.Controls.Add($pnlBody)
    
    # Campo 1: Nome do Fotógrafo
    $lblPhotog = New-Object System.Windows.Forms.Label
    $lblPhotog.Text = "1. Nome do Fotógrafo Responsável por este Cartão:"
    $lblPhotog.Font = $fontBold
    $lblPhotog.Location = New-Object System.Drawing.Point(0, 0)
    $lblPhotog.AutoSize = $true
    $pnlBody.Controls.Add($lblPhotog)
    
    $cmbPhotog = New-Object System.Windows.Forms.ComboBox
    $cmbPhotog.Location = New-Object System.Drawing.Point(0, 24)
    $cmbPhotog.Size = New-Object System.Drawing.Size(580, 26)
    $cmbPhotog.BackColor = $colorElevated
    $cmbPhotog.ForeColor = $colorText
    $cmbPhotog.Font = $fontRegular
    $cmbPhotog.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    
    # Carrega fotógrafos já existentes no evento para reutilização rápida
    $existingPhotogs = @(Get-EventPhotographers -EventName $EventName)
    foreach ($p in $existingPhotogs) {
        [void]$cmbPhotog.Items.Add($p)
    }
    if ($existingPhotogs.Count -gt 0) {
        $cmbPhotog.SelectedIndex = 0
    } else {
        $cmbPhotog.Text = "Fotografo_1"
    }
    $pnlBody.Controls.Add($cmbPhotog)
    
    $lblPhotogRule = New-Object System.Windows.Forms.Label
    $lblPhotogRule.Text = "Regra DIT: Um fotógrafo pode ter vários cartões, mas este cartão pertencerá apenas a este fotógrafo."
    $lblPhotogRule.Font = $fontSmall
    $lblPhotogRule.ForeColor = $colorMuted
    $lblPhotogRule.Location = New-Object System.Drawing.Point(0, 52)
    $lblPhotogRule.AutoSize = $true
    $pnlBody.Controls.Add($lblPhotogRule)
    
    # Campo 2: Caminho das Fotos no Cartão (Subpasta)
    $lblSubf = New-Object System.Windows.Forms.Label
    $lblSubf.Text = "2. Caminho onde estão as Fotos no Cartão (Formatação da Câmera):"
    $lblSubf.Font = $fontBold
    $lblSubf.Location = New-Object System.Drawing.Point(0, 80)
    $lblSubf.AutoSize = $true
    $pnlBody.Controls.Add($lblSubf)
    
    $cmbSubf = New-Object System.Windows.Forms.ComboBox
    $cmbSubf.Location = New-Object System.Drawing.Point(0, 104)
    $cmbSubf.Size = New-Object System.Drawing.Size(460, 26)
    $cmbSubf.BackColor = $colorElevated
    $cmbSubf.ForeColor = $colorText
    $cmbSubf.Font = $fontMono
    $cmbSubf.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    
    # Escaneia pastas de fotos candidatas no cartão físico
    $detectedFolders = @(Get-CardPhotoFolders -DriveRoot $DriveLetter)
    foreach ($f in $detectedFolders) {
        [void]$cmbSubf.Items.Add($f)
    }
    if ($cmbSubf.Items.Count -gt 0) {
        $cmbSubf.SelectedIndex = 0
    }
    $pnlBody.Controls.Add($cmbSubf)
    
    $btnBrowseCardSubf = New-Object System.Windows.Forms.Button
    $btnBrowseCardSubf.Text = "Procurar..."
    $btnBrowseCardSubf.Font = $fontRegular
    $btnBrowseCardSubf.BackColor = $colorElevated
    $btnBrowseCardSubf.ForeColor = $colorText
    $btnBrowseCardSubf.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBrowseCardSubf.Location = New-Object System.Drawing.Point(470, 102)
    $btnBrowseCardSubf.Size = New-Object System.Drawing.Size(110, 28)
    $pnlBody.Controls.Add($btnBrowseCardSubf)
    
    $btnBrowseCardSubf.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione a Pasta de Fotos dentro do Cartão $DriveLetter"
        $fbd.SelectedPath = $DriveLetter
        if ($fbd.ShowDialog($setupModal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $sel = $fbd.SelectedPath
            $root = [System.IO.Path]::GetPathRoot($sel)
            $rel = $sel.Substring($root.Length).TrimStart('\')
            $cmbSubf.Text = if ($rel) { $rel } else { "\ (Raiz do Cartão)" }
        }
    })
    
    # Campo 3: Onde Salvar os Arquivos Deste Cartão
    $lblDest = New-Object System.Windows.Forms.Label
    $lblDest.Text = "3. Pasta de Destino Onde Salvar as Fotos deste Cartão:"
    $lblDest.Font = $fontBold
    $lblDest.Location = New-Object System.Drawing.Point(0, 145)
    $lblDest.AutoSize = $true
    $pnlBody.Controls.Add($lblDest)
    
    $txtDest = New-Object System.Windows.Forms.TextBox
    $txtDest.Location = New-Object System.Drawing.Point(0, 169)
    $txtDest.Size = New-Object System.Drawing.Size(460, 25)
    $txtDest.BackColor = $colorElevated
    $txtDest.ForeColor = $colorText
    $txtDest.Font = $fontMono
    
    $defaultBase = [System.IO.Path]::Combine($script:CurrentConfig.TargetRootPath, $EventName)
    $txtDest.Text = [System.IO.Path]::Combine($defaultBase, ($cmbPhotog.Text -replace '[\\/:*?"<>|]', '_'))
    $pnlBody.Controls.Add($txtDest)
    
    $btnBrowseDestCard = New-Object System.Windows.Forms.Button
    $btnBrowseDestCard.Text = "Procurar..."
    $btnBrowseDestCard.Font = $fontRegular
    $btnBrowseDestCard.BackColor = $colorElevated
    $btnBrowseDestCard.ForeColor = $colorText
    $btnBrowseDestCard.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBrowseDestCard.Location = New-Object System.Drawing.Point(470, 167)
    $btnBrowseDestCard.Size = New-Object System.Drawing.Size(110, 28)
    $pnlBody.Controls.Add($btnBrowseDestCard)
    
    $cmbPhotog.Add_TextChanged({
        $cleanP = ($cmbPhotog.Text.Trim() -replace '[\\/:*?"<>|]', '_')
        if ($cleanP) {
            $txtDest.Text = [System.IO.Path]::Combine($defaultBase, $cleanP)
        }
    })
    
    $btnBrowseDestCard.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione a Pasta de Destino para as Fotos deste Cartão"
        if ($fbd.ShowDialog($setupModal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtDest.Text = $fbd.SelectedPath
        }
    })
    
    $lblNotice = New-Object System.Windows.Forms.Label
    $lblNotice.Text = "Esta configuração só é solicitada UMA VEZ por evento para cada cartão.`nNas próximas inserções, o sistema reconhecerá o cartão e descarregará sozinho."
    $lblNotice.Font = $fontSmall
    $lblNotice.ForeColor = $colorGreen
    $lblNotice.Location = New-Object System.Drawing.Point(0, 220)
    $lblNotice.Size = New-Object System.Drawing.Size(580, 40)
    $pnlBody.Controls.Add($lblNotice)
    
    # Botões de Ação
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Salvar e Iniciar Descarregamento"
    $btnSave.Font = $fontBold
    $btnSave.BackColor = $colorCyan
    $btnSave.ForeColor = [System.Drawing.Color]::Black
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.Location = New-Object System.Drawing.Point(20, 415)
    $btnSave.Size = New-Object System.Drawing.Size(320, 38)
    $setupModal.Controls.Add($btnSave)
    
    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancelar (Ignorar Cartão)"
    $btnCancel.Font = $fontRegular
    $btnCancel.BackColor = $colorElevated
    $btnCancel.ForeColor = $colorMuted
    $btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancel.Location = New-Object System.Drawing.Point(360, 415)
    $btnCancel.Size = New-Object System.Drawing.Size(245, 38)
    $setupModal.Controls.Add($btnCancel)
    
    $script:RegisteredResult = $null
    
    $btnSave.Add_Click({
        $photogName = $cmbPhotog.Text.Trim()
        $subfPath = $cmbSubf.Text.Trim()
        $destPath = $txtDest.Text.Trim()
        
        if ([string]::IsNullOrWhiteSpace($photogName) -or [string]::IsNullOrWhiteSpace($destPath)) {
            [System.Windows.Forms.MessageBox]::Show($setupModal, "Nome do fotógrafo e pasta de destino são obrigatórios.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        $script:RegisteredResult = Register-CardForEvent -EventName $EventName `
            -CardIdentifier $CardIdentifier `
            -Photographer $photogName `
            -DestinationPath $destPath `
            -PhotoSubfolder $subfPath
        
        $setupModal.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $setupModal.Close()
    })
    
    $btnCancel.Add_Click({
        $script:RegisteredResult = $null
        $setupModal.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $setupModal.Close()
    })
    
    [void]$setupModal.ShowDialog()
    $setupModal.Dispose()
    return $script:RegisteredResult
}

# -----------------------------------------------------------------------------
# JANELA PRINCIPAL DA APLICAÇÃO
# -----------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Estação de Ingestão DIT - Backup Seguro de Alta Confiabilidade"
$form.Size = New-Object System.Drawing.Size(1080, 760)
$form.MinimumSize = New-Object System.Drawing.Size(950, 700)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $colorBg
$form.ForeColor = $colorText
$form.Font = $fontRegular

# BARRA SUPERIOR (HEADER)
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height = 65
$headerPanel.BackColor = $colorSurface
$headerPanel.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($headerPanel)

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = "ESTAÇÃO DE INGESTÃO DIT"
$lblBrand.Font = $fontTitle
$lblBrand.ForeColor = $colorCyan
$lblBrand.Location = New-Object System.Drawing.Point(20, 12)
$lblBrand.AutoSize = $true
$headerPanel.Controls.Add($lblBrand)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Backup Fotográfico Automatizado com SHA-256 e Ejeção Segura"
$lblSub.Font = $fontSmall
$lblSub.ForeColor = $colorMuted
$lblSub.Location = New-Object System.Drawing.Point(20, 36)
$lblSub.AutoSize = $true
$headerPanel.Controls.Add($lblSub)

# Badge e Botão do Evento Ativo
$lblActiveEventBadge = New-Object System.Windows.Forms.Label
$lblActiveEventBadge.Text = "EVENTO: $script:CurrentEvent"
$lblActiveEventBadge.Font = $fontBold
$lblActiveEventBadge.ForeColor = $colorCyan
$lblActiveEventBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 6, 182, 212)
$lblActiveEventBadge.Location = New-Object System.Drawing.Point(540, 15)
$lblActiveEventBadge.Size = New-Object System.Drawing.Size(260, 32)
$lblActiveEventBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblActiveEventBadge.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.Controls.Add($lblActiveEventBadge)

$btnSwitchEvent = New-Object System.Windows.Forms.Button
$btnSwitchEvent.Text = "Trocar / Novo Evento"
$btnSwitchEvent.Font = $fontBold
$btnSwitchEvent.BackColor = $colorElevated
$btnSwitchEvent.ForeColor = $colorText
$btnSwitchEvent.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSwitchEvent.Location = New-Object System.Drawing.Point(815, 15)
$btnSwitchEvent.Size = New-Object System.Drawing.Size(160, 32)
$btnSwitchEvent.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.Controls.Add($btnSwitchEvent)

# BARRA DE CONTROLE DE MONITORAMENTO (ATIVO / PAUSADO)
$monitorBar = New-Object System.Windows.Forms.Panel
$monitorBar.Dock = [System.Windows.Forms.DockStyle]::Top
$monitorBar.Height = 50
$monitorBar.BackColor = [System.Drawing.Color]::FromArgb(18, 30, 49)
$monitorBar.Padding = New-Object System.Windows.Forms.Padding(20, 8, 20, 8)
$form.Controls.Add($monitorBar)

$lblMonitorState = New-Object System.Windows.Forms.Label
$lblMonitorState.Text = "● MONITORAMENTO ATIVO - Leitura Automática de Cartões Ligada"
$lblMonitorState.Font = $fontBold
$lblMonitorState.ForeColor = $colorGreen
$lblMonitorState.Location = New-Object System.Drawing.Point(20, 15)
$lblMonitorState.AutoSize = $true
$monitorBar.Controls.Add($lblMonitorState)

$btnToggleMonitor = New-Object System.Windows.Forms.Button
$btnToggleMonitor.Text = "Pausar Leitura de Cartões"
$btnToggleMonitor.Font = $fontBold
$btnToggleMonitor.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
$btnToggleMonitor.ForeColor = $colorAmber
$btnToggleMonitor.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnToggleMonitor.Location = New-Object System.Drawing.Point(815, 10)
$btnToggleMonitor.Size = New-Object System.Drawing.Size(220, 30)
$btnToggleMonitor.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$monitorBar.Controls.Add($btnToggleMonitor)

function Update-MonitoringUI {
    if ($script:MonitoringActive) {
        $lblMonitorState.Text = "● MONITORAMENTO ATIVO - Leitura Automática de Cartões Ligada"
        $lblMonitorState.ForeColor = $colorGreen
        $monitorBar.BackColor = [System.Drawing.Color]::FromArgb(15, 35, 30)
        $btnToggleMonitor.Text = "❚❚ Pausar Leitura de Cartões"
        $btnToggleMonitor.ForeColor = $colorAmber
        $btnToggleMonitor.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
    } else {
        $lblMonitorState.Text = "❚❚ MONITORAMENTO PAUSADO - Nenhuma Leitura de Cartão Será Feita"
        $lblMonitorState.ForeColor = $colorAmber
        $monitorBar.BackColor = [System.Drawing.Color]::FromArgb(40, 30, 15)
        $btnToggleMonitor.Text = "▶ Iniciar Leitura de Cartões"
        $btnToggleMonitor.ForeColor = $colorGreen
        $btnToggleMonitor.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
    }
}
Update-MonitoringUI

$btnToggleMonitor.Add_Click({
    $script:MonitoringActive = -not $script:MonitoringActive
    Set-MonitoringState -Active $script:MonitoringActive | Out-Null
    Update-MonitoringUI
})

# PAINEL DE STATUS & PROGRESSO DE INGESTÃO
$pnlProgress = New-Object System.Windows.Forms.Panel
$pnlProgress.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlProgress.Height = 110
$pnlProgress.BackColor = $colorSurface
$pnlProgress.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
$form.Controls.Add($pnlProgress)

$lblBadge = New-Object System.Windows.Forms.Label
$lblBadge.Text = "SISTEMA ARMADO"
$lblBadge.Font = $fontBold
$lblBadge.ForeColor = $colorGreen
$lblBadge.BackColor = [System.Drawing.Color]::FromArgb(30, 16, 185, 129)
$lblBadge.Location = New-Object System.Drawing.Point(20, 12)
$lblBadge.Size = New-Object System.Drawing.Size(180, 26)
$lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$pnlProgress.Controls.Add($lblBadge)

$lblStatusDetail = New-Object System.Windows.Forms.Label
$lblStatusDetail.Text = "Aguardando conexão de cartões ou disparo manual..."
$lblStatusDetail.Font = $fontRegular
$lblStatusDetail.ForeColor = $colorMuted
$lblStatusDetail.Location = New-Object System.Drawing.Point(215, 16)
$lblStatusDetail.AutoSize = $true
$pnlProgress.Controls.Add($lblStatusDetail)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Parar com Segurança"
$btnCancel.Font = $fontBold
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
$btnCancel.ForeColor = $colorAmber
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.Location = New-Object System.Drawing.Point(860, 10)
$btnCancel.Size = New-Object System.Drawing.Size(175, 30)
$btnCancel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnCancel.Enabled = $false
$pnlProgress.Controls.Add($btnCancel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 48)
$progressBar.Size = New-Object System.Drawing.Size(1015, 16)
$progressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlProgress.Controls.Add($progressBar)

$lblProgressMetrics = New-Object System.Windows.Forms.Label
$lblProgressMetrics.Text = "0 / 0 fotos (0%)"
$lblProgressMetrics.Font = $fontMono
$lblProgressMetrics.ForeColor = $colorText
$lblProgressMetrics.Location = New-Object System.Drawing.Point(20, 72)
$lblProgressMetrics.AutoSize = $true
$pnlProgress.Controls.Add($lblProgressMetrics)

$lblFileDetail = New-Object System.Windows.Forms.Label
$lblFileDetail.Text = ""
$lblFileDetail.Font = $fontMono
$lblFileDetail.ForeColor = $colorCyan
$lblFileDetail.Location = New-Object System.Drawing.Point(250, 72)
$lblFileDetail.Size = New-Object System.Drawing.Size(785, 20)
$lblFileDetail.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlProgress.Controls.Add($lblFileDetail)

# CORPO PRINCIPAL COM DUAS COLUNAS
$mainContainer = New-Object System.Windows.Forms.SplitContainer
$mainContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainContainer.BackColor = $colorBg
$mainContainer.SplitterWidth = 8
$mainContainer.SplitterDistance = 560
$form.Controls.Add($mainContainer)

# -----------------------------------------------------------------------------
# COLUNA ESQUERDA: CARTÕES CADASTRADOS NO EVENTO & DISPARO MANUAL
# -----------------------------------------------------------------------------
$grpCards = New-Object System.Windows.Forms.GroupBox
$grpCards.Text = "  Cartões Cadastrados no Evento Atual  "
$grpCards.Font = $fontBold
$grpCards.ForeColor = $colorText
$grpCards.Dock = [System.Windows.Forms.DockStyle]::Top
$grpCards.Height = 240
$grpCards.Padding = New-Object System.Windows.Forms.Padding(10)
$mainContainer.Panel1.Controls.Add($grpCards)

$gridEventCards = New-Object System.Windows.Forms.ListView
$gridEventCards.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridEventCards.View = [System.Windows.Forms.View]::Details
$gridEventCards.FullRowSelect = $true
$gridEventCards.GridLines = $true
$gridEventCards.BackColor = $colorElevated
$gridEventCards.ForeColor = $colorText
$gridEventCards.Font = $fontRegular
[void]$gridEventCards.Columns.Add("Cartão / ID", 130)
[void]$gridEventCards.Columns.Add("Fotógrafo", 130)
[void]$gridEventCards.Columns.Add("Subpasta", 100)
[void]$gridEventCards.Columns.Add("Destino", 160)
$grpCards.Controls.Add($gridEventCards)

function Refresh-EventCardsGrid {
    $gridEventCards.Items.Clear()
    $cards = @(Get-EventCards -EventName $script:CurrentEvent)
    if ($cards.Count -eq 0) {
        $item = New-Object System.Windows.Forms.ListViewItem("Nenhum cartão cadastrado ainda")
        [void]$item.SubItems.Add("Insira um cartão")
        [void]$item.SubItems.Add("Automático")
        [void]$item.SubItems.Add("Destino Padrão")
        $item.ForeColor = $colorMuted
        $gridEventCards.Items.Add($item)
    } else {
        foreach ($c in $cards) {
            $item = New-Object System.Windows.Forms.ListViewItem($c.CardIdentifier)
            [void]$item.SubItems.Add($c.Photographer)
            [void]$item.SubItems.Add($c.PhotoSubfolder)
            [void]$item.SubItems.Add($c.DestinationPath)
            $gridEventCards.Items.Add($item)
        }
    }
}
Refresh-EventCardsGrid

# DISPARO MANUAL
$grpManual = New-Object System.Windows.Forms.GroupBox
$grpManual.Text = "  Descarregar Manualmente (Se já conectado)  "
$grpManual.Font = $fontBold
$grpManual.ForeColor = $colorText
$grpManual.Dock = [System.Windows.Forms.DockStyle]::Fill
$grpManual.Padding = New-Object System.Windows.Forms.Padding(12)
$mainContainer.Panel1.Controls.Add($grpManual)

$lblManual = New-Object System.Windows.Forms.Label
$lblManual.Text = "Unidade ou Pasta de Origem (Ex: E:\ ou E:\DCIM\100CANON):"
$lblManual.Font = $fontRegular
$lblManual.Location = New-Object System.Drawing.Point(12, 28)
$lblManual.AutoSize = $true
$grpManual.Controls.Add($lblManual)

$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Location = New-Object System.Drawing.Point(12, 52)
$txtSource.Size = New-Object System.Drawing.Size(380, 25)
$txtSource.BackColor = $colorElevated
$txtSource.ForeColor = $colorText
$txtSource.Font = $fontMono
$grpManual.Controls.Add($txtSource)

$btnBrowseSource = New-Object System.Windows.Forms.Button
$btnBrowseSource.Text = "Procurar..."
$btnBrowseSource.Font = $fontRegular
$btnBrowseSource.BackColor = $colorElevated
$btnBrowseSource.ForeColor = $colorText
$btnBrowseSource.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseSource.Location = New-Object System.Drawing.Point(400, 50)
$btnBrowseSource.Size = New-Object System.Drawing.Size(120, 28)
$grpManual.Controls.Add($btnBrowseSource)

$btnBrowseSource.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a Unidade ou Pasta do Cartão Fotográfico"
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSource.Text = $fbd.SelectedPath
    }
})

$btnIngestNow = New-Object System.Windows.Forms.Button
$btnIngestNow.Text = "Iniciar Ingestão Manual Agora"
$btnIngestNow.Font = $fontBold
$btnIngestNow.BackColor = $colorCyan
$btnIngestNow.ForeColor = [System.Drawing.Color]::Black
$btnIngestNow.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnIngestNow.Location = New-Object System.Drawing.Point(12, 95)
$btnIngestNow.Size = New-Object System.Drawing.Size(510, 38)
$grpManual.Controls.Add($btnIngestNow)

# -----------------------------------------------------------------------------
# COLUNA DIREITA: HISTÓRICO DE AUDITORIA & PROTEÇÕES
# -----------------------------------------------------------------------------
$grpAudit = New-Object System.Windows.Forms.GroupBox
$grpAudit.Text = "  Auditoria e Histórico de Ingestões DIT  "
$grpAudit.Font = $fontBold
$grpAudit.ForeColor = $colorText
$grpAudit.Dock = [System.Windows.Forms.DockStyle]::Fill
$grpAudit.Padding = New-Object System.Windows.Forms.Padding(10)
$mainContainer.Panel2.Controls.Add($grpAudit)

$gridHistory = New-Object System.Windows.Forms.ListView
$gridHistory.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridHistory.View = [System.Windows.Forms.View]::Details
$gridHistory.FullRowSelect = $true
$gridHistory.GridLines = $true
$gridHistory.BackColor = $colorElevated
$gridHistory.ForeColor = $colorText
$gridHistory.Font = $fontRegular
[void]$gridHistory.Columns.Add("Hora", 70)
[void]$gridHistory.Columns.Add("Cartão / Fotógrafo", 140)
[void]$gridHistory.Columns.Add("Fotos", 80)
[void]$gridHistory.Columns.Add("Volume", 70)
[void]$gridHistory.Columns.Add("Status / Ejeção", 100)
$grpAudit.Controls.Add($gridHistory)

# -----------------------------------------------------------------------------
# FLUXO DE EXECUÇÃO DE INGESTÃO COM INTERRUPÇÃO SEGURA
# -----------------------------------------------------------------------------
$btnCancel.Add_Click({
    if ($script:IsIngesting) {
        $script:CancelRequested = $true
        $btnCancel.Enabled = $false
        $lblStatusDetail.Text = "Interrupção solicitada. Finalizando foto atual e limpando arquivos temporários..."
    }
})

function Run-AppIngest {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath
    )
    
    if ($script:IsIngesting) {
        [System.Windows.Forms.MessageBox]::Show($form, "Uma ingestão já está em andamento. Aguarde a conclusão.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    if (!(Test-Path $SourcePath)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Caminho de origem não encontrado: $SourcePath", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    
    $cardId = Get-CardIdentifier -DriveLetter $SourcePath
    
    # Checa se o cartão já foi cadastrado para este evento
    $cardReg = Get-CardRegistration -EventName $script:CurrentEvent -CardIdentifier $cardId
    if ($null -eq $cardReg) {
        # Primeira vez que o cartão é visto neste evento: exibe modal de cadastro obrigatório
        $cardReg = Show-CardSetupModal -DriveLetter $SourcePath -CardIdentifier $cardId -EventName $script:CurrentEvent
        if ($null -eq $cardReg) {
            # Usuário cancelou o cadastro
            return
        }
        Refresh-EventCardsGrid
    }
    
    $script:IsIngesting = $true
    $script:CancelRequested = $false
    $btnCancel.Enabled = $true
    $btnIngestNow.Enabled = $false
    
    $lblBadge.Text = "COPIANDO & SHA-256"
    $lblBadge.ForeColor = $colorCyan
    $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 6, 182, 212)
    $lblStatusDetail.Text = "Fotógrafo: $($cardReg.Photographer) | Cartão: $cardId"
    $progressBar.Value = 0
    $form.Update()
    
    try {
        $res = Invoke-CardIngest -SourceDrive $SourcePath `
            -DestinationFolder $cardReg.DestinationPath `
            -EventName $script:CurrentEvent `
            -AutoEject ([bool]$script:CurrentConfig.AutoEject) `
            -CancelCheck { $script:CancelRequested } `
            -CardPhotoSubfolder $cardReg.PhotoSubfolder `
            -ProgressCallback {
                param($prog)
                $pct = if ($prog.TotalFiles -gt 0) { [math]::Min(100, [int](($prog.CurrentIndex / $prog.TotalFiles) * 100)) } else { 0 }
                $progressBar.Value = $pct
                $lblProgressMetrics.Text = "$($prog.CurrentIndex) / $($prog.TotalFiles) fotos ($pct%)"
                $lblFileDetail.Text = "Foto: $($prog.CurrentFile)"
                [System.Windows.Forms.Application]::DoEvents()
            }
        
        $item = New-Object System.Windows.Forms.ListViewItem((Get-Date -Format "HH:mm:ss"))
        [void]$item.SubItems.Add("$($cardReg.Photographer) ($cardId)")
        [void]$item.SubItems.Add("+$($res.CopiedCount) fotos")
        $mb = [math]::Round($res.TotalBytesCopied / 1MB, 1)
        [void]$item.SubItems.Add("$mb MB")
        
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
            $lblBadge.Text = "INTERROMPIDO COM SEGURANÇA"
            $lblBadge.ForeColor = $colorAmber
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
            $lblStatusDetail.Text = "Ingestão interrompida pelo usuário. Nenhum arquivo foi corrompido e o cartão está intacto."
            [System.Windows.Forms.MessageBox]::Show($form, "Ingestão interrompida com total segurança!`n`nNenhum arquivo foi corrompido, os arquivos já verificados continuam salvos e o cartão está intacto.", "Interrupção Segura", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        elseif ($res.Ejected) {
            $progressBar.Value = 100
            $lblBadge.Text = "CONCLUÍDO & EJETADO"
            $lblBadge.ForeColor = $colorGreen
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
            $lblStatusDetail.Text = "Backup de $($cardReg.Photographer) concluído! Cartão ejetado com segurança. Pode retirar."
            $lblFileDetail.Text = ""
        } else {
            $progressBar.Value = 100
            $lblBadge.Text = "CONCLUÍDO COM SUCESSO"
            $lblBadge.ForeColor = $colorGreen
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
            $lblStatusDetail.Text = "Backup de $($cardReg.Photographer) concluído com sucesso."
        }
    }
    catch {
        $lblBadge.Text = "ERRO"
        $lblBadge.ForeColor = $colorRed
        $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 239, 68, 68)
        $lblStatusDetail.Text = "Erro: $_"
        [System.Windows.Forms.MessageBox]::Show($form, "Erro durante a ingestão:`n$_", "Erro Crítico", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        $script:IsIngesting = $false
        $script:CancelRequested = $false
        $btnCancel.Enabled = $false
        $btnIngestNow.Enabled = $true
        $form.Update()
    }
}

$btnIngestNow.Add_Click({
    $src = $txtSource.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($src)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Informe a unidade ou pasta do cartão fotográfico.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    Run-AppIngest -SourcePath $src
})

$btnSwitchEvent.Add_Click({
    $res = Show-EventSelectionModal -IsInitial $false
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $lblActiveEventBadge.Text = "EVENTO: $script:CurrentEvent"
        Refresh-EventCardsGrid
    }
})

# -----------------------------------------------------------------------------
# DAEMON DE DETECÇÃO AUTOMÁTICA DE CARTÕES (TIMER NO FORMULÁRIO)
# -----------------------------------------------------------------------------
$knownDrives = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$initialDrives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
foreach ($d in $initialDrives) {
    [void]$knownDrives.Add($d.Name)
}

$usbTimer = New-Object System.Windows.Forms.Timer
$usbTimer.Interval = 1500
$usbTimer.Add_Tick({
    if ($script:IsIngesting) { return }
    if (-not $script:MonitoringActive) { return }
    
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
                    $usbTimer.Stop()
                    try {
                        Run-AppIngest -SourcePath $driveName
                    } finally {
                        $usbTimer.Start()
                    }
                }
                
                [void]$knownDrives.Add($driveName)
            }
        }
        
        $removed = [System.Collections.Generic.List[string]]::new()
        foreach ($k in $knownDrives) {
            if (-not $currentSet.Contains($k)) {
                $removed.Add($k)
            }
        }
        foreach ($rem in $removed) {
            [void]$knownDrives.Remove($rem)
        }
    } catch {}
})

# EXIBE MODAL DE SELEÇÃO DE EVENTO NO INÍCIO DA EXECUÇÃO
$form.Add_Load({
    $resInit = Show-EventSelectionModal -IsInitial $true
    $lblActiveEventBadge.Text = "EVENTO: $script:CurrentEvent"
    Refresh-EventCardsGrid
    $usbTimer.Start()
})

[void]$form.ShowDialog()
$usbTimer.Stop()
$usbTimer.Dispose()
$form.Dispose()
