#requires -Version 5.1
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ===== Opslaglocatie =====
$AppDir      = Join-Path $env:APPDATA 'TilePinger'
$ConfigPath  = Join-Path $AppDir 'servers.json'
$SettingsPath= Join-Path $AppDir 'settings.json'
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

# ===== Defaults =====
$DefaultServers = @(
    @{ name='Google DNS'; host='8.8.8.8' },
    @{ name='Cloudflare'; host='1.1.1.1' }
)
$RefreshSeconds = 5
$TimeoutMs      = 2000

# ===== Helpers opslag =====
function Save-Servers([array]$servers) {
    @{ servers = $servers } | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigPath -Encoding UTF8
}
function Load-Servers {
    if (Test-Path $ConfigPath) {
        try {
            $data = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            if ($data -and $data.servers) {
                # nieuw formaat (objecten)
                if ($data.servers[0] -and ($data.servers[0] | Get-Member -MemberType NoteProperty -Name name -ErrorAction SilentlyContinue)) {
                    return @($data.servers | ForEach-Object { @{ name = $_.name; host = $_.host } })
                }
                # oud formaat (strings) -> migreer
                $i=1; $migrated=@()
                foreach ($h in $data.servers) { $migrated += @{ name="Server $i"; host="$h" }; $i++ }
                Save-Servers $migrated
                return $migrated
            }
        } catch {}
    }
    Save-Servers $DefaultServers
    return $DefaultServers
}
function Load-Settings {
    if (Test-Path $SettingsPath) {
        try {
            $s = Get-Content $SettingsPath -Raw | ConvertFrom-Json
            if ($s.RefreshSeconds) { $script:RefreshSeconds = [int]$s.RefreshSeconds }
            if ($s.TimeoutMs)      { $script:TimeoutMs      = [int]$s.TimeoutMs }
        } catch {}
    }
}
function Save-Settings {
    @{ RefreshSeconds = $RefreshSeconds; TimeoutMs = $TimeoutMs } |
        ConvertTo-Json | Set-Content -Path $SettingsPath -Encoding UTF8
}

$Servers = Load-Servers
Load-Settings

# ===== UI helpers =====
function New-TextBlock($text, $size=16, $weight='SemiBold', $align='Center', $fg='White') {
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $text; $tb.FontSize = $size; $tb.FontWeight = $weight
    $tb.TextAlignment = $align; $tb.HorizontalAlignment = 'Center'
    $tb.VerticalAlignment = 'Center'; $tb.TextWrapping = 'Wrap'
    $tb.Foreground = $fg
    $tb
}
function New-Tile($serverObj) {
    $border = New-Object Windows.Controls.Border
    $border.CornerRadius=16; $border.Margin='8'; $border.Padding='12'
    $border.BorderThickness=1; $border.BorderBrush='LightGray'; $border.Background='Gainsboro'

    $stack = New-Object Windows.Controls.StackPanel
    $nameTb  = New-TextBlock $serverObj.name 18 'Bold' 'Center' 'Black'
    $hostTb  = New-TextBlock $serverObj.host 12 'Normal' 'Center' 'DimGray'  # <-- NIET $host (gereserveerd)
    $statusTb= New-TextBlock '⏳ checking...' 14 'Normal' 'Center' 'Black'
    $rttTb   = New-TextBlock '' 12 'Normal' 'Center' 'Black'
    $stack.Children.Add($nameTb) | Out-Null
    $stack.Children.Add($hostTb) | Out-Null
    $stack.Children.Add($statusTb) | Out-Null
    $stack.Children.Add($rttTb) | Out-Null
    $border.Child = $stack

    # Rechtsklik-menu
    $menu = New-Object Windows.Controls.ContextMenu
    foreach ($item in @(
        @{H='Kopieer host'; A={[System.Windows.Clipboard]::SetText($serverObj.host)}},
        @{H='Kopieer naam'; A={[System.Windows.Clipboard]::SetText($serverObj.name)}},
        @{H='Open cmd ping -t'; A={Start-Process 'cmd.exe' "/k ping -t $($serverObj.host)"}},
        @{H='Start RDP (mstsc)'; A={Start-Process 'mstsc.exe' "/v:$($serverObj.host)"}},
        @{H='Verwijder'; A={ Remove-Server $serverObj }}
    )) {
        $m=New-Object Windows.Controls.MenuItem; $m.Header=$item.H; $m.Add_Click($item.A)|Out-Null; $menu.Items.Add($m)|Out-Null
    }
    $border.ContextMenu = $menu

    [PSCustomObject]@{
        key         = "{0}|{1}" -f $serverObj.name, $serverObj.host
        server      = $serverObj
        Border      = $border
        NameBlock   = $nameTb
        HostBlock   = $hostTb
        StatusBlock = $statusTb
        RttBlock    = $rttTb
    }
}

# ===== Ping & kleur =====
$BrushOK   = [Windows.Media.Brushes]::LightGreen
$BrushFail = [Windows.Media.Brushes]::LightCoral
$BrushWait = [Windows.Media.Brushes]::Gainsboro
$BrushWarn = [Windows.Media.Brushes]::Khaki
$ui = @{} # key -> tile

function Update-ServerStatus($serverObj) {
    $key = "{0}|{1}" -f $serverObj.name, $serverObj.host
    if (-not $ui.ContainsKey($key)) { return }
    $tile = $ui[$key]

    # Visueel "busy"
    $tile.Border.Background = $BrushWait
    $tile.StatusBlock.Text  = "⏳ checking..."
    $tile.RttBlock.Text     = ""

    # Draai ping op ThreadPool, update UI met BeginInvoke
    [System.Threading.ThreadPool]::QueueUserWorkItem({
        param($state)
        $svr   = $state.server
        $tileL = $state.tile

        $ok = $false
        $rtt = $null

        try {
            $ping  = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($svr.host, $state.TimeoutMs)
            if ($reply -and $reply.Status -eq 'Success') {
                $ok = $true
                $rtt = [int]$reply.RoundtripTime
            }
        } catch {
            # laat ok=$false
        }

        # Altijd terug naar UI-thread, non-blocking
        $null = $tileL.Border.Dispatcher.BeginInvoke([Action]{
            if ($ok) {
                $tileL.Border.Background = if ($rtt -gt 150) { $BrushWarn } else { $BrushOK }
                $tileL.StatusBlock.Text  = "✅ online"
                $tileL.RttBlock.Text     = if ($rtt -ne $null) { "RTT: $rtt ms" } else { "" }
            } else {
                $tileL.Border.Background = $BrushFail
                $tileL.StatusBlock.Text  = "❌ offline/time-out"
                $tileL.RttBlock.Text     = ""
            }
        })
    }, @{ server=$serverObj; tile=$tile; TimeoutMs=$TimeoutMs }) | Out-Null
}


# ===== XAML (let op xmlns:x toegevoegd) =====
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tile Pinger" Width="1120" Height="780"
        WindowStartupLocation="CenterScreen" Background="#0f1115">
  <DockPanel LastChildFill="True" Margin="8">
    <StackPanel DockPanel.Dock="Top" Orientation="Vertical" Margin="0,0,0,8">
      <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
        <TextBlock Text="Tile Pinger" Foreground="White" FontSize="24" FontWeight="Bold" Margin="0,0,12,0"/>
        <TextBlock x:Name="Info" Text="" Foreground="LightGray" VerticalAlignment="Center"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
        <TextBox x:Name="TxtName" MinWidth="160" ToolTip="Naam (bv. SQL01)" />
        <TextBox x:Name="TxtHost" MinWidth="280" Margin="8,0,0,0" ToolTip="Host (IP of DNS)" />
        <Button x:Name="BtnAdd" Content="Toevoegen" Margin="8,0,0,0" Width="120"/>
        <Button x:Name="BtnRemoveSel" Content="Verwijder geselecteerde" Margin="8,0,0,0" Width="160"/>
        <TextBox x:Name="TxtRefresh" Width="70" Margin="16,0,0,0" ToolTip="Interval (s)"/>
        <TextBox x:Name="TxtTimeout" Width="90" Margin="8,0,0,0" ToolTip="Timeout (ms)"/>
        <Button x:Name="BtnSaveSettings" Content="Opslaan" Margin="8,0,0,0" Width="90"/>
      </StackPanel>
      <TextBlock Text="Tip: je kunt bulk hosts plakken hieronder (één per regel of met komma’s)."
                 Foreground="Gray" FontSize="12"/>
      <StackPanel Orientation="Horizontal" Margin="0,4,0,6">
        <TextBox x:Name="BulkHosts" MinWidth="540" AcceptsReturn="True" Height="60" TextWrapping="Wrap"
                 ToolTip="Bulk host invoer (één per regel of komma-gescheiden). Naam wordt 'Server {n}'."/>
        <Button x:Name="BtnBulkAdd" Content="Bulk toevoegen" Margin="8,0,0,0" Width="140"/>
      </StackPanel>
    </StackPanel>
    <Grid>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="2*"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <ScrollViewer VerticalScrollBarVisibility="Auto" Grid.Column="0">
        <UniformGrid x:Name="Grid" Rows="1" Columns="1" Margin="0"/>
      </ScrollViewer>
      <StackPanel Grid.Column="1" Margin="8,0,0,0">
        <TextBlock Text="Lijst" Foreground="White" FontSize="16" FontWeight="Bold" Margin="0,0,0,6"/>
        <ListBox x:Name="ListHosts" Height="600" />
      </StackPanel>
    </Grid>
  </DockPanel>
</Window>
"@

# Laad XAML simpel met Parse (geen XmlNodeReader nodig)
$window = [Windows.Markup.XamlReader]::Parse($xaml)
$grid   = $window.FindName('Grid')
$info   = $window.FindName('Info')
$txtName= $window.FindName('TxtName')
$txtHostTb= $window.FindName('TxtHost')
$txtRef = $window.FindName('TxtRefresh')
$txtTo  = $window.FindName('TxtTimeout')
$btnAdd = $window.FindName('BtnAdd')
$btnRem = $window.FindName('BtnRemoveSel')
$btnSav = $window.FindName('BtnSaveSettings')
$bulk   = $window.FindName('BulkHosts')
$btnBulk= $window.FindName('BtnBulkAdd')
$list   = $window.FindName('ListHosts')

$txtRef.Text = "$RefreshSeconds"
$txtTo.Text  = "$TimeoutMs"

function Reflow-Grid {
    $count = [math]::Max(1, $Servers.Count)
    $cols  = [math]::Ceiling([math]::Sqrt($count))
    $rows  = [math]::Ceiling($count / $cols)
    $grid.Columns = $cols; $grid.Rows = $rows
}
function Refresh-ListUI {
    # Normaliseer: strings -> objecten {name,host}
    $normalized = foreach ($item in $Servers) {
        if ($null -eq $item) { continue }
        if ($item -is [string]) {
            [pscustomobject]@{ name = $item; host = $item }
        }
        elseif ($item.PSObject.Properties.Name -contains 'host' -and $item.PSObject.Properties.Name -contains 'name') {
            [pscustomobject]@{ name = "$($item.name)"; host = "$($item.host)" }
        }
        else {
            # Onbekende vorm -> sla over
            continue
        }
    }

    # Sla genormaliseerde lijst meteen op (houd JSON netjes)
    $script:Servers = $normalized
    Save-Servers $script:Servers

    # UI vullen
    $list.Items.Clear()
    foreach ($s in $script:Servers) {
        [void]$list.Items.Add("$($s.name) — $($s.host)")
    }

    $info.Text = "Servers: $($script:Servers.Count)   •   Interval: ${RefreshSeconds}s   •   Timeout: ${TimeoutMs}ms   •   Opslag: $ConfigPath"
}
function Exists-Server($name,$host) {
    return $Servers | Where-Object { $_.name -eq $name -and $_.host -eq $host } | ForEach-Object { $true } | Select-Object -First 1
}

function Add-Server([string]$name,[string]$hostStr) {
    if ([string]::IsNullOrWhiteSpace($hostStr)) { return }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $hostStr }
    if (-not (Exists-Server $name $hostStr)) {
        $Servers += @{ name=$name; host=$hostStr }
        $tile = New-Tile @{ name=$name; host=$hostStr }
        $ui[$tile.key] = $tile
        [void]$grid.Children.Add($tile.Border)
        Update-ServerStatus $tile.server
        Save-Servers $Servers
        Reflow-Grid; Refresh-ListUI
    }
}
function Add-ServersBulk([string[]]$hosts) {
    $i = $Servers.Count + 1
    foreach($h in $hosts){
        $h = $h.Trim()
        if (-not $h) { continue }
        Add-Server ("Server $i") $h
        $i++
    }
}
function Remove-Server($serverObj) {
    $Servers = $Servers | Where-Object { -not ( $_.name -eq $serverObj.name -and $_.host -eq $serverObj.host ) }
    $key = "{0}|{1}" -f $serverObj.name, $serverObj.host
    if ($ui.ContainsKey($key)) {
        $tile = $ui[$key]
        [void]$grid.Children.Remove($tile.Border)
        $ui.Remove($key) | Out-Null
    }
    Save-Servers $Servers
    Reflow-Grid; Refresh-ListUI
    Set-Variable -Name Servers -Value $Servers -Scope Script
}

# Knoppen
$btnAdd.Add_Click({
    Add-Server $txtName.Text $txtHostTb.Text
    $txtName.Clear(); $txtHostTb.Clear()
}) | Out-Null

$btnBulk.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($bulk.Text)){
        $parts = $bulk.Text -split "[,\r\n]+" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        Add-ServersBulk $parts
        $bulk.Clear()
    }
}) | Out-Null

$btnRem.Add_Click({
    $sel = @($list.SelectedItems)
    if ($sel.Count -gt 0) {
        foreach($item in $sel){
            $parts = $item -split " — "
            if ($parts.Count -eq 2) {
                $obj = @{ name=$parts[0]; host=$parts[1] }
                Remove-Server $obj
            }
        }
    }
}) | Out-Null

$btnSav.Add_Click({
    # Lees waarden uit de tekstvakken en probeer ze als int te interpreteren
    $newRef = $txtRef.Text -as [int]
    $newTo  = $txtTo.Text  -as [int]

    # Basisvalidatie + toewijzen
    if ($newRef -and $newRef -gt 0) {
        $script:RefreshSeconds = $newRef
    }

    if ($newTo -and $newTo -ge 100) {      # voorkom absurd lage timeouts
        $script:TimeoutMs = $newTo
    }

    # Timer meteen bijstellen als hij al bestaat
    if ($null -ne $timer) {
        $timer.Interval = [TimeSpan]::FromSeconds($script:RefreshSeconds)
    }

    Save-Settings
    Refresh-ListUI
}) | Out-Null


# Init tegels
foreach ($s in $Servers) {
    $tile = New-Tile $s
    $ui[$tile.key] = $tile
    [void]$grid.Children.Add($tile.Border)
}

Reflow-Grid; Refresh-ListUI

# Timer
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds($RefreshSeconds)
$timer.Add_Tick({
    $timer.Interval = [TimeSpan]::FromSeconds($RefreshSeconds)
    $Servers | ForEach-Object { Update-ServerStatus $_ }
})
$timer.Start()

# Herflow bij resize
$window.Add_SizeChanged({ Reflow-Grid }) | Out-Null

# Eerste ping
$Servers | ForEach-Object { Update-ServerStatus $_ }

$null = $window.ShowDialog()
