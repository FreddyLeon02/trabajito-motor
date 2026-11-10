#!/usr/bin/env bash
# Arma un instalador de Trabajito Motor con la config del entorno, revisa lo que lleva adentro y lo deja
# en salida/ con su nombre final, más su sha256, la versión y el commit de trabajito-admin. La versión y
# el commit van también por sistema (version-mac.txt, commit-win.txt…): ci/publicar.sh exige que coincidan.
# Uso (desde la carpeta de trabajo del job): bash ci-repo/ci/armar.sh <mac|win> <prod|dev>
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

so="${1:-}"
entorno="${2:-}"
case "$so" in
  mac | win) ;;
  *) falla "Uso: armar.sh <mac|win> <prod|dev>" ;;
esac
cargar_config_de_la_web "$entorno"

cd "$MOTOR"
version="$(node -p "require('./package.json').version")"
commit="$(commit_de_origen)"
titulo "Armar el instalador de ${so} para ${entorno}: Trabajito Motor ${version} (commit ${commit:0:7})"
rm -rf release
unset MOTOR_CONFIG_RELLENO ELECTRON_RUN_AS_NODE
# Sin buscar certificados: la app de Mac se firma ad hoc (identity "-" en electron-builder.yml).
export CSC_IDENTITY_AUTO_DISCOVERY=false
if [ "$so" = mac ]; then npm run empaquetar:mac; else npm run empaquetar:win; fi

if [ "$so" = mac ]; then
  recursos="release/mac-universal/Trabajito Motor.app/Contents/Resources"
  instalador="release/Trabajito-Motor-mac.dmg"
else
  recursos="release/win-unpacked/resources"
  instalador="release/Trabajito-Motor-Setup.exe"
fi
[ -f "$instalador" ] || falla "electron-builder no dejó ${instalador}."

titulo "Lo que va adentro"
node "${CI_DIR}/revisar-config.cjs" "${recursos}/config.json" "$MOTOR_SUPABASE_URL"
node "${CI_DIR}/buscar-secretos.cjs" "${recursos}/app.asar"

nombre="$(nombre_final "$so" "$entorno")"
mkdir -p "$SALIDA"
cp "$instalador" "${SALIDA}/${nombre}"
(cd "$SALIDA" && sha256_de "$nombre" >>"SHA256SUMS-${so}.txt")
printf '%s\n' "$version" >"${SALIDA}/version.txt"
printf '%s\n' "$commit" >"${SALIDA}/commit.txt"
printf '%s\n' "$version" >"${SALIDA}/version-${so}.txt"
printf '%s\n' "$commit" >"${SALIDA}/commit-${so}.txt"
suma="$(cd "$SALIDA" && sha256_de "$nombre" | cut -d' ' -f1)"
tamano="$(du -h "${SALIDA}/${nombre}" | cut -f1)"
aviso "Listo: ${nombre} (${tamano}), sha256 ${suma}"
resumen "- 📦 **${nombre}** (${entorno}) · ${tamano} · Trabajito Motor ${version} · commit \`${commit:0:7}\` · sha256 \`${suma}\`"

# Las copias de la app que dejó el armado no tienen que atender trabajito-motor:// en esta Mac: solo
# la que se instala desde el .dmg (ci/mac/probar-dmg.sh).
if [ "$so" = mac ]; then
  for app in release/*/"Trabajito Motor.app"; do
    if [ -d "$app" ]; then "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true; fi
  done
fi
rm -rf release
