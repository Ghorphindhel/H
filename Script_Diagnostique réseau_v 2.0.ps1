#requires -Version 5.1

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms


# ============================================================
# NETWORK DIAGNOSTIC TOOL
# ============================================================
#
# - Authentification de la session Windows interactive
# - 3 tentatives maximum
# - Diagnostic lancé uniquement après authentification
# - Détection renforcée du pilote réseau
# - Fenêtre principale adaptative à l'écran
#
# ============================================================


# ============================================================
# API WINDOWS - LOGONUSER
# ============================================================

if (-not ("NativeLogon" -as [type])) {

    Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeLogon
{
    [DllImport(
        "advapi32.dll",
        SetLastError = true,
        CharSet = CharSet.Unicode
    )]
    public static extern bool LogonUser(
        string lpszUsername,
        string lpszDomain,
        string lpszPassword,
        int dwLogonType,
        int dwLogonProvider,
        out IntPtr phToken
    );

    [DllImport(
        "kernel32.dll",
        SetLastError = true
    )]
    public static extern bool CloseHandle(
        IntPtr hObject
    );
}
"@

}


# ============================================================
# SESSION WINDOWS INTERACTIVE
# ============================================================

function Get-InteractiveWindowsUser {

    try {

        $CurrentUser =
            (Get-CimInstance Win32_ComputerSystem `
                -ErrorAction Stop).UserName

        if ($CurrentUser) {
            return $CurrentUser
        }

    }
    catch {}


    return "$env:USERDOMAIN\$env:USERNAME"
}


# ============================================================
# VALIDATION DES IDENTIFIANTS WINDOWS
# ============================================================

function Test-WindowsCredential {

    param(

        [Parameter(Mandatory = $true)]
        [string]$WindowsUser,

        [Parameter(Mandatory = $true)]
        [string]$Password
    )


    $Domain   = "."
    $UserName = $WindowsUser


    if ($WindowsUser -match "\\") {

        $Parts =
            $WindowsUser.Split(
                '\',
                2
            )

        $Domain   = $Parts[0]
        $UserName = $Parts[1]
    }


    $Token =
        [IntPtr]::Zero


    try {

        # LOGON32_LOGON_NETWORK = 3
        # LOGON32_PROVIDER_DEFAULT = 0

        $Result =
            [NativeLogon]::LogonUser(
                $UserName,
                $Domain,
                $Password,
                3,
                0,
                [ref]$Token
            )


        return $Result

    }
    finally {

        if ($Token -ne [IntPtr]::Zero) {

            [NativeLogon]::CloseHandle(
                $Token
            ) | Out-Null
        }
    }
}


# ============================================================
# FENETRE D'AUTHENTIFICATION
# ============================================================

function Show-AuthenticationWindow {

    $CurrentWindowsUser =
        Get-InteractiveWindowsUser


    [xml]$LoginXAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"

    Title="Network Diagnostic - Authentification"

    Width="500"
    Height="420"

    ResizeMode="NoResize"

    WindowStartupLocation="CenterScreen"

    Background="#0F172A"

    FontFamily="Segoe UI">


    <Window.Resources>


        <Style TargetType="TextBlock">

            <Setter
                Property="Foreground"
                Value="#E2E8F0"/>

        </Style>


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
                Value="20,10"/>

            <Setter
                Property="FontWeight"
                Value="SemiBold"/>

            <Setter
                Property="Cursor"
                Value="Hand"/>

        </Style>


    </Window.Resources>


    <Grid Margin="35">


        <Grid.RowDefinitions>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="25"/>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="22"/>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="Auto"/>

            <RowDefinition Height="*"/>

            <RowDefinition Height="Auto"/>

        </Grid.RowDefinitions>


        <!-- TITRE -->


        <StackPanel Grid.Row="0">


            <TextBlock
                Text="NETWORK DIAGNOSTIC"
                Foreground="#38BDF8"
                FontSize="27"
                FontWeight="Bold"/>


            <TextBlock
                Text="Authentification requise"
                Foreground="#94A3B8"
                FontSize="14"
                Margin="0,4,0,0"/>


        </StackPanel>


        <!-- SESSION -->


        <StackPanel Grid.Row="2">


            <TextBlock
                Text="SESSION WINDOWS"
                Foreground="#94A3B8"
                FontSize="11"
                FontWeight="SemiBold"
                Margin="0,0,0,7"/>


            <Border
                Background="#1E293B"
                CornerRadius="8"
                Padding="14,11">


                <TextBlock
                    x:Name="WindowsUser"
                    Foreground="#F8FAFC"
                    FontSize="15"
                    FontWeight="SemiBold"/>


            </Border>


        </StackPanel>


        <!-- MOT DE PASSE -->


        <StackPanel Grid.Row="4">


            <TextBlock
                Text="MOT DE PASSE"
                Foreground="#94A3B8"
                FontSize="11"
                FontWeight="SemiBold"
                Margin="0,0,0,7"/>


            <PasswordBox
                x:Name="PasswordInput"
                Height="42"
                Background="#1E293B"
                Foreground="#F8FAFC"
                BorderBrush="#334155"
                BorderThickness="1"
                Padding="11,8"
                FontSize="15"/>


        </StackPanel>


        <!-- MESSAGE -->


        <TextBlock
            x:Name="LoginMessage"
            Grid.Row="5"
            Foreground="#F87171"
            FontSize="12"
            Margin="0,10,0,0"
            TextWrapping="Wrap"/>


        <!-- BOUTONS -->


        <Grid Grid.Row="7">


            <Grid.ColumnDefinitions>

                <ColumnDefinition Width="*"/>

                <ColumnDefinition Width="Auto"/>

                <ColumnDefinition Width="10"/>

                <ColumnDefinition Width="Auto"/>

            </Grid.ColumnDefinitions>


            <Button
                x:Name="CancelButton"
                Grid.Column="1"
                Content="Quitter"
                Background="#475569"/>


            <Button
                x:Name="LoginButton"
                Grid.Column="3"
                Content="Se connecter"
                IsDefault="True"/>


        </Grid>


    </Grid>


</Window>
"@


    $Reader =
        New-Object `
        System.Xml.XmlNodeReader `
        $LoginXAML


    $LoginWindow =
        [Windows.Markup.XamlReader]::Load(
            $Reader
        )


    $WindowsUserText =
        $LoginWindow.FindName(
            "WindowsUser"
        )


    $PasswordInput =
        $LoginWindow.FindName(
            "PasswordInput"
        )


    $LoginMessage =
        $LoginWindow.FindName(
            "LoginMessage"
        )


    $LoginButton =
        $LoginWindow.FindName(
            "LoginButton"
        )


    $CancelButton =
        $LoginWindow.FindName(
            "CancelButton"
        )


    $WindowsUserText.Text =
        $CurrentWindowsUser


    $script:AuthenticationSucceeded =
        $false


    $script:LoginAttempts =
        0


    # --------------------------------------------------------
    # CONNEXION
    # --------------------------------------------------------

    $LoginButton.Add_Click({

        $Password =
            $PasswordInput.Password


        if (
            [string]::IsNullOrWhiteSpace(
                $Password
            )
        ) {

            $LoginMessage.Foreground =
                "#F87171"

            $LoginMessage.Text =
                "Veuillez saisir votre mot de passe Windows."

            $PasswordInput.Focus()

            return
        }


        $LoginButton.IsEnabled =
            $false


        $LoginMessage.Foreground =
            "#94A3B8"


        $LoginMessage.Text =
            "Vérification des identifiants..."


        try {

            $Valid =
                Test-WindowsCredential `
                    -WindowsUser $CurrentWindowsUser `
                    -Password $Password

        }
        catch {

            $Valid =
                $false
        }


        $Password =
            $null


        if ($Valid) {

            $script:AuthenticationSucceeded =
                $true


            $PasswordInput.Clear()


            $LoginMessage.Foreground =
                "#4ADE80"


            $LoginMessage.Text =
                "Authentification réussie."


            $LoginWindow.DialogResult =
                $true


            $LoginWindow.Close()

        }
        else {

            $script:LoginAttempts++


            $PasswordInput.Clear()


            $Remaining =
                3 - $script:LoginAttempts


            if ($Remaining -le 0) {

                [System.Windows.MessageBox]::Show(
                    "Authentification refusée.`n`nL'application va se fermer.",
                    "Network Diagnostic",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                ) | Out-Null


                $LoginWindow.DialogResult =
                    $false


                $LoginWindow.Close()

            }
            else {

                $LoginMessage.Foreground =
                    "#F87171"


                if ($Remaining -eq 1) {

                    $LoginMessage.Text =
                        "Mot de passe incorrect. Il reste 1 tentative."

                }
                else {

                    $LoginMessage.Text =
                        "Mot de passe incorrect. Il reste $Remaining tentatives."
                }


                $LoginButton.IsEnabled =
                    $true


                $PasswordInput.Focus()
            }
        }

    })


    # --------------------------------------------------------
    # QUITTER
    # --------------------------------------------------------

    $CancelButton.Add_Click({

        $script:AuthenticationSucceeded =
            $false


        $PasswordInput.Clear()


        $LoginWindow.DialogResult =
            $false


        $LoginWindow.Close()

    })


    # --------------------------------------------------------
    # FOCUS
    # --------------------------------------------------------

    $LoginWindow.Add_ContentRendered({

        $PasswordInput.Focus()

    })


    $LoginWindow.ShowDialog() |
        Out-Null


    return $script:AuthenticationSucceeded
}


# ============================================================
# AUTHENTIFICATION
# ============================================================

$Authenticated =
    Show-AuthenticationWindow


if (-not $Authenticated) {

    return
}


# ============================================================
# DETECTION RENFORCEE DU PILOTE
# ============================================================

function Get-NetworkDriverInformation {

    param(

        [Parameter(Mandatory = $true)]
        $Adapter
    )


    $Result = [ordered]@{

        DriverName         = "Non détecté"
        DriverPath         = "-"
        DriverManufacturer = "Non détecté"
        DriverProvider     = "-"
        DriverDate         = "-"
        DriverInf          = "-"
        Chipset            = $Adapter.InterfaceDescription
        DriverService      = "-"
    }


    $PnPDeviceID =
        $Adapter.PnPDeviceID


    if (-not $PnPDeviceID) {

        return [PSCustomObject]$Result
    }


    # ========================================================
    # METHODE 1
    # WIN32_PNPSIGNEDDRIVER
    # ========================================================

    try {

        $SignedDriver =

            Get-CimInstance `
                Win32_PnPSignedDriver `
                -ErrorAction Stop |

            Where-Object {

                $_.DeviceID -eq
                $PnPDeviceID

            } |

            Select-Object -First 1


        if ($SignedDriver) {


            if ($SignedDriver.DeviceName) {

                $Result.Chipset =
                    $SignedDriver.DeviceName
            }


            if ($SignedDriver.DriverName) {

                $Result.DriverName =
                    $SignedDriver.DriverName
            }


            if ($SignedDriver.Manufacturer) {

                $Result.DriverManufacturer =
                    $SignedDriver.Manufacturer
            }


            if ($SignedDriver.DriverProviderName) {

                $Result.DriverProvider =
                    $SignedDriver.DriverProviderName
            }


            if ($SignedDriver.InfName) {

                $Result.DriverInf =
                    $SignedDriver.InfName
            }


            if ($SignedDriver.DriverDate) {

                try {

                    $Result.DriverDate =

                        ([datetime]$SignedDriver.DriverDate).ToString(
                            "dd/MM/yyyy"
                        )

                }
                catch {

                    $Result.DriverDate =
                        "$($SignedDriver.DriverDate)"
                }
            }
        }

    }
    catch {}


    # ========================================================
    # METHODE 2
    # PROPRIETES PNP
    # ========================================================

    try {

        $PnpDevice =

            Get-PnpDevice `
                -InstanceId $PnPDeviceID `
                -ErrorAction Stop


        if (
            $PnpDevice -and
            $PnpDevice.FriendlyName
        ) {

            $Result.Chipset =
                $PnpDevice.FriendlyName
        }

    }
    catch {}


    # --------------------------------------------------------
    # PROVIDER
    # --------------------------------------------------------

    try {

        $Property =

            Get-PnpDeviceProperty `
                -InstanceId $PnPDeviceID `
                -KeyName "DEVPKEY_Device_DriverProvider" `
                -ErrorAction Stop


        if ($Property.Data) {

            $Result.DriverProvider =
                "$($Property.Data)"


            if (
                $Result.DriverManufacturer -eq
                "Non détecté"
            ) {

                $Result.DriverManufacturer =
                    "$($Property.Data)"
            }
        }

    }
    catch {}


    # --------------------------------------------------------
    # DATE
    # --------------------------------------------------------

    try {

        $Property =

            Get-PnpDeviceProperty `
                -InstanceId $PnPDeviceID `
                -KeyName "DEVPKEY_Device_DriverDate" `
                -ErrorAction Stop


        if ($Property.Data) {

            try {

                $Result.DriverDate =

                    ([datetime]$Property.Data).ToString(
                        "dd/MM/yyyy"
                    )

            }
            catch {

                $Result.DriverDate =
                    "$($Property.Data)"
            }
        }

    }
    catch {}


    # --------------------------------------------------------
    # INF
    # --------------------------------------------------------

    try {

        $Property =

            Get-PnpDeviceProperty `
                -InstanceId $PnPDeviceID `
                -KeyName "DEVPKEY_Device_DriverInfPath" `
                -ErrorAction Stop


        if ($Property.Data) {

            $Result.DriverInf =
                "$($Property.Data)"
        }

    }
    catch {}


    # ========================================================
    # METHODE 3
    # SERVICE DU PERIPHERIQUE
    # ========================================================

    $DriverService =
        $null


    try {

        $Property =

            Get-PnpDeviceProperty `
                -InstanceId $PnPDeviceID `
                -KeyName "DEVPKEY_Device_Service" `
                -ErrorAction Stop


        if ($Property.Data) {

            $DriverService =
                "$($Property.Data)"


            $Result.DriverService =
                $DriverService
        }

    }
    catch {}


    # ========================================================
    # METHODE 4
    # REGISTRE DU SERVICE
    # ========================================================

    if ($DriverService) {

        try {

            $RegistryPath =

                "HKLM:\SYSTEM\CurrentControlSet\Services\$DriverService"


            $ServiceData =

                Get-ItemProperty `
                    -Path $RegistryPath `
                    -ErrorAction Stop


            if ($ServiceData.ImagePath) {

                $DriverPath =
                    "$($ServiceData.ImagePath)"


                $DriverPath =
                    $DriverPath.Trim('"')


                # --------------------------------------------
                # \SystemRoot\...
                # --------------------------------------------

                if (
                    $DriverPath -like
                    "\SystemRoot\*"
                ) {

                    $DriverPath =

                        $DriverPath.Replace(
                            "\SystemRoot",
                            $env:SystemRoot
                        )
                }


                # --------------------------------------------
                # System32\...
                # --------------------------------------------

                if (
                    $DriverPath -like
                    "System32\*"
                ) {

                    $DriverPath =

                        Join-Path `
                            $env:SystemRoot `
                            $DriverPath
                }


                $Result.DriverPath =
                    $DriverPath


                try {

                    $FileName =

                        Split-Path `
                            -Path $DriverPath `
                            -Leaf


                    if ($FileName) {

                        $Result.DriverName =
                            $FileName
                    }

                }
                catch {}
            }

        }
        catch {}
    }


    # ========================================================
    # METHODE 5
    # DRIVERSTORE VIA INF
    # ========================================================

    if (
        $Result.DriverName -eq "Non détecté" -and
        $Result.DriverInf -ne "-"
    ) {

        try {

            $InfBaseName =

                [System.IO.Path]::GetFileNameWithoutExtension(
                    $Result.DriverInf
                )


            $DriverStore =

                Join-Path `
                    $env:SystemRoot `
                    "System32\DriverStore\FileRepository"


            $DriverDirectory =

                Get-ChildItem `
                    -Path $DriverStore `
                    -Directory `
                    -Filter "$InfBaseName*" `
                    -ErrorAction SilentlyContinue |

                Select-Object -First 1


            if ($DriverDirectory) {

                $SysFile =

                    Get-ChildItem `
                        -Path $DriverDirectory.FullName `
                        -Filter "*.sys" `
                        -File `
                        -Recurse `
                        -ErrorAction SilentlyContinue |

                    Select-Object -First 1


                if ($SysFile) {

                    $Result.DriverName =
                        $SysFile.Name


                    $Result.DriverPath =
                        $SysFile.FullName
                }
            }

        }
        catch {}
    }


    # ========================================================
    # DERNIER FALLBACK
    # ========================================================

    if (
        $Result.DriverName -eq "Non détecté" -and
        $DriverService
    ) {

        $Result.DriverName =
            $DriverService
    }


    if (
        $Result.DriverManufacturer -eq "Non détecté" -and
        $Result.DriverProvider -ne "-"
    ) {

        $Result.DriverManufacturer =
            $Result.DriverProvider
    }


    return [PSCustomObject]$Result
}


# ============================================================
# COLLECTE DU DIAGNOSTIC
# ============================================================

function Get-NetworkDiagnostic {


    # --------------------------------------------------------
    # PC / UTILISATEUR
    # --------------------------------------------------------

    $ComputerName =
        $env:COMPUTERNAME


    $UserName =
        Get-InteractiveWindowsUser


    # --------------------------------------------------------
    # CARTES
    # --------------------------------------------------------

    $AllAdapters = @(

        Get-NetAdapter `
            -ErrorAction SilentlyContinue |

        Sort-Object Name
    )


    # --------------------------------------------------------
    # ROUTE PAR DEFAUT
    # --------------------------------------------------------

    $DefaultRoute =

        Get-NetRoute `
            -AddressFamily IPv4 `
            -DestinationPrefix "0.0.0.0/0" `
            -ErrorAction SilentlyContinue |

        Where-Object {

            $_.NextHop -ne "0.0.0.0" -and
            $_.State -eq "Alive"

        } |

        Sort-Object `
            RouteMetric,
            InterfaceMetric |

        Select-Object -First 1


    # --------------------------------------------------------
    # CARTE ACTIVE
    # --------------------------------------------------------

    $ActiveAdapter =
        $null


    if ($DefaultRoute) {

        $ActiveAdapter =

            Get-NetAdapter `
                -InterfaceIndex $DefaultRoute.InterfaceIndex `
                -ErrorAction SilentlyContinue
    }


    # --------------------------------------------------------
    # VALEURS
    # --------------------------------------------------------

    $IPAddress =
        "Non détectée"

    $Gateway =
        "-"

    $DNS =
        "-"

    $AdapterName =
        "Non détectée"

    $AdapterDescription =
        "Non détectée"

    $AdapterStatus =
        "Inconnu"

    $MacAddress =
        "-"

    $LinkSpeed =
        "-"

    $Chipset =
        "Non détecté"

    $DriverName =
        "Non détecté"

    $DriverPath =
        "-"

    $DriverManufacturer =
        "Non détecté"

    $DriverProvider =
        "-"

    $DriverDate =
        "-"

    $DriverInf =
        "-"


    # --------------------------------------------------------
    # CARTE ACTIVE
    # --------------------------------------------------------

    if ($ActiveAdapter) {

        $AdapterName =
            $ActiveAdapter.Name


        $AdapterDescription =
            $ActiveAdapter.InterfaceDescription


        $AdapterStatus =
            $ActiveAdapter.Status


        $MacAddress =
            $ActiveAdapter.MacAddress


        $LinkSpeed =
            $ActiveAdapter.LinkSpeed


        # ----------------------------------------------------
        # IPv4
        # ----------------------------------------------------

        $IPObject =

            Get-NetIPAddress `
                -InterfaceIndex $ActiveAdapter.InterfaceIndex `
                -AddressFamily IPv4 `
                -ErrorAction SilentlyContinue |

            Where-Object {

                $_.IPAddress -notlike
                "169.254.*"

            } |

            Select-Object -First 1


        if ($IPObject) {

            $IPAddress =
                $IPObject.IPAddress
        }


        # ----------------------------------------------------
        # IP CONFIG
        # ----------------------------------------------------

        try {

            $IPConfig =

                Get-NetIPConfiguration `
                    -InterfaceIndex $ActiveAdapter.InterfaceIndex `
                    -ErrorAction Stop


            if (
                $IPConfig.IPv4DefaultGateway
            ) {

                $Gateway =
                    $IPConfig.IPv4DefaultGateway.NextHop
            }


            if (
                $IPConfig.DNSServer.ServerAddresses
            ) {

                $DNS =

                    $IPConfig.DNSServer.ServerAddresses `
                    -join ", "
            }

        }
        catch {}


        # ----------------------------------------------------
        # PILOTE RENFORCE
        # ----------------------------------------------------

        $DriverInfo =

            Get-NetworkDriverInformation `
                -Adapter $ActiveAdapter


        if ($DriverInfo) {

            $Chipset =
                $DriverInfo.Chipset


            $DriverName =
                $DriverInfo.DriverName


            $DriverPath =
                $DriverInfo.DriverPath


            $DriverManufacturer =
                $DriverInfo.DriverManufacturer


            $DriverProvider =
                $DriverInfo.DriverProvider


            $DriverDate =
                $DriverInfo.DriverDate


            $DriverInf =
                $DriverInfo.DriverInf
        }
    }


    # ========================================================
    # TOUTES LES CARTES
    # ========================================================

    $AdapterList =
        @()


    foreach (
        $NetworkAdapter in
        $AllAdapters
    ) {

        $IsActive =
            $false


        if ($ActiveAdapter) {

            if (
                $NetworkAdapter.InterfaceIndex -eq
                $ActiveAdapter.InterfaceIndex
            ) {

                $IsActive =
                    $true
            }
        }


        $CurrentIP =
            "-"


        try {

            $CurrentIPObject =

                Get-NetIPAddress `
                    -InterfaceIndex $NetworkAdapter.InterfaceIndex `
                    -AddressFamily IPv4 `
                    -ErrorAction SilentlyContinue |

                Where-Object {

                    $_.IPAddress -notlike
                    "169.254.*"

                } |

                Select-Object -First 1


            if ($CurrentIPObject) {

                $CurrentIP =
                    $CurrentIPObject.IPAddress
            }

        }
        catch {}


        if ($IsActive) {

            $Usage =
                "ACTIVE"

        }
        elseif (
            $NetworkAdapter.Status -eq
            "Up"
        ) {

            $Usage =
                "CONNECTEE"

        }
        else {

            $Usage =
                "INACTIVE"
        }


        $AdapterList +=

            [PSCustomObject]@{

                Utilisation =
                    $Usage

                Nom =
                    $NetworkAdapter.Name

                Chipset =
                    $NetworkAdapter.InterfaceDescription

                Etat =
                    $NetworkAdapter.Status

                IP =
                    $CurrentIP

                Vitesse =
                    $NetworkAdapter.LinkSpeed

                MAC =
                    $NetworkAdapter.MacAddress
            }
    }


    # ========================================================
    # EVENEMENTS RESEAU
    # ========================================================

    $Events =
        @()


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

            $RawEvents =

                Get-WinEvent `
                    -FilterHashtable @{

                        LogName =
                            "System"

                        Level =
                            1,2

                        StartTime =
                            (Get-Date).AddDays(-7)

                    } `
                    -ErrorAction SilentlyContinue


            foreach (
                $Event in
                $RawEvents
            ) {

                $Match =
                    $false


                foreach (
                    $Term in
                    $SearchTerms
                ) {

                    if (
                        $Event.ProviderName -like "*$Term*" -or
                        $Event.Message -like "*$Term*"
                    ) {

                        $Match =
                            $true

                        break
                    }
                }


                if (
                    $Event.ProviderName -match
                    "NDIS|Tcpip|NetAdapter|WLAN-AutoConfig|Netwtw|e1d|e1rexpress|rtwlane|rt640x64|qcamain"
                ) {

                    $Match =
                        $true
                }


                if ($Match) {

                    $Message =
                        $Event.Message


                    if ($Message) {

                        $Message =
                            $Message -replace "`r", " "

                        $Message =
                            $Message -replace "`n", " "

                        $Message =
                            $Message -replace "\s+", " "
                    }


                    $Events +=

                        [PSCustomObject]@{

                            TimeCreated =
                                $Event.TimeCreated

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


    $Events = @(

        $Events |

        Sort-Object `
            TimeCreated `
            -Descending |

        Select-Object `
            -First 100
    )


    # ========================================================
    # RESULTAT
    # ========================================================

    return [PSCustomObject]@{

        ComputerName =
            $ComputerName

        UserName =
            $UserName

        IP =
            $IPAddress

        Gateway =
            $Gateway

        DNS =
            $DNS

        AdapterName =
            $AdapterName

        AdapterDescription =
            $AdapterDescription

        AdapterStatus =
            $AdapterStatus

        MacAddress =
            $MacAddress

        LinkSpeed =
            $LinkSpeed

        Chipset =
            $Chipset

        DriverName =
            $DriverName

        DriverPath =
            $DriverPath

        DriverManufacturer =
            $DriverManufacturer

        DriverProvider =
            $DriverProvider

        DriverDate =
            $DriverDate

        DriverInf =
            $DriverInf

        AdapterList =
            $AdapterList

        Events =
            $Events
    }
}


# ============================================================
# COLLECTE
# ============================================================

$Data =
    Get-NetworkDiagnostic


# ============================================================
# TAILLE DE LA FENETRE
# 95 % DE LA ZONE DE TRAVAIL
# ============================================================

$WorkArea =
    [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea


$WindowWidth =
    [Math]::Floor(
        $WorkArea.Width * 0.95
    )


$WindowHeight =
    [Math]::Floor(
        $WorkArea.Height * 0.95
    )


if ($WindowWidth -lt 900) {

    $WindowWidth =
        [Math]::Max(
            700,
            $WorkArea.Width - 20
        )
}


if ($WindowHeight -lt 650) {

    $WindowHeight =
        [Math]::Max(
            550,
            $WorkArea.Height - 20
        )
}


# ============================================================
# INTERFACE PRINCIPALE
# ============================================================

[xml]$XAML = @"
<Window

    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"

    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"

    Title="Network Diagnostic Tool"

    Width="$WindowWidth"

    Height="$WindowHeight"

    MinWidth="700"

    MinHeight="550"

    WindowStartupLocation="CenterScreen"

    Background="#0F172A"

    FontFamily="Segoe UI">


    <Window.Resources>


        <!-- TEXTES -->


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


        <!-- CARTES -->


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


        <!-- DATAGRID -->


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

        </Style>


        <!-- BOUTON -->


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
         CONTENU
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
             PC / USER / IP
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
             CARTE UTILISEE
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
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="DNS"
                            Style="{StaticResource ValueStyle}"
                            TextWrapping="Wrap"/>


                    </StackPanel>


                </Grid>


            </StackPanel>


        </Border>


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
                            Text="PILOTE (.SYS)"
                            Style="{StaticResource LabelStyle}"/>


                        <TextBlock
                            x:Name="DriverName"
                            Foreground="#F8FAFC"
                            FontSize="15"
                            FontWeight="SemiBold"
                            TextWrapping="Wrap"/>


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


            <Grid.RowDefinitions>

                <!-- PLUS DE PLACE AUX CARTES -->

                <RowDefinition Height="1.5*"/>

                <RowDefinition Height="12"/>

                <RowDefinition Height="*"/>

            </Grid.RowDefinitions>


            <!-- =================================================
                 TOUTES LES CARTES
                 ================================================= -->


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


            <!-- =================================================
                 ERREURS
                 ================================================= -->


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
    New-Object `
    System.Xml.XmlNodeReader `
    $XAML


$Window =
    [Windows.Markup.XamlReader]::Load(
        $Reader
    )


# ============================================================
# DONNEES GENERALES
# ============================================================

$Window.FindName(
    "ComputerName"
).Text =
    $Data.ComputerName


$Window.FindName(
    "UserName"
).Text =
    $Data.UserName


$Window.FindName(
    "IPAddress"
).Text =
    $Data.IP


# ============================================================
# CARTE ACTIVE
# ============================================================

$Window.FindName(
    "AdapterName"
).Text =
    $Data.AdapterName


$Window.FindName(
    "Chipset"
).Text =
    $Data.Chipset


$Window.FindName(
    "LinkSpeed"
).Text =
    $Data.LinkSpeed


$Window.FindName(
    "MacAddress"
).Text =
    $Data.MacAddress


$Window.FindName(
    "Gateway"
).Text =
    $Data.Gateway


$Window.FindName(
    "DNS"
).Text =
    $Data.DNS


# ============================================================
# PILOTE
# ============================================================

$Window.FindName(
    "DriverName"
).Text =
    $Data.DriverName


$Window.FindName(
    "DriverManufacturer"
).Text =
    $Data.DriverManufacturer


$Window.FindName(
    "DriverDate"
).Text =
    $Data.DriverDate


$Window.FindName(
    "DriverInf"
).Text =
    $Data.DriverInf


# ============================================================
# CARTES
# ============================================================

$Window.FindName(
    "AdapterGrid"
).ItemsSource =
    @($Data.AdapterList)


# ============================================================
# EVENEMENTS
# ============================================================

$Window.FindName(
    "EventGrid"
).ItemsSource =
    @($Data.Events)


$EventNumber =
    @($Data.Events).Count


if ($EventNumber -eq 0) {

    $Window.FindName(
        "EventCount"
    ).Text =

        "Aucune erreur réseau détectée sur les 7 derniers jours."

}
elseif ($EventNumber -eq 1) {

    $Window.FindName(
        "EventCount"
    ).Text =

        "1 erreur réseau détectée sur les 7 derniers jours."

}
else {

    $Window.FindName(
        "EventCount"
    ).Text =

        "$EventNumber erreurs réseau détectées sur les 7 derniers jours."
}


# ============================================================
# ETAT GLOBAL
# ============================================================

$GlobalStatus =
    $Window.FindName(
        "GlobalStatus"
    )


if (
    $Data.AdapterStatus -eq
    "Up"
) {

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
# FERMETURE
# ============================================================

$CloseButton =
    $Window.FindName(
        "CloseButton"
    )


$CloseButton.Add_Click({

    $Window.Close()

})


# ============================================================
# AFFICHAGE
# ============================================================

$Window.ShowDialog() |
    Out-Null