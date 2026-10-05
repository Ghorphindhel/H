#requires -Version 5.1

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ============================================================
# NETWORK DIAGNOSTIC TOOL
# ============================================================

function Get-NetworkDiagnostic {

    # --------------------------------------------------------
    # PC / UTILISATEUR
    # --------------------------------------------------------

    $ComputerName = $env:COMPUTERNAME

    try {
        $UserName = (Get-CimInstance Win32_ComputerSystem).UserName

        if (-not $UserName) {
            $UserName = "$env:USERDOMAIN\$env:USERNAME"
        }
    }
    catch {
        $UserName = "$env:USERDOMAIN\$env:USERNAME"
    }


    # --------------------------------------------------------
    # TOUTES LES CARTES RESEAU
    # --------------------------------------------------------

    $AllAdapters = @(
        Get-NetAdapter -ErrorAction SilentlyContinue |
        Sort-Object Name
    )


    # --------------------------------------------------------
    # ROUTE IPv4 PAR DEFAUT
    # --------------------------------------------------------

    $DefaultRoute = Get-NetRoute `
        -AddressFamily IPv4 `
        -DestinationPrefix "0.0.0.0/0" `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.NextHop -ne "0.0.0.0" -and
            $_.State -eq "Alive"
        } |
        Sort-Object RouteMetric, InterfaceMetric |
        Select-Object -First 1


    # --------------------------------------------------------
    # CARTE REELLEMENT UTILISEE
    # --------------------------------------------------------

    $ActiveAdapter = $null

    if ($DefaultRoute) {
        $ActiveAdapter = Get-NetAdapter `
            -InterfaceIndex $DefaultRoute.InterfaceIndex `
            -ErrorAction SilentlyContinue
    }


    # --------------------------------------------------------
    # VALEURS PAR DEFAUT
    # --------------------------------------------------------

    $IPAddress          = "Non détectée"
    $Gateway            = "-"
    $DNS                = "-"

    $AdapterName        = "Non détectée"
    $AdapterDescription = "Non détectée"
    $AdapterStatus      = "Inconnu"

    $MacAddress         = "-"
    $LinkSpeed          = "-"
    $PnPDeviceID        = $null

    $Chipset            = "Non détecté"

    $DriverName         = "Non détecté"
    $DriverManufacturer = "Non détecté"
    $DriverProvider     = "-"
    $DriverDate         = "-"
    $DriverInf          = "-"


    # --------------------------------------------------------
    # INFORMATIONS DE LA CARTE ACTIVE
    # --------------------------------------------------------

    if ($ActiveAdapter) {

        $AdapterName        = $ActiveAdapter.Name
        $AdapterDescription = $ActiveAdapter.InterfaceDescription
        $AdapterStatus      = $ActiveAdapter.Status
        $MacAddress         = $ActiveAdapter.MacAddress
        $LinkSpeed          = $ActiveAdapter.LinkSpeed
        $PnPDeviceID        = $ActiveAdapter.PnPDeviceID

        if ($ActiveAdapter.InterfaceDescription) {
            $Chipset = $ActiveAdapter.InterfaceDescription
        }


        # ----------------------------------------------------
        # IPv4
        # ----------------------------------------------------

        $IPObject = Get-NetIPAddress `
            -InterfaceIndex $ActiveAdapter.InterfaceIndex `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike "169.254.*"
            } |
            Select-Object -First 1


        if ($IPObject) {
            $IPAddress = $IPObject.IPAddress
        }


        # ----------------------------------------------------
        # PASSERELLE + DNS
        # ----------------------------------------------------

        try {

            $IPConfig = Get-NetIPConfiguration `
                -InterfaceIndex $ActiveAdapter.InterfaceIndex `
                -ErrorAction Stop


            if ($IPConfig.IPv4DefaultGateway) {
                $Gateway = $IPConfig.IPv4DefaultGateway.NextHop
            }


            if ($IPConfig.DNSServer.ServerAddresses) {
                $DNS = $IPConfig.DNSServer.ServerAddresses -join ", "
            }

        }
        catch {}
    }


    # --------------------------------------------------------
    # INFORMATIONS PILOTE
    # --------------------------------------------------------

    if ($PnPDeviceID) {

        try {

            $SignedDriver =
                Get-CimInstance Win32_PnPSignedDriver `
                -ErrorAction Stop |
                Where-Object {
                    $_.DeviceID -eq $PnPDeviceID
                } |
                Select-Object -First 1


            if ($SignedDriver) {

                if ($SignedDriver.DeviceName) {
                    $Chipset = $SignedDriver.DeviceName
                }


                if ($SignedDriver.DriverName) {
                    $DriverName = $SignedDriver.DriverName
                }


                if ($SignedDriver.Manufacturer) {
                    $DriverManufacturer = $SignedDriver.Manufacturer
                }


                if ($SignedDriver.DriverProviderName) {
                    $DriverProvider = $SignedDriver.DriverProviderName
                }


                if ($SignedDriver.InfName) {
                    $DriverInf = $SignedDriver.InfName
                }


                if ($SignedDriver.DriverDate) {

                    try {
                        $DriverDate =
                            ([datetime]$SignedDriver.DriverDate).ToString(
                                "dd/MM/yyyy"
                            )
                    }
                    catch {
                        $DriverDate = $SignedDriver.DriverDate
                    }
                }
            }

        }
        catch {}
    }


    # ========================================================
    # LISTE DE TOUTES LES CARTES
    # ========================================================

    $AdapterList = @()


    foreach ($NetworkAdapter in $AllAdapters) {

        $IsActive = $false


        if ($ActiveAdapter) {

            if (
                $NetworkAdapter.InterfaceIndex -eq
                $ActiveAdapter.InterfaceIndex
            ) {
                $IsActive = $true
            }
        }


        # ----------------------------------------------------
        # IPv4 DE CETTE CARTE
        # ----------------------------------------------------

        $CurrentIP = "-"

        try {

            $CurrentIPObject = Get-NetIPAddress `
                -InterfaceIndex $NetworkAdapter.InterfaceIndex `
                -AddressFamily IPv4 `
                -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.IPAddress -notlike "169.254.*"
                } |
                Select-Object -First 1


            if ($CurrentIPObject) {
                $CurrentIP = $CurrentIPObject.IPAddress
            }

        }
        catch {}


        # ----------------------------------------------------
        # ETAT / UTILISATION
        # ----------------------------------------------------

        if ($IsActive) {
            $Usage = "ACTIVE"
        }
        elseif ($NetworkAdapter.Status -eq "Up") {
            $Usage = "CONNECTEE"
        }
        else {
            $Usage = "INACTIVE"
        }


        # ----------------------------------------------------
        # AJOUT
        # ----------------------------------------------------

        $AdapterList += [PSCustomObject]@{

            Utilisation = $Usage
            Nom         = $NetworkAdapter.Name
            Chipset     = $NetworkAdapter.InterfaceDescription
            Etat        = $NetworkAdapter.Status
            IP          = $CurrentIP
            Vitesse     = $NetworkAdapter.LinkSpeed
            MAC         = $NetworkAdapter.MacAddress
        }
    }


    # ========================================================
    # EVENEMENTS RESEAU
    # ========================================================

    $Events = @()


    if ($ActiveAdapter) {

        $SearchTerms = @(

            $AdapterName
            $AdapterDescription
            $Chipset
            $DriverName

        ) |
        Where-Object {
            $_ -and
            $_ -ne "-" -and
            $_ -notlike "Non détect*"
        } |
        Select-Object -Unique


        try {

            $RawEvents = Get-WinEvent `
                -FilterHashtable @{

                    LogName   = "System"
                    Level     = 1,2
                    StartTime = (Get-Date).AddDays(-7)

                } `
                -ErrorAction SilentlyContinue


            foreach ($Event in $RawEvents) {

                $Match = $false


                # --------------------------------------------
                # RECHERCHE PAR CARTE / PILOTE / CHIPSET
                # --------------------------------------------

                foreach ($Term in $SearchTerms) {

                    if (
                        $Event.ProviderName -like "*$Term*" -or
                        $Event.Message -like "*$Term*"
                    ) {

                        $Match = $true
                        break
                    }
                }


                # --------------------------------------------
                # PROVIDERS RESEAU CONNUS
                # --------------------------------------------

                if (
                    $Event.ProviderName -match
                    "NDIS|Tcpip|NetAdapter|WLAN-AutoConfig|Netwtw|e1d|e1rexpress|rtwlane|rt640x64|qcamain"
                ) {

                    $Match = $true
                }


                # --------------------------------------------
                # AJOUT DE L'EVENEMENT
                # --------------------------------------------

                if ($Match) {

                    $Message = $Event.Message


                    if ($Message) {

                        $Message = $Message -replace "`r", " "
                        $Message = $Message -replace "`n", " "
                        $Message = $Message -replace "\s+", " "
                    }


                    $Events += [PSCustomObject]@{

                        TimeCreated = $Event.TimeCreated

                        Date =
                            $Event.TimeCreated.ToString(
                                "dd/MM/yyyy HH:mm:ss"
                            )

                        ID =
                            $Event.Id

                        Source =
                            $Event.ProviderName

                        Message =
                            $Message
                    }
                }
            }

        }
        catch {}
    }


    # --------------------------------------------------------
    # TRI CHRONOLOGIQUE
    # --------------------------------------------------------

    $Events = @(
        $Events |
        Sort-Object TimeCreated -Descending |
        Select-Object -First 100
    )


    # ========================================================
    # RESULTAT
    # ========================================================

    return [PSCustomObject]@{

        ComputerName = $ComputerName
        UserName     = $UserName

        IP      = $IPAddress
        Gateway = $Gateway
        DNS     = $DNS

        AdapterName        = $AdapterName
        AdapterDescription = $AdapterDescription
        AdapterStatus      = $AdapterStatus

        MacAddress = $MacAddress
        LinkSpeed  = $LinkSpeed

        Chipset = $Chipset

        DriverName         = $DriverName
        DriverManufacturer = $DriverManufacturer
        DriverProvider     = $DriverProvider
        DriverDate         = $DriverDate
        DriverInf          = $DriverInf

        AdapterList = $AdapterList
        Events      = $Events
    }
}


# ============================================================
# COLLECTE DES DONNEES
# ============================================================

$Data = Get-NetworkDiagnostic


# ============================================================
# INTERFACE WPF
#
# Fenêtre agrandie :
# 1400 x 1000
#
# ============================================================

[xml]$XAML = @"
<Window

    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"

    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"

    Title="Network Diagnostic Tool"

    Width="1400"

    Height="1200"

    MinWidth="1150"

    MinHeight="800"

    WindowStartupLocation="CenterScreen"

    Background="#0F172A"

    FontFamily="Segoe UI">


    <Window.Resources>


        <!-- =================================================
             TEXTES
             ================================================= -->


        <Style TargetType="TextBlock">

            <Setter
                Property="Foreground"
                Value="#E2E8F0"/>

        </Style>


        <Style
            x:Key="LabelStyle"
            TargetType="TextBlock">

            <Setter
                Property="Foreground"
                Value="#94A3B8"/>

            <Setter
                Property="FontSize"
                Value="11"/>

            <Setter
                Property="FontWeight"
                Value="SemiBold"/>

            <Setter
                Property="Margin"
                Value="0,0,0,5"/>

        </Style>


        <Style
            x:Key="ValueStyle"
            TargetType="TextBlock">

            <Setter
                Property="Foreground"
                Value="#F8FAFC"/>

            <Setter
                Property="FontSize"
                Value="15"/>

            <Setter
                Property="FontWeight"
                Value="SemiBold"/>

            <Setter
                Property="TextWrapping"
                Value="Wrap"/>

        </Style>


        <!-- =================================================
             CARTES
             ================================================= -->


        <Style
            x:Key="CardStyle"
            TargetType="Border">

            <Setter
                Property="Background"
                Value="#1E293B"/>

            <Setter
                Property="CornerRadius"
                Value="12"/>

            <Setter
                Property="Padding"
                Value="18"/>

            <Setter
                Property="Margin"
                Value="5"/>

        </Style>


        <!-- =================================================
             DATAGRID
             ================================================= -->


        <Style TargetType="DataGrid">

            <Setter
                Property="Background"
                Value="#1E293B"/>

            <Setter
                Property="Foreground"
                Value="#E2E8F0"/>

            <Setter
                Property="BorderBrush"
                Value="#334155"/>

            <Setter
                Property="BorderThickness"
                Value="1"/>

            <Setter
                Property="RowBackground"
                Value="#1E293B"/>

            <Setter
                Property="AlternatingRowBackground"
                Value="#172033"/>

            <Setter
                Property="GridLinesVisibility"
                Value="Horizontal"/>

            <Setter
                Property="HorizontalGridLinesBrush"
                Value="#334155"/>

            <Setter
                Property="HeadersVisibility"
                Value="Column"/>

            <Setter
                Property="RowHeaderWidth"
                Value="0"/>

            <Setter
                Property="ColumnHeaderHeight"
                Value="36"/>

            <Setter
                Property="RowHeight"
                Value="30"/>

        </Style>


        <!-- =================================================
             CELLULES
             ================================================= -->


        <Style TargetType="DataGridCell">

            <Setter
                Property="Foreground"
                Value="#E2E8F0"/>

            <Setter
                Property="Background"
                Value="Transparent"/>

            <Setter
                Property="BorderThickness"
                Value="0"/>

            <Setter
                Property="Padding"
                Value="8,4"/>

            <Setter
                Property="VerticalContentAlignment"
                Value="Center"/>

        </Style>


        <!-- =================================================
             EN-TETES DES TABLEAUX
             ================================================= -->


        <Style TargetType="DataGridColumnHeader">

            <Setter
                Property="Background"
                Value="#334155"/>

            <Setter
                Property="Foreground"
                Value="#F8FAFC"/>

            <Setter
                Property="FontWeight"
                Value="SemiBold"/>

            <Setter
                Property="FontSize"
                Value="12"/>

            <Setter
                Property="Height"
                Value="36"/>

            <Setter
                Property="Padding"
                Value="10,0"/>

            <Setter
                Property="HorizontalContentAlignment"
                Value="Left"/>

            <Setter
                Property="VerticalContentAlignment"
                Value="Center"/>


            <Setter Property="ContentTemplate">

                <Setter.Value>

                    <DataTemplate>

                        <TextBlock
                            Text="{Binding}"
                            Foreground="#F8FAFC"
                            FontSize="12"
                            FontWeight="SemiBold"
                            VerticalAlignment="Center"
                            TextTrimming="CharacterEllipsis"/>

                    </DataTemplate>

                </Setter.Value>

            </Setter>

        </Style>


        <!-- =================================================
             BOUTONS
             ================================================= -->


        <Style TargetType="Button">

            <Setter
                Property="Background"
                Value="#0284C7"/>

            <Setter
                Property="Foreground"
                Value="White"/>

            <Setter
                Property="BorderThickness"
                Value="0"/>

            <Setter
                Property="Padding"
                Value="18,9"/>

            <Setter
                Property="FontWeight"
                Value="SemiBold"/>

            <Setter
                Property="Cursor"
                Value="Hand"/>

        </Style>


    </Window.Resources>


    <!-- ====================================================
         CONTENU PRINCIPAL
         ==================================================== -->


    <Grid Margin="25">


        <Grid.RowDefinitions>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="*"/>

            <RowDefinition Height="Auto"/>

        </Grid.RowDefinitions>


        <!-- =================================================
             HEADER
             ================================================= -->


        <Grid
            Grid.Row="0"
            Margin="5,0,5,20">


            <Grid.ColumnDefinitions>

                <ColumnDefinition Width="*"/>

                <ColumnDefinition Width="Auto"/>

            </Grid.ColumnDefinitions>


            <StackPanel>


                <TextBlock
                    Text="NETWORK DIAGNOSTIC"
                    FontSize="30"
                    FontWeight="Bold"
                    Foreground="#38BDF8"/>


                <TextBlock
                    Text="Diagnostic de la connexion réseau Windows"
                    Foreground="#94A3B8"
                    FontSize="14"/>


            </StackPanel>


            <Border
                Grid.Column="1"
                Background="#064E3B"
                CornerRadius="20"
                Padding="16,8"
                VerticalAlignment="Center">


                <TextBlock
                    x:Name="GlobalStatus"
                    Text="● CONNECTÉ"
                    Foreground="#4ADE80"
                    FontWeight="Bold"/>


            </Border>


        </Grid>


        <!-- =================================================
             PC / UTILISATEUR / IPv4
             ================================================= -->


        <Grid Grid.Row="1">


            <Grid.ColumnDefinitions>

                <ColumnDefinition Width="*"/>

                <ColumnDefinition Width="*"/>

                <ColumnDefinition Width="*"/>

            </Grid.ColumnDefinitions>


            <Border
                Grid.Column="0"
                Style="{StaticResource CardStyle}">


                <StackPanel>


                    <TextBlock
                        Text="NOM DU PC"
                        Style="{StaticResource LabelStyle}"/>


                    <TextBlock
                        x:Name="ComputerName"
                        Style="{StaticResource ValueStyle}"/>


                </StackPanel>


            </Border>


            <Border
                Grid.Column="1"
                Style="{StaticResource CardStyle}">


                <StackPanel>


                    <TextBlock
                        Text="SESSION UTILISATEUR"
                        Style="{StaticResource LabelStyle}"/>


                    <TextBlock
                        x:Name="UserName"
                        Style="{StaticResource ValueStyle}"/>


                </StackPanel>


            </Border>


            <Border
                Grid.Column="2"
                Style="{StaticResource CardStyle}">


                <StackPanel>


                    <TextBlock
                        Text="ADRESSE IPv4"
                        Style="{StaticResource LabelStyle}"/>


                    <TextBlock
                        x:Name="IPAddress"
                        Foreground="#38BDF8"
                        FontSize="19"
                        FontWeight="Bold"/>


                </StackPanel>


            </Border>


        </Grid>


        <!-- =================================================
             CARTE ACTIVE
             ================================================= -->


        <Border
            Grid.Row="2"
            Style="{StaticResource CardStyle}"
            Margin="5,12,5,5">


            <StackPanel>


                <TextBlock
                    Text="CARTE RÉSEAU UTILISÉE"
                    Foreground="#4ADE80"
                    FontSize="15"
                    FontWeight="Bold"
                    Margin="0,0,0,15"/>


                <Grid>


                    <Grid.ColumnDefinitions>

                        <ColumnDefinition Width="2*"/>

                        <ColumnDefinition Width="2*"/>

                        <ColumnDefinition Width="*"/>

                    </Grid.ColumnDefinitions>


                    <Grid.RowDefinitions>

                        <RowDefinition Height="Auto"/>

                        <RowDefinition Height="Auto"/>

                    </Grid.RowDefinitions>


                    <StackPanel
                        Grid.Row="0"
                        Grid.Column="0"
                        Margin="0,0,20,18">


                        <TextBlock
                            Text="INTERFACE"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="AdapterName"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Row="0"
                        Grid.Column="1"
                        Margin="0,0,20,18">


                        <TextBlock
                            Text="CHIPSET / CONTRÔLEUR RÉSEAU"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="Chipset"
                            Foreground="#A78BFA"
                            FontSize="16"
                            FontWeight="Bold"
                            TextWrapping="Wrap"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Row="0"
                        Grid.Column="2">


                        <TextBlock
                            Text="VITESSE DE LIAISON"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="LinkSpeed"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Row="1"
                        Grid.Column="0">


                        <TextBlock
                            Text="ADRESSE MAC"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="MacAddress"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Row="1"
                        Grid.Column="1">


                        <TextBlock
                            Text="PASSERELLE"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="Gateway"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Row="1"
                        Grid.Column="2">


                        <TextBlock
                            Text="DNS"
                            Style="{StaticResource LabelStyle}"
                            />


                        <TextBlock
                            x:Name="DNS"
                            Style="{StaticResource ValueStyle}"
                            TextWrapping="Wrap"/>


                    </StackPanel>


                </Grid>


            </StackPanel>


        </Border>


        <!-- =================================================
             BANDE PASSANTE
             DESACTIVEE VOLONTAIREMENT
             ================================================= -->


        <!-- =================================================
             INFORMATIONS PILOTE
             ================================================= -->


        <Border
            Grid.Row="3"
            Style="{StaticResource CardStyle}"
            Margin="5,10,5,5">


            <StackPanel>


                <TextBlock
                    Text="INFORMATIONS PILOTE"
                    Foreground="#A78BFA"
                    FontSize="15"
                    FontWeight="Bold"
                    Margin="0,0,0,15"/>


                <Grid>


                    <Grid.ColumnDefinitions>

                        <ColumnDefinition Width="*"/>

                        <ColumnDefinition Width="*"/>

                        <ColumnDefinition Width="*"/>

                        <ColumnDefinition Width="*"/>

                    </Grid.ColumnDefinitions>


                    <StackPanel
                        Grid.Column="0"
                        Margin="0,0,15,0">


                        <TextBlock
                            Text="PILOTE"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="DriverName"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Column="1"
                        Margin="0,0,15,0">


                        <TextBlock
                            Text="CONSTRUCTEUR"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="DriverManufacturer"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Column="2"
                        Margin="0,0,15,0">


                        <TextBlock
                            Text="DATE DU PILOTE"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="DriverDate"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                    <StackPanel
                        Grid.Column="3">


                        <TextBlock
                            Text="FICHIER INF"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="DriverInf"
                            Style="{StaticResource ValueStyle}"/>


                    </StackPanel>


                </Grid>


            </StackPanel>


        </Border>


        <!-- =================================================
             TABLEAUX
             ================================================= -->


        <Grid
            Grid.Row="4"
            Margin="5,10,5,0">


            <!--
                TOUTES LES CARTES RESEAU :
                1.5 fois la hauteur de la zone erreurs.
            -->


            <Grid.RowDefinitions>

                <RowDefinition Height="1.5*"/>

                <RowDefinition Height="12"/>

                <RowDefinition Height="*"/>

            </Grid.RowDefinitions>


            <!-- =============================================
                 TOUTES LES CARTES RESEAU
                 ============================================= -->


            <Border
                Grid.Row="0"
                Background="#1E293B"
                CornerRadius="12"
                Padding="15">


                <Grid>


                    <Grid.RowDefinitions>

                        <RowDefinition Height="Auto"/>

                        <RowDefinition Height="*"/>

                    </Grid.RowDefinitions>


                    <StackPanel
                        Grid.Row="0"
                        Margin="0,0,0,12">


                        <TextBlock
                            Text="TOUTES LES CARTES RÉSEAU"
                            Foreground="#38BDF8"
                            FontSize="15"
                            FontWeight="Bold"/>


                        <TextBlock
                            Text="ACTIVE = interface utilisée par la route IPv4 par défaut."
                            Foreground="#94A3B8"
                            FontSize="11"
                            Margin="0,3,0,0"/>


                    </StackPanel>


                    <DataGrid
                        x:Name="AdapterGrid"

                        Grid.Row="1"

                        AutoGenerateColumns="False"

                        IsReadOnly="True"

                        CanUserAddRows="False"

                        CanUserDeleteRows="False"

                        CanUserResizeRows="False"

                        SelectionMode="Single"

                        ColumnHeaderHeight="36"

                        RowHeight="30"

                        MinHeight="150">


                        <DataGrid.Columns>


                            <DataGridTextColumn
                                Header="Utilisation"
                                Binding="{Binding Utilisation}"
                                Width="115"/>


                            <DataGridTextColumn
                                Header="Interface"
                                Binding="{Binding Nom}"
                                Width="160"/>


                            <DataGridTextColumn
                                Header="Chipset / Contrôleur"
                                Binding="{Binding Chipset}"
                                Width="*"/>


                            <DataGridTextColumn
                                Header="État"
                                Binding="{Binding Etat}"
                                Width="100"/>


                            <DataGridTextColumn
                                Header="Adresse IP"
                                Binding="{Binding IP}"
                                Width="145"/>


                            <DataGridTextColumn
                                Header="Vitesse"
                                Binding="{Binding Vitesse}"
                                Width="125"/>


                            <DataGridTextColumn
                                Header="MAC"
                                Binding="{Binding MAC}"
                                Width="170"/>


                        </DataGrid.Columns>


                    </DataGrid>


                </Grid>


            </Border>


            <!-- =============================================
                 ERREURS RESEAU
                 ============================================= -->


            <Border
                Grid.Row="2"
                Background="#1E293B"
                CornerRadius="12"
                Padding="15">


                <Grid>


                    <Grid.RowDefinitions>

                        <RowDefinition Height="Auto"/>

                        <RowDefinition Height="*"/>

                    </Grid.RowDefinitions>


                    <StackPanel
                        Grid.Row="0"
                        Margin="0,0,0,12">


                        <TextBlock
                            Text="ERREURS RÉSEAU"
                            Foreground="#F87171"
                            FontSize="15"
                            FontWeight="Bold"/>


                        <TextBlock
                            x:Name="EventCount"
                            Foreground="#94A3B8"
                            FontSize="11"
                            Margin="0,3,0,0"/>


                    </StackPanel>


                    <DataGrid
                        x:Name="EventGrid"

                        Grid.Row="1"

                        AutoGenerateColumns="False"

                        IsReadOnly="True"

                        CanUserAddRows="False"

                        CanUserDeleteRows="False"

                        CanUserResizeRows="False"

                        SelectionMode="Single"

                        ColumnHeaderHeight="36"

                        RowHeight="30"

                        MinHeight="130">


                        <DataGrid.Columns>


                            <DataGridTextColumn
                                Header="Date"
                                Binding="{Binding Date}"
                                Width="165"/>


                            <DataGridTextColumn
                                Header="ID"
                                Binding="{Binding ID}"
                                Width="75"/>


                            <DataGridTextColumn
                                Header="Source"
                                Binding="{Binding Source}"
                                Width="220"/>


                            <DataGridTextColumn
                                Header="Message"
                                Binding="{Binding Message}"
                                Width="*"/>


                        </DataGrid.Columns>


                    </DataGrid>


                </Grid>


            </Border>


        </Grid>


        <!-- =================================================
             FOOTER
             ================================================= -->


        <Grid
            Grid.Row="5"
            Margin="5,12,5,0">


            <Grid.ColumnDefinitions>

                <ColumnDefinition Width="*"/>

                <ColumnDefinition Width="Auto"/>

            </Grid.ColumnDefinitions>


            <TextBlock
                Grid.Column="0"
                Text="Diagnostic Windows • événements analysés sur les 7 derniers jours"
                Foreground="#64748B"
                FontSize="11"
                VerticalAlignment="Center"/>


            <Button
                Grid.Column="1"
                x:Name="CloseButton"
                Content="Fermer"/>


        </Grid>


    </Grid>


</Window>
"@


# ============================================================
# CREATION DE LA FENETRE
# ============================================================

$Reader =
    New-Object System.Xml.XmlNodeReader $XAML


$Window =
    [Windows.Markup.XamlReader]::Load($Reader)


# ============================================================
# INFORMATIONS GENERALES
# ============================================================

$Window.FindName("ComputerName").Text =
    $Data.ComputerName


$Window.FindName("UserName").Text =
    $Data.UserName


$Window.FindName("IPAddress").Text =
    $Data.IP


# ============================================================
# CARTE ACTIVE
# ============================================================

$Window.FindName("AdapterName").Text =
    $Data.AdapterName


$Window.FindName("Chipset").Text =
    $Data.Chipset


$Window.FindName("LinkSpeed").Text =
    $Data.LinkSpeed


$Window.FindName("MacAddress").Text =
    $Data.MacAddress


$Window.FindName("Gateway").Text =
    $Data.Gateway


$Window.FindName("DNS").Text =
    $Data.DNS


# ============================================================
# PILOTE
# ============================================================

$Window.FindName("DriverName").Text =
    $Data.DriverName


$Window.FindName("DriverManufacturer").Text =
    $Data.DriverManufacturer


$Window.FindName("DriverDate").Text =
    $Data.DriverDate


$Window.FindName("DriverInf").Text =
    $Data.DriverInf


# ============================================================
# TOUTES LES CARTES
# ============================================================

$Window.FindName("AdapterGrid").ItemsSource =
    @($Data.AdapterList)


# ============================================================
# EVENEMENTS
# ============================================================

$Window.FindName("EventGrid").ItemsSource =
    @($Data.Events)


$EventNumber =
    @($Data.Events).Count


if ($EventNumber -eq 0) {

    $Window.FindName("EventCount").Text =
        "Aucune erreur réseau détectée sur les 7 derniers jours."

}
elseif ($EventNumber -eq 1) {

    $Window.FindName("EventCount").Text =
        "1 erreur réseau détectée sur les 7 derniers jours."

}
else {

    $Window.FindName("EventCount").Text =
        "$EventNumber erreurs réseau détectées sur les 7 derniers jours."
}


# ============================================================
# ETAT GLOBAL
# ============================================================

$GlobalStatus =
    $Window.FindName("GlobalStatus")


if ($Data.AdapterStatus -eq "Up") {

    $GlobalStatus.Text =
        "● CONNECTÉ"

    $GlobalStatus.Foreground =
        "#4ADE80"

}
else {

    $GlobalStatus.Text =
        "● NON CONNECTÉ"

    $GlobalStatus.Foreground =
        "#F87171"
}


# ============================================================
# BOUTON FERMER
# ============================================================

$CloseButton =
    $Window.FindName("CloseButton")


$CloseButton.Add_Click({

    $Window.Close()

})


# ============================================================
# AFFICHAGE
# ============================================================

$Window.ShowDialog() | Out-Null