#!/usr/bin/env bash
# Instala el .dmg recién armado como lo haría una persona y prueba Trabajito Motor en esta Mac:
#   1. abre el .dmg y copia la app a Aplicaciones;
#   2. revisa la firma (ad hoc), los dos chips (Apple Silicon e Intel), el Info.plist (versión, macOS
#      mínimo, el enlace trabajito-motor:// y App Nap apagado) y el Supabase que trae;
#   3. primera apertura, desde Aplicaciones y sin enlace: tiene que mostrar su ventana y pedir iniciar sesión;
#   4. en frío: con el motor cerrado abre trabajito-motor://encender, que es lo que hace «Encender mi
#      motor» en la web. Tiene que arrancar con el Supabase de su entorno, atender el enlace y mostrarse;
#   5. en caliente: con el motor abierto, el mismo enlace lo tiene que atender ese mismo motor;
#   6. al apagarlo, revisa motor.log y que macOS no haya registrado cierres inesperados;
#   7. muestra qué dirá Gatekeeper a quien lo baje de internet (no está notarizada: «Abrir igualmente»).
# Nunca inicia sesión ni toca WhatsApp. Uso: bash ci-repo/ci/mac/probar-dmg.sh <prod|dev>
# Solo para las Macs de GitHub, que se borran al terminar: cambia el llavero por defecto y, si el motor
# no se cierra cuando se le pide, lo termina.
set -euo pipefail
. "$(cd "$(dirname "$0")/.." && pwd)/comun.sh"

entorno="${1:-}"
datos_de_entorno "$entorno"
[ "$(uname -s)" = "Darwin" ] || falla "Este script es para macOS."
version="$(cat "${SALIDA}/version.txt")"
dmg="${SALIDA}/$(nombre_final mac "$entorno")"
[ -f "$dmg" ] || falla "No está ${dmg}."

readonly APP_NOMBRE="Trabajito Motor"
readonly APP="/Applications/${APP_NOMBRE}.app"
readonly BINARIO="${APP}/Contents/MacOS/${APP_NOMBRE}"
readonly DATOS="${HOME}/Library/Application Support/${APP_NOMBRE}"
readonly LOG="${DATOS}/motor.log"
readonly LINEA_ARRANQUE="Trabajito Motor ${version} (prod, proyecto ${PROYECTO}); WhatsApp real."
readonly LINEA_SIN_SESION="Arranque sin sesión guardada: se pide iniciar sesión."
readonly LINEA_URL="URL recibida: encender (open-url)."
readonly LINEA_ENCENDER="Encender: se muestra la ventana."
readonly ENLACE="trabajito-motor://encender?proyecto=${PROYECTO}"
readonly EQUIPO="macOS $(sw_vers -productVersion) ($(uname -m))"
readonly CAPTURA="${SALIDA}/mac-$(sw_vers -productVersion)-$(uname -m)-${entorno}"

tamano_log() { if [ -f "$LOG" ]; then stat -f%z "$LOG"; else echo 0; fi; }

lineas_desde() {
  if [ -f "$LOG" ]; then tail -c +"$(($1 + 1))" "$LOG"; fi
}

# Espera una línea en motor.log escrita después de «desde» (bytes). Sin tuberías con grep -q: con
# pipefail, el SIGPIPE de tail haría fallar la condición aunque la línea esté.
esperar_linea() {
  local desde="$1" texto="$2" segundos="$3" i=0 nuevas
  while [ "$i" -lt "$segundos" ]; do
    nuevas="$(lineas_desde "$desde")"
    if grep -qF -- "$texto" <<<"$nuevas"; then
      aviso "  ✓ ${texto}"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  aviso "Líneas nuevas de motor.log:"
  lineas_desde "$desde" | tail -n 40 | sed 's/^/  /' || true
  falla "${EQUIPO}: no apareció en ${segundos} s la línea «${texto}»."
}

# Cuántas veces aparece una línea en motor.log después de «desde» (bytes).
contar_lineas() {
  local nuevas
  nuevas="$(lineas_desde "$1")"
  grep -cF -- "$2" <<<"$nuevas" || true
}

motor_abierto() { pgrep -x "$APP_NOMBRE" >/dev/null 2>&1; }

pid_motor() { pgrep -x "$APP_NOMBRE" | head -n 1 || true; }

# Primero como «Apagar»: pedirle a la app que salga. Si macOS no deja mandarle el evento (permiso de
# Automatización, que en una Mac de GitHub nadie puede aceptar), SIGTERM y al final SIGKILL.
cerrar_motor() {
  motor_abierto || return 0
  osascript -e "quit app \"${APP_NOMBRE}\"" >/dev/null 2>&1 &
  local pid_osa=$! i=0
  while [ "$i" -lt 20 ]; do
    if ! motor_abierto; then
      kill "$pid_osa" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  kill "$pid_osa" >/dev/null 2>&1 || true
  aviso "  (No salió al pedírselo: lo termino con SIGTERM.)"
  pkill -TERM -x "$APP_NOMBRE" >/dev/null 2>&1 || true
  i=0
  while [ "$i" -lt 15 ]; do
    motor_abierto || return 0
    sleep 1
    i=$((i + 1))
  done
  pkill -KILL -x "$APP_NOMBRE" >/dev/null 2>&1 || true
  sleep 2
  if motor_abierto; then falla "No pude cerrar el motor."; fi
}

# Ventanas normales (capa 0) del motor a la vista, o «?» si no se pudo contar. Igual que
# scripts/mac/probar-motor.sh del equipo: CGWindowListCopyWindowInfo da el dueño y la capa sin pedir
# permisos (solo los títulos piden Grabación de pantalla).
ventanas_en_pantalla() {
  osascript -l JavaScript -e "
ObjC.import('CoreGraphics');
var lista = ObjC.deepUnwrap(ObjC.castRefToObject(\$.CGWindowListCopyWindowInfo(\$.kCGWindowListOptionOnScreenOnly, 0)));
lista.filter(function (v) { return v.kCGWindowOwnerName === '${APP_NOMBRE}' && v.kCGWindowLayer === 0; }).length;
" 2>/dev/null || printf '?\n'
}

# Espera hasta 15 s a que el motor tenga una ventana a la vista: abrir la app sin mostrar nada es
# justo el «no se abre nada» que ve la persona.
exigir_ventana() {
  local motivo="$1" i=0 n
  while [ "$i" -lt 15 ]; do
    n="$(ventanas_en_pantalla)"
    case "$n" in
      '?')
        aviso "::warning::${EQUIPO}: no pude contar las ventanas del motor (${motivo})."
        return 0
        ;;
      '' | 0) ;;
      *)
        aviso "  ✓ ${n} ventana(s) del motor a la vista."
        return 0
        ;;
    esac
    sleep 1
    i=$((i + 1))
  done
  falla "${EQUIPO}: ${motivo}, pero no hay ninguna ventana del motor a la vista."
}

capturar() {
  if screencapture -x "$1" >/dev/null 2>&1 && [ -s "$1" ]; then
    aviso "  Captura: $(basename "$1")"
  else
    rm -f "$1"
    aviso "  (Esta Mac de GitHub no dejó capturar la pantalla.)"
  fi
}

# Un llavero nuevo, abierto y por defecto: el motor guarda ahí su clave «Trabajito Motor Safe Storage»
# (safeStorage) sin abrir el diálogo del Llavero, que en una Mac de GitHub nadie puede responder. Nuevo
# en cada corrida: con firma ad hoc, la app de otro entorno no podría leer la clave de la anterior.
preparar_llavero() {
  local llavero="${HOME}/Library/Keychains/motor-prueba.keychain-db" otros
  security delete-keychain "$llavero" >/dev/null 2>&1 || true
  security create-keychain -p prueba "$llavero"
  security set-keychain-settings "$llavero"
  security unlock-keychain -p prueba "$llavero"
  otros="$(security list-keychains -d user | tr -d '"' | grep -v 'motor-prueba' || true)"
  # shellcheck disable=SC2086 # una ruta por palabra
  security list-keychains -d user -s "$llavero" $otros
  security default-keychain -d user -s "$llavero"
}

leer_plist() { plutil -extract "$1" raw -o - "$2" 2>/dev/null || echo "?"; }

titulo "${EQUIPO}: instalador de ${entorno} (Trabajito Motor ${version})"
cerrar_motor
rm -rf "$APP" "$DATOS"
# Los informes de cierre de macOS más nuevos que esta marca son de esta prueba.
marca="$(mktemp)"

titulo "1. Abrir el .dmg y copiar la app a Aplicaciones"
punto="$(mktemp -d)/dmg"
mkdir -p "$punto"
hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$punto" "$dmg" >/dev/null
if [ ! -d "${punto}/${APP_NOMBRE}.app" ]; then
  hdiutil detach "$punto" -force >/dev/null 2>&1 || true
  falla "El .dmg no trae «${APP_NOMBRE}.app»."
fi
if [ -L "${punto}/Applications" ]; then
  aviso "El .dmg trae el acceso a Aplicaciones, para arrastrar la app."
else
  aviso "::warning::El .dmg no trae el acceso a Aplicaciones."
fi
ditto "${punto}/${APP_NOMBRE}.app" "$APP"
hdiutil detach "$punto" >/dev/null 2>&1 || hdiutil detach "$punto" -force >/dev/null
aviso "Copiada: ${APP}"

titulo "2. Firma, chips, Info.plist y Supabase"
if ! verificacion="$(codesign --verify --deep --strict --verbose=2 "$APP" 2>&1)"; then
  printf '%s\n' "$verificacion" | sed 's/^/  /'
  falla "La firma de la app no es válida."
fi
printf '%s\n' "$verificacion" | sed 's/^/  /'
firma="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
grep -E '^(Identifier|Format|CodeDirectory|Signature|TeamIdentifier|Runtime Version)' <<<"$firma" | sed 's/^/  /' || true
grep -q 'Identifier=bo.com.trabajito.motor' <<<"$firma" || falla "La firma no dice Identifier=bo.com.trabajito.motor."
grep -q 'Signature=adhoc' <<<"$firma" || aviso "::warning::La firma no es ad hoc (¿se firmó con un certificado?)."
chips="$(lipo -archs "$BINARIO")"
aviso "Chips del binario: ${chips}"
case " ${chips} " in *" x86_64 "*) ;; *) falla "Al binario le falta Intel (x86_64)." ;; esac
case " ${chips} " in *" arm64 "*) ;; *) falla "Al binario le falta Apple Silicon (arm64)." ;; esac
plist="${APP}/Contents/Info.plist"
v="$(leer_plist CFBundleShortVersionString "$plist")"
aviso "Versión: ${v}"
[ "$v" = "$version" ] || falla "La app dice versión ${v} y se esperaba ${version}."
minimo="$(leer_plist LSMinimumSystemVersion "$plist")"
aviso "macOS mínimo: ${minimo}"
[ "$minimo" = "12.0" ] || aviso "::warning::LSMinimumSystemVersion es ${minimo} (se esperaba 12.0)."
nap="$(leer_plist LSAppNapIsDisabled "$plist")"
aviso "App Nap apagado: ${nap}"
case "$nap" in true | 1 | YES) ;; *) falla "El Info.plist no apaga App Nap (LSAppNapIsDisabled)." ;; esac
esquemas="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$plist" 2>/dev/null || true)"
grep -q 'trabajito-motor' <<<"$esquemas" || falla "El Info.plist no declara el enlace trabajito-motor://."
aviso "Enlace declarado: trabajito-motor://"
config="$(cat "${APP}/Contents/Resources/config.json")"
url_app="$(sed -n 's/.*"supabaseUrl"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$config" | head -n 1)"
[ "$url_app" = "https://${PROYECTO}.supabase.co" ] || falla "La app trae el Supabase «${url_app}» y se esperaba el de ${entorno} (${PROYECTO})."
aviso "Supabase de la app: ${url_app} (${entorno})"

titulo "3. Primera apertura: desde Aplicaciones y sin enlace"
preparar_llavero
aviso "Llavero de prueba listo."
"$LSREGISTER" -f "$APP"
desde="$(tamano_log)"
open -a "$APP"
esperar_linea "$desde" "$LINEA_ARRANQUE" 120
esperar_linea "$desde" "$LINEA_SIN_SESION" 30
exigir_ventana "abrió sin sesión"
sleep 2
capturar "${CAPTURA}-1-primera-apertura.png"
cerrar_motor
aviso "  ✓ Cerrado."

titulo "4. En frío: el motor cerrado y la persona toca «Encender mi motor»"
desde_frio="$(tamano_log)"
open "$ENLACE"
esperar_linea "$desde_frio" "$LINEA_ARRANQUE" 120
esperar_linea "$desde_frio" "$LINEA_URL" 30
esperar_linea "$desde_frio" "$LINEA_ENCENDER" 30
nuevas="$(lineas_desde "$desde_frio")"
if grep -q 'Enlace de otro entorno' <<<"$nuevas"; then falla "${EQUIPO}: el motor dice «Enlace de otro entorno»: la app no es de ${entorno}."; fi
if pgrep -f "^${BINARIO}" >/dev/null 2>&1; then
  aviso "  ✓ Corre la app de Aplicaciones."
else
  falla "${EQUIPO}: el enlace no abrió la app de Aplicaciones."
fi
exigir_ventana "atendió el enlace en frío"
pid_frio="$(pid_motor)"
sleep 2
capturar "${CAPTURA}-2-encender-en-frio.png"

titulo "5. En caliente: con el motor abierto, el mismo enlace"
desde="$(tamano_log)"
open "$ENLACE"
esperar_linea "$desde" "$LINEA_URL" 30
esperar_linea "$desde" "$LINEA_ENCENDER" 30
pid_caliente="$(pid_motor)"
if [ -z "$pid_frio" ] || [ "$pid_caliente" != "$pid_frio" ]; then
  falla "${EQUIPO}: el motor cambió de proceso entre el frío y el caliente (¿se cayó y volvió a arrancar?)."
fi
arranques="$(contar_lineas "$desde_frio" "$LINEA_ARRANQUE")"
[ "$arranques" = "1" ] || falla "${EQUIPO}: motor.log tiene ${arranques} arranques desde el paso 4: el enlace en caliente no lo atendió el motor abierto."
aviso "  ✓ Lo atendió el mismo motor (proceso ${pid_frio})."
exigir_ventana "atendió el enlace en caliente"
aviso "  (La ventana estaba abierta: en una Mac de GitHub no se puede cerrar con el botón rojo. El caso con la ventana cerrada lo cubre scripts/mac/probar-motor.sh del equipo.)"

titulo "6. Apagar, motor.log y cierres inesperados"
cerrar_motor
aviso "  ✓ Cerrado."
todo="$(cat "$LOG" 2>/dev/null || true)"
if grep -E 'Error al iniciar|no pudo iniciar' <<<"$todo"; then falla "${EQUIPO}: motor.log tiene un error de arranque."; fi
informes="$(find "${HOME}/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports -newer "$marca" -name "${APP_NOMBRE}*" 2>/dev/null || true)"
if [ -n "$informes" ]; then
  printf '%s\n' "$informes" | sed 's/^/  /'
  falla "${EQUIPO}: macOS registró un cierre inesperado del motor o de una de sus partes."
fi
aviso "  ✓ Sin cierres inesperados."
rm -f "$marca"
aviso "motor.log completo (sin correos ni números):"
sed -E 's/[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}/[correo]/g; s/\+?[0-9]{8,}/[número]/g; s/^/  /' <<<"$todo"

titulo "7. Lo que verá quien lo baje de internet (Gatekeeper)"
carpeta_copia="$(mktemp -d)"
ditto "$APP" "${carpeta_copia}/${APP_NOMBRE}.app"
xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;" "${carpeta_copia}/${APP_NOMBRE}.app"
spctl --assess --type execute -vv "${carpeta_copia}/${APP_NOMBRE}.app" 2>&1 | sed 's/^/  /' || true
if command -v syspolicy_check >/dev/null 2>&1; then
  syspolicy_check distribution "${carpeta_copia}/${APP_NOMBRE}.app" 2>&1 | head -n 20 | sed 's/^/  /' || true
fi
aviso "Esperado: «rejected». La app no está notarizada: la primera vez macOS la frena y la persona la abre desde Privacidad y seguridad («Abrir igualmente»)."
rm -rf "$carpeta_copia"

titulo "8. Limpiar"
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
rm -rf "$APP" "$DATOS"
aviso "Listo: el instalador de ${entorno} funciona en ${EQUIPO}."
resumen "- ✅ **${EQUIPO}** · $(basename "$dmg"): se instaló desde el .dmg, abrió sin enlace con su ventana, y atendió «Encender» en frío y en caliente con el Supabase de ${entorno}."
