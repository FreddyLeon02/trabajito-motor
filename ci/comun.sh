# Datos y funciones que comparten los scripts de armado. Se carga con «. ci/comun.sh».
# Compatible con el bash 3.2 de macOS y con el Git Bash de Windows.

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Carpeta de trabajo del job: ci-repo/ (este repo), codigo/ (la copia privada de motor-whatsapp) y
# salida/ (instaladores).
RAIZ="$(cd "${CI_DIR}/../.." && pwd)"
MOTOR="${RAIZ}/codigo/motor-whatsapp"
SALIDA="${RAIZ}/salida"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

titulo() { printf '\n== %s ==\n' "$*"; }
aviso() { printf '%s\n' "$*"; }
# «::error::» lo muestra GitHub en el resumen de la corrida.
falla() {
  printf '::error::%s\n' "$*"
  exit 1
}
# Una línea en el resumen de la corrida (la página del job en GitHub).
resumen() {
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"; fi
}

# La opción «entornos» del workflow → la lista que recorren los pasos.
entornos_de() {
  case "${1:-}" in
    "prod y dev") echo "prod dev" ;;
    prod) echo "prod" ;;
    dev) echo "dev" ;;
    *) falla "Entornos desconocidos: «${1:-}»." ;;
  esac
}

# Define WEB (el superadmin publicado) y PROYECTO (el ref de su Supabase). Los mismos que usa
# ci/windows/probar-instalador.ps1: si cambian, cambian en los dos.
datos_de_entorno() {
  case "${1:-}" in
    prod)
      WEB="https://superadministrador.trabajitohr.com"
      PROYECTO="qnroulkqbhhdnfctfooc"
      ;;
    dev)
      WEB="https://devsuperadministrador.trabajitohr.com"
      PROYECTO="qtlugjtvbgiesphxwgwl"
      ;;
    *) falla "Entorno desconocido: «${1:-}» (prod o dev)." ;;
  esac
}

# Nombre con el que se publica cada instalador: el enlace de descarga del superadmin no cambia.
nombre_final() {
  case "${1:-}-${2:-}" in
    mac-prod) echo "Trabajito-Motor-mac.dmg" ;;
    mac-dev) echo "Trabajito-Motor-mac-DEV.dmg" ;;
    win-prod) echo "Trabajito-Motor-Setup.exe" ;;
    win-dev) echo "Trabajito-Motor-Setup-DEV.exe" ;;
    *) falla "No hay nombre para «${1:-} ${2:-}»." ;;
  esac
}

# El commit de trabajito-admin del que salió la copia (lo anota ci/subir-codigo.sh en ORIGEN.txt).
# Sin ORIGEN.txt, el commit de la copia.
commit_de_origen() {
  local origen="${RAIZ}/codigo/ORIGEN.txt" commit=""
  if [ -f "$origen" ]; then commit="$(sed -n 's/^commit: //p' "$origen" | tr -d '\r' | head -n 1)"; fi
  if [ -z "$commit" ]; then commit="$(git -C "${RAIZ}/codigo" rev-parse HEAD)"; fi
  printf '%s\n' "$commit"
}

sha256_de() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

# Exporta MOTOR_SUPABASE_URL y MOTOR_SUPABASE_ANON_KEY con la URL y la clave PÚBLICA del Supabase del
# entorno, sacadas de la web publicada del superadmin: el motor sale conectado a lo mismo que usa la web.
# La clave pública viaja legible en la web y en cada instalador; igual se enmascara en los logs.
cargar_config_de_la_web() {
  local entorno="$1" tmp js url clave n
  datos_de_entorno "$entorno"
  tmp="$(mktemp)"
  js="$(curl -fsS --retry 3 --max-time 30 "${WEB}/" | grep -oE '/assets/index-[A-Za-z0-9_-]+\.js' | head -n 1 || true)"
  [ -n "$js" ] || falla "No encontré el JavaScript principal de ${WEB}."
  curl -fsS --retry 3 --max-time 120 "${WEB}${js}" -o "$tmp" || falla "No pude bajar ${WEB}${js}."
  url="$(grep -oE 'https://[a-z0-9]{20}\.supabase\.co' "$tmp" | sort -u || true)"
  clave="$(grep -oE 'sb_publishable_[A-Za-z0-9_-]+' "$tmp" | sort -u || true)"
  rm -f "$tmp"
  n="$(printf '%s\n' "$clave" | grep -c . || true)"
  [ "$url" = "https://${PROYECTO}.supabase.co" ] || falla "La web de ${entorno} apunta a otro Supabase: «${url}»."
  [ "$n" = "1" ] || falla "Se esperaba 1 clave pública en la web de ${entorno} y hay ${n}."
  printf '::add-mask::%s\n' "$clave"
  export MOTOR_SUPABASE_URL="$url"
  export MOTOR_SUPABASE_ANON_KEY="$clave"
  aviso "Supabase de ${entorno}: ${url} (de ${WEB}${js}); clave pública de ${#clave} caracteres (no se muestra)."
}
