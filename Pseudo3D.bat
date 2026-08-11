@echo off
setlocal EnableExtensions

mode con cols=120 lines=40 >nul 2>&1
chcp 65001 >nul 2>&1

set "PSFILE=%TEMP%\CommandLineFPS_%RANDOM%_%RANDOM%.ps1"

for /f "tokens=1 delims=:" %%L in ('findstr /n /b ":POWERSHELL" "%~f0"') do (
    more +%%L "%~f0" > "%PSFILE%"
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%PSFILE%"
set "EXITCODE=%ERRORLEVEL%"

del "%PSFILE%" >nul 2>&1
exit /b %EXITCODE%


:POWERSHELL
$ErrorActionPreference = 'Stop'

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class NativeKeyboard
{
    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    public static bool Down(int key)
    {
        return (GetAsyncKeyState(key) & unchecked((short)0x8000)) != 0;
    }
}
"@

$nScreenWidth  = 120
$nScreenHeight = 40

$nMapWidth  = 16
$nMapHeight = 16

[double]$fPlayerX = 12.41
[double]$fPlayerY = 11.09
[double]$fPlayerA = -1.52
[double]$fFOV     = [Math]::PI / 4.0
[double]$fDepth   = 16.0
[double]$fSpeed   = 5.0

$mapRows = @(
    "################"
    "#..............#"
    "#.......########"
    "#..............#"
    "#......##......#"
    "#......##......#"
    "#..............#"
    "###............#"
    "##.............#"
    "#......####..###"
    "#......#.......#"
    "#......#.......#"
    "#..............#"
    "#......#########"
    "#..............#"
    "################"
)

$map = $mapRows -join ''

function Test-Wall([int]$x, [int]$y)
{
    if ($x -lt 0 -or $x -ge $script:nMapWidth -or
        $y -lt 0 -or $y -ge $script:nMapHeight)
    {
        return $true
    }

    return $script:map[$x * $script:nMapWidth + $y] -eq '#'
}

function Set-ScreenChar(
    [char[]]$screen,
    [int]$x,
    [int]$y,
    [char]$value
)
{
    if ($x -ge 0 -and $x -lt $script:nScreenWidth -and
        $y -ge 0 -and $y -lt $script:nScreenHeight)
    {
        $screen[$y * $script:nScreenWidth + $x] = $value
    }
}

try {
    [Console]::CursorVisible = $false
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::Clear()
}
catch {
}

$screen = New-Object char[] ($nScreenWidth * $nScreenHeight)

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$previousTime = $stopwatch.Elapsed.TotalSeconds
$running = $true

while ($running)
{
    $currentTime = $stopwatch.Elapsed.TotalSeconds
    [double]$fElapsedTime = $currentTime - $previousTime
    $previousTime = $currentTime

    if ($fElapsedTime -le 0) {
        $fElapsedTime = 0.016
    }
    if ($fElapsedTime -gt 0.25) {
        $fElapsedTime = 0.25
    }

    if ([NativeKeyboard]::Down(0x1B) -or [NativeKeyboard]::Down(0x51)) {
        $running = $false
        break
    }

    if ([NativeKeyboard]::Down(0x41)) {
        $fPlayerA -= ($fSpeed * 0.75) * $fElapsedTime
    }

    if ([NativeKeyboard]::Down(0x44)) {
        $fPlayerA += ($fSpeed * 0.75) * $fElapsedTime
    }

    [double]$sinA = [Math]::Sin($fPlayerA)
    [double]$cosA = [Math]::Cos($fPlayerA)

    if ([NativeKeyboard]::Down(0x57)) {
        [double]$oldX = $fPlayerX
        [double]$oldY = $fPlayerY

        $fPlayerX += $sinA * $fSpeed * $fElapsedTime
        $fPlayerY += $cosA * $fSpeed * $fElapsedTime

        if (Test-Wall ([int]$fPlayerX) ([int]$fPlayerY)) {
            $fPlayerX = $oldX
            $fPlayerY = $oldY
        }
    }

    if ([NativeKeyboard]::Down(0x53)) {
        [double]$oldX = $fPlayerX
        [double]$oldY = $fPlayerY

        $fPlayerX -= $sinA * $fSpeed * $fElapsedTime
        $fPlayerY -= $cosA * $fSpeed * $fElapsedTime

        if (Test-Wall ([int]$fPlayerX) ([int]$fPlayerY)) {
            $fPlayerX = $oldX
            $fPlayerY = $oldY
        }
    }

    for ($i = 0; $i -lt $screen.Length; $i++) {
        $screen[$i] = ' '
    }

    for ($x = 0; $x -lt $nScreenWidth; $x++)
    {
        [double]$fRayAngle =
            ($fPlayerA - $fFOV / 2.0) +
            (($x / [double]$nScreenWidth) * $fFOV)

        [double]$fStepSize = 0.1
        [double]$fDistanceToWall = 0.0
        [bool]$bHitWall = $false
        [bool]$bBoundary = $false

        [double]$fEyeX = [Math]::Sin($fRayAngle)
        [double]$fEyeY = [Math]::Cos($fRayAngle)

        while (-not $bHitWall -and $fDistanceToWall -lt $fDepth)
        {
            $fDistanceToWall += $fStepSize

            [int]$nTestX = [int]($fPlayerX + $fEyeX * $fDistanceToWall)
            [int]$nTestY = [int]($fPlayerY + $fEyeY * $fDistanceToWall)

            if ($nTestX -lt 0 -or $nTestX -ge $nMapWidth -or
                $nTestY -lt 0 -or $nTestY -ge $nMapHeight)
            {
                $bHitWall = $true
                $fDistanceToWall = $fDepth
                break
            }

            if ($map[$nTestX * $nMapWidth + $nTestY] -eq '#')
            {
                $bHitWall = $true

                $corners = New-Object System.Collections.Generic.List[object]

                for ($tx = 0; $tx -lt 2; $tx++)
                {
                    for ($ty = 0; $ty -lt 2; $ty++)
                    {
                        [double]$vy = $nTestY + $ty - $fPlayerY
                        [double]$vx = $nTestX + $tx - $fPlayerX
                        [double]$distance = [Math]::Sqrt($vx * $vx + $vy * $vy)

                        if ($distance -gt 0.0) {
                            [double]$dot =
                                ($fEyeX * $vx / $distance) +
                                ($fEyeY * $vy / $distance)

                            if ($dot -gt 1.0)  { $dot = 1.0 }
                            if ($dot -lt -1.0) { $dot = -1.0 }

                            [double]$angle = [Math]::Acos($dot)
                            [void]$corners.Add([PSCustomObject]@{
                                Distance = $distance
                                Angle    = $angle
                            })
                        }
                    }
                }

                $corners = @($corners | Sort-Object Distance)

                $boundaryLimit = 0.01
                $checkCount = [Math]::Min(3, $corners.Count)

                for ($i = 0; $i -lt $checkCount; $i++) {
                    if ($corners[$i].Angle -lt $boundaryLimit) {
                        $bBoundary = $true
                    }
                }
            }
        }

        [int]$nCeiling =
            [Math]::Floor(($nScreenHeight / 2.0) -
                          ($nScreenHeight / $fDistanceToWall))

        [int]$nFloor = $nScreenHeight - $nCeiling

        [char]$wallShade = ' '

        if ($fDistanceToWall -le ($fDepth / 4.0)) {
            $wallShade = [char]0x2588
        }
        elseif ($fDistanceToWall -lt ($fDepth / 3.0)) {
            $wallShade = [char]0x2593
        }
        elseif ($fDistanceToWall -lt ($fDepth / 2.0)) {
            $wallShade = [char]0x2592
        }
        elseif ($fDistanceToWall -lt $fDepth) {
            $wallShade = [char]0x2591
        }

        if ($bBoundary) {
            $wallShade = "|"
        }

        for ($y = 0; $y -lt $nScreenHeight; $y++)
        {
            if ($y -le $nCeiling)
            {
                $screen[$y * $nScreenWidth + $x] = ' '
            }
            elseif ($y -le $nFloor)
            {
                $screen[$y * $nScreenWidth + $x] = $wallShade
            }
            else
            {
                [double]$b =
                    1.0 - (($y - $nScreenHeight / 2.0) /
                           ($nScreenHeight / 2.0))

                [char]$floorShade = ' '

                if ($b -lt 0.25) {
                    $floorShade = '#'
                }
                elseif ($b -lt 0.5) {
                    $floorShade = 'x'
                }
                elseif ($b -lt 0.75) {
                    $floorShade = '.'
                }
                elseif ($b -lt 0.9) {
                    $floorShade = '-'
                }

                $screen[$y * $nScreenWidth + $x] = $floorShade
            }
        }
    }

    [double]$fps = 1.0 / $fElapsedTime
    $stats = "X={0,6:N2}, Y={1,6:N2}, A={2,6:N2} FPS={3,6:N2}" -f `
             $fPlayerX, $fPlayerY, $fPlayerA, $fps

    for ($i = 0; $i -lt $stats.Length -and $i -lt $nScreenWidth; $i++) {
        $screen[$i] = $stats[$i]
    }

    for ($nx = 0; $nx -lt $nMapWidth; $nx++)
    {
        for ($ny = 0; $ny -lt $nMapHeight; $ny++)
        {
            $screen[($ny + 1) * $nScreenWidth + $nx] =
                $map[$ny * $nMapWidth + $nx]
        }
    }

    [int]$playerMapX = [int]$fPlayerX
    [int]$playerMapY = [int]$fPlayerY

    if ($playerMapX -ge 0 -and $playerMapX -lt $nMapHeight -and
        $playerMapY -ge 0 -and $playerMapY -lt $nMapWidth)
    {
        $screen[($playerMapX + 1) * $nScreenWidth + $playerMapY] = 'P'
    }

    try {
        [Console]::SetCursorPosition(0, 0)
    }
    catch {
    }

    $builder = New-Object System.Text.StringBuilder

    for ($row = 0; $row -lt $nScreenHeight; $row++)
    {
        [void]$builder.Append(
            $screen,
            $row * $nScreenWidth,
            $nScreenWidth
        )

        if ($row -lt ($nScreenHeight - 1)) {
            [void]$builder.Append("`n")
        }
    }

    [Console]::Write($builder.ToString())
}

try {
    [Console]::CursorVisible = $true
    [Console]::SetCursorPosition(0, $nScreenHeight - 1)
}
catch {
}

exit 0