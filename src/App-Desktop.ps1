# App-Desktop.ps1 - Aplicativo Gráfico Nativo da Estação de Ingestão DIT
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {}

# Renderização nítida em telas com escala de 125%, 150% etc.
try {
    Add-Type -Namespace DitNative -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    [void][DitNative.Dpi]::SetProcessDPIAware()
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
# ESCALA DE TELA (DPI)
# -----------------------------------------------------------------------------
$script:DpiScale = 1.0
try {
    $gdi = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:DpiScale = [double]$gdi.DpiX / 96.0
    $gdi.Dispose()
} catch {}

function Px {
    param([double]$Value)
    return [int][math]::Round($Value * $script:DpiScale)
}

# -----------------------------------------------------------------------------
# SISTEMA DE DESIGN: CORES, FONTES E PINCÉIS
# -----------------------------------------------------------------------------
function New-Rgb {
    param([int]$R, [int]$G, [int]$B)
    return [System.Drawing.Color]::FromArgb($R, $G, $B)
}

function Get-Blend {
    param([System.Drawing.Color]$Front, [System.Drawing.Color]$Back, [double]$Amount)
    $r = [int][math]::Round($Front.R * $Amount + $Back.R * (1 - $Amount))
    $g = [int][math]::Round($Front.G * $Amount + $Back.G * (1 - $Amount))
    $b = [int][math]::Round($Front.B * $Amount + $Back.B * (1 - $Amount))
    return [System.Drawing.Color]::FromArgb($r, $g, $b)
}

$colorBg            = New-Rgb 9 13 22
$colorSurface       = New-Rgb 16 23 38
$colorSurfaceAlt    = New-Rgb 12 18 31
$colorElevated      = New-Rgb 30 41 62
$colorElevatedHover = New-Rgb 42 56 82
$colorBorder        = New-Rgb 40 53 78
$colorText          = New-Rgb 241 245 249
$colorMuted         = New-Rgb 148 163 184
$colorDim           = New-Rgb 107 122 148
$colorCyan          = New-Rgb 34 211 238
$colorCyanBtn       = New-Rgb 14 165 198
$colorGreen         = New-Rgb 52 211 153
$colorGreenBtn      = New-Rgb 16 185 129
$colorAmber         = New-Rgb 251 191 36
$colorRed           = New-Rgb 248 113 113
$colorOnAccent      = New-Rgb 4 18 28
$colorDisabledBg    = New-Rgb 24 33 50
$colorSelect        = Get-Blend $colorCyan $colorSurface 0.16
$colorRowAlt        = Get-Blend $colorText $colorSurface 0.025

$brushSurface = New-Object System.Drawing.SolidBrush($colorSurface)
$brushHeader  = New-Object System.Drawing.SolidBrush($colorSurfaceAlt)
$brushSelect  = New-Object System.Drawing.SolidBrush($colorSelect)
$brushRowAlt  = New-Object System.Drawing.SolidBrush($colorRowAlt)
$brushElev    = New-Object System.Drawing.SolidBrush($colorElevated)
$penBorder    = New-Object System.Drawing.Pen($colorBorder, 1)
$penFocus     = New-Object System.Drawing.Pen($colorCyan, 1)
$penRow       = New-Object System.Drawing.Pen((Get-Blend $colorBorder $colorSurface 0.55), 1)

$fontHero     = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
$fontTitle    = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$fontSubTitle = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$fontRegular  = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular)
$fontBold     = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$fontSmall    = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Regular)
$fontCaps     = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$fontMono     = New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Regular)

$script:TextFlags = [System.Windows.Forms.TextFormatFlags]::Left -bor `
    [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor `
    [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor `
    [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor `
    [System.Windows.Forms.TextFormatFlags]::SingleLine

# -----------------------------------------------------------------------------
# ESTADO GLOBAL DA APLICACAO
# -----------------------------------------------------------------------------
$script:CurrentConfig      = Get-StationConfig
$script:CurrentEvent       = $script:CurrentConfig.CurrentEvent
$script:MonitoringActive   = Get-MonitoringState
$script:IsIngesting        = $false
$script:CancelRequested    = $false
$script:RegisteredResult   = $null
$script:StatusState        = 'idle'
$script:StatusColor        = $colorGreen
$script:ProgressPct        = 0

# -----------------------------------------------------------------------------
# COMPONENTES VISUAIS REUTILIZÁVEIS
# -----------------------------------------------------------------------------
function Enable-DoubleBuffer {
    param($Control)
    try {
        $prop = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
        $prop.SetValue($Control, $true, $null)
    } catch {}
}

function New-RoundedPath {
    param([System.Drawing.Rectangle]$Rect, [int]$Radius)
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $Radius * 2
    $path.AddArc($Rect.X, $Rect.Y, $d, $d, 180, 90)
    $path.AddArc(($Rect.Right - $d), $Rect.Y, $d, $d, 270, 90)
    $path.AddArc(($Rect.Right - $d), ($Rect.Bottom - $d), $d, $d, 0, 90)
    $path.AddArc($Rect.X, ($Rect.Bottom - $d), $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Add-RowStyle {
    param($Table, [string]$Kind, [double]$Value = 0)
    $k = switch ($Kind) { 'abs' { 'Absolute' } 'pct' { 'Percent' } default { 'AutoSize' } }
    [void]$Table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]$k, [single]$Value)))
}

function Add-ColStyle {
    param($Table, [string]$Kind, [double]$Value = 0)
    $k = switch ($Kind) { 'abs' { 'Absolute' } 'pct' { 'Percent' } default { 'AutoSize' } }
    [void]$Table.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]$k, [single]$Value)))
}

function New-Table {
    param([int]$Cols, [int]$Rows)
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.Dock = [System.Windows.Forms.DockStyle]::Fill
    $t.ColumnCount = $Cols
    $t.RowCount = $Rows
    $t.Margin = New-Object System.Windows.Forms.Padding(0)
    $t.Padding = New-Object System.Windows.Forms.Padding(0)
    $t.BackColor = [System.Drawing.Color]::Transparent
    return $t
}

function New-Lbl {
    param([string]$Text, $Font = $fontRegular, $Color = $colorText)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Font = $Font
    $l.ForeColor = $Color
    $l.AutoSize = $true
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Margin = New-Object System.Windows.Forms.Padding(0)
    return $l
}

function Update-BtnLook {
    param([System.Windows.Forms.Button]$Btn)
    $style = [string]$Btn.Tag
    if (-not $Btn.Enabled) {
        $Btn.BackColor = $colorDisabledBg
        $Btn.ForeColor = $colorDim
        $Btn.FlatAppearance.MouseOverBackColor = $colorDisabledBg
        $Btn.FlatAppearance.MouseDownBackColor = $colorDisabledBg
        return
    }
    switch ($style) {
        'primary' { $bg = $colorCyanBtn;  $fg = $colorOnAccent; $hv = $colorCyan }
        'success' { $bg = $colorGreenBtn; $fg = $colorOnAccent; $hv = $colorGreen }
        'danger'  { $bg = $colorElevated; $fg = $colorRed;      $hv = (Get-Blend $colorRed $colorElevated 0.22) }
        'warning' { $bg = (Get-Blend $colorAmber $colorSurface 0.16); $fg = $colorAmber; $hv = (Get-Blend $colorAmber $colorSurface 0.30) }
        'ghost'   { $bg = $colorSurface;  $fg = $colorMuted;    $hv = $colorElevated }
        default   { $bg = $colorElevated; $fg = $colorText;     $hv = $colorElevatedHover }
    }
    $Btn.BackColor = $bg
    $Btn.ForeColor = $fg
    $Btn.FlatAppearance.MouseOverBackColor = $hv
    $Btn.FlatAppearance.MouseDownBackColor = (Get-Blend $hv ([System.Drawing.Color]::Black) 0.82)
}

function New-Btn {
    param([string]$Text, [string]$Style = 'secondary', [int]$Width = 120, [int]$Height = 36, [bool]$Bold = $true)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderSize = 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Size = New-Object System.Drawing.Size($Width, $Height)
    $b.Font = if ($Bold) { $fontBold } else { $fontRegular }
    $b.UseVisualStyleBackColor = $false
    $b.Tag = $Style
    $b.Margin = New-Object System.Windows.Forms.Padding(0)
    Update-BtnLook $b
    $b.Add_EnabledChanged({ param($s, $e) Update-BtnLook $s })
    return $b
}

function New-CardPanel {
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = $colorBg
    $p.Padding = New-Object System.Windows.Forms.Padding(20)
    $p.Margin = New-Object System.Windows.Forms.Padding(0)
    Enable-DoubleBuffer $p
    $p.Add_Resize({ param($s, $e) $s.Invalidate() })
    $p.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
        $path = New-RoundedPath $rect (Px 12)
        $g.FillPath($brushSurface, $path)
        $g.DrawPath($penBorder, $path)
        $path.Dispose()
    })
    return $p
}

function New-TextInput {
    param([string]$Text = "", $Font = $fontRegular)
    $wrap = New-Object System.Windows.Forms.Panel
    $wrap.Dock = [System.Windows.Forms.DockStyle]::Fill
    $wrap.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 4)
    $wrap.BackColor = $colorElevated
    $wrap.Margin = New-Object System.Windows.Forms.Padding(0)
    Enable-DoubleBuffer $wrap
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $tb.BackColor = $colorElevated
    $tb.ForeColor = $colorText
    $tb.Font = $Font
    $tb.Dock = [System.Windows.Forms.DockStyle]::Fill
    $tb.Text = $Text
    $wrap.Controls.Add($tb)
    $wrap.Add_Paint({
        param($s, $e)
        $pen = if ($s.Tag -eq 'focus') { $penFocus } else { $penBorder }
        $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
    })
    $tb.Add_Enter({ param($s, $e) $s.Parent.Tag = 'focus'; $s.Parent.Invalidate() })
    $tb.Add_Leave({ param($s, $e) $s.Parent.Tag = $null; $s.Parent.Invalidate() })
    return $tb
}

function New-ComboInput {
    param($Font = $fontRegular)
    $wrap = New-Object System.Windows.Forms.Panel
    $wrap.Dock = [System.Windows.Forms.DockStyle]::Fill
    $wrap.Padding = New-Object System.Windows.Forms.Padding(8, 7, 8, 0)
    $wrap.BackColor = $colorElevated
    $wrap.Margin = New-Object System.Windows.Forms.Padding(0)
    Enable-DoubleBuffer $wrap
    $cb = New-Object System.Windows.Forms.ComboBox
    $cb.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $cb.BackColor = $colorElevated
    $cb.ForeColor = $colorText
    $cb.Font = $Font
    $cb.Dock = [System.Windows.Forms.DockStyle]::Fill
    $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
    $wrap.Controls.Add($cb)
    $wrap.Add_Paint({
        param($s, $e)
        $pen = if ($s.Tag -eq 'focus') { $penFocus } else { $penBorder }
        $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
    })
    $cb.Add_Enter({ param($s, $e) $s.Parent.Tag = 'focus'; $s.Parent.Invalidate() })
    $cb.Add_Leave({ param($s, $e) $s.Parent.Tag = $null; $s.Parent.Invalidate() })
    return $cb
}

function Set-FlexColumn {
    param([System.Windows.Forms.ListView]$List, [int]$Index, [int]$Min = 100)
    $fixed = 0
    for ($i = 0; $i -lt $List.Columns.Count; $i++) {
        if ($i -ne $Index) { $fixed += $List.Columns[$i].Width }
    }
    $w = $List.ClientSize.Width - $fixed
    if ($w -lt (Px $Min)) { $w = (Px $Min) }
    $List.Columns[$Index].Width = $w
}

function Initialize-DarkList {
    param([System.Windows.Forms.ListView]$List, [int]$RowHeight = 42)
    $List.View = [System.Windows.Forms.View]::Details
    $List.FullRowSelect = $true
    $List.GridLines = $false
    $List.MultiSelect = $false
    $List.HideSelection = $false
    $List.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $List.BackColor = $colorSurface
    $List.ForeColor = $colorText
    $List.Font = $fontRegular
    $List.HeaderStyle = [System.Windows.Forms.ColumnHeaderStyle]::Nonclickable
    $List.OwnerDraw = $true
    $List.Dock = [System.Windows.Forms.DockStyle]::Fill
    $imgs = New-Object System.Windows.Forms.ImageList
    $imgs.ImageSize = New-Object System.Drawing.Size(1, (Px $RowHeight))
    $List.SmallImageList = $imgs
    Enable-DoubleBuffer $List

    $List.Add_DrawColumnHeader({
        param($s, $e)
        $e.Graphics.FillRectangle($brushHeader, $e.Bounds)
        $e.Graphics.DrawLine($penBorder, $e.Bounds.Left, ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1))
        $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + (Px 12)), $e.Bounds.Y, [math]::Max(4, ($e.Bounds.Width - (Px 16))), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $fontCaps, $r, $colorDim, $script:TextFlags)
    })

    $List.Add_DrawItem({ param($s, $e) })

    $List.Add_DrawSubItem({
        param($s, $e)
        $b = $e.Bounds
        if ($e.ColumnIndex -eq 0) {
            $b = New-Object System.Drawing.Rectangle($b.X, $b.Y, $s.Columns[0].Width, $b.Height)
        }
        if ($e.Item.Selected) { $brush = $brushSelect }
        elseif (($e.ItemIndex % 2) -eq 1) { $brush = $brushRowAlt }
        else { $brush = $brushSurface }
        $e.Graphics.FillRectangle($brush, $b)
        $e.Graphics.DrawLine($penRow, $b.Left, ($b.Bottom - 1), $b.Right, ($b.Bottom - 1))
        $r = New-Object System.Drawing.Rectangle(($b.X + (Px 12)), $b.Y, [math]::Max(4, ($b.Width - (Px 16))), $b.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.SubItem.Text, $e.SubItem.Font, $r, $e.SubItem.ForeColor, $script:TextFlags)
    })
}

function New-EmptyHint {
    param([string]$Text)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Font = $fontRegular
    $l.ForeColor = $colorMuted
    $l.BackColor = $colorSurface
    $l.Dock = [System.Windows.Forms.DockStyle]::Fill
    $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
    $l.Padding = New-Object System.Windows.Forms.Padding(24)
    return $l
}

function New-ModalForm {
    param([string]$Title, [int]$Width, [int]$Height)
    $m = New-Object System.Windows.Forms.Form
    $m.Text = $Title
    $m.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $m.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $m.ClientSize = New-Object System.Drawing.Size($Width, $Height)
    $m.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $m.BackColor = $colorBg
    $m.ForeColor = $colorText
    $m.Font = $fontRegular
    $m.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $m.MaximizeBox = $false
    $m.MinimizeBox = $false
    $m.ShowInTaskbar = $false
    $m.TopMost = $true
    return $m
}

function New-ModalRoot {
    param($Form, [int]$HeaderH = 88, [int]$FooterH = 72)
    $t = New-Table 1 3
    Add-ColStyle $t 'pct' 100
    Add-RowStyle $t 'abs' $HeaderH
    Add-RowStyle $t 'pct' 100
    Add-RowStyle $t 'abs' $FooterH
    $Form.Controls.Add($t)
    return $t
}

function New-ModalHeader {
    param([string]$Title, [string]$Subtitle, $Accent)
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = [System.Windows.Forms.DockStyle]::Fill
    $p.BackColor = $colorSurface
    $p.Padding = New-Object System.Windows.Forms.Padding(28, 18, 28, 10)
    $p.Margin = New-Object System.Windows.Forms.Padding(0)
    Enable-DoubleBuffer $p
    $p.Tag = $Accent
    $p.Add_Paint({
        param($s, $e)
        $e.Graphics.DrawLine($penBorder, 0, ($s.Height - 1), $s.Width, ($s.Height - 1))
        $accentBrush = New-Object System.Drawing.SolidBrush($s.Tag)
        $e.Graphics.FillRectangle($accentBrush, 0, 0, (Px 4), $s.Height)
        $accentBrush.Dispose()
    })
    $flow = New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Dock = [System.Windows.Forms.DockStyle]::Fill
    $flow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
    $flow.WrapContents = $false
    $flow.BackColor = [System.Drawing.Color]::Transparent
    $t1 = New-Lbl $Title $fontTitle $Accent
    $t1.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4)
    $t2 = New-Lbl $Subtitle $fontSmall $colorMuted
    $flow.Controls.Add($t1)
    $flow.Controls.Add($t2)
    $p.Controls.Add($flow)
    return $p
}

function New-ModalFooter {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Dock = [System.Windows.Forms.DockStyle]::Fill
    $f.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
    $f.WrapContents = $false
    $f.BackColor = $colorSurface
    $f.Padding = New-Object System.Windows.Forms.Padding(28, 16, 28, 12)
    $f.Margin = New-Object System.Windows.Forms.Padding(0)
    $f.Add_Paint({
        param($s, $e)
        $e.Graphics.DrawLine($penBorder, 0, 0, $s.Width, 0)
    })
    return $f
}

function New-StepHeader {
    param([string]$Number, [string]$Text)
    $t = New-Table 2 1
    $t.Dock = [System.Windows.Forms.DockStyle]::Top
    $t.AutoSize = $true
    Add-ColStyle $t 'abs' 36
    Add-ColStyle $t 'pct' 100
    Add-RowStyle $t 'auto'
    $badge = New-Object System.Windows.Forms.Panel
    $badge.Size = New-Object System.Drawing.Size(26, 26)
    $badge.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 0)
    $badge.BackColor = $colorBg
    $badge.Tag = $Number
    $badge.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $fill = New-Object System.Drawing.SolidBrush((Get-Blend $colorCyan $colorBg 0.18))
        $g.FillEllipse($fill, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $fill.Dispose()
        $g.DrawEllipse($penFocus, 0, 0, ($s.Width - 1), ($s.Height - 1))
        $rc = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
        $fl = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
        [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$s.Tag, $fontBold, $rc, $colorCyan, $fl)
    })
    $lbl = New-Lbl $Text $fontSubTitle $colorText
    $lbl.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $t.Controls.Add($badge, 0, 0)
    $t.Controls.Add($lbl, 1, 0)
    return $t
}

# -----------------------------------------------------------------------------
# MODAL: PERGUNTA DE TEXTO SIMPLES
# -----------------------------------------------------------------------------
function Show-TextPrompt {
    param([string]$Title, [string]$Message, [string]$DefaultText = "")

    $dlg = New-ModalForm -Title $Title -Width 520 -Height 230
    $root = New-ModalRoot -Form $dlg -HeaderH 0 -FooterH 68
    $root.RowStyles[0].Height = 0

    $body = New-Table 1 2
    $body.Padding = New-Object System.Windows.Forms.Padding(28, 24, 28, 8)
    Add-ColStyle $body 'pct' 100
    Add-RowStyle $body 'abs' 52
    Add-RowStyle $body 'abs' 44
    $lblMsg = New-Lbl $Message $fontRegular $colorText
    $lblMsg.MaximumSize = New-Object System.Drawing.Size((Px 460), 0)
    $txt = New-TextInput -Text $DefaultText -Font $fontMono
    $body.Controls.Add($lblMsg, 0, 0)
    $body.Controls.Add($txt.Parent, 0, 1)
    $root.Controls.Add($body, 0, 1)

    $footer = New-ModalFooter
    $btnOk = New-Btn "Continuar" 'primary' 130 38
    $btnNo = New-Btn "Cancelar" 'secondary' 110 38
    $btnNo.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $footer.Controls.Add($btnOk)
    $footer.Controls.Add($btnNo)
    $root.Controls.Add($footer, 0, 2)

    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnNo
    $btnOk.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::OK; $dlg.Close() })
    $btnNo.Add_Click({ $dlg.DialogResult = [System.Windows.Forms.DialogResult]::Cancel; $dlg.Close() })

    $dlg.Add_Shown({ $txt.Focus(); $txt.SelectAll() })
    $res = $dlg.ShowDialog()
    $value = $txt.Text
    $dlg.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) { return $value }
    return $null
}

# -----------------------------------------------------------------------------
# MODAL: SELECAO E CRIACAO DE EVENTO (INICIAL E TROCA)
# -----------------------------------------------------------------------------
function Show-EventSelectionModal {
    param([bool]$IsInitial = $false)

    $modal = New-ModalForm -Title "Estação DIT - Eventos" -Width 940 -Height 600
    $root = New-ModalRoot -Form $modal -HeaderH 88 -FooterH 70

    $titleText = if ($IsInitial) { "Bem-vindo! Qual evento você vai cobrir agora?" } else { "Trocar ou criar evento" }
    $hdr = New-ModalHeader -Title $titleText -Subtitle "Cada evento guarda seus próprios cartões, fotógrafos e histórico. Continue um evento existente ou crie um novo." -Accent $colorCyan
    $root.Controls.Add($hdr, 0, 0)

    $body = New-Table 3 1
    $body.Padding = New-Object System.Windows.Forms.Padding(28, 20, 28, 8)
    Add-ColStyle $body 'pct' 52
    Add-ColStyle $body 'abs' 20
    Add-ColStyle $body 'pct' 48
    Add-RowStyle $body 'pct' 100
    $root.Controls.Add($body, 0, 1)

    # ----- Cartao esquerdo: continuar evento existente
    $pnlLeft = New-CardPanel
    $pnlLeft.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridLeft = New-Table 1 3
    Add-ColStyle $gridLeft 'pct' 100
    Add-RowStyle $gridLeft 'abs' 34
    Add-RowStyle $gridLeft 'pct' 100
    Add-RowStyle $gridLeft 'abs' 48
    $gridLeft.Controls.Add((New-Lbl "Continuar um evento" $fontSubTitle $colorText), 0, 0)

    $hostList = New-Object System.Windows.Forms.Panel
    $hostList.Dock = [System.Windows.Forms.DockStyle]::Fill
    $hostList.BackColor = $colorSurface
    $hostList.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 12)

    $listEvents = New-Object System.Windows.Forms.ListView
    Initialize-DarkList -List $listEvents -RowHeight 40
    [void]$listEvents.Columns.Add("EVENTO", (Px 200))
    [void]$listEvents.Columns.Add("CARTÕES", (Px 80))
    [void]$listEvents.Columns.Add("CRIADO EM", (Px 90))
    $listEvents.Add_Resize({ param($s, $e) Set-FlexColumn -List $s -Index 0 -Min 120 })
    $hostList.Controls.Add($listEvents)

    $lblNoEvents = New-EmptyHint "Nenhum evento anterior.`nCrie o primeiro ao lado."
    $hostList.Controls.Add($lblNoEvents)

    $allEvents = @(Get-StationEvents)
    foreach ($ev in $allEvents) {
        $item = New-Object System.Windows.Forms.ListViewItem($ev.Name)
        [void]$item.SubItems.Add($ev.CardCount.ToString())
        $dtStr = if ($ev.CreatedAt) {
            try { ([System.DateTime]::Parse($ev.CreatedAt)).ToString("dd/MM/yy") } catch { "-" }
        } else { "-" }
        [void]$item.SubItems.Add($dtStr)
        if ($ev.Name -eq $script:CurrentEvent) {
            $item.UseItemStyleForSubItems = $true
            $item.ForeColor = $colorCyan
            $item.Selected = $true
        }
        [void]$listEvents.Items.Add($item)
    }
    if ($listEvents.Items.Count -gt 0) {
        $lblNoEvents.Visible = $false
    } else {
        $lblNoEvents.BringToFront()
    }
    $gridLeft.Controls.Add($hostList, 0, 1)

    $btnOpenSelected = New-Btn "Abrir evento selecionado" 'primary' 200 40
    $btnOpenSelected.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridLeft.Controls.Add($btnOpenSelected, 0, 2)
    $pnlLeft.Controls.Add($gridLeft)
    $body.Controls.Add($pnlLeft, 0, 0)

    # ----- Cartao direito: novo evento
    $pnlRight = New-CardPanel
    $pnlRight.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridRight = New-Table 1 8
    Add-ColStyle $gridRight 'pct' 100
    Add-RowStyle $gridRight 'abs' 34
    Add-RowStyle $gridRight 'abs' 22
    Add-RowStyle $gridRight 'abs' 42
    Add-RowStyle $gridRight 'abs' 30
    Add-RowStyle $gridRight 'abs' 42
    Add-RowStyle $gridRight 'pct' 100
    Add-RowStyle $gridRight 'abs' 48
    Add-RowStyle $gridRight 'abs' 0
    $gridRight.Controls.Add((New-Lbl "Criar um novo evento" $fontSubTitle $colorText), 0, 0)

    $gridRight.Controls.Add((New-Lbl "Nome do evento" $fontSmall $colorMuted), 0, 1)
    $txtNewEventName = New-TextInput -Text ("Evento_" + (Get-Date -Format "yyyy-MM-dd"))
    $gridRight.Controls.Add($txtNewEventName.Parent, 0, 2)

    $lblDestCap = New-Lbl "Pasta onde salvar" $fontSmall $colorMuted
    $lblDestCap.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
    $lblDestCap.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
    $gridRight.Controls.Add($lblDestCap, 0, 3)

    $validBaseDir = $script:CurrentConfig.TargetRootPath
    if (-not (Test-DriveIsConnected -Path $validBaseDir)) {
        $validBaseDir = Get-DefaultTargetDirectory
    }

    $rowDest = New-Table 2 1
    Add-ColStyle $rowDest 'pct' 100
    Add-ColStyle $rowDest 'abs' 108
    Add-RowStyle $rowDest 'pct' 100
    $txtNewEventDest = New-TextInput -Text $validBaseDir -Font $fontMono
    $btnBrowseDest = New-Btn "Procurar..." 'secondary' 100 42 $false
    $btnBrowseDest.Dock = [System.Windows.Forms.DockStyle]::Fill
    $btnBrowseDest.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $rowDest.Controls.Add($txtNewEventDest.Parent, 0, 0)
    $rowDest.Controls.Add($btnBrowseDest, 1, 0)
    $gridRight.Controls.Add($rowDest, 0, 4)

    $lblEventExpl = New-Lbl "" $fontSmall $colorMuted
    $lblEventExpl.Dock = [System.Windows.Forms.DockStyle]::Fill
    $lblEventExpl.AutoSize = $false
    $lblEventExpl.Padding = New-Object System.Windows.Forms.Padding(0, 12, 0, 0)
    $gridRight.Controls.Add($lblEventExpl, 0, 5)

    $btnCreateEvent = New-Btn "Criar e iniciar evento" 'success' 200 40
    $btnCreateEvent.Dock = [System.Windows.Forms.DockStyle]::Fill
    $gridRight.Controls.Add($btnCreateEvent, 0, 6)
    $pnlRight.Controls.Add($gridRight)
    $body.Controls.Add($pnlRight, 2, 0)

    $updateExplain = {
        $d = $txtNewEventDest.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($d)) { $d = "[pasta de destino]" }
        $lblEventExpl.Text = "Organização automática no disco:`n`n  $d`n      \ [Nome do fotógrafo]`n          \ fotos verificadas (SHA-256)`n`nCada cartão é associado a um único fotógrafo. Um fotógrafo pode ter vários cartões."
    }
    & $updateExplain
    $txtNewEventDest.Add_TextChanged($updateExplain)

    # ----- Rodape
    $footer = New-ModalFooter
    $closeText = if ($IsInitial) { "Continuar com o evento atual" } else { "Cancelar" }
    $btnCancelModal = New-Btn $closeText 'secondary' 230 38
    $footer.Controls.Add($btnCancelModal)
    $root.Controls.Add($footer, 0, 2)
    $modal.CancelButton = $btnCancelModal

    $btnBrowseDest.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione a pasta onde salvar os arquivos do evento"
        if ($fbd.ShowDialog($modal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtNewEventDest.Text = $fbd.SelectedPath
        }
    })

    $btnCancelModal.Add_Click({
        $modal.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        $modal.Close()
    })

    $openSelected = {
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
    }
    $btnOpenSelected.Add_Click($openSelected)
    $listEvents.Add_DoubleClick($openSelected)

    $btnCreateEvent.Add_Click({
        $evName = $txtNewEventName.Text.Trim()
        $destPath = $txtNewEventDest.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($evName)) {
            [System.Windows.Forms.MessageBox]::Show($modal, "Por favor, informe o nome do evento.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
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

    $script:RegisteredResult = $null
    $isEditMode = ($null -ne $ExistingRegistration)

    $winTitle = if ($isEditMode) { "Estação DIT - Editar cadastro do cartão" } else { "Estação DIT - Cadastro de cartão" }
    $setupModal = New-ModalForm -Title $winTitle -Width 700 -Height 640
    $root = New-ModalRoot -Form $setupModal -HeaderH 92 -FooterH 76

    $hdrTitle = if ($isEditMode) { "Editar cadastro do cartão" } else { "Novo cartão detectado" }
    $hdrAccent = if ($isEditMode) { $colorCyan } else { $colorAmber }
    $hdrSub = if ($isEditMode) {
        "Cartão $CardIdentifier  ·  Evento $EventName"
    } else {
        "Preencha 3 passos rápidos. É só desta vez: nas próximas inserções a descarga é automática.`nCartão $CardIdentifier  ·  Unidade $DriveLetter  ·  Evento $EventName"
    }
    $hdr = New-ModalHeader -Title $hdrTitle -Subtitle $hdrSub -Accent $hdrAccent
    $root.Controls.Add($hdr, 0, 0)

    $body = New-Table 1 9
    $body.Padding = New-Object System.Windows.Forms.Padding(32, 20, 32, 4)
    Add-ColStyle $body 'pct' 100
    Add-RowStyle $body 'abs' 30   # passo 1
    Add-RowStyle $body 'abs' 44   # combo fotografo
    Add-RowStyle $body 'abs' 34   # dica 1
    Add-RowStyle $body 'abs' 30   # passo 2
    Add-RowStyle $body 'abs' 44   # combo subpasta
    Add-RowStyle $body 'abs' 34   # dica 2
    Add-RowStyle $body 'abs' 30   # passo 3
    Add-RowStyle $body 'abs' 44   # destino
    Add-RowStyle $body 'pct' 100  # dica 3
    $root.Controls.Add($body, 0, 1)

    # ----- Passo 1: fotografo
    $body.Controls.Add((New-StepHeader "1" "Quem é o fotógrafo deste cartão?"), 0, 0)
    $cmbPhotog = New-ComboInput
    $existingPhotogs = @(Get-EventPhotographers -EventName $EventName)
    foreach ($p in $existingPhotogs) { [void]$cmbPhotog.Items.Add($p) }

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
    $body.Controls.Add($cmbPhotog.Parent, 0, 1)
    $hint1 = New-Lbl "Escolha um nome da lista ou digite um novo. Um fotógrafo pode ter vários cartões." $fontSmall $colorMuted
    $hint1.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $body.Controls.Add($hint1, 0, 2)

    # ----- Passo 2: subpasta no cartao
    $body.Controls.Add((New-StepHeader "2" "Em qual pasta do cartão estão as fotos?"), 0, 3)
    $rowSubf = New-Table 2 1
    Add-ColStyle $rowSubf 'pct' 100
    Add-ColStyle $rowSubf 'abs' 118
    Add-RowStyle $rowSubf 'pct' 100
    $cmbSubf = New-ComboInput $fontMono
    $detectedFolders = @(Get-CardPhotoFolders -DriveRoot $DriveLetter)
    foreach ($f in $detectedFolders) { [void]$cmbSubf.Items.Add($f) }
    if ($isEditMode -and $ExistingRegistration.PhotoSubfolder) {
        $cmbSubf.Text = $ExistingRegistration.PhotoSubfolder
    } elseif ($cmbSubf.Items.Count -gt 0) {
        $cmbSubf.SelectedIndex = 0
    }
    $btnBrowseCardSubf = New-Btn "Procurar..." 'secondary' 110 44 $false
    $btnBrowseCardSubf.Dock = [System.Windows.Forms.DockStyle]::Fill
    $btnBrowseCardSubf.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $rowSubf.Controls.Add($cmbSubf.Parent, 0, 0)
    $rowSubf.Controls.Add($btnBrowseCardSubf, 1, 0)
    $body.Controls.Add($rowSubf, 0, 4)
    $hintText2 = if ($detectedFolders.Count -gt 0) { "Detectamos automaticamente as pastas de fotos deste cartão (ex.: DCIM\100CANON)." } else { "Não achamos uma pasta de fotos. Deixe a raiz ou use Procurar para indicar." }
    $hint2 = New-Lbl $hintText2 $fontSmall $colorMuted
    $hint2.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $body.Controls.Add($hint2, 0, 5)

    $btnBrowseCardSubf.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione a pasta de fotos dentro do cartão $DriveLetter"
        $fbd.SelectedPath = $DriveLetter
        if ($fbd.ShowDialog($setupModal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $sel = $fbd.SelectedPath
            $root2 = [System.IO.Path]::GetPathRoot($sel)
            $rel = $sel.Substring($root2.Length).TrimStart('\')
            $cmbSubf.Text = if ($rel) { $rel } else { "\ (Raiz do Cartao)" }
        }
    })

    # ----- Passo 3: destino
    $body.Controls.Add((New-StepHeader "3" "Onde salvar as fotos deste cartão?"), 0, 6)
    $rowDest = New-Table 2 1
    Add-ColStyle $rowDest 'pct' 100
    Add-ColStyle $rowDest 'abs' 118
    Add-RowStyle $rowDest 'pct' 100
    $txtDest = New-TextInput -Text "" -Font $fontMono

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

    $btnBrowseDestCard = New-Btn "Procurar..." 'secondary' 110 44 $false
    $btnBrowseDestCard.Dock = [System.Windows.Forms.DockStyle]::Fill
    $btnBrowseDestCard.Margin = New-Object System.Windows.Forms.Padding(8, 0, 0, 0)
    $rowDest.Controls.Add($txtDest.Parent, 0, 0)
    $rowDest.Controls.Add($btnBrowseDestCard, 1, 0)
    $body.Controls.Add($rowDest, 0, 7)

    $lblNotice = New-Lbl "O destino acompanha o nome do fotógrafo automaticamente. Você pode ajustar se quiser." $fontSmall $colorMuted
    $lblNotice.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top
    $lblNotice.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
    $body.Controls.Add($lblNotice, 0, 8)

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

    $btnBrowseDestCard.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = "Selecione onde salvar as fotos deste cartão"
        $fbd.SelectedPath = $baseTarget
        if ($fbd.ShowDialog($setupModal) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtDest.Text = $fbd.SelectedPath
        }
    })

    # ----- Rodape
    $footer = New-ModalFooter
    $saveText = if ($isEditMode) { "Salvar alterações" } else { "Salvar e iniciar descarga" }
    $btnSave = New-Btn $saveText 'success' 220 42
    $btnCancelModal = New-Btn "Cancelar" 'secondary' 110 42
    $btnCancelModal.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
    $footer.Controls.Add($btnSave)
    $footer.Controls.Add($btnCancelModal)
    $root.Controls.Add($footer, 0, 2)
    $setupModal.AcceptButton = $btnSave
    $setupModal.CancelButton = $btnCancelModal

    $btnSave.Add_Click({
        $photogName = $cmbPhotog.Text.Trim()
        $subfPath = $cmbSubf.Text.Trim()
        $destPath = $txtDest.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($photogName)) {
            [System.Windows.Forms.MessageBox]::Show($setupModal, "Informe o nome do fotógrafo (passo 1).", "Falta um dado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            $cmbPhotog.Focus()
            return
        }
        if ([string]::IsNullOrWhiteSpace($destPath)) {
            [System.Windows.Forms.MessageBox]::Show($setupModal, "Informe a pasta de destino (passo 3).", "Falta um dado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            $txtDest.Focus()
            return
        }

        if (-not (Test-DriveIsConnected -Path $destPath)) {
            [System.Windows.Forms.MessageBox]::Show($setupModal, "A unidade de disco para '$destPath' não está disponível ou conectada neste computador!`n`nEscolha outra pasta em um disco válido.", "Disco indisponível", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
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
$form.Text = "Estação de Ingestão DIT - Backup Seguro"
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.ClientSize = New-Object System.Drawing.Size(1220, 800)
$form.MinimumSize = New-Object System.Drawing.Size(1060, 720)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $colorBg
$form.ForeColor = $colorText
$form.Font = $fontRegular
Enable-DoubleBuffer $form

$root = New-Table 1 5
$root.Padding = New-Object System.Windows.Forms.Padding(28, 18, 28, 22)
Add-ColStyle $root 'pct' 100
Add-RowStyle $root 'abs' 68      # cabecalho
Add-RowStyle $root 'auto'        # aviso de disco
Add-RowStyle $root 'abs' 160     # painel de status
Add-RowStyle $root 'pct' 100     # corpo
Add-RowStyle $root 'abs' 118     # rodape
$form.Controls.Add($root)

# ----- CABECALHO
$headerPanel = New-Table 5 1
Add-ColStyle $headerPanel 'abs' 62
Add-ColStyle $headerPanel 'pct' 100
Add-ColStyle $headerPanel 'auto'
Add-ColStyle $headerPanel 'auto'
Add-ColStyle $headerPanel 'auto'
Add-RowStyle $headerPanel 'pct' 100
$root.Controls.Add($headerPanel, 0, 0)

$logo = New-Object System.Windows.Forms.Panel
$logo.Size = New-Object System.Drawing.Size(46, 46)
$logo.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$logo.BackColor = $colorBg
$logo.Margin = New-Object System.Windows.Forms.Padding(0)
$logo.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))
    $path = New-RoundedPath $rect (Px 12)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (New-Rgb 6 182 212), (New-Rgb 59 130 246), 45.0)
    $g.FillPath($grad, $path)
    $grad.Dispose(); $path.Dispose()
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2.2)
    $cx = $s.Width / 2.0; $cy = $s.Height / 2.0 + 1
    $bodyRect = New-Object System.Drawing.RectangleF(($cx - 12), ($cy - 8), 24, 17)
    $g.DrawRectangle($pen, [int]$bodyRect.X, [int]$bodyRect.Y, [int]$bodyRect.Width, [int]$bodyRect.Height)
    $g.DrawEllipse($pen, ($cx - 5), ($cy - 5), 10, 10)
    $g.DrawLine($pen, ($cx - 5), ($cy - 8), ($cx - 3), ($cy - 12))
    $g.DrawLine($pen, ($cx - 3), ($cy - 12), ($cx + 3), ($cy - 12))
    $g.DrawLine($pen, ($cx + 3), ($cy - 12), ($cx + 5), ($cy - 8))
    $pen.Dispose()
})
$headerPanel.Controls.Add($logo, 0, 0)

$titleFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$titleFlow.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$titleFlow.WrapContents = $false
$titleFlow.AutoSize = $true
$titleFlow.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$titleFlow.BackColor = [System.Drawing.Color]::Transparent
$titleFlow.Margin = New-Object System.Windows.Forms.Padding(0)
$lblBrand = New-Lbl "Estação de Ingestão DIT" $fontHero $colorText
$lblSub = New-Lbl "Backup fotográfico automático, verificado byte a byte (SHA-256)" $fontSmall $colorMuted
$titleFlow.Controls.Add($lblBrand)
$titleFlow.Controls.Add($lblSub)
$headerPanel.Controls.Add($titleFlow, 1, 0)

$lblEventCaption = New-Lbl "EVENTO ATIVO" $fontCaps $colorDim
$lblEventCaption.Anchor = [System.Windows.Forms.AnchorStyles]::Right
$lblEventCaption.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$headerPanel.Controls.Add($lblEventCaption, 2, 0)

$lblActiveEventBadge = New-Object System.Windows.Forms.Label
$lblActiveEventBadge.Text = $script:CurrentEvent
$lblActiveEventBadge.Font = $fontBold
$lblActiveEventBadge.ForeColor = $colorCyan
$lblActiveEventBadge.BackColor = (Get-Blend $colorCyan $colorBg 0.14)
$lblActiveEventBadge.AutoSize = $true
$lblActiveEventBadge.Padding = New-Object System.Windows.Forms.Padding(14, 8, 14, 8)
$lblActiveEventBadge.Anchor = [System.Windows.Forms.AnchorStyles]::Right
$lblActiveEventBadge.Margin = New-Object System.Windows.Forms.Padding(0, 0, 12, 0)
$headerPanel.Controls.Add($lblActiveEventBadge, 3, 0)

$btnSwitchEvent = New-Btn "Trocar / novo evento" 'secondary' 170 38
$btnSwitchEvent.Anchor = [System.Windows.Forms.AnchorStyles]::Right
$headerPanel.Controls.Add($btnSwitchEvent, 4, 0)

# ----- AVISO DE UNIDADE DESCONECTADA
$bannerWarning = New-Object System.Windows.Forms.Panel
$bannerWarning.Dock = [System.Windows.Forms.DockStyle]::Fill
$bannerWarning.Height = 50
$bannerWarning.BackColor = (Get-Blend $colorAmber $colorBg 0.13)
$bannerWarning.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 14)
$bannerWarning.Visible = $false

$lblWarningText = New-Object System.Windows.Forms.Label
$lblWarningText.Text = ""
$lblWarningText.Font = $fontBold
$lblWarningText.ForeColor = $colorAmber
$lblWarningText.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblWarningText.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblWarningText.AutoEllipsis = $true
$lblWarningText.Padding = New-Object System.Windows.Forms.Padding(16, 0, 8, 0)
$bannerWarning.Controls.Add($lblWarningText)

$btnFixStorage = New-Btn "Escolher outro disco..." 'warning' 210 50
$btnFixStorage.Dock = [System.Windows.Forms.DockStyle]::Right
$bannerWarning.Controls.Add($btnFixStorage)
$root.Controls.Add($bannerWarning, 0, 1)

# ----- PAINEL DE STATUS & PROGRESSO
$pnlProgress = New-CardPanel
$pnlProgress.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlProgress.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 16)
$pnlProgress.Padding = New-Object System.Windows.Forms.Padding(28, 16, 22, 14)
$pnlProgress.Add_Paint({
    param($s, $e)
    $accent = New-Object System.Drawing.SolidBrush($script:StatusColor)
    $e.Graphics.FillRectangle($accent, (Px 1), (Px 16), (Px 4), ($s.Height - (Px 32)))
    $accent.Dispose()
})
$root.Controls.Add($pnlProgress, 0, 2)

$heroGrid = New-Table 2 3
Add-ColStyle $heroGrid 'pct' 100
Add-ColStyle $heroGrid 'abs' 220
Add-RowStyle $heroGrid 'abs' 46
Add-RowStyle $heroGrid 'abs' 44
Add-RowStyle $heroGrid 'abs' 32
$pnlProgress.Controls.Add($heroGrid)

# linha 0: selo de estado + detalhe | estado da leitura
$rowStatus = New-Table 2 1
Add-ColStyle $rowStatus 'auto'
Add-ColStyle $rowStatus 'pct' 100
Add-RowStyle $rowStatus 'pct' 100

$lblBadge = New-Object System.Windows.Forms.Label
$lblBadge.Text = "SISTEMA ARMADO"
$lblBadge.Font = $fontCaps
$lblBadge.AutoSize = $true
$lblBadge.Padding = New-Object System.Windows.Forms.Padding(12, 7, 12, 7)
$lblBadge.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$lblBadge.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 0)
$lblBadge.ForeColor = $colorGreen
$lblBadge.BackColor = (Get-Blend $colorGreen $colorSurface 0.16)
$rowStatus.Controls.Add($lblBadge, 0, 0)

$lblStatusDetail = New-Object System.Windows.Forms.Label
$lblStatusDetail.Text = "Plugue um cartão de memória: o backup começa sozinho."
$lblStatusDetail.Font = $fontSubTitle
$lblStatusDetail.ForeColor = $colorText
$lblStatusDetail.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblStatusDetail.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblStatusDetail.AutoEllipsis = $true
$lblStatusDetail.BackColor = [System.Drawing.Color]::Transparent
$rowStatus.Controls.Add($lblStatusDetail, 1, 0)
$heroGrid.Controls.Add($rowStatus, 0, 0)

$lblMonitorState = New-Object System.Windows.Forms.Label
$lblMonitorState.Text = "Leitura automática ligada"
$lblMonitorState.Font = $fontSmall
$lblMonitorState.ForeColor = $colorGreen
$lblMonitorState.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblMonitorState.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$lblMonitorState.BackColor = [System.Drawing.Color]::Transparent
$heroGrid.Controls.Add($lblMonitorState, 1, 0)

# linha 1: barra de progresso | parar
$pnlTrack = New-Object System.Windows.Forms.Panel
$pnlTrack.Height = 12
$pnlTrack.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$pnlTrack.Margin = New-Object System.Windows.Forms.Padding(0, 0, 20, 0)
$pnlTrack.BackColor = $colorSurface
Enable-DoubleBuffer $pnlTrack
$pnlTrack.Add_Resize({ param($s, $e) $s.Invalidate() })
$pnlTrack.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $h = $s.Height
    $trackRect = New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($h - 1))
    $tp = New-RoundedPath $trackRect ([int]($h / 2))
    $g.FillPath($brushElev, $tp)
    $tp.Dispose()
    $w = [int](($s.Width - 1) * $script:ProgressPct / 100)
    if ($script:ProgressPct -gt 0 -and $w -lt $h) { $w = $h }
    if ($w -gt 0) {
        $fillRect = New-Object System.Drawing.Rectangle(0, 0, $w, ($h - 1))
        $fp = New-RoundedPath $fillRect ([int]($h / 2))
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($fillRect, $colorCyanBtn, $colorGreen, 0.0)
        $g.FillPath($gb, $fp)
        $gb.Dispose(); $fp.Dispose()
    }
})
$heroGrid.Controls.Add($pnlTrack, 0, 1)

$btnCancel = New-Btn "Parar com segurança" 'warning' 200 36
$btnCancel.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnCancel.Margin = New-Object System.Windows.Forms.Padding(0, 3, 0, 3)
$btnCancel.Enabled = $false
$heroGrid.Controls.Add($btnCancel, 1, 1)

# linha 2: metricas | pausar leitura
$rowMetrics = New-Table 2 1
Add-ColStyle $rowMetrics 'auto'
Add-ColStyle $rowMetrics 'pct' 100
Add-RowStyle $rowMetrics 'pct' 100

$lblProgressMetrics = New-Object System.Windows.Forms.Label
$lblProgressMetrics.Text = "Nenhuma descarga em andamento"
$lblProgressMetrics.Font = $fontMono
$lblProgressMetrics.ForeColor = $colorMuted
$lblProgressMetrics.AutoSize = $true
$lblProgressMetrics.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$lblProgressMetrics.Margin = New-Object System.Windows.Forms.Padding(0, 0, 18, 0)
$lblProgressMetrics.BackColor = [System.Drawing.Color]::Transparent
$rowMetrics.Controls.Add($lblProgressMetrics, 0, 0)

$lblFileDetail = New-Object System.Windows.Forms.Label
$lblFileDetail.Text = ""
$lblFileDetail.Font = $fontMono
$lblFileDetail.ForeColor = $colorCyan
$lblFileDetail.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblFileDetail.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblFileDetail.AutoEllipsis = $true
$lblFileDetail.BackColor = [System.Drawing.Color]::Transparent
$rowMetrics.Controls.Add($lblFileDetail, 1, 0)
$heroGrid.Controls.Add($rowMetrics, 0, 2)

$btnToggleMonitor = New-Btn "Pausar leitura" 'ghost' 200 28 $false
$btnToggleMonitor.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnToggleMonitor.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0)
$btnToggleMonitor.FlatAppearance.BorderSize = 1
$btnToggleMonitor.FlatAppearance.BorderColor = $colorBorder
$heroGrid.Controls.Add($btnToggleMonitor, 1, 2)

# ----- CORPO: CARTOES (ESQUERDA) | HISTORICO (DIREITA)
$bodyGrid = New-Table 3 1
Add-ColStyle $bodyGrid 'pct' 58
Add-ColStyle $bodyGrid 'abs' 16
Add-ColStyle $bodyGrid 'pct' 42
Add-RowStyle $bodyGrid 'pct' 100
$root.Controls.Add($bodyGrid, 0, 3)

# --- Cartao esquerdo
$pnlLeftCards = New-CardPanel
$pnlLeftCards.Dock = [System.Windows.Forms.DockStyle]::Fill
$leftGrid = New-Table 1 3
Add-ColStyle $leftGrid 'pct' 100
Add-RowStyle $leftGrid 'abs' 44
Add-RowStyle $leftGrid 'pct' 100
Add-RowStyle $leftGrid 'abs' 54
$pnlLeftCards.Controls.Add($leftGrid)
$bodyGrid.Controls.Add($pnlLeftCards, 0, 0)

$cardsHead = New-Table 2 1
Add-ColStyle $cardsHead 'pct' 100
Add-ColStyle $cardsHead 'auto'
Add-RowStyle $cardsHead 'pct' 100
$lblCardsTitle = New-Lbl "Cartões deste evento" $fontSubTitle $colorText
$lblCardsTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$cardsHead.Controls.Add($lblCardsTitle, 0, 0)
$btnAddCardManual = New-Btn "+ Cadastrar cartão" 'primary' 168 34
$btnAddCardManual.Anchor = [System.Windows.Forms.AnchorStyles]::Right
$cardsHead.Controls.Add($btnAddCardManual, 1, 0)
$leftGrid.Controls.Add($cardsHead, 0, 0)

$pnlCardsHost = New-Object System.Windows.Forms.Panel
$pnlCardsHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlCardsHost.BackColor = $colorSurface
$pnlCardsHost.Margin = New-Object System.Windows.Forms.Padding(0)
$leftGrid.Controls.Add($pnlCardsHost, 0, 1)

$gridEventCards = New-Object System.Windows.Forms.ListView
Initialize-DarkList -List $gridEventCards -RowHeight 44
[void]$gridEventCards.Columns.Add("CARTÃO", (Px 130))
[void]$gridEventCards.Columns.Add("FOTÓGRAFO", (Px 150))
[void]$gridEventCards.Columns.Add("PASTA NA CÂMERA", (Px 140))
[void]$gridEventCards.Columns.Add("SALVO EM", (Px 220))
$pnlCardsHost.Controls.Add($gridEventCards)

$lblCardsEmpty = New-EmptyHint "Nenhum cartão cadastrado neste evento ainda.`n`nPlugue um cartão de memória: ele é reconhecido na hora e o cadastro (fotógrafo e pasta) é pedido uma única vez. Nas próximas inserções a descarga é 100% automática."
$pnlCardsHost.Controls.Add($lblCardsEmpty)
$lblCardsEmpty.BringToFront()

$cardActions = New-Object System.Windows.Forms.FlowLayoutPanel
$cardActions.Dock = [System.Windows.Forms.DockStyle]::Fill
$cardActions.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$cardActions.WrapContents = $false
$cardActions.BackColor = [System.Drawing.Color]::Transparent
$cardActions.Padding = New-Object System.Windows.Forms.Padding(0, 14, 0, 0)
$btnRemoveCard = New-Btn "Excluir cadastro" 'danger' 150 36 $false
$btnEditCard = New-Btn "Editar cadastro" 'secondary' 150 36 $false
$btnEditCard.Margin = New-Object System.Windows.Forms.Padding(10, 0, 0, 0)
$btnEditCard.Enabled = $false
$btnRemoveCard.Enabled = $false
$cardActions.Controls.Add($btnRemoveCard)
$cardActions.Controls.Add($btnEditCard)
$leftGrid.Controls.Add($cardActions, 0, 2)

# --- Cartao direito: historico
$pnlRightHist = New-CardPanel
$pnlRightHist.Dock = [System.Windows.Forms.DockStyle]::Fill
$rightGrid = New-Table 1 2
Add-ColStyle $rightGrid 'pct' 100
Add-RowStyle $rightGrid 'abs' 44
Add-RowStyle $rightGrid 'pct' 100
$pnlRightHist.Controls.Add($rightGrid)
$bodyGrid.Controls.Add($pnlRightHist, 2, 0)

$lblHistColTitle = New-Lbl "Histórico de descargas" $fontSubTitle $colorText
$lblHistColTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$rightGrid.Controls.Add($lblHistColTitle, 0, 0)

$pnlHistHost = New-Object System.Windows.Forms.Panel
$pnlHistHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlHistHost.BackColor = $colorSurface
$pnlHistHost.Margin = New-Object System.Windows.Forms.Padding(0)
$rightGrid.Controls.Add($pnlHistHost, 0, 1)

$gridHistory = New-Object System.Windows.Forms.ListView
Initialize-DarkList -List $gridHistory -RowHeight 44
[void]$gridHistory.Columns.Add("HORA", (Px 78))
[void]$gridHistory.Columns.Add("FOTÓGRAFO / CARTÃO", (Px 180))
[void]$gridHistory.Columns.Add("FOTOS", (Px 90))
[void]$gridHistory.Columns.Add("VOLUME", (Px 90))
[void]$gridHistory.Columns.Add("STATUS", (Px 130))
$pnlHistHost.Controls.Add($gridHistory)

$lblHistEmpty = New-EmptyHint "As descargas feitas neste evento aparecem aqui, com horário, quantidade de fotos e situação."
$pnlHistHost.Controls.Add($lblHistEmpty)
$lblHistEmpty.BringToFront()

# ----- RODAPE: DESTINO | DESCARGA MANUAL
$pnlFooter = New-CardPanel
$pnlFooter.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlFooter.Margin = New-Object System.Windows.Forms.Padding(0, 16, 0, 0)
$pnlFooter.Padding = New-Object System.Windows.Forms.Padding(22, 14, 22, 12)
$root.Controls.Add($pnlFooter, 0, 4)

$footGrid = New-Table 3 1
Add-ColStyle $footGrid 'pct' 46
Add-ColStyle $footGrid 'abs' 30
Add-ColStyle $footGrid 'pct' 54
Add-RowStyle $footGrid 'pct' 100
$pnlFooter.Controls.Add($footGrid)

# destino
$destGrid = New-Table 1 2
Add-ColStyle $destGrid 'pct' 100
Add-RowStyle $destGrid 'abs' 22
Add-RowStyle $destGrid 'pct' 100
$lblStorageTitle = New-Lbl "DESTINO DO EVENTO" $fontCaps $colorDim
$destGrid.Controls.Add($lblStorageTitle, 0, 0)

$destRow = New-Table 2 1
Add-ColStyle $destRow 'pct' 100
Add-ColStyle $destRow 'abs' 130
Add-RowStyle $destRow 'pct' 100
$lblStoragePath = New-Object System.Windows.Forms.Label
$lblStoragePath.Font = $fontMono
$lblStoragePath.ForeColor = $colorCyan
$lblStoragePath.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblStoragePath.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$lblStoragePath.AutoEllipsis = $true
$lblStoragePath.BackColor = [System.Drawing.Color]::Transparent
$destRow.Controls.Add($lblStoragePath, 0, 0)
$btnChangeStorage = New-Btn "Alterar pasta..." 'secondary' 120 38 $false
$btnChangeStorage.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnChangeStorage.Margin = New-Object System.Windows.Forms.Padding(8, 4, 0, 4)
$destRow.Controls.Add($btnChangeStorage, 1, 0)
$destGrid.Controls.Add($destRow, 0, 1)
$footGrid.Controls.Add($destGrid, 0, 0)

# descarga manual
$manualGrid = New-Table 1 2
Add-ColStyle $manualGrid 'pct' 100
Add-RowStyle $manualGrid 'abs' 22
Add-RowStyle $manualGrid 'pct' 100
$lblManualTitle = New-Lbl "DESCARGA MANUAL (CARTÃO JÁ CONECTADO)" $fontCaps $colorDim
$manualGrid.Controls.Add($lblManualTitle, 0, 0)

$manualRow = New-Table 3 1
Add-ColStyle $manualRow 'pct' 100
Add-ColStyle $manualRow 'abs' 108
Add-ColStyle $manualRow 'abs' 170
Add-RowStyle $manualRow 'pct' 100
$txtSource = New-TextInput -Text "" -Font $fontMono
$txtSource.Parent.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 4)
$btnBrowseSource = New-Btn "Procurar..." 'secondary' 100 38 $false
$btnBrowseSource.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnBrowseSource.Margin = New-Object System.Windows.Forms.Padding(8, 4, 0, 4)
$btnIngestNow = New-Btn "Descarregar agora" 'primary' 160 38
$btnIngestNow.Dock = [System.Windows.Forms.DockStyle]::Fill
$btnIngestNow.Margin = New-Object System.Windows.Forms.Padding(8, 4, 0, 4)
$manualRow.Controls.Add($txtSource.Parent, 0, 0)
$manualRow.Controls.Add($btnBrowseSource, 1, 0)
$manualRow.Controls.Add($btnIngestNow, 2, 0)
$manualGrid.Controls.Add($manualRow, 0, 1)
$footGrid.Controls.Add($manualGrid, 2, 0)

# -----------------------------------------------------------------------------
# FUNCOES DE ATUALIZACAO DE STATUS E TELA
# -----------------------------------------------------------------------------
function Set-AppStatus {
    param([string]$State, [string]$Badge, [string]$Detail = "")
    $c = switch ($State) {
        'busy'   { $colorCyan }
        'warn'   { $colorAmber }
        'paused' { $colorAmber }
        'error'  { $colorRed }
        default  { $colorGreen }
    }
    $script:StatusState = $State
    $script:StatusColor = $c
    $lblBadge.Text = $Badge
    $lblBadge.ForeColor = $c
    $lblBadge.BackColor = (Get-Blend $c $colorSurface 0.16)
    if ($Detail) { $lblStatusDetail.Text = $Detail }
    $pnlProgress.Invalidate()
}

function Set-Progress {
    param([int]$Percent)
    $script:ProgressPct = [math]::Max(0, [math]::Min(100, $Percent))
    $pnlTrack.Invalidate()
    $pnlTrack.Update()
}

function Set-ActiveEventBadge {
    $lblActiveEventBadge.Text = $script:CurrentEvent
}

function Update-StorageUI {
    $ev = Get-CurrentEvent
    $dest = $ev.DefaultDestination
    $lblStoragePath.Text = $dest

    if (-not (Test-DriveIsConnected -Path $dest)) {
        $root2 = [System.IO.Path]::GetPathRoot($dest)
        $bannerWarning.Visible = $true
        $lblWarningText.Text = "Atenção: a unidade '$root2' não está conectada. Escolha um disco válido para guardar os backups."
    } else {
        $bannerWarning.Visible = $false
    }
}

function Update-MonitoringUI {
    if ($script:MonitoringActive) {
        $lblMonitorState.Text = "Leitura automática ligada"
        $lblMonitorState.ForeColor = $colorGreen
        $btnToggleMonitor.Text = "Pausar leitura"
        if ($script:StatusState -eq 'paused') {
            Set-AppStatus 'idle' "SISTEMA ARMADO" "Plugue um cartão de memória: o backup começa sozinho."
        }
    } else {
        $lblMonitorState.Text = "Leitura automática pausada"
        $lblMonitorState.ForeColor = $colorAmber
        $btnToggleMonitor.Text = "Retomar leitura"
        if ($script:StatusState -eq 'idle') {
            Set-AppStatus 'paused' "LEITURA PAUSADA" "Nenhum cartão será lido até você retomar a leitura."
        }
    }
}

$btnToggleMonitor.Add_Click({
    $script:MonitoringActive = -not $script:MonitoringActive
    Set-MonitoringState -Active $script:MonitoringActive | Out-Null
    Update-MonitoringUI
})

$btnChangeStorage.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a pasta onde salvar os arquivos do evento $script:CurrentEvent"
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Set-EventDestination -EventName $script:CurrentEvent -NewDestination $fbd.SelectedPath -UpdateRegisteredCards $true | Out-Null
            $script:CurrentConfig = Get-StationConfig
            Update-StorageUI
            Refresh-EventCardsGrid
            [System.Windows.Forms.MessageBox]::Show($form, "Pasta de armazenamento alterada com sucesso!`n`nNovo destino: $($fbd.SelectedPath)`n`nTodos os cartões cadastrados foram atualizados.", "Destino atualizado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        } catch {
            [System.Windows.Forms.MessageBox]::Show($form, "Erro ao alterar a pasta de destino: $_", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }
})

$btnFixStorage.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione uma pasta em um disco válido para os backups"
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            Set-EventDestination -EventName $script:CurrentEvent -NewDestination $fbd.SelectedPath -UpdateRegisteredCards $true | Out-Null
            $script:CurrentConfig = Get-StationConfig
            Update-StorageUI
            Refresh-EventCardsGrid
        } catch {}
    }
})

$btnBrowseSource.Add_Click({
    $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
    $fbd.Description = "Selecione a unidade ou pasta do cartão fotográfico"
    if ($fbd.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtSource.Text = $fbd.SelectedPath
    }
})

# -----------------------------------------------------------------------------
# LISTAS: CARTOES CADASTRADOS E HISTORICO
# -----------------------------------------------------------------------------
$gridEventCards.Add_Resize({ param($s, $e) Set-FlexColumn -List $s -Index 3 -Min 140 })
$gridHistory.Add_Resize({ param($s, $e) Set-FlexColumn -List $s -Index 1 -Min 120 })

function Add-CardRow {
    param([string]$CardId, [string]$Photographer, [string]$Subfolder, [string]$Destination)
    $item = New-Object System.Windows.Forms.ListViewItem($CardId)
    $item.UseItemStyleForSubItems = $false
    $item.Font = $fontBold
    [void]$item.SubItems.Add($Photographer)
    $subText = if ($Subfolder) { $Subfolder } else { "\ (raiz)" }
    [void]$item.SubItems.Add($subText)
    [void]$item.SubItems.Add($Destination)
    $item.SubItems[0].ForeColor = $colorText
    $item.SubItems[1].ForeColor = $colorText
    $item.SubItems[2].ForeColor = $colorMuted
    $item.SubItems[3].ForeColor = $colorMuted
    [void]$gridEventCards.Items.Add($item)
}

function Add-HistoryRow {
    param([string]$Time, [string]$Who, [string]$Photos, [string]$Volume, [string]$StatusText, $StatusColor)
    $item = New-Object System.Windows.Forms.ListViewItem($Time)
    $item.UseItemStyleForSubItems = $false
    [void]$item.SubItems.Add($Who)
    [void]$item.SubItems.Add($Photos)
    [void]$item.SubItems.Add($Volume)
    [void]$item.SubItems.Add($StatusText)
    $item.SubItems[0].ForeColor = $colorMuted
    $item.SubItems[1].ForeColor = $colorText
    $item.SubItems[2].ForeColor = $colorText
    $item.SubItems[3].ForeColor = $colorMuted
    $item.SubItems[4].ForeColor = $StatusColor
    $item.SubItems[4].Font = $fontBold
    [void]$gridHistory.Items.Insert(0, $item)
    $lblHistEmpty.Visible = $false
}

function Refresh-EventCardsGrid {
    $gridEventCards.Items.Clear()
    $cards = @(Get-EventCards -EventName $script:CurrentEvent)
    foreach ($c in $cards) {
        Add-CardRow -CardId $c.CardIdentifier -Photographer $c.Photographer -Subfolder $c.PhotoSubfolder -Destination $c.DestinationPath
    }
    if ($cards.Count -eq 0) {
        $lblCardsEmpty.Visible = $true
        $lblCardsEmpty.BringToFront()
        $lblCardsTitle.Text = "Cartões deste evento"
    } else {
        $lblCardsEmpty.Visible = $false
        $word = if ($cards.Count -eq 1) { "cartão" } else { "cartões" }
        $lblCardsTitle.Text = "Cartões deste evento  ·  $($cards.Count) $word"
    }
    $btnEditCard.Enabled = $false
    $btnRemoveCard.Enabled = $false
    Set-FlexColumn -List $gridEventCards -Index 3 -Min 140
}

$gridEventCards.Add_SelectedIndexChanged({
    $has = ($gridEventCards.SelectedItems.Count -gt 0)
    $btnEditCard.Enabled = $has
    $btnRemoveCard.Enabled = $has
    $gridEventCards.Invalidate()
})

# Acao: Editar Cartao Selecionado
$btnEditCard.Add_Click({
    if ($gridEventCards.SelectedItems.Count -eq 0) { return }
    $selectedId = $gridEventCards.SelectedItems[0].Text

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
        [System.Windows.Forms.MessageBox]::Show($form, "Cadastro do cartão atualizado com sucesso!`n`nFotógrafo: $($res.Photographer)`nDestino: $($res.DestinationPath)", "Atualizado", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})

$gridEventCards.Add_DoubleClick({
    if ($btnEditCard.Enabled) { $btnEditCard.PerformClick() }
})

# Acao: Excluir Cartao
$btnRemoveCard.Add_Click({
    if ($gridEventCards.SelectedItems.Count -eq 0) { return }
    $selectedId = $gridEventCards.SelectedItems[0].Text

    $confirm = [System.Windows.Forms.MessageBox]::Show($form, "Tem certeza que deseja remover o cadastro do cartão '$selectedId'?`n`nAs fotos já salvas não são apagadas. Ao plugar o cartão novamente, ele pedirá um novo cadastro.", "Confirmar exclusão", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Remove-CardRegistration -EventName $script:CurrentEvent -CardIdentifier $selectedId | Out-Null
        $script:CurrentConfig = Get-StationConfig
        Refresh-EventCardsGrid
    }
})

# Acao: Cadastrar Cartao Manualmente
$btnAddCardManual.Add_Click({
    $defaultId = "CARTAO_" + (Get-Random -Minimum 100 -Maximum 999)
    $cardIdInput = Show-TextPrompt -Title "Cadastrar novo cartão" -Message "Informe um nome ou identificador para o cartão (ex.: CARD_01 ou EOS_DIGITAL):" -DefaultText $defaultId
    if ([string]::IsNullOrWhiteSpace($cardIdInput)) { return }

    $res = Show-CardSetupModal -DriveLetter "C:\" -CardIdentifier $cardIdInput.Trim() -EventName $script:CurrentEvent
    if ($null -ne $res) {
        $script:CurrentConfig = Get-StationConfig
        Refresh-EventCardsGrid
    }
})

# -----------------------------------------------------------------------------
# FLUXO DE EXECUCAO DE INGESTAO COM INTERRUPCAO SEGURA
# -----------------------------------------------------------------------------
$btnCancel.Add_Click({
    if ($script:IsIngesting) {
        $script:CancelRequested = $true
        $btnCancel.Enabled = $false
        $lblStatusDetail.Text = "Interrupção solicitada. Finalizando a foto atual e limpando arquivos temporários..."
    }
})

function Run-AppIngest {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath
    )

    if ($script:IsIngesting) {
        [System.Windows.Forms.MessageBox]::Show($form, "Uma descarga já está em andamento. Aguarde a conclusão.", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    if (!(Test-Path $SourcePath)) {
        [System.Windows.Forms.MessageBox]::Show($form, "Caminho de origem não encontrado: $SourcePath", "Erro", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return
    }

    $cardId = Get-CardIdentifier -DriveLetter $SourcePath

    # Checa se o cartao ja foi cadastrado para este evento
    $cardReg = Get-CardRegistration -EventName $script:CurrentEvent -CardIdentifier $cardId
    if ($null -eq $cardReg) {
        # Primeira vez que o cartao e visto neste evento: exibe modal de cadastro obrigatorio
        $cardReg = Show-CardSetupModal -DriveLetter $SourcePath -CardIdentifier $cardId -EventName $script:CurrentEvent
        if ($null -eq $cardReg) {
            $lblStatusDetail.Text = "Descarga cancelada. O cartão $cardId precisa ser cadastrado no evento $script:CurrentEvent."
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

    Set-AppStatus 'busy' "DESCARGA EM ANDAMENTO" "$($cardReg.Photographer)  ·  cartão $cardId"
    Set-Progress 0
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
                $done = if ($null -ne $prog.CurrentIndex) { $prog.CurrentIndex } elseif ($null -ne $prog.ProcessedFiles) { $prog.ProcessedFiles } elseif ($null -ne $prog.FilesDone) { $prog.FilesDone } else { 0 }
                $total = if ($null -ne $prog.TotalFiles) { $prog.TotalFiles } else { 0 }
                $pct = if ($null -ne $prog.Percent) { $prog.Percent } elseif ($total -gt 0) { [math]::Min(100, [int](($done / $total) * 100)) } else { 0 }

                Set-Progress $pct
                if ($total -gt 0) {
                    $lblProgressMetrics.Text = "$done / $total fotos  -  $pct%"
                }
                $lblFileDetail.Text = "$($prog.CurrentFile)"
                [System.Windows.Forms.Application]::DoEvents()
            }

        $mb = [math]::Round($res.TotalBytesCopied / 1MB, 1)
        $who = "$($cardReg.Photographer)  ($cardId)"

        if ($res.Status -eq "ABORTED_BY_USER") {
            Add-HistoryRow -Time (Get-Date -Format "HH:mm:ss") -Who $who -Photos "+$($res.CopiedCount)" -Volume "$mb MB" -StatusText "Interrompido" -StatusColor $colorAmber
            Set-AppStatus 'warn' "INTERROMPIDO COM SEGURANÇA" "Descarga interrompida por você. Nenhum arquivo foi corrompido e o cartão está intacto."
            [System.Windows.Forms.MessageBox]::Show($form, "Descarga interrompida com total segurança!`n`nNenhum arquivo foi corrompido, os arquivos já verificados continuam salvos e o cartão está intacto.", "Interrupção segura", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        elseif ($res.Status -eq "IDLE_NO_NEW_FILES") {
            Add-HistoryRow -Time (Get-Date -Format "HH:mm:ss") -Who $who -Photos "0 fotos novas" -Volume "0 MB" -StatusText "Todas ja salvas" -StatusColor $colorCyan
            Set-Progress 100
            Set-AppStatus 'ok' "NENHUMA FOTO NOVA" "Todas as fotos deste cartao ja foram descarregadas anteriormente com integridade SHA-256."
            $lblProgressMetrics.Text = "$($res.SkippedCount) fotos ignoradas (idempotencia)"
            $lblFileDetail.Text = "Idempotente: nenhuma copia duplicada necessaria."
        }
        elseif ($res.Ejected) {
            Add-HistoryRow -Time (Get-Date -Format "HH:mm:ss") -Who $who -Photos "+$($res.CopiedCount)" -Volume "$mb MB" -StatusText "Salvo e ejetado" -StatusColor $colorGreen
            Set-Progress 100
            Set-AppStatus 'ok' "CONCLUÍDO E EJETADO" "Backup de $($cardReg.Photographer) concluído! Cartão ejetado com segurança. Pode retirar."
            $lblFileDetail.Text = ""
        } else {
            Add-HistoryRow -Time (Get-Date -Format "HH:mm:ss") -Who $who -Photos "+$($res.CopiedCount)" -Volume "$mb MB" -StatusText "Salvo" -StatusColor $colorGreen
            Set-Progress 100
            Set-AppStatus 'ok' "CONCLUÍDO COM SUCESSO" "Backup de $($cardReg.Photographer) concluído com sucesso."
        }
    }
    catch {
        Set-AppStatus 'error' "ERRO" "Erro: $_"
        [System.Windows.Forms.MessageBox]::Show($form, "Erro durante a descarga:`n$_", "Erro crítico", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
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
        [System.Windows.Forms.MessageBox]::Show($form, "Informe a unidade ou pasta do cartão fotográfico (ou use Procurar).", "Aviso", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    Run-AppIngest -SourcePath $src
})

$btnSwitchEvent.Add_Click({
    $res = Show-EventSelectionModal -IsInitial $false
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) {
        Set-ActiveEventBadge
        Update-StorageUI
        Refresh-EventCardsGrid
        $gridHistory.Items.Clear()
        $lblHistEmpty.Visible = $true
        $lblHistEmpty.BringToFront()
    }
})

# Impede fechar a janela no meio de uma copia (evita estado inconsistente)
$form.Add_FormClosing({
    param($s, $e)
    if ($script:IsIngesting) {
        $e.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show($form, "Há uma descarga em andamento.`n`nUse 'Parar com segurança', aguarde a finalização e então feche a janela.", "Descarga em andamento", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
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
    Set-ActiveEventBadge
    Update-StorageUI
    Update-MonitoringUI
    Refresh-EventCardsGrid
    $usbTimer.Start()
})

[void]$form.ShowDialog()
$usbTimer.Stop()
$usbTimer.Dispose()
$form.Dispose()
