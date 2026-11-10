<#
Instala el .exe recién armado como lo haría una persona y prueba Trabajito Motor en esta computadora:
  1. instala en silencio (el mismo instalador por usuario que baja la persona, sin ventanas);
  2. revisa «Aplicaciones instaladas» (versión), el enlace trabajito-motor:// (con «URL Protocol», que
     Chrome y Edge necesitan) y el Supabase que trae;
  3. primera apertura, como desde el menú Inicio y sin enlace: tiene que mostrar su ventana;
  4. en frío: con el motor cerrado abre trabajito-motor://encender, que es lo que hace «Encender mi
     motor» en la web. Tiene que arrancar con el Supabase de su entorno y atender el enlace;
  5. en caliente: con el motor abierto, el mismo enlace lo tiene que atender ese mismo motor;
  6. lo cierra, revisa motor.log y lo desinstala en silencio (y revisa que también se borre el enlace).
Nunca inicia sesión ni toca WhatsApp. Solo para las computadoras de GitHub, que se borran al terminar:
cierra el motor a la fuerza.
Uso: pwsh -File ci-repo/ci/windows/probar-instalador.ps1 -Entorno prod|dev
#>
param(
  [Parameter(Mandatory = $true)][ValidateSet('prod', 'dev')][string]$Entorno
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# Los mismos datos que ci/comun.sh: si cambian, cambian en los dos.
$proyecto = @{ prod = 'qnroulkqbhhdnfctfooc'; dev = 'qtlugjtvbgiesphxwgwl' }[$Entorno]
$nombre = @{ prod = 'Trabajito-Motor-Setup.exe'; dev = 'Trabajito-Motor-Setup-DEV.exe' }[$Entorno]

$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$salida = Join-Path $raiz 'salida'
$instalador = Join-Path $salida $nombre
$version = (Get-Content -LiteralPath (Join-Path $salida 'version.txt') -Raw).Trim()
$datos = Join-Path $env:APPDATA 'Trabajito Motor'
$log = Join-Path $datos 'motor.log'
$lineaArranque = "Trabajito Motor $version (prod, proyecto $proyecto); WhatsApp real."
$lineaSinEnlace = 'Arranque sin enlace: se muestra la ventana.'
$lineaEncender = 'Encender: se muestra la ventana.'
$enlace = "trabajito-motor://encender?proyecto=$proyecto"
$version_so = [System.Environment]::OSVersion.Version
$arquitectura = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()
$equipo = "Windows $version_so ($arquitectura)"
$captura = Join-Path $salida ("windows-{0}-{1}-{2}" -f $version_so, $arquitectura, $Entorno)

function Titulo([string]$texto) { Write-Host ''; Write-Host "== $texto ==" }
function Aviso([string]$texto) { Write-Host $texto }
function Falla([string]$texto) { Write-Host "::error::$texto"; throw $texto }
function Resumen([string]$texto) {
  if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $texto -Encoding utf8 }
}

function Tamano-Log { if (Test-Path -LiteralPath $log) { (Get-Item -LiteralPath $log).Length } else { 0 } }

# Lo escrito en motor.log después de «desde» (bytes), sin bloquear al motor, que lo tiene abierto.
function Lineas-Desde([long]$desde) {
  if (-not (Test-Path -LiteralPath $log)) { return '' }
  $fs = [System.IO.File]::Open($log, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
  try {
    [void]$fs.Seek([Math]::Min($desde, $fs.Length), [System.IO.SeekOrigin]::Begin)
    return (New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)).ReadToEnd()
  } finally { $fs.Dispose() }
}

function Esperar-Linea([long]$desde, [string]$texto, [int]$segundos) {
  $limite = (Get-Date).AddSeconds($segundos)
  while ((Get-Date) -lt $limite) {
    if ((Lineas-Desde $desde).Contains($texto)) { Aviso "  ✓ $texto"; return }
    Start-Sleep -Seconds 1
  }
  Aviso 'Líneas nuevas de motor.log:'
  (Lineas-Desde $desde) -split "`r?`n" | Select-Object -Last 40 | ForEach-Object { Aviso "  $_" }
  Falla "${equipo}: no apareció en $segundos s la línea «$texto»."
}

function Contar-Lineas([long]$desde, [string]$texto) {
  ([regex]::Matches((Lineas-Desde $desde), [regex]::Escape($texto))).Count
}

function Procesos-Motor { Get-Process -Name 'Trabajito Motor' -ErrorAction SilentlyContinue }

# @() donde se lee .Count: con Set-StrictMode, «ningún proceso» ($null) o uno solo no tienen .Count.
function Cerrar-Motor {
  if (@(Procesos-Motor).Count -eq 0) { return }
  Procesos-Motor | Stop-Process -Force -ErrorAction SilentlyContinue
  $limite = (Get-Date).AddSeconds(20)
  while (@(Procesos-Motor).Count -gt 0 -and (Get-Date) -lt $limite) { Start-Sleep -Milliseconds 500 }
  if (@(Procesos-Motor).Count -gt 0) { Falla 'No pude cerrar el motor.' }
}

function Capturar([string]$archivo) {
  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $zona = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $imagen = New-Object System.Drawing.Bitmap $zona.Width, $zona.Height
    $lienzo = [System.Drawing.Graphics]::FromImage($imagen)
    $lienzo.CopyFromScreen($zona.Left, $zona.Top, 0, 0, $imagen.Size)
    $imagen.Save($archivo, [System.Drawing.Imaging.ImageFormat]::Png)
    $lienzo.Dispose(); $imagen.Dispose()
    Aviso "  Captura: $(Split-Path -Leaf $archivo)"
  } catch {
    Aviso "  (Esta computadora de GitHub no dejó capturar la pantalla: $($_.Exception.Message))"
  }
}

function Registro-Desinstalar {
  Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath } |
    Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'Trabajito Motor*' } |
    Select-Object -First 1
}

function Comando-Enlace {
  $clave = 'HKCU:\Software\Classes\trabajito-motor\shell\open\command'
  if (-not (Test-Path -LiteralPath $clave)) { return $null }
  (Get-ItemProperty -LiteralPath $clave).'(default)'
}

Titulo "${equipo}: instalador de $Entorno (Trabajito Motor $version)"
if (-not (Test-Path -LiteralPath $instalador)) { Falla "No está $instalador." }
if (Registro-Desinstalar) { Falla 'Ya hay un Trabajito Motor instalado en esta computadora: la prueba empieza sin ninguno.' }
Cerrar-Motor
Remove-Item -LiteralPath $datos -Recurse -Force -ErrorAction SilentlyContinue

Titulo '1. Instalar (en silencio, por usuario)'
$proceso = Start-Process -FilePath $instalador -ArgumentList '/S' -PassThru -Wait
if ($proceso.ExitCode -ne 0) { Falla "El instalador terminó con el código $($proceso.ExitCode)." }
Start-Sleep -Seconds 3
Cerrar-Motor # por si el instalador lo abrió al terminar
$instalado = Registro-Desinstalar
if (-not $instalado) { Falla 'No quedó en «Aplicaciones instaladas».' }
Aviso "En «Aplicaciones instaladas»: $($instalado.DisplayName) $($instalado.DisplayVersion)"
if ($instalado.DisplayVersion -ne $version) { Falla "Dice versión $($instalado.DisplayVersion) y se esperaba $version." }

Titulo '2. El enlace trabajito-motor:// y el Supabase de la app'
$comando = Comando-Enlace
if (-not $comando) { Falla 'trabajito-motor:// no quedó registrado.' }
if ($comando -notmatch '^"([^"]+\.exe)"') { Falla "El enlace tiene un comando inesperado: $comando" }
$exe = $Matches[1]
if (-not (Test-Path -LiteralPath $exe)) { Falla "El enlace abre $exe, que no existe." }
Aviso "El enlace abre: $exe"
$clase = Get-ItemProperty -LiteralPath 'HKCU:\Software\Classes\trabajito-motor'
if (-not $clase.PSObject.Properties['URL Protocol']) { Falla 'trabajito-motor:// no tiene el valor «URL Protocol»: sin él, Chrome y Edge no abren el motor.' }
Aviso 'Tiene «URL Protocol» (lo necesitan Chrome y Edge).'
$config = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $exe) 'resources\config.json') -Raw | ConvertFrom-Json
if ($config.supabaseUrl -ne "https://$proyecto.supabase.co") { Falla "La app trae el Supabase «$($config.supabaseUrl)» y se esperaba el de $Entorno ($proyecto)." }
Aviso "Supabase de la app: $($config.supabaseUrl) ($Entorno)"

Titulo '3. Primera apertura: como desde el menú Inicio, sin enlace'
$desde = Tamano-Log
Start-Process -FilePath $exe
Esperar-Linea $desde $lineaArranque 120
Esperar-Linea $desde $lineaSinEnlace 30
Start-Sleep -Seconds 3
Capturar "$captura-1-primera-apertura.png"
Cerrar-Motor
Aviso '  ✓ Cerrado.'

Titulo '4. En frío: el motor cerrado y la persona toca «Encender mi motor»'
$desdeFrio = Tamano-Log
Start-Process $enlace
Esperar-Linea $desdeFrio $lineaArranque 120
Esperar-Linea $desdeFrio 'URL recibida: encender (argv).' 30
Esperar-Linea $desdeFrio $lineaEncender 30
if ((Lineas-Desde $desdeFrio).Contains('Enlace de otro entorno')) { Falla "El motor dice «Enlace de otro entorno»: la app no es de $Entorno." }
Start-Sleep -Seconds 3
Capturar "$captura-2-encender-en-frio.png"

Titulo '5. En caliente: con el motor abierto, el mismo enlace'
$desde = Tamano-Log
Start-Process $enlace
Esperar-Linea $desde 'URL recibida: encender (second-instance).' 30
Esperar-Linea $desde $lineaEncender 30
$arranques = Contar-Lineas $desdeFrio $lineaArranque
if ($arranques -ne 1) { Falla "motor.log tiene $arranques arranques desde el paso 4: el enlace en caliente no lo atendió el motor abierto." }
Aviso '  ✓ Lo atendió el mismo motor.'

Titulo '6. Cerrar, revisar motor.log y desinstalar'
Cerrar-Motor
Aviso '  ✓ Cerrado.'
$todo = Get-Content -LiteralPath $log -Raw
if ($todo -match 'Error al iniciar') { Falla 'motor.log tiene un error de arranque.' }
Aviso 'motor.log completo (sin correos ni números):'
(($todo -replace '[\w.+-]+@[\w-]+\.[\w.]+', '[correo]') -replace '\+?\d{8,}', '[número]') -split "`r?`n" |
  Where-Object { $_ } | ForEach-Object { Aviso "  $_" }
$silencioso = $instalado.QuietUninstallString
if ($silencioso -notmatch '^"([^"]+)"\s*(.*)$') { Falla "Desinstalador inesperado: $silencioso" }
Start-Process -FilePath $Matches[1] -ArgumentList $Matches[2] -Wait
# El desinstalador de NSIS se copia a una carpeta temporal y sigue desde ahí: se espera al registro.
$limite = (Get-Date).AddSeconds(90)
while ((Registro-Desinstalar) -and (Get-Date) -lt $limite) { Start-Sleep -Seconds 1 }
if (Registro-Desinstalar) { Falla 'No se desinstaló en 90 s.' }
if (Comando-Enlace) { Falla 'Se desinstaló, pero trabajito-motor:// sigue registrado.' }
Aviso '  ✓ Desinstalado, y sin el enlace.'
Remove-Item -LiteralPath $datos -Recurse -Force -ErrorAction SilentlyContinue
Resumen "- ✅ **$equipo** · ${nombre}: se instaló, abrió sin enlace, atendió «Encender» en frío y en caliente con el Supabase de $Entorno, y se desinstaló."
