# App-Desktop.ps1 - Aplicativo Grafico Nativo da Estacao de Ingestao DIT
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {}

$candidates = [System.Collections.Generic.List[string]]::new()
if (![string]::IsNullOrWhiteSpace($PSScriptRoot)) { $candidates.Add($PSScriptRoot) }
if ($MyInvocation.MyCommand -and ![string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    $candidates.Add((Split-Path -Parent $MyInvocation.MyCommand.Path))
}
$candidates.Add("C:\Users\Usuario\Documents\GitHub\auto-ingest-station\src")
$candidates.Add("C:\auto-ingest-station\src")
$candidates.Add((Join-Path (Get-Location).Path "src"))
$candidates.Add((Get-Location).Path)

$scriptDir = $null
foreach ($c in $candidates) {
    if (![string]::IsNullOrWhiteSpace($c) -and (Test-Path (Join-Path $c "ConfigManager.ps1"))) {
        $scriptDir = $c
        break
    }
}
if ([string]::IsNullOrWhiteSpace($scriptDir)) {
    $scriptDir = (Get-Location).Path
}

$enginePath = Join-Path $scriptDir "IngestEngine.ps1"
$configPath = Join-Path $scriptDir "ConfigManager.ps1"

if (Test-Path $enginePath) { . $enginePath }
if (Test-Path $configPath) { . $configPath }

[System.Windows.Forms.Application]::EnableVisualStyles()

# -----------------------------------------------------------------------------
# PALETA DE CORES E FONTES DIT PROFISSIONAL
# -----------------------------------------------------------------------------
$colorBg         = [System.Drawing.Color]::FromArgb(11, 15, 25)
$colorSurface    = [System.Drawing.Color]::FromArgb(17, 24, 39)
$colorElevated   = [System.Drawing.Color]::FromArgb(31, 41, 55)
$colorBorder     = [System.Drawing.Color]::FromArgb(55, 65, 81)
$colorText       = [System.Drawing.Color]::FromArgb(248, 250, 252)
$colorMuted      = [System.Drawing.Color]::FromArgb(148, 163, 184)
$colorCyan       = [System.Drawing.Color]::FromArgb(6, 182, 212)
$colorGreen      = [System.Drawing.Color]::FromArgb(16, 185, 129)
$colorAmber      = [System.Drawing.Color]::FromArgb(245, 158, 11)
$colorRed        = [System.Drawing.Color]::FromArgb(239, 68, 68)

$fontTitle       = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$fontSubTitle    = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fontRegular     = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$fontBold        = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$fontSmall       = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Regular)
$fontMono        = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Regular)

# -----------------------------------------------------------------------------
# ESTADO GLOBAL DA APLICACAO
# -----------------------------------------------------------------------------
$script:CurrentConfig      = Get-StationConfig
$script:CurrentEvent       = $script:CurrentConfig.CurrentEvent
$script:MonitoringActive   = Get-MonitoringState
$script:IsIngesting        = $false
$script:CancelRequested    = $false
$script:RegisteredResult   = $null

# -----------------------------------------------------------------------------
# MODAL: SELECAO E CRIACAO DE EVENTO (INICIAL E TROCA)
# -----------------------------------------------------------------------------
function Show-EventSelectionModal {
    param([bool]$IsInitial = $false)
    
    $modal = New-Object System.Windows.Forms.Form
    $modal.Text = "Estacao DIT - Selecao de Evento"
    $modal.Size = New-Object System.Drawing.Size(740, 560)
    $modal.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $modal.BackColor = $colorBg
    $modal.ForeColor = $colorText
    $modal.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $modal.MaximizeBox = $false
    $modal.MinimizeBox = $false
    $modal.TopMost = $true
    
    $pnlHeader = New-Object System.Windows.Forms.Panel
    $pnlHeader.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlHeader.Height = 70
    $pnlHeader.BackColor = $colorSurface
    $pnlHeader.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
    $modal.Controls.Add($pnlHeader)
    
    $lblMTitle = New-Object System.Windows.Forms.Label
    $lblMTitle.Text = "ORGANIZACAO DE EVENTOS DIT"
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
    $pnlLeft = New-Object System.Windows.Forms.Panel
    $pnlLeft.Location = New-Object System.Drawing.Point(20, 85)
    $pnlLeft.Size = New-Object System.Drawing.Size(350, 360)
    $modal.Controls.Add($pnlLeft)
    
    $lblHistTitle = New-Object System.Windows.Forms.Label
    $lblHistTitle.Text = "Eventos Anteriores (Historico & Auditoria)"
    $lblHistTitle.Font = $fontBold
    $lblHistTitle.ForeColor = $colorText
    $lblHistTitle.Location = New-Object System.Drawing.Point(0, 0)
    $lblHistTitle.AutoSize = $true
    $pnlLeft.Controls.Add($lblHistTitle)
    
    $listEvents = New-Object System.Windows.Forms.ListView
    $listEvents.Location = New-Object System.Drawing.Point(0, 24)
    $listEvents.Size = New-Object System.Drawing.Size(350, 285)
    $listEvents.View = [System.Windows.Forms.View]::Details
    $listEvents.FullRowSelect = $true
    $listEvents.GridLines = $true
    $listEvents.MultiSelect = $false
    $listEvents.BackColor = $colorElevated
    $listEvents.ForeColor = $colorText
    $listEvents.Font = $fontRegular
    [void]$listEvents.Columns.Add("Nome do Evento", 180)
    [void]$listEvents.Columns.Add("Cartoes", 65)
    [void]$listEvents.Columns.Add("Criado em", 85)
    $pnlLeft.Controls.Add($listEvents)
    
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
    $btnOpenSelected.Location = New-Object System.Drawing.Point(0, 318)
    $btnOpenSelected.Size = New-Object System.Drawing.Size(350, 36)
    $pnlLeft.Controls.Add($btnOpenSelected)
    
    # Painel Direito: Criar Novo Evento
    $pnlRight = New-Object System.Windows.Forms.Panel
    $pnlRight.Location = New-Object System.Drawing.Point(390, 85)
    $pnlRight.Size = New-Object System.Drawing.Size(320, 360)
    $modal.Controls.Add($pnlRight)
    
    $lblNewTitle = New-Object System.Windows.Forms.Label
    $lblNewTitle.Text = "Criar Novo Evento"
    $lblNewTitle.Font = $fontBold
    $lblNewTitle.ForeColor = $colorGreen
    $lblNewTitle.Location = New-Object System.Drawing.Point(0, 0)
    $lblNewTitle.AutoSize = $true
    $pnlRight.Controls.Add($lblNewTitle)
    
    $lblNewName = New-Object System.Windows.Forms.Label
    $lblNewName.Text = "Nome do Evento:"
    $lblNewName.Font = $fontRegular
    $lblNewName.Location = New-Object System.Drawing.Point(0, 28)
    $lblNewName.AutoSize = $true
    $pnlRight.Controls.Add($lblNewName)
    
    $txtNewEventName = New-Object System.Windows.Forms.TextBox
    $txtNewEventName.Location = New-Object System.Drawing.Point(0, 48)
    $txtNewEventName.Size = New-Object System.Drawing.Size(320, 25)
    $txtNewEventName.BackColor = $colorElevated
    $txtNewEventName.ForeColor = $colorText
    $txtNewEventName.Font = $fontRegular
    $txtNewEventName.Text = "Evento_" + (Get-Date -Format "yyyy-MM-dd")
    $pnlRight.Controls.Add($txtNewEventName)
    
    $lblNewDest = New-Object System.Windows.Forms.Label
    $lblNewDest.Text = "Pasta Base de Armazenamento:"
    $lblNewDest.Font = $fontRegular
    $lblNewDest.Location = New-Object System.Drawing.Point(0, 85)
    $lblNewDest.AutoSize = $true
    $pnlRight.Controls.Add($lblNewDest)
    
    $validBaseDir = $script:CurrentConfig.TargetRootPath
    if (-not (Test-DriveIsConnected -Path $validBaseDir)) {
        $validBaseDir = Get-DefaultTargetDirectory
    }
    
    $txtNewEventDest = New-Object System.Windows.Forms.TextBox
    $txtNewEventDest.Location = New-Object System.Drawing.Point(0, 107)
    $txtNewEventDest.Size = New-Object System.Drawing.Size(235, 25)
    $txtNewEventDest.BackColor = $colorElevated
    $txtNewEventDest.ForeColor = $colorText
    $txtNewEventDest.Font = $fontMono
    $txtNewEventDest.Text = $validBaseDir
    $pnlRight.Controls.Add($txtNewEventDest)
    
    $btnBrowseDest = New-Object System.Windows.Forms.Button
    $btnBrowseDest.Text = "Procurar..."
    $btnBrowseDest.Font = $fontRegular
    $btnBrowseDest.BackColor = $colorElevated
    $btnBrowseDest.ForeColor = $colorText
    $btnBrowseDest.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBrowseDest.Location = New-Object System.Drawing.Point(240, 105)
    $btnBrowseDest.Size = New-Object System.Drawing.Size(80, 27)
    $pnlRight.Controls.Add($btnBrowseDest)
    
    $btnBrowseDest.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione a Pasta Base de Armazenamento para os Eventos"
        if ($fbd.ShowDialog($modal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtNewEventDest.Text = $fbd.SelectedPath
        }
    })
    
    $lblEventExpl = New-Object System.Windows.Forms.Label
    $lblEventExpl.Text = "Estrutura automatica de pastas:`n[Armazenamento]\[Evento]\[Fotografo]\...`n`nTodos os cartoes serao organizados com seguranca nesta pasta."
    $lblEventExpl.Font = $fontSmall
    $lblEventExpl.ForeColor = $colorMuted
    $lblEventExpl.Location = New-Object System.Drawing.Point(0, 145)
    $lblEventExpl.Size = New-Object System.Drawing.Size(320, 80)
    $pnlRight.Controls.Add($lblEventExpl)
    
    $btnCreateEvent = New-Object System.Windows.Forms.Button
    $btnCreateEvent.Text = "+ Criar e Iniciar Evento"
    $btnCreateEvent.Font = $fontBold
    $btnCreateEvent.BackColor = $colorGreen
    $btnCreateEvent.ForeColor = [System.Drawing.Color]::Black
    $btnCreateEvent.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCreateEvent.Location = New-Object System.Drawing.Point(0, 318)
    $btnCreateEvent.Size = New-Object System.Drawing.Size(320, 36)
    $pnlRight.Controls.Add($btnCreateEvent)
    
    $btnCancelModal = New-Object System.Windows.Forms.Button
    $btnCancelModal.Text = "Fechar"
    $btnCancelModal.Font = $fontRegular
    $btnCancelModal.BackColor = $colorElevated
    $btnCancelModal.ForeColor = $colorText
    $btnCancelModal.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancelModal.Location = New-Object System.Drawing.Point(610, 470)
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
# MODAL: CADASTRO OU EDICAO DE CARTAO POR EVENTO
# -----------------------------------------------------------------------------
function Show-CardSetupModal {
    param(
        [Parameter(Mandatory=$true)][string]$DriveLetter,
        [Parameter(Mandatory=$true)][string]$CardIdentifier,
        [Parameter(Mandatory=$true)][string]$EventName,
        [PSObject]$ExistingRegistration = $null
    )
    
    $isEditMode = ($null -ne $ExistingRegistration)
    
    $setupModal = New-Object System.Windows.Forms.Form
    $setupModal.Text = if ($isEditMode) { "Estacao DIT - Editar Cadastro do Cartao" } else { "Estacao DIT - Cadastro Obrigatorio de Cartao" }
    $setupModal.Size = New-Object System.Drawing.Size(640, 480)
    $setupModal.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $setupModal.BackColor = $colorBg
    $setupModal.ForeColor = $colorText
    $setupModal.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $setupModal.MaximizeBox = $false
    $setupModal.MinimizeBox = $false
    $setupModal.TopMost = $true
    
    $pnlTop = New-Object System.Windows.Forms.Panel
    $pnlTop.Dock = [System.Windows.Forms.DockStyle]::Top
    $pnlTop.Height = 70
    $pnlTop.BackColor = $colorSurface
    $pnlTop.Padding = New-Object System.Windows.Forms.Padding(20, 12, 20, 12)
    $setupModal.Controls.Add($pnlTop)
    
    $lblTop1 = New-Object System.Windows.Forms.Label
    $lblTop1.Text = if ($isEditMode) { "EDITAR CADASTRO DO CARTAO" } else { "NOVO CARTAO DETECTADO - CONFIGURACAO DE DESTINO" }
    $lblTop1.Font = $fontTitle
    $lblTop1.ForeColor = if ($isEditMode) { $colorCyan } else { $colorAmber }
    $lblTop1.AutoSize = $true
    $pnlTop.Controls.Add($lblTop1)
    
    $lblTop2 = New-Object System.Windows.Forms.Label
    $lblTop2.Text = "Unidade: $DriveLetter  |  ID do Cartao: $CardIdentifier  |  Evento: $EventName"
    $lblTop2.Font = $fontMono
    $lblTop2.ForeColor = $colorCyan
    $lblTop2.Location = New-Object System.Drawing.Point(20, 40)
    $lblTop2.AutoSize = $true
    $pnlTop.Controls.Add($lblTop2)
    
    $pnlBody = New-Object System.Windows.Forms.Panel
    $pnlBody.Location = New-Object System.Drawing.Point(20, 85)
    $pnlBody.Size = New-Object System.Drawing.Size(585, 320)
    $setupModal.Controls.Add($pnlBody)
    
    # Campo 1: Nome do Fotografo
    $lblPhotog = New-Object System.Windows.Forms.Label
    $lblPhotog.Text = "1. Nome do Fotografo Deste Cartao:"
    $lblPhotog.Font = $fontBold
    $lblPhotog.Location = New-Object System.Drawing.Point(0, 0)
    $lblPhotog.AutoSize = $true
    $pnlBody.Controls.Add($lblPhotog)
    
    $cmbPhotog = New-Object System.Windows.Forms.ComboBox
    $cmbPhotog.Location = New-Object System.Drawing.Point(0, 24)
    $cmbPhotog.Size = New-Object System.Drawing.Size(585, 26)
    $cmbPhotog.BackColor = $colorElevated
    $cmbPhotog.ForeColor = $colorText
    $cmbPhotog.Font = $fontRegular
    $cmbPhotog.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    
    $existingPhotogs = @(Get-EventPhotographers -EventName $EventName)
    foreach ($p in $existingPhotogs) {
        [void]$cmbPhotog.Items.Add($p)
    }
    
    if ($isEditMode -and $ExistingRegistration.Photographer) {
        $cmbPhotog.Text = $ExistingRegistration.Photographer
    } elseif ($existingPhotogs.Count -gt 0) {
        $cmbPhotog.SelectedIndex = 0
    } else {
        $fotografoTxt = Join-Path $DriveLetter "fotografo.txt"
        if (Test-Path $fotografoTxt) {
            $fromCard = Get-PhotographerFromCard -DriveLetter $DriveLetter
            $cmbPhotog.Text = if ($fromCard) { $fromCard } else { "Fotografo_1" }
        } else {
            $cmbPhotog.Text = "Fotografo_1"
        }
    }
    $pnlBody.Controls.Add($cmbPhotog)
    
    $lblPhotogRule = New-Object System.Windows.Forms.Label
    $lblPhotogRule.Text = "Regra DIT: Um fotografo pode ter varios cartoes, mas cada cartao pertence a um unico fotografo."
    $lblPhotogRule.Font = $fontSmall
    $lblPhotogRule.ForeColor = $colorMuted
    $lblPhotogRule.Location = New-Object System.Drawing.Point(0, 52)
    $lblPhotogRule.AutoSize = $true
    $pnlBody.Controls.Add($lblPhotogRule)
    
    # Campo 2: Subpasta das Fotos no Cartao
    $lblSubf = New-Object System.Windows.Forms.Label
    $lblSubf.Text = "2. Subpasta onde estao as fotos no cartao (Camera):"
    $lblSubf.Font = $fontBold
    $lblSubf.Location = New-Object System.Drawing.Point(0, 80)
    $lblSubf.AutoSize = $true
    $pnlBody.Controls.Add($lblSubf)
    
    $cmbSubf = New-Object System.Windows.Forms.ComboBox
    $cmbSubf.Location = New-Object System.Drawing.Point(0, 104)
    $cmbSubf.Size = New-Object System.Drawing.Size(465, 26)
    $cmbSubf.BackColor = $colorElevated
    $cmbSubf.ForeColor = $colorText
    $cmbSubf.Font = $fontMono
    $cmbSubf.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    
    $detectedFolders = @(Get-CardPhotoFolders -DriveRoot $DriveLetter)
    foreach ($f in $detectedFolders) {
        [void]$cmbSubf.Items.Add($f)
    }
    
    if ($isEditMode -and $ExistingRegistration.PhotoSubfolder) {
        $cmbSubf.Text = $ExistingRegistration.PhotoSubfolder
    } elseif ($cmbSubf.Items.Count -gt 0) {
        $cmbSubf.SelectedIndex = 0
    }
    $pnlBody.Controls.Add($cmbSubf)
    
    $btnBrowseCardSubf = New-Object System.Windows.Forms.Button
    $btnBrowseCardSubf.Text = "Procurar..."
    $btnBrowseCardSubf.Font = $fontRegular
    $btnBrowseCardSubf.BackColor = $colorElevated
    $btnBrowseCardSubf.ForeColor = $colorText
    $btnBrowseCardSubf.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBrowseCardSubf.Location = New-Object System.Drawing.Point(475, 102)
    $btnBrowseCardSubf.Size = New-Object System.Drawing.Size(110, 28)
    $pnlBody.Controls.Add($btnBrowseCardSubf)
    
    $btnBrowseCardSubf.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione a Pasta de Fotos dentro do Cartao $DriveLetter"
        $fbd.SelectedPath = $DriveLetter
        if ($fbd.ShowDialog($setupModal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $sel = $fbd.SelectedPath
            $root = [System.IO.Path]::GetPathRoot($sel)
            $rel = $sel.Substring($root.Length).TrimStart('\')
            $cmbSubf.Text = if ($rel) { $rel } else { "\ (Raiz do Cartao)" }
        }
    })
    
    # Campo 3: Pasta de Destino das Fotos
    $lblDest = New-Object System.Windows.Forms.Label
    $lblDest.Text = "3. Pasta Onde Salvar os Arquivos Deste Cartao:"
    $lblDest.Font = $fontBold
    $lblDest.Location = New-Object System.Drawing.Point(0, 145)
    $lblDest.AutoSize = $true
    $pnlBody.Controls.Add($lblDest)
    
    $txtDest = New-Object System.Windows.Forms.TextBox
    $txtDest.Location = New-Object System.Drawing.Point(0, 169)
    $txtDest.Size = New-Object System.Drawing.Size(465, 25)
    $txtDest.BackColor = $colorElevated
    $txtDest.ForeColor = $colorText
    $txtDest.Font = $fontMono
    
    $curEventInfo = Get-CurrentEvent
    $baseTarget = if ($curEventInfo.DefaultDestination -and (Test-DriveIsConnected -Path $curEventInfo.DefaultDestination)) {
        $curEventInfo.DefaultDestination
    } elseif (Test-DriveIsConnected -Path $script:CurrentConfig.TargetRootPath) {
        [System.IO.Path]::Combine($script:CurrentConfig.TargetRootPath, $EventName)
    } else {
        [System.IO.Path]::Combine((Get-DefaultTargetDirectory), $EventName)
    }
    
    if ($isEditMode -and $ExistingRegistration.DestinationPath -and (Test-DriveIsConnected -Path $ExistingRegistration.DestinationPath)) {
        $txtDest.Text = $ExistingRegistration.DestinationPath
    } else {
        $txtDest.Text = [System.IO.Path]::Combine($baseTarget, ($cmbPhotog.Text -replace '[\\/:*?"<>|]', '_'))
    }
    $pnlBody.Controls.Add($txtDest)
    
    # Atualiza destino quando o nome do fotografo mudar
    $cmbPhotog.Add_TextChanged({
        $photogClean = $cmbPhotog.Text.Trim() -replace '[\\/:*?"<>|]', '_'
        if (-not [string]::IsNullOrWhiteSpace($photogClean)) {
            $curParent = Split-Path -Parent $txtDest.Text
            if (-not [string]::IsNullOrWhiteSpace($curParent)) {
                $txtDest.Text = [System.IO.Path]::Combine($curParent, $photogClean)
            } else {
                $txtDest.Text = [System.IO.Path]::Combine($baseTarget, $photogClean)
            }
        }
    })
    
    $btnBrowseDestCard = New-Object System.Windows.Forms.Button
    $btnBrowseDestCard.Text = "Procurar..."
    $btnBrowseDestCard.Font = $fontRegular
    $btnBrowseDestCard.BackColor = $colorElevated
    $btnBrowseDestCard.ForeColor = $colorText
    $btnBrowseDestCard.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnBrowseDestCard.Location = New-Object System.Drawing.Point(475, 167)
    $btnBrowseDestCard.Size = New-Object System.Drawing.Size(110, 28)
    $pnlBody.Controls.Add($btnBrowseDestCard)
    
    $btnBrowseDestCard.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione Onde Salvar as Fotos Deste Cartao"
        $fbd.SelectedPath = $baseTarget
        if ($fbd.ShowDialog($setupModal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtDest.Text = $fbd.SelectedPath
        }
    })
    
    $lblNotice = New-Object System.Windows.Forms.Label
    $lblNotice.Text = "Configuracao salva no evento. Proximas insercoes deste mesmo cartao serao automaticas!"
    $lblNotice.Font = $fontSmall
    $lblNotice.ForeColor = $colorGreen
    $lblNotice.Location = New-Object System.Drawing.Point(0, 215)
    $lblNotice.AutoSize = $true
    $pnlBody.Controls.Add($lblNotice)
    
    # Rodape
    $pnlFooter = New-Object System.Windows.Forms.Panel
    $pnlFooter.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $pnlFooter.Height = 60
    $pnlFooter.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
    $setupModal.Controls.Add($pnlFooter)
    
    $btnCancelModal = New-Object System.Windows.Forms.Button
    $btnCancelModal.Text = "Cancelar"
    $btnCancelModal.Font = $fontRegular
    $btnCancelModal.BackColor = $colorElevated
    $btnCancelModal.ForeColor = $colorText
    $btnCancelModal.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnCancelModal.Location = New-Object System.Drawing.Point(355, 14)
    $btnCancelModal.Size = New-Object System.Drawing.Size(110, 36)
    $pnlFooter.Controls.Add($btnCancelModal)
    
    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = if ($isEditMode) { "Salvar Alteracoes" } else { "Salvar e Iniciar Ingestao" }
    $btnSave.Font = $fontBold
    $btnSave.BackColor = $colorGreen
    $btnSave.ForeColor = [System.Drawing.Color]::Black
    $btnSave.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnSave.Location = New-Object System.Drawing.Point(475, 14)
    $btnSave.Size = New-Object System.Drawing.Size(130, 36)
    $pnlFooter.Controls.Add($btnSave)
    
    $btnSave.Add_Click({
        $photogName = $cmbPhotog.Text.Trim()
        $subfPath = $cmbSubf.Text.Trim()
        $destPath = $txtDest.Text.Trim()
        
        if ([string]::IsNullOrWhiteSpace($photogName)) {
            [System.Windows.Forms.MessageBox]::Show($setupModal, "Informe o nome do fotografo.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        if ([string]::IsNullOrWhiteSpace($destPath)) {
            [System.Windows.Forms.MessageBox]::Show($setupModal, "Informe a pasta de destino.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return
        }
        
        if (-not (Test-DriveIsConnected -Path $destPath)) {
            [System.Windows.Forms.MessageBox]::Show($setupModal, "A unidade de disco para '$destPath' nao esta disponivel ou conectada neste computador! Escolha outra pasta em um disco valido.", "Disco Indisponivel", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            return
        }
        
        if ($subfPath -eq "\ (Raiz do Cartao)") {
            $subfPath = ""
        }
        
        $script:RegisteredResult = Register-CardForEvent -EventName $EventName `
            -CardIdentifier $CardIdentifier `
            -Photographer $photogName `
            -DestinationPath $destPath `
            -PhotoSubfolder $subfPath
        
        $setupModal.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $setupModal.Close()
    })
    
    $btnCancelModal.Add_Click({
        $script:RegisteredResult = $null
        $setupModal.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $setupModal.Close()
    })
    
    [void]$setupModal.ShowDialog()
    $setupModal.Dispose()
    return $script:RegisteredResult
}

# -----------------------------------------------------------------------------
# JANELA PRINCIPAL DA APLICACAO
# -----------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Estacao de Ingestao DIT - Backup Seguro de Alta Confiabilidade"
$form.Size = New-Object System.Drawing.Size(1100, 780)
$form.MinimumSize = New-Object System.Drawing.Size(980, 680)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $colorBg
$form.ForeColor = $colorText
$form.Font = $fontRegular

# CORPO PRINCIPAL COM DUAS COLUNAS (ADICIONADO PRIMEIRO PARA DOCK=FILL)
$mainContainer = New-Object System.Windows.Forms.SplitContainer
$mainContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainContainer.BackColor = $colorBg
$mainContainer.SplitterWidth = 8
$mainContainer.SplitterDistance = 640
# skipped min
try { $mainContainer.SplitterDistance = 640 } catch {}
$form.Add_Resize({
    try {
        Adjust-CardsGridColumns
        Adjust-HistoryGridColumns
    } catch {} try { if ($form.ClientSize.Width -gt 800) { $mainContainer.SplitterDistance = [math]::Max(450, [int]($form.ClientSize.Width * 0.60)) } } catch {} })
$form.Controls.Add($mainContainer)

# PAINEL DE STATUS & PROGRESSO DE INGESTAO (DOCK=TOP)
$pnlProgress = New-Object System.Windows.Forms.Panel
$pnlProgress.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlProgress.Height = 100
$pnlProgress.BackColor = $colorSurface
$pnlProgress.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($pnlProgress)

$lblBadge = New-Object System.Windows.Forms.Label
$lblBadge.Text = "SISTEMA ARMADO"
$lblBadge.Font = $fontBold
$lblBadge.ForeColor = $colorGreen
$lblBadge.BackColor = [System.Drawing.Color]::FromArgb(30, 16, 185, 129)
$lblBadge.Location = New-Object System.Drawing.Point(20, 10)
$lblBadge.Size = New-Object System.Drawing.Size(180, 26)
$lblBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$pnlProgress.Controls.Add($lblBadge)

$lblStatusDetail = New-Object System.Windows.Forms.Label
$lblStatusDetail.Text = "Aguardando conexao de cartoes ou disparo manual..."
$lblStatusDetail.Font = $fontRegular
$lblStatusDetail.ForeColor = $colorMuted
$lblStatusDetail.Location = New-Object System.Drawing.Point(215, 14)
$lblStatusDetail.Size = New-Object System.Drawing.Size(650, 20)
$lblStatusDetail.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlProgress.Controls.Add($lblStatusDetail)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Parar com Seguranca"
$btnCancel.Font = $fontBold
$btnCancel.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
$btnCancel.ForeColor = $colorAmber
$btnCancel.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancel.Location = New-Object System.Drawing.Point(880, 8)
$btnCancel.Size = New-Object System.Drawing.Size(180, 30)
$btnCancel.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnCancel.Enabled = $false
$pnlProgress.Controls.Add($btnCancel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 44)
$progressBar.Size = New-Object System.Drawing.Size(1040, 18)
$progressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$progressBar.Value = 0
$pnlProgress.Controls.Add($progressBar)

$lblProgressMetrics = New-Object System.Windows.Forms.Label
$lblProgressMetrics.Text = "0 / 0 fotos (0%)"
$lblProgressMetrics.Font = $fontMono
$lblProgressMetrics.ForeColor = $colorMuted
$lblProgressMetrics.Location = New-Object System.Drawing.Point(20, 68)
$lblProgressMetrics.AutoSize = $true
$pnlProgress.Controls.Add($lblProgressMetrics)

$lblFileDetail = New-Object System.Windows.Forms.Label
$lblFileDetail.Text = ""
$lblFileDetail.Font = $fontMono
$lblFileDetail.ForeColor = $colorCyan
$lblFileDetail.Location = New-Object System.Drawing.Point(260, 68)
$lblFileDetail.Size = New-Object System.Drawing.Size(800, 20)
$lblFileDetail.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlProgress.Controls.Add($lblFileDetail)

# BANNER DE AVISO DE UNIDADE DESCONECTADA (DOCK=TOP)
$bannerWarning = New-Object System.Windows.Forms.Panel
$bannerWarning.Dock = [System.Windows.Forms.DockStyle]::Top
$bannerWarning.Height = 36
$bannerWarning.BackColor = [System.Drawing.Color]::FromArgb(50, 40, 15)
$bannerWarning.Visible = $false
$bannerWarning.Padding = New-Object System.Windows.Forms.Padding(20, 6, 20, 6)
$form.Controls.Add($bannerWarning)

$lblWarningText = New-Object System.Windows.Forms.Label
$lblWarningText.Text = "ATENCAO: A unidade de armazenamento configurada nao esta conectada! Clique ao lado para selecionar um disco valido."
$lblWarningText.Font = $fontBold
$lblWarningText.ForeColor = $colorAmber
$lblWarningText.Location = New-Object System.Drawing.Point(20, 8)
$lblWarningText.AutoSize = $true
$bannerWarning.Controls.Add($lblWarningText)

$btnFixStorage = New-Object System.Windows.Forms.Button
$btnFixStorage.Text = "Selecionar Disco Valido..."
$btnFixStorage.Font = $fontBold
$btnFixStorage.BackColor = $colorAmber
$btnFixStorage.ForeColor = [System.Drawing.Color]::Black
$btnFixStorage.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnFixStorage.Location = New-Object System.Drawing.Point(850, 4)
$btnFixStorage.Size = New-Object System.Drawing.Size(210, 26)
$btnFixStorage.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$bannerWarning.Controls.Add($btnFixStorage)

# BARRA DE CONTROLE: MONITORAMENTO & DESTINO DE ARMAZENAMENTO (DOCK=TOP)
$monitorBar = New-Object System.Windows.Forms.Panel
$monitorBar.Dock = [System.Windows.Forms.DockStyle]::Top
$monitorBar.Height = 50
$monitorBar.BackColor = [System.Drawing.Color]::FromArgb(18, 30, 49)
$monitorBar.Padding = New-Object System.Windows.Forms.Padding(20, 8, 20, 8)
$form.Controls.Add($monitorBar)

$lblMonitorState = New-Object System.Windows.Forms.Label
$lblMonitorState.Text = "MONITORAMENTO ATIVO - Leitura Automatica Ligada"
$lblMonitorState.Font = $fontBold
$lblMonitorState.ForeColor = $colorGreen
$lblMonitorState.Location = New-Object System.Drawing.Point(20, 15)
$lblMonitorState.AutoSize = $true
$monitorBar.Controls.Add($lblMonitorState)

$btnToggleMonitor = New-Object System.Windows.Forms.Button
$btnToggleMonitor.Text = "Pausar Leitura"
$btnToggleMonitor.Font = $fontBold
$btnToggleMonitor.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
$btnToggleMonitor.ForeColor = $colorAmber
$btnToggleMonitor.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnToggleMonitor.Location = New-Object System.Drawing.Point(380, 10)
$btnToggleMonitor.Size = New-Object System.Drawing.Size(160, 30)
$monitorBar.Controls.Add($btnToggleMonitor)

$lblStorageTitle = New-Object System.Windows.Forms.Label
$lblStorageTitle.Text = "Destino do Evento:"
$lblStorageTitle.Font = $fontBold
$lblStorageTitle.ForeColor = $colorMuted
$lblStorageTitle.Location = New-Object System.Drawing.Point(560, 15)
$lblStorageTitle.AutoSize = $true
$monitorBar.Controls.Add($lblStorageTitle)

$lblStoragePath = New-Object System.Windows.Forms.Label
$lblStoragePath.Font = $fontMono
$lblStoragePath.ForeColor = $colorCyan
$lblStoragePath.Location = New-Object System.Drawing.Point(680, 15)
$lblStoragePath.Size = New-Object System.Drawing.Size(260, 20)
$lblStoragePath.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$monitorBar.Controls.Add($lblStoragePath)

$btnChangeStorage = New-Object System.Windows.Forms.Button
$btnChangeStorage.Text = "Alterar Pasta..."
$btnChangeStorage.Font = $fontRegular
$btnChangeStorage.BackColor = $colorElevated
$btnChangeStorage.ForeColor = $colorText
$btnChangeStorage.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnChangeStorage.Location = New-Object System.Drawing.Point(950, 10)
$btnChangeStorage.Size = New-Object System.Drawing.Size(110, 30)
$btnChangeStorage.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$monitorBar.Controls.Add($btnChangeStorage)

# BARRA SUPERIOR (HEADER) (DOCK=TOP - ADICIONADO POR ULTIMO FICA NO TOPO EXTREMO)
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$headerPanel.Height = 65
$headerPanel.BackColor = $colorSurface
$headerPanel.Padding = New-Object System.Windows.Forms.Padding(20, 10, 20, 10)
$form.Controls.Add($headerPanel)

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Text = "ESTACAO DE INGESTAO DIT"
$lblBrand.Font = $fontTitle
$lblBrand.ForeColor = $colorCyan
$lblBrand.Location = New-Object System.Drawing.Point(20, 12)
$lblBrand.AutoSize = $true
$headerPanel.Controls.Add($lblBrand)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "Backup Fotografico Automatizado com SHA-256 e Ejecao Segura"
$lblSub.Font = $fontSmall
$lblSub.ForeColor = $colorMuted
$lblSub.Location = New-Object System.Drawing.Point(20, 36)
$lblSub.AutoSize = $true
$headerPanel.Controls.Add($lblSub)

$lblActiveEventBadge = New-Object System.Windows.Forms.Label
$lblActiveEventBadge.Text = "EVENTO: $script:CurrentEvent"
$lblActiveEventBadge.Font = $fontBold
$lblActiveEventBadge.ForeColor = $colorCyan
$lblActiveEventBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 6, 182, 212)
$lblActiveEventBadge.Location = New-Object System.Drawing.Point(620, 15)
$lblActiveEventBadge.Size = New-Object System.Drawing.Size(250, 32)
$lblActiveEventBadge.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblActiveEventBadge.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.Controls.Add($lblActiveEventBadge)

$btnSwitchEvent = New-Object System.Windows.Forms.Button
$btnSwitchEvent.Text = "Trocar / Novo Evento"
$btnSwitchEvent.Font = $fontBold
$btnSwitchEvent.BackColor = $colorElevated
$btnSwitchEvent.ForeColor = $colorText
$btnSwitchEvent.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSwitchEvent.Location = New-Object System.Drawing.Point(880, 15)
$btnSwitchEvent.Size = New-Object System.Drawing.Size(180, 32)
$btnSwitchEvent.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.Controls.Add($btnSwitchEvent)

# -----------------------------------------------------------------------------
# FUNCOES DE ATUALIZACAO DE STATUS E TELA
# -----------------------------------------------------------------------------
function Update-StorageUI {
    $ev = Get-CurrentEvent
    $dest = $ev.DefaultDestination
    $lblStoragePath.Text = $dest
    
    if (-not (Test-DriveIsConnected -Path $dest)) {
        $root = [System.IO.Path]::GetPathRoot($dest)
        $bannerWarning.Visible = $true
        $lblWarningText.Text = "ATENCAO: A unidade '$root' nao esta conectada! Destino salvo sera redirecionado para um disco valido."
    } else {
        $bannerWarning.Visible = $false
    }
}

function Update-MonitoringUI {
    if ($script:MonitoringActive) {
        $lblMonitorState.Text = "MONITORAMENTO ATIVO - Leitura Automatica Ligada"
        $lblMonitorState.ForeColor = $colorGreen
        $monitorBar.BackColor = [System.Drawing.Color]::FromArgb(15, 35, 30)
        $btnToggleMonitor.Text = "Pausar Leitura"
        $btnToggleMonitor.ForeColor = $colorAmber
        $btnToggleMonitor.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
    } else {
        $lblMonitorState.Text = "MONITORAMENTO PAUSADO - Nenhuma Leitura Sera Feita"
        $lblMonitorState.ForeColor = $colorAmber
        $monitorBar.BackColor = [System.Drawing.Color]::FromArgb(40, 30, 15)
        $btnToggleMonitor.Text = "Retomar Leitura"
        $btnToggleMonitor.ForeColor = $colorGreen
        $btnToggleMonitor.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
    }
}

$btnToggleMonitor.Add_Click({
    $script:MonitoringActive = -not $script:MonitoringActive
    Set-MonitoringState -Active $script:MonitoringActive | Out-Null
    Update-MonitoringUI
})

$btnChangeStorage.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a Pasta Onde Salvar os Arquivos do Evento $script:CurrentEvent"
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Set-EventDestination -EventName $script:CurrentEvent -NewDestination $fbd.SelectedPath -UpdateRegisteredCards $true | Out-Null
            $script:CurrentConfig = Get-StationConfig
            Update-StorageUI
            Refresh-EventCardsGrid
            [System.Windows.Forms.MessageBox]::Show($form, "Pasta de armazenamento alterada com sucesso!`n`nNovo Destino: $($fbd.SelectedPath)`n`nTodos os cartoes cadastrados foram atualizados.", "Destino Atualizado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show($form, "Erro ao alterar pasta de destino: $_", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$btnFixStorage.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione uma Pasta em um Disco Valido para os Backups"
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Set-EventDestination -EventName $script:CurrentEvent -NewDestination $fbd.SelectedPath -UpdateRegisteredCards $true | Out-Null
            $script:CurrentConfig = Get-StationConfig
            Update-StorageUI
            Refresh-EventCardsGrid
        } catch {}
    }
})

# -----------------------------------------------------------------------------
# COLUNA ESQUERDA: CARTOES CADASTRADOS & DISPARO MANUAL
# -----------------------------------------------------------------------------
# 1. Painel Inferior: Disparo Manual (Dock = Bottom para ficar sempre visivel e proporcional)
$pnlManual = New-Object System.Windows.Forms.Panel
$pnlManual.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlManual.Height = 140
$pnlManual.BackColor = $colorSurface
$pnlManual.Padding = New-Object System.Windows.Forms.Padding(14, 10, 14, 10)
$mainContainer.Panel1.Controls.Add($pnlManual)

$lblManualTitle = New-Object System.Windows.Forms.Label
$lblManualTitle.Text = "DESCARREGAR MANUALMENTE (SE JA CONECTADO)"
$lblManualTitle.Font = $fontSubTitle
$lblManualTitle.ForeColor = $colorCyan
$lblManualTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$lblManualTitle.Height = 22
$pnlManual.Controls.Add($lblManualTitle)

$lblManualSub = New-Object System.Windows.Forms.Label
$lblManualSub.Text = "Informe ou selecione a unidade/pasta do cartao fotografico:"
$lblManualSub.Font = $fontSmall
$lblManualSub.ForeColor = $colorMuted
$lblManualSub.Dock = [System.Windows.Forms.DockStyle]::Top
$lblManualSub.Height = 18
$pnlManual.Controls.Add($lblManualSub)

$pnlManualInputRow = New-Object System.Windows.Forms.Panel
$pnlManualInputRow.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlManualInputRow.Height = 32
$pnlManualInputRow.Padding = New-Object System.Windows.Forms.Padding(0, 2, 0, 2)
$pnlManual.Controls.Add($pnlManualInputRow)

$btnBrowseSource = New-Object System.Windows.Forms.Button
$btnBrowseSource.Text = "Procurar..."
$btnBrowseSource.Font = $fontRegular
$btnBrowseSource.BackColor = $colorElevated
$btnBrowseSource.ForeColor = $colorText
$btnBrowseSource.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnBrowseSource.Dock = [System.Windows.Forms.DockStyle]::Right
$btnBrowseSource.Width = 95
$pnlManualInputRow.Controls.Add($btnBrowseSource)

$pnlInputSpacer = New-Object System.Windows.Forms.Panel
$pnlInputSpacer.Dock = [System.Windows.Forms.DockStyle]::Right
$pnlInputSpacer.Width = 8
$pnlManualInputRow.Controls.Add($pnlInputSpacer)

$txtSource = New-Object System.Windows.Forms.TextBox
$txtSource.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtSource.BackColor = $colorElevated
$txtSource.ForeColor = $colorText
$txtSource.Font = $fontMono
$pnlManualInputRow.Controls.Add($txtSource)

$pnlBtnSpacer = New-Object System.Windows.Forms.Panel
$pnlBtnSpacer.Dock = [System.Windows.Forms.DockStyle]::Top
$pnlBtnSpacer.Height = 6
$pnlManual.Controls.Add($pnlBtnSpacer)

$btnIngestNow = New-Object System.Windows.Forms.Button
$btnIngestNow.Text = "Iniciar Ingestao Manual Agora"
$btnIngestNow.Font = $fontBold
$btnIngestNow.BackColor = $colorCyan
$btnIngestNow.ForeColor = [System.Drawing.Color]::Black
$btnIngestNow.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnIngestNow.Dock = [System.Windows.Forms.DockStyle]::Top
$btnIngestNow.Height = 36
$pnlManual.Controls.Add($btnIngestNow)

$btnBrowseSource.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a Unidade ou Pasta do Cartao Fotografico"
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSource.Text = $fbd.SelectedPath
    }
})

# 2. Painel Superior: Cartoes Cadastrados no Evento (Dock = Fill para aproveitar todo espaco)
$pnlLeftCards = New-Object System.Windows.Forms.Panel
$pnlLeftCards.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlLeftCards.BackColor = $colorBg
$pnlLeftCards.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
$mainContainer.Panel1.Controls.Add($pnlLeftCards)

$lblCardsTitle = New-Object System.Windows.Forms.Label
$lblCardsTitle.Text = "CARTOES CADASTRADOS NO EVENTO ATUAL"
$lblCardsTitle.Font = $fontSubTitle
$lblCardsTitle.ForeColor = $colorCyan
$lblCardsTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$lblCardsTitle.Height = 28
$pnlLeftCards.Controls.Add($lblCardsTitle)

# Barra de Botoes de Acao do Cartao (Usando TableLayoutPanel responsivo para NUNCA cortar botoes)
$pnlCardActions = New-Object System.Windows.Forms.TableLayoutPanel
$pnlCardActions.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlCardActions.Height = 36
$pnlCardActions.ColumnCount = 3
$pnlCardActions.RowCount = 1
[void]$pnlCardActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 35)))
[void]$pnlCardActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 30)))
[void]$pnlCardActions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 35)))
[void]$pnlCardActions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$pnlLeftCards.Controls.Add($pnlCardActions)

$btnEditCard = New-Object System.Windows.Forms.Button
$btnEditCard.Text = "Editar Cadastro"
$btnEditCard.Font = $fontBold
$btnEditCard.BackColor = $colorCyan
$btnEditCard.ForeColor = [System.Drawing.Color]::Black
$btnEditCard.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnEditCard.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnEditCard.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0)
$pnlCardActions.Controls.Add($btnEditCard, 0, 0)

$btnRemoveCard = New-Object System.Windows.Forms.Button
$btnRemoveCard.Text = "Excluir Cadastro"
$btnRemoveCard.Font = $fontRegular
$btnRemoveCard.BackColor = $colorElevated
$btnRemoveCard.ForeColor = $colorRed
$btnRemoveCard.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRemoveCard.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnRemoveCard.Margin = New-Object System.Windows.Forms.Padding(4, 0, 4, 0)
$pnlCardActions.Controls.Add($btnRemoveCard, 1, 0)

$btnAddCardManual = New-Object System.Windows.Forms.Button
$btnAddCardManual.Text = "+ Cadastrar Cartao"
$btnAddCardManual.Font = $fontRegular
$btnAddCardManual.BackColor = $colorElevated
$btnAddCardManual.ForeColor = $colorText
$btnAddCardManual.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAddCardManual.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnAddCardManual.Margin = New-Object System.Windows.Forms.Padding(4, 0, 0, 0)
$pnlCardActions.Controls.Add($btnAddCardManual, 2, 0)

$pnlCardGridSpacer = New-Object System.Windows.Forms.Panel
$pnlCardGridSpacer.Dock = [System.Windows.Forms.DockStyle]::Bottom
$pnlCardGridSpacer.Height = 8
$pnlLeftCards.Controls.Add($pnlCardGridSpacer)

# Grid de Cartoes (GridLines = $false para eliminar linhas fantasmas brancas no fundo escuro!)
$gridEventCards = New-Object System.Windows.Forms.ListView
$gridEventCards.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridEventCards.View = [System.Windows.Forms.View]::Details
$gridEventCards.FullRowSelect = $true
$gridEventCards.GridLines = $false
$gridEventCards.MultiSelect = $false
$gridEventCards.BackColor = $colorElevated
$gridEventCards.ForeColor = $colorText
$gridEventCards.Font = $fontRegular
$gridEventCards.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
[void]$gridEventCards.Columns.Add("Cartao / ID", 110)
[void]$gridEventCards.Columns.Add("Fotografo", 120)
[void]$gridEventCards.Columns.Add("Subpasta Camera", 110)
[void]$gridEventCards.Columns.Add("Destino dos Arquivos", 220)
$pnlLeftCards.Controls.Add($gridEventCards)

function Adjust-CardsGridColumns {
    if ($gridEventCards.Columns.Count -ge 4) {
        $w = $gridEventCards.ClientSize.Width
        $rem = $w - (110 + 120 + 110) - 4
        if ($rem -gt 100) {
            $gridEventCards.Columns[3].Width = $rem
        }
    }
}
$gridEventCards.Add_Resize({ Adjust-CardsGridColumns })

function Refresh-EventCardsGrid {
    $gridEventCards.Items.Clear()
    $cards = @(Get-EventCards -EventName $script:CurrentEvent)
    if ($cards.Count -eq 0) {
        $item = New-Object System.Windows.Forms.ListViewItem("Nenhum cartao cadastrado")
        [void]$item.SubItems.Add("Insira um cartao para cadastrar")
        [void]$item.SubItems.Add("Detectado ao plugar")
        [void]$item.SubItems.Add($lblStoragePath.Text)
        $item.ForeColor = $colorMuted
        $gridEventCards.Items.Add($item)
    } else {
        foreach ($c in $cards) {
            $item = New-Object System.Windows.Forms.ListViewItem($c.CardIdentifier)
            [void]$item.SubItems.Add($c.Photographer)
            $subText = if ($c.PhotoSubfolder) { $c.PhotoSubfolder } else { "\ (Raiz)" }
            [void]$item.SubItems.Add($subText)
            [void]$item.SubItems.Add($c.DestinationPath)
            $gridEventCards.Items.Add($item)
        }
    }
    Adjust-CardsGridColumns
}

# Acao: Editar Cartao Selecionado
$btnEditCard.Add_Click({
    if ($gridEventCards.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($form, "Selecione um cartao na tabela acima para editar o cadastro.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    $selectedId = $gridEventCards.SelectedItems[0].Text
    if ($selectedId -eq "Nenhum cartao cadastrado") { return }
    
    $cardReg = Get-CardRegistration -EventName $script:CurrentEvent -CardIdentifier $selectedId
    if ($null -eq $cardReg) { return }
    
    # Procura a unidade atual deste cartao se estiver plugado, senao usa C:\
    $currentDrive = "C:\"
    $readyDrives = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
    foreach ($d in $readyDrives) {
        $idTest = Get-CardIdentifier -DriveLetter $d.Name
        if ($idTest -eq $selectedId) {
            $currentDrive = $d.Name
            break
        }
    }
    
    $res = Show-CardSetupModal -DriveLetter $currentDrive -CardIdentifier $selectedId -EventName $script:CurrentEvent -ExistingRegistration $cardReg
    if ($null -ne $res) {
        $script:CurrentConfig = Get-StationConfig
        Refresh-EventCardsGrid
        [System.Windows.Forms.MessageBox]::Show($form, "Cadastro do cartao atualizado com sucesso!`n`nFotografo: $($res.Photographer)`nDestino: $($res.DestinationPath)", "Atualizado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

$gridEventCards.Add_DoubleClick({
    $btnEditCard.PerformClick()
})

# Acao: Excluir Cartao
$btnRemoveCard.Add_Click({
    if ($gridEventCards.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show($form, "Selecione um cartao para excluir.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    $selectedId = $gridEventCards.SelectedItems[0].Text
    if ($selectedId -eq "Nenhum cartao cadastrado") { return }
    
    $confirm = [System.Windows.Forms.MessageBox]::Show($form, "Tem certeza que deseja remover o cadastro do cartao '$selectedId'?`n`nAo plugar o cartao novamente, ele pedira um novo cadastro.", "Confirmar Exclusao", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Remove-CardRegistration -EventName $script:CurrentEvent -CardIdentifier $selectedId | Out-Null
        $script:CurrentConfig = Get-StationConfig
        Refresh-EventCardsGrid
    }
})

# Acao: Cadastrar Cartao Manualmente
$btnAddCardManual.Add_Click({
    $cardIdInput = [Microsoft.VisualBasic.Interaction]::InputBox("Informe o Identificador / Nome do Cartao (Ex: CARD_01 ou EOS_DIGITAL):", "Cadastrar Novo Cartao", "CARTAO_" + (Get-Random -Minimum 100 -Maximum 999))
    if ([string]::IsNullOrWhiteSpace($cardIdInput)) { return }
    
    $res = Show-CardSetupModal -DriveLetter "C:\" -CardIdentifier $cardIdInput.Trim() -EventName $script:CurrentEvent
    if ($null -ne $res) {
        $script:CurrentConfig = Get-StationConfig
        Refresh-EventCardsGrid
    }
})

# -----------------------------------------------------------------------------
# COLUNA DIREITA: AUDITORIA & HISTORICO DE TRANSFERENCIAS
# -----------------------------------------------------------------------------
$pnlRightHist = New-Object System.Windows.Forms.Panel
$pnlRightHist.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlRightHist.BackColor = $colorBg
$pnlRightHist.Padding = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$mainContainer.Panel2.Controls.Add($pnlRightHist)

$lblHistColTitle = New-Object System.Windows.Forms.Label
$lblHistColTitle.Text = "AUDITORIA & HISTORICO DE INGESTOES DIT"
$lblHistColTitle.Font = $fontSubTitle
$lblHistColTitle.ForeColor = $colorCyan
$lblHistColTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$lblHistColTitle.Height = 28
$pnlRightHist.Controls.Add($lblHistColTitle)

$gridHistory = New-Object System.Windows.Forms.ListView
$gridHistory.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridHistory.View = [System.Windows.Forms.View]::Details
$gridHistory.FullRowSelect = $true
$gridHistory.GridLines = $false
$gridHistory.BackColor = $colorElevated
$gridHistory.ForeColor = $colorText
$gridHistory.Font = $fontRegular
$gridHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
[void]$gridHistory.Columns.Add("Hora", 70)
[void]$gridHistory.Columns.Add("Cartao / Fotografo", 150)
[void]$gridHistory.Columns.Add("Fotos", 75)
[void]$gridHistory.Columns.Add("Volume", 75)
[void]$gridHistory.Columns.Add("Status / Ejecao", 110)
$pnlRightHist.Controls.Add($gridHistory)

function Adjust-HistoryGridColumns {
    if ($gridHistory.Columns.Count -ge 5) {
        $w = $gridHistory.ClientSize.Width
        $rem = $w - (70 + 150 + 75 + 75) - 4
        if ($rem -gt 90) {
            $gridHistory.Columns[4].Width = $rem
        }
    }
}
$gridHistory.Add_Resize({ Adjust-HistoryGridColumns })
# FLUXO DE EXECUCAO DE INGESTAO COM INTERRUPCAO SEGURA
# -----------------------------------------------------------------------------
$btnCancel.Add_Click({
    if ($script:IsIngesting) {
        $script:CancelRequested = $true
        $btnCancel.Enabled = $false
        $lblStatusDetail.Text = "Interrupcao solicitada. Finalizando foto atual e limpando arquivos temporarios..."
    }
})

function Run-AppIngest {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath
    )
    
    if ($script:IsIngesting) {
        [System.Windows.Forms.MessageBox]::Show($form, "Uma ingestao ja esta em andamento. Aguarde a conclusao.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    
    if (!(Test-Path $SourcePath)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Caminho de origem nao encontrado: $SourcePath", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }
    
    $cardId = Get-CardIdentifier -DriveLetter $SourcePath
    
    # Checa se o cartao ja foi cadastrado para este evento
    $cardReg = Get-CardRegistration -EventName $script:CurrentEvent -CardIdentifier $cardId
    if ($null -eq $cardReg) {
        # Primeira vez que o cartao e visto neste evento: exibe modal de cadastro obrigatorio
        $cardReg = Show-CardSetupModal -DriveLetter $SourcePath -CardIdentifier $cardId -EventName $script:CurrentEvent
        if ($null -eq $cardReg) {
            $lblStatusDetail.Text = "Ingestao cancelada. O cartao $cardId precisa ser configurado para o evento $script:CurrentEvent."
            return
        }
        $script:CurrentConfig = Get-StationConfig
        Refresh-EventCardsGrid
    }
    
    $targetDest = Get-DestinationForCard -CardIdentifier $cardId -SourcePath $SourcePath -Config $script:CurrentConfig -EventName $script:CurrentEvent
    
    $subfToCopy = if ($cardReg.PhotoSubfolder) { $cardReg.PhotoSubfolder } else { "" }
    
    $script:IsIngesting = $true
    $script:CancelRequested = $false
    $btnCancel.Enabled = $true
    $btnIngestNow.Enabled = $false
    
    $lblBadge.Text = "INGESTAO EM ANDAMENTO"
    $lblBadge.ForeColor = $colorAmber
    $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
    $lblStatusDetail.Text = "Descarregando: $($cardReg.Photographer) [$cardId] -> $targetDest"
    $progressBar.Value = 0
    $lblProgressMetrics.Text = "Calculando arquivos..."
    $lblFileDetail.Text = ""
    $form.Update()
    
    try {
        $res = Invoke-CardIngest -SourceDrive $SourcePath `
            -DestinationFolder $targetDest `
            -EventName $script:CurrentEvent `
            -AutoEject $script:CurrentConfig.AutoEject `
            -CardPhotoSubfolder $subfToCopy `
            -CancelCheck { return $script:CancelRequested } `
            -ProgressCallback {
                param($prog)
                if ($prog.TotalFiles -gt 0) {
                    $pct = [math]::Min(100, [int](($prog.ProcessedFiles / $prog.TotalFiles) * 100))
                    $progressBar.Value = $pct
                    $lblProgressMetrics.Text = "$($prog.ProcessedFiles) / $($prog.TotalFiles) fotos ($pct%)"
                }
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
            $lblBadge.Text = "INTERROMPIDO COM SEGURANCA"
            $lblBadge.ForeColor = $colorAmber
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 245, 158, 11)
            $lblStatusDetail.Text = "Ingestao interrompida pelo usuario. Nenhum arquivo foi corrompido e o cartao esta intacto."
            [System.Windows.Forms.MessageBox]::Show($form, "Ingestao interrompida com total seguranca!`n`nNenhum arquivo foi corrompido, os arquivos ja verificados continuam salvos e o cartao esta intacto.", "Interrupcao Segura", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        elseif ($res.Ejected) {
            $progressBar.Value = 100
            $lblBadge.Text = "CONCLUIDO & EJETADO"
            $lblBadge.ForeColor = $colorGreen
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
            $lblStatusDetail.Text = "Backup de $($cardReg.Photographer) concluido! Cartao ejetado com seguranca. Pode retirar."
            $lblFileDetail.Text = ""
        } else {
            $progressBar.Value = 100
            $lblBadge.Text = "CONCLUIDO COM SUCESSO"
            $lblBadge.ForeColor = $colorGreen
            $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 16, 185, 129)
            $lblStatusDetail.Text = "Backup de $($cardReg.Photographer) concluido com sucesso."
        }
    }
    catch {
        $lblBadge.Text = "ERRO"
        $lblBadge.ForeColor = $colorRed
        $lblBadge.BackColor = [System.Drawing.Color]::FromArgb(40, 239, 68, 68)
        $lblStatusDetail.Text = "Erro: $_"
        [System.Windows.Forms.MessageBox]::Show($form, "Erro durante a ingestao:`n$_", "Erro Critico", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
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
        [System.Windows.Forms.MessageBox]::Show($form, "Informe a unidade ou pasta do cartao fotografico.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    Run-AppIngest -SourcePath $src
})

$btnSwitchEvent.Add_Click({
    $res = Show-EventSelectionModal -IsInitial $false
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        $lblActiveEventBadge.Text = "EVENTO: $script:CurrentEvent"
        Update-StorageUI
        Refresh-EventCardsGrid
    }
})

# -----------------------------------------------------------------------------
# DAEMON DE DETECCAO AUTOMATICA DE CARTOES (TIMER NO FORMULARIO)
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

# EXIBE MODAL DE SELECAO DE EVENTO NO INICIO DA EXECUCAO
$form.Add_Load({
    $resInit = Show-EventSelectionModal -IsInitial $true
    $lblActiveEventBadge.Text = "EVENTO: $script:CurrentEvent"
    Update-StorageUI
    Update-MonitoringUI
    Refresh-EventCardsGrid
    $usbTimer.Start()
})

[void]$form.ShowDialog()
$usbTimer.Stop()
$usbTimer.Dispose()
$form.Dispose()
