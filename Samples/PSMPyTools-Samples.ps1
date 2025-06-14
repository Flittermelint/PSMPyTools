
#region Import-Module

    Import-Module PSMPyTools -Force

    Get-Command -Module PSMPyTools

break

#endregion

#region Demo > Board & Firmware

                   Open-MPyWebSite

                   Find-MPyBoard | ? Product -like "ESP32*S3"              | Tee -Variable Board    | Open-MPyWebSite

    $Board    |    Find-MPyFirmware -State Release -Variant SPIRAM -Latest | Tee -Variable Firmware | Open-MPyWebSite -Notes

    $Firmware |     Get-MPyFirmware -ReUse -Verbose | Get-ChildItem

    $Firmware | Install-MPyFirmware        -Verbose
    
                  Start-Thonny

break

#endregion

#region Demo > Device / Port

       Find-MPyDevice  -Verbose

        Get-MPyDeviceDetails | ConvertTo-Json

       Copy-MPyItem -FromPath (Get-MPySample enhanced-boot.py) -ToMPy "/boot.py"
       Copy-MPyItem -FromPath (Get-MPySample original-boot.py) -ToMPy "/boot.py"

    Restart-MPyDevice  -PassThru

       Stop-MPyProcess -PassThru

break

#endregion

#region Tip > install latest release

    "ESP32_GENERIC_S3" |

       Find-MPyFirmware -Verbose -Variant SPIRAM -State Release -Latest |
        Get-MPyFirmware -Verbose -ReUse |
    Install-MPyFirmware -Verbose
    
      Start-Thonny

    "ESP32_GENERIC_S3" | Find-MPyFirmware -Verbose -Cache | Install-MPyFirmware -Verbose

break

#endregion

#region Tip > install latest preview

    "ESP32_GENERIC_S3" |

       Find-MPyFirmware -Verbose -Variant SPIRAM -State Preview -Latest |
        Get-MPyFirmware -Verbose -ReUse |
    Install-MPyFirmware -Verbose
    
      Start-Thonny

break

#endregion

#region 

    Get-MPyChildItem -Path "/" -Recurse -PassThru

break

    Get-MPyContent -Path "boot-xxx.py" -PassThru
    Get-MPyContent -Path "test.py"
    Get-MPyContent -Path "A-Team.txt"

break

    Out-MPyFile -Path "A-Teamx.txt" -Data 'print("Ich liebe es, wenn ein Plan funktioniert ;-)"'

break

    Copy-MPyItem -FromMPy "/boot.py"   -ToPath ".\boot.py"    -PassThru

    Copy-MPyItem -FromPath ".\boot.py" -ToMPy  "/boot-xxx.py" -PassThru

break

    New-MPyPath -Path "NewDirFromPowershell"

break

    Remove-MPyItem -Path "test.py"
    Remove-MPyItem -Path "/empty"
    Remove-MPyItem -Path "NewDirFromPowershell"

break

#endregion
