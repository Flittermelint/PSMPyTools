
if($PSScriptRoot)  { $thisScriptRoot  = $PSScriptRoot  }
if($PSCommandPath) { $thisCommandPath = $PSCommandPath }

$Script:ModuleItem = Get-Item $thisCommandPath

$Script:ModuleName = $Script:ModuleItem.BaseName

#region State

$Script:State = [PSCustomObject]@{

    ModuleName = $Script:ModuleName
    ModuleItem = $Script:ModuleItem
}

$Script:State | Add-Member -Force -MemberType   NoteProperty -Name MPyBoard    -Value ([ordered]@{})
$Script:State | Add-Member -Force -MemberType   NoteProperty -Name MPyFirmware -Value ([ordered]@{})

$Script:State | Add-Member -Force -MemberType   NoteProperty -Name PnPEntity   -Value   $null
$Script:State | Add-Member -Force -MemberType ScriptProperty -Name MPyDevice   -Value { $this.PnPEntity.MPyDevice }
$Script:State | Add-Member -Force -MemberType ScriptProperty -Name SerialPort  -Value { $this.PnPEntity.MPyDevice.SerialPort }
$Script:State | Add-Member -Force -MemberType ScriptProperty -Name PortName    -Value { $this.PnPEntity.MPyDevice.SerialPort.PortName }
$Script:State | Add-Member -Force -MemberType ScriptProperty -Name IsOpen      -Value { $this.PnPEntity.MPyDevice.SerialPort.IsOpen }

function Get-MPyState
{
    $Script:State
}

#endregion

function Get-MPySample
{
    [CmdletBinding()]
    param(
        [string]$Name = "*.py"
    )

    Get-ChildItem -Path "$($Script:ModuleItem.DirectoryName)\Python\$($Name)" -File
}

function Get-MPyUri
{
    [CmdletBinding()]
    param(
        [string]$Path
    )

    "https://micropython.org/$($Path)".TrimEnd("/")
}

function Get-MPyDownloadUri
{
    [CmdletBinding()]
    param(
        [string]$Board
    )

    Get-MPyUri -Path "download/$($Board)"
}

function Open-MPyWebSite
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][string]$Board,
        [Parameter()]                                                 [switch]$Notes,
        [Parameter(ValueFromPipeline)]                                [object]$InputObject
    )

    if($Notes -and $InputObject.NotesUri)
    {
        Start-Process -Verb Open -FilePath $InputObject.NotesUri
    }    
    else
    {
        Start-Process -Verb Open -FilePath (Get-MPyDownloadUri -Board $Board)
    }
}

function Find-MPyBoard
{
    [CmdletBinding()]
    param(
        [switch]$AsDictionary,
        [switch]$Force
    )

    if($Force -or ($Script:State.MPyBoard.Count -eq 0))
    {
        $WebSite = Invoke-WebRequest -Uri (Get-MPyDownloadUri)

        $Lines = $WebSite.RawContent.Substring($WebSite.RawContent.IndexOf('<a class="board-card" href="')).Split([System.Environment]::NewLine) | ForEach-Object Trim | Where-Object { $_ }

        $Script:State.MPyBoard = [ordered]@{}

        foreach($Line in $Lines)
        {
            switch -Regex ($Line)
            {
                '^<footer>$'                                  { break }

                '^\<a class="board-card" href="(.*)"\>$'      { $Board = "" | Select-Object @{ Name = "Board"; Expression = { $Matches[1] } }, Product, Vendor, ImageUri }

                '^\<img src="(.*)"\>'                         { $Board.ImageUri = $Matches[1] }
                '^\<div class="board-product"\>(.*)\</div\>$' { $Board.Product  = $Matches[1] }
                '^\<div class="board-vendor"\>(.*)\</div\>$'  { $Board.Vendor   = $Matches[1]; $Script:State.MPyBoard[$Board.Board] = $Board }
            }
        }
    }

    switch($AsDictionary)
    {
        $true  { $Script:State.MPyBoard        }
        $false { $Script:State.MPyBoard.Values }
    }
}

function Find-MPyFirmware
{
    [CmdletBinding(DefaultParameterSetName="Online")]
    param(
        [Parameter(ParameterSetName="Online")]
        [Parameter()]                                                           [switch]$Online,

        [Parameter(ParameterSetName="Cache" )]
        [Parameter()]                                                           [switch]$Cache,

        [Parameter(ParameterSetName="Online")]
        [Parameter(ParameterSetName="Cache" )]
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)][string]$Board,

        [Parameter(ParameterSetName="Online")]
        [Parameter(ParameterSetName="Cache" )]
        [Parameter()]                                                           [string]$Variant,

        [Parameter(ParameterSetName="Online")]
        [Parameter(ParameterSetName="Cache" )]
        [Parameter()]                         [ValidateSet("Release","Preview")][string]$State = "Release",

        [Parameter(ParameterSetName="Online")]
        [Parameter()]                                                           [switch]$Latest,

        [Parameter(ParameterSetName="Online")]
        [Parameter()]                                                           [switch]$AsDictionary,

        [Parameter(ParameterSetName="Online")]
        [Parameter()]                                                           [switch]$Force
    )

    $MyInvocationName = $MyInvocation.MyCommand.Name

    switch($PSCmdlet.ParameterSetName)
    {
        "Online" {

            if($Force -or (-not $Script:State.MPyFirmware[$Board]))
            {
                $Script:State.MPyFirmware[$Board] = Invoke-WebRequest -Uri (Get-MPyDownloadUri -Board $Board)
            }

            $WebSite = $Script:State.MPyFirmware[$Board]

            $FirmwareCollection = [ordered]@{}

            $Lines = $WebSite.RawContent.Substring($WebSite.RawContent.IndexOf("<h2>Firmware")).Split([System.Environment]::NewLine) | ForEach-Object Trim | Where-Object { $_ }

            foreach($Line in $Lines)
            {
                switch -Regex ($Line)
                {
                    '^<footer>$' { break }

                    '^\<div\>$' {
            
                        $Firmware = "" | Select-Object @{ Name = "Board"; Expression = { $Board } }, Variant, State, Version, Date, Uri, NotesUri

                        $Collect = $true
                     }

                    '^\<h2\>Firmware(.*)\<\/h2\>$' {
            
                        $Firmware_Variant = if($Matches[1]) { $Matches[1].Trim([char[]]" ()") }  else { "Default" }

                        $FirmwareCollection[$Firmware_Variant] = [ordered]@{}
                    }

                    '^\<h3\>(.*)\<\/h3\>$' {
            
                        $Firmware_State = ($Matches[1].Split(" ") | Select-Object -First 1).Trim("s")
                
                        $FirmwareCollection[$Firmware_Variant][$Firmware_State] = [ordered]@{}
                    }

                    '^\<\/div\>$' {

                        if($Collect)
                        {
                            if((-not $Variant) -or ($Firmware_Variant -match $Variant))
                            {
                                if((-not $State) -or ($Firmware_State -eq $State))
                                {
                                    if((-not $Latest) -or (($FirmwareCollection[$Firmware_Variant][$Firmware_State].Count -eq 0)))
                                    {
                                        $FirmwareCollection[$Firmware_Variant][$Firmware_State][$Firmware.Version] = $Firmware

                                        if(-not $AsDictionary) { $Firmware }
                                    }
                                }
                            }

                            $Collect = $false
                        }
                    }

                    '\<a href="(.*)"\>(.*)\<\/a\>$' {

                        $href      = $Matches[1]
                        $textAll   = $Matches[2].Trim([char[]]"[].").Split(' ')
                        $textSplit = $textAll

                        switch -Wildcard ($textAll)
                        {
                            "v*"     { $Firmware.Version  = $textSplit[0]
                                       $Firmware.Date     = $textSplit[1].Trim([char[]]"()") }
                            "*bin"   { $Firmware.Uri      = "https://micropython.org$href" }
                            "*notes" { $Firmware.NotesUri = $href }
                        }

                        $Firmware.Variant = $Firmware_Variant
                        $Firmware.State   = $Firmware_State  
                    }
                }
            }
            
            if($AsDictionary) { $FirmwareCollection }
        }

        "Cache" {

            $StateFilter = switch($State)
            {
                Release {}

                Preview { "-$($State).*" }
            }

            $FirmwareFilter = "$($env:TEMP)\MPyFirmware\$($Board)-*$($Variant)*-????????-v?.??.?$($StateFilter).bin"

            Write-Verbose "$($MyInvocationName): $FirmwareFilter"

            Get-ChildItem -Path $FirmwareFilter
        }
    }
}

function Get-MPyFirmware
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][string]$Uri,
        [Parameter()]                                                 [string]$OutPath,
        [Parameter(ValueFromPipeline)]                                [object]$InputObject,
        [Parameter()]                                                 [switch]$ReUse
    )

    $MyInvocationName = $MyInvocation.MyCommand.Name

    if(-not $OutPath)
    {
        [void](mkdir ($OutPath = "$($env:TEMP)\MPyFirmware") -ErrorAction SilentlyContinue)

        $OutPath = "$OutPath\{0}"
    }

    $OutPath = $OutPath -f (Split-Path $uri -Leaf)

    Write-Verbose "$($MyInvocationName): $('Uri({0})'     -f $Uri)"
    Write-Verbose "$($MyInvocationName): $('OutPath({0})' -f $OutPath)"

    if($ReUse -and (Test-Path -Path $OutPath -PathType Leaf))
    {
    }
    else
    {
        Invoke-WebRequest -Uri $Uri -OutFile $OutPath
    }

    if(Test-Path -Path $OutPath -PathType Leaf)
    {
        if($OutPath -like "*.zip")
        {
            $OutItem = Get-Item -Path $OutPath

            $DestinationPath = "$($OutItem.DirectoryName)\$($OutItem.BaseName)"

            Write-Verbose "$($MyInvocationName): DestinationPath($($DestinationPath))"

            Remove-Item -Path $DestinationPath -Recurse -ErrorAction SilentlyContinue

            Expand-Archive -Path $OutPath -DestinationPath $DestinationPath

            $OutPath = Get-ChildItem -Path "$DestinationPath\*.bin" -Recurse -File
        }

        Write-Verbose "$($MyInvocationName): OutPath($($OutPath))"

        if($InputObject.Uri)
        {
            $InputObject | Add-Member -MemberType NoteProperty -Name Path -Value $OutPath -Force -PassThru
        }
        else
        {
            $OutPath
        }
    }
}

function Start-Thonny
{
    Start-Process -FilePath "C:\Program Files\Thonny\thonny.exe"
}

function Start-ProcessWithProgress
{
    [CmdLetBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$FilePath,
        [Parameter(Mandatory=$false)]                         [string]$ArgumentList,
        [Parameter(Mandatory=$false)]                         [string]$Verb
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($FilePath, $ArgumentList)

    $startInfo.CreateNoWindow         = $true
    $startInfo.UseShellExecute        = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError  = $true

    $process = [System.Diagnostics.Process]::new()

    $process.StartInfo           = $startInfo
    $process.EnableRaisingEvents = $true

    $global:Progress = [PSCustomObject]@{
    
        Activity = ""
    }

    $dataReceived = {

        if($EventArgs.Data)
        {
            if($EventArgs.Data -match "(\d*)%")
            {
                Write-Progress -Activity $global:Progress.Activity -PercentComplete $Matches[1] -Status "$($Matches[1])% Complete"
            }
            else
            {
                $global:Progress.Activity = $EventArgs.Data

                Write-Progress -Activity $global:Progress.Activity -PercentComplete 0
            }
        }
    }

    $eventStdOut = Register-ObjectEvent -InputObject $process -Action $dataReceived -EventName 'OutputDataReceived'
    $eventStdErr = Register-ObjectEvent -InputObject $process -Action $dataReceived -EventName  'ErrorDataReceived'

    [void]$process.Start()

    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    do
    {
        sleep -Milliseconds 10
    }
    until($process.HasExited)

    [void]$process.WaitForExit()

    Unregister-Event -SourceIdentifier $eventStdOut.Name
    Unregister-Event -SourceIdentifier $eventStdErr.Name
}

function Install-MPyFirmware
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]               [string]$Path, # [Alias("FullName")]
        [Parameter(                            ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName
    )

    $MyInvocationName = $MyInvocation.MyCommand.Name

    if($MPyDevice = $PortName | Get-MPyPnPEntity)
    {
        if(Test-Path -Path $Path -PathType Leaf)
        {
            $runThis = @{

                FilePath     = "$thisScriptRoot\bin\esplink.exe"
                ArgumentList = '{0} "{1}" {2}' -f $MPyDevice.PortName, $Path, "0x00000000"
            }

            Write-Verbose "$($MyInvocationName): $($runThis.FilePath) $($runThis.ArgumentList)"

            Start-ProcessWithProgress @runThis
        }
    }
}

class MPyDevice
{
<#
    ox https://github.com/scientifichackers/ampy/blob/master/ampy/pyboard.py
#>
    [object]$PnPEntity

    [System.IO.Ports.SerialPort]$SerialPort

    [int32]$BufferSize = 64

    [bool]$Verbose = $false

    MPyDevice( [object]$PnPEntity)                   { $this.Init($PnPEntity, 115200   ) }
    MPyDevice( [object]$PnPEntity, [int32]$BaudRate) { $this.Init($PnPEntity, $BaudRate) }

    [void]Init([object]$PnPEntity, [int32]$BaudRate)
    {
        $this.PnPEntity  = $PnPEntity

        $this.SerialPort = [System.IO.Ports.SerialPort]::new($this.PnPEntity.PortName, $BaudRate)
    }

    [string]ToString() { return $this.PnPEntity.InstanceID }

    [void]Write([string]$Text) { $this.SerialPort.Write($Text) }

    [bool]IsOpen() { return $this.SerialPort.IsOpen  }
    [void]  Open() {        $this.SerialPort.Open()  }
    [void] Close() {        $this.SerialPort.Close() }

    [string]ReadExisting() { return $this.SerialPort.ReadExisting() }

    hidden [PSCustomObject]$ExpectedResponse = [PSCustomObject]@{

        "A" = "raw REPL; CTRL-B to exit`r`n>"                         # Ctrl-A: SOH > start of heading    > enter raw repl
        "B" = ">>>"                                                   # Ctrl-B: STX > start of text       > exit  raw repl
        "C" = $null                                                   # Ctrl-C: ETX > end of text         > stop running program
        "D" = "MPY: soft reboot`r`n"                                  # Ctrl-D: EOT > end of transmission > soft reboot
        "E" = "paste mode; Ctrl-C to cancel, Ctrl-D to finish`r`n===" # Ctrl-E: ENQ > enquiry             > paste mode
    }

    [void]EnterRawRepl()
    {
        if(-not $this.SerialPort.IsOpen) { $this.Open() }

        $this.Ctrl("C", 5) # 2 for simple ESP32, 5 for Elecrow display
        $this.Ctrl("A", 4, $this.ExpectedResponse.A)
        $this.Ctrl("D", 1, $this.ExpectedResponse.D)
        $this.Ctrl("C", 2) # 2 for simple ESP32, 5 for Elecrow display
    }

    [void]ExitRawRepl()
    {
        $this.Ctrl("B", 1, $this.ExpectedResponse.B)

        $this.Close()
    }

    [void]EnterPasteMode()
    {
        if(-not $this.SerialPort.IsOpen) { $this.Open() }

        $this.Ctrl("E", 1, $this.ExpectedResponse.E)
    }

    [void]FinishPasteMode()
    {
        $this.Ctrl("D", 1, "`r`n>>>")

        $this.Close()
    }

    [void]CancelPasteMode()
    {
        $this.Ctrl("C", 2)

        $this.Close()
    }

    [void]Ctrl([string]$Key) { $this.SerialPort.Write([char[]]@(," ABCDE".IndexOf($Key)), 0, 1) }

    [void]Ctrl([string]$Key, [int]$MaxTries) { $this.Ctrl($Key, $MaxTries, $null) }

    [void]Ctrl([string]$Key, [int]$MaxTries, [string]$ExpectedResponse)
    {
        $Expected = $ExpectedResponse.Replace("`r`n",'`r`n')

        $Response = ""

        foreach($zz in (1..$MaxTries))
        {
            $this.SerialPort.Write([char[]]@(," ABCDE".IndexOf($Key)), 0, 1)
        
            sleep -Milliseconds 200
        
            $Response = $this.ReadExisting().Trim(" ").Replace("`r`n",'`r`n')

            $ValidResponse = . {

                if($Expected)
                {
                    $Response.IndexOf($Expected, [System.StringComparison]::OrdinalIgnoreCase) -ne -1
                }
                else
                {
                    $true
                }
            }

            if($this.Verbose)
            {
                Write-Host "Ctrl($Key) $zz/$MaxTries Valid($("➖✔"[$ValidResponse])) Expected($Expected) Response($Response)"
            }

            if($Expected)
            {
                if($ValidResponse)
                {
                    return
                }
            }
            elseif($zz -eq $MaxTries)
            {
                return
            }
        }

        $this.Close()

        throw [System.Exception]::new("Sent Ctrl($Key) received($($Response)) but expected($($Expected))")
    }

    [object]Execute([string]$Command)
    {
        for($zz = 0; $zz -lt $Command.Length; $zz += $this.BufferSize)
        {
            try
            {
                $this.SerialPort.Write($Command.Substring($zz, $this.BufferSize))
            }
            catch
            {
                try
                {
                    $this.SerialPort.Write($Command.Substring($zz))
                }
                catch
                {
                }
            }

            sleep -Milliseconds 10
        }

        $this.Ctrl("D")

        sleep -Milliseconds 500

        $Response = $this.SerialPort.ReadExisting()

        $Response -match "(?smi)(?<OK>..)(?<Result>.*?)$([char]0x04)(?<Error>.*?)$([char]0x04)`>"

        return [PSCustomObject]@{

            OK        = $Matches.OK
            Result    = $Matches.Result
            Error     = $Matches.Error
            Raw       = $Response
            Exception = ( . { if($Matches.Error) { [System.Exception]::new($Matches.Error) } } )
        }
    }
<#
    ox https://github.com/scientifichackers/ampy/blob/master/ampy/files.py
#>
    hidden [PSCustomObject]$Python = [PSCustomObject]@{

        GetMPyContent = @'
import sys
import ubinascii

with open("{0}", 'rb') as infile:
    while True:
        result = infile.read({1})
        if result == b'': break
        sys.stdout.write(ubinascii.hexlify(result))
'@

        OutMPyFile = @'
with open("{0}", "w") as file:
    file.write('''{1}''')
'@

        RemoveMPyItem = @'
try:
    import os
except ImportError:
    import uos as os

def RemoveDirectory(path, recurse=False):
    if recurse:
        os.chdir(path)
        for item in os.ilistdir():
            if (item[1] & (1<<15)) != 0: os.remove(item[0]) # 0x8000 = File
        for item in os.ilistdir():
            if (item[1] & (1<<14)) != 0: os.rmdir (item[0]) # 0x4000 = Directory
        os.chdir('..')
    os.rmdir(path)

def RemoveItem(path, recurse=False):
    mode = os.stat(path)
    isFile = (mode[0] & (1<<15)) != 0 # 0x8000 = File
    isDir  = (mode[0] & (1<<14)) != 0 # 0x4000 = Directory

    if isFile: os.remove('{0}')
    if isDir:  RemoveDirectory(path, recurse)

RemoveItem('{0}', {1})
'@

        NewMPyPath = @'
import re

try:
    import os
except ImportError:
    import uos as os

path = ""
for p in re.compile("[/]").split('{0}'.strip('/')):
    path += f"/{{p}}"
    try:
        os.mkdir(path)
    except OSError:
        pass
'@

        GetMPyChildItem = @'
import re

try:
    import os
except ImportError:
    import uos as os

def GetChildItem(path, recurse=False):
    try:
        path = ("/" + path.lstrip("/")).rstrip("/") + "/"
        for item in os.ilistdir(path):
            file   =  item[0]
            isFile = (item[1] & (1<<15)) != 0 # 0x8000 = File
            isDir  = (item[1] & (1<<14)) != 0 # 0x4000 = Directory
            size   =  item[3] if isFile else 0

            if isFile: print(f'{{{{ "Path": "{{path}}", "File": "{{file}}", "Size": {{size}} }}}}')
            if isDir:  print(f'{{{{ "Path": "{{path}}{{file}}/" }}}}')

            if isDir and recurse: GetChildItem(f'{{path}}{{file}}', recurse)
    except OSError:
        try:
            path = path.rstrip("/")
            mode = os.stat(path)
            isFile = (mode[0] & (1<<15)) != 0 # 0x8000 = File
            isDir  = (mode[0] & (1<<14)) != 0 # 0x4000 = Directory
            size   =  mode[6] if isFile else 0

            matches = re.match("(.*/)(.*)", path)
            path = matches.group(1)
            file = matches.group(2)

            if isFile: print(f'{{{{ "Path": "{{path}}", "File": "{{file}}", "Size": {{size}} }}}}')
            if isDir:  print(f'{{{{ "Path": "{{path}}{{file}}/" }}}}')

        except:
            pass

GetChildItem('{0}', {1})
'@

        RestartMPyDevice = @'
import machine
if {0}:
    machine.soft_reset()
else:
    machine.reset()
'@

        GetMPyDeviceDetails = @'
import sys
import uos
import platform as pf
import machine
import ubinascii

try:
    import lvgl as lv
    lvgl_version = "%d.%d.%d" % (lv.version_major(), lv.version_minor(), lv.version_patch())
    lvgl = f'''    "lvgl":      {{{{ "version":         "{{lvgl_version}}"
                 }}}},'''
except:
    lvgl = ""


uname           = uos.uname()                                     # print("uos.uname: %s"                % uname)
platform        = pf.platform()                                   # print("platform.platform: %s"        % platform)
libc_ver        = pf.libc_ver()                                   # print("platform.libc_ver: %s %s"     % libc_ver)
python_compiler = pf.python_compiler()                            # print("platform.python_compiler: %s" % python_compiler)
sys_version     = sys.version                                     # print("sys.version: %s"              % sys_version)
unique_id       = ubinascii.hexlify(machine.unique_id()).decode() # print("machine.unique_id: %s"        % unique_id)

print(f'''
{{{{
    "uname":     {{{{ "sysname":         "{{uname.sysname}}",
                   "nodename":        "{{uname.nodename}}",
                   "release":         "{{uname.release}}",
                   "version":         "{{uname.version}}",
                   "machine":         "{{uname.machine}}"
                 }}}},
    "plattform": {{{{ "platform":        "{{platform}}",
                   "libc_ver":        "{{libc_ver[0]}} {{libc_ver[1]}}",
                   "python_compiler": "{{python_compiler}}"
                 }}}},
    "sys":       {{{{ "version":         "{{sys_version}}"
                 }}}},
{{lvgl}}
    "machine":   {{{{ "unique_id":       "{{unique_id}}"
                 }}}}
}}}}
''')
'@
    }

    [object]GetMPyContent([string]$Path)
    {
        $this.EnterRawRepl()

        $out = $this.Execute(($this.Python.GetMPyContent -f ($Path, $this.BufferSize)))

        $this.ExitRawRepl()

        $out.Result = $this.Unhexlify($out.Result)

        return $out
    }

    [object]OutMPyFile([string]$Path, [string]$Data)
    {
        $this.EnterRawRepl()

        $out = $this.Execute(($this.Python.OutMPyFile -f ($Path, $Data)))

        $this.ExitRawRepl()

        return $out
    }

    [object]RemoveMPyItem([string]$Path, [switch]$Recurse)
    {
        $this.EnterRawRepl()

        $out = $this.Execute(($this.Python.RemoveMPyItem -f ($Path, $Recurse)))

        $this.ExitRawRepl()

        return $out
    }

    [object]NewMPyPath([string]$Path)
    {
        $this.EnterRawRepl()

        $out = $this.Execute(($this.Python.NewMPyPath -f ($Path)))

        $this.ExitRawRepl()

        return $out
    }

    [object]GetMPyChildItem([string]$Path, [switch]$Recurse)
    {
        $this.EnterRawRepl()

        $out = $this.Execute(($this.Python.GetMPyChildItem -f ($Path, $Recurse)))

        $this.ExitRawRepl()
        
        $out.Result = "[ $($out.Result.Split([char[]]"`r`n", [System.StringSplitOptions]::RemoveEmptyEntries) -join ',') ]" | ConvertFrom-Json

        return $out
    }

    [object]RestartMPyDevice([switch]$Soft)
    {
        $this.EnterRawRepl()

        $out = $this.Execute(($this.Python.RestartMPyDevice -f ($Soft)))

        if($Soft)
        {
            $this.ExitRawRepl()
        }
        else
        {
            # $this.ExitRawRepl() # >>> not necessary after restart / reboot

            $this.Close() # >>> required after restart / reboot instead of "$this.ExitRawRepl()" 
        }

        return $out
    }

    [object]GetMPyDeviceDetails()
    {
        $this.EnterRawRepl()

        $out = $this.Execute(($this.Python.GetMPyDeviceDetails -f ($null)))

        $this.ExitRawRepl()

        $out.Result = $out.Result | ConvertFrom-Json

        return $out
    }

    [string]Unhexlify([string]$HexString)
    {
        return (. { 

            for($zz = 0; $zz -lt $HexString.Length; $zz += 2)
            {
                [char]([Convert]::ToInt32($HexString.Substring($zz, 2), 16))
            }

        }) -join ""
    }
}

function Get-MPyPnPEntity
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter(                  ValueFromPipelineByPropertyName)]               [switch]$ToString
    )

    if($Script:State.PortName)
    {
        if($PortName -and ($PortName -ne $Script:State.PortName))
        {
            $Script:State.PnPEntity = $PortName | Find-MPyDevice
        }
    }
    else
    {
        $Script:State.PnPEntity = $PortName | Find-MPyDevice
    }

    $Script:State.PnPEntity
}

function Find-MPyDevice
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipelineByPropertyName,ValueFromPipeline)][Alias("Port")][string]$InstanceId
    )

    $MyInvocationName = $MyInvocation.MyCommand.Name

    $PortPattern = ".*\((?<PortName>COM\d{1,})\)"

    $PnPEntity = . {

        if($InstanceId -like "COM*")
        {
            Write-Verbose "$($MyInvocationName): by Port ($($InstanceId))"

            Get-PnpDevice -Class Ports -Status OK -FriendlyName "*($InstanceId)"
        }
        elseif($InstanceId)
        {
            Write-Verbose "$($MyInvocationName): by InstanceId ($($InstanceId))"

            Get-PnpDevice -Class Ports -Status OK -InstanceId "*$($InstanceId)*"
        }
        else
        {
            Write-Verbose "$($MyInvocationName): by FriendlyName & Manufacturer"

            Get-PnpDevice -Class Ports -Status OK -FriendlyName "USB*SERIAL*CH*(COM*)" | Where-Object Manufacturer -eq "wch.cn"
        }

    } | Where-Object Name -match $PortPattern | Select-Object -First 1

    if($PnPEntity.Name -match $PortPattern)
    {
        $PnPEntity | Add-Member -MemberType  NoteProperty -Name PortName  -Value $Matches.PortName
        $PnPEntity | Add-Member -MemberType AliasProperty -Name Port      -Value PortName
        $PnPEntity | Add-Member -MemberType  NoteProperty -Name MPyDevice -Value ([MPyDevice]::new($PnPEntity))
        $PnPEntity

        $Script:State.PnPEntity = $PnPEntity

        Write-Verbose "$($MyInvocationName): Found on PortName($($PnPEntity.PortName)) InstanceId($($PnPEntity.InstanceId))"
    }
}

function Stop-MPyProcess
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter()]                                                                [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        if(-not $PnPEntity.MPyDevice.IsOpen()) { $PnPEntity.MPyDevice.Open() }

        foreach($zz in (1..10))
        {
            $PnPEntity.MPyDevice.Ctrl("C")

            sleep -Milliseconds 50
        }

        $Response = $PnPEntity.MPyDevice.ReadExisting().Trim()

        $PnPEntity.MPyDevice.Close()

        if($Response.EndsWith(">>>"))
        {
            $result = [PSCustomObject]@{

                OK        = "OK"
                Result    = $Response
                Error     = ""
                Raw       = $Response
                Exception = $null
            }
        }
        else
        {
            $result = [PSCustomObject]@{

                OK        = ""
                Result    = ""
                Error     = $Response
                Raw       = $Response
                Exception = [System.Exception]::new($Response)
            }
        }

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
    }
}

function Get-MPyContent
{
    [CmdletBinding()]
    param(
        [Parameter(          ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]               [string]$Path,
        [Parameter()]                                                                          [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        $result = $PnPEntity.MPyDevice.GetMPyContent($Path)

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
        
        return $result.Result
    }
}

function Out-MPyFile
{
    [CmdletBinding()]
    param(
        [Parameter(          ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]               [string]$Path,
        [Parameter(Mandatory)]                                                                 [string]$Data,
        [Parameter()]                                                                          [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        $result = $PnPEntity.MPyDevice.OutMPyFile($Path, $Data)

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
    }
}

function Copy-MPyItem
{
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName="MPyToPC")]
        [Parameter(ParameterSetName="PCToMPy")]
        [Parameter(                           ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,

        [Parameter(ParameterSetName="MPyToPC",ValueFromPipeline,ValueFromPipelineByPropertyName,Mandatory)]     [string]$FromMPy,
        [Parameter(ParameterSetName="MPyToPC",ValueFromPipeline,ValueFromPipelineByPropertyName,Mandatory)]     [string]$ToPath,

        [Parameter(ParameterSetName="PCToMPy",ValueFromPipeline,ValueFromPipelineByPropertyName,Mandatory)]     [string]$FromPath,
        [Parameter(ParameterSetName="PCToMPy",ValueFromPipeline,ValueFromPipelineByPropertyName,Mandatory)]     [string]$ToMPy,

        [Parameter()]                                                                                           [switch]$PassThru
    )

    $MyInvocationName = $MyInvocation.MyCommand.Name

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        Write-Verbose "$($MyInvocationName): $($PnPEntity.PortName) > $($PnPEntity.InstanceID) > $($PSCmdlet.ParameterSetName)"

        switch($PSCmdlet.ParameterSetName)
        {
            "MPyToPC" {
            
                $result = $PnPEntity.MPyDevice.GetMPyContent($FromMpy)

                if(-not $result.Exception)
                {
                    Set-Content -Path $ToPath -Value $result.Result
                }
            } 

            "PCToMPy" {

                $Data = Get-Content -Path $FromPath -Raw
            
                $result = $PnPEntity.MPyDevice.OutMPyFile($ToMPy, $Data)
            }
        }

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
    }
}

function Remove-MPyItem
{
    [CmdletBinding()]
    param(
        [Parameter(          ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]               [string]$Path,
        [Parameter()]                                                                          [switch]$Recurse,
        [Parameter()]                                                                          [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        $result = $PnPEntity.MPyDevice.RemoveMPyItem($Path, $Recurse)

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
    }
}

function New-MPyPath
{
    [CmdletBinding()]
    param(
        [Parameter(          ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter(Mandatory,ValueFromPipeline,ValueFromPipelineByPropertyName)]               [string]$Path,
        [Parameter()]                                                                          [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        $result = $PnPEntity.MPyDevice.NewMPyPath($Path)

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
    }
}

function Get-MPyChildItem
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)]               [string]$Path,
        [Parameter()]                                                                [switch]$Recurse,
        [Parameter()]                                                                [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        $result = $PnPEntity.MPyDevice.GetMPyChildItem($Path, $Recurse)

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
        
        return $result.Result
    }
}

function Restart-MPyDevice
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter()]                                                                [switch]$Soft,
        [Parameter()]                                                                [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        $result = $PnPEntity.MPyDevice.RestartMPyDevice($Soft)

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
    }
}

function Get-MPyDeviceDetails
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter()]                                                                [switch]$PassThru
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        $result = $PnPEntity.MPyDevice.GetMPyDeviceDetails()

        if($PassThru)         { return $result }
        if($result.Exception) { throw  $result.Exception }
        
        return $result.Result
    }
}

function Invoke-MPyExpression
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]  $PortName,
        [Parameter()]                                                                [string[]]$Command,
        [Parameter()]                                                                [int]     $WaitMS4Result = 100
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        foreach($cmd in $Command)
        {
            $PnPEntity.MPyDevice.Write("$($cmd)$([char]0x0d)")
        }

        sleep -Milliseconds $WaitMS4Result

        $PnPEntity.MPyDevice.ReadExisting()
    }
}

function Invoke-MPyScript
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline,ValueFromPipelineByPropertyName)][Alias("Port")][string]$PortName,
        [Parameter()]                                                                [string]$Path,
        [Parameter()]                                                                [int]   $WaitMS4Result = 100
    )

    if($PnPEntity = $PortName | Get-MPyPnPEntity)
    {
        if(-not $Path.EndsWith(".py", [System.StringComparison]::OrdinalIgnoreCase)) { $Path += ".py" }

        $PnPEntity.MPyDevice.Write("execfile('$($Path)')$([char]0x0d)")

        sleep -Milliseconds $WaitMS4Result

        $PnPEntity.MPyDevice.ReadExisting()
    }
}

<#
    ox https://www.amazon.de/dp/B0DMN5T1GQ # Simple ESP32-S3 board
        USB-Enhanced-SERIAL CH343
        USB\VID_1A86&PID_55D3\595B066834
#>
