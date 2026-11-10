#!/usr/bin/env bash
# Copia motor-whatsapp/ de trabajito-admin al repo PRIVADO FreddyLeon02/trabajito-motor-codigo, que es de
# donde lo lee el robot de armado. Se corre antes de armar, cada vez que cambie el motor.
#   - Solo los archivos versionados de motor-whatsapp/ (git archive): nada de node_modules,
#     config/dev.json ni config/prod.json, y nada del resto del superadmin.
#   - Cada copia es un commit nuevo en la rama del mismo nombre, con ORIGEN.txt: de qué commit salió.
#   - Si el repo de destino no es privado, no sube nada.
# Uso (Git Bash): bash ci/subir-codigo.sh <carpeta de trabajito-admin> [dev|main]   (por defecto dev)
set -euo pipefail
readonly REPO_CODIGO="FreddyLeon02/trabajito-motor-codigo"
readonly REPO_ORIGEN="jose-mendoza-trabajito/trabajito-admin"

origen="${1:-}"
rama="${2:-dev}"
case "$rama" in
  dev | main) ;;
  *) echo "La rama tiene que ser dev o main."; exit 1 ;;
esac
git -C "$origen" rev-parse --git-dir >/dev/null 2>&1 || { echo "Uso: bash ci/subir-codigo.sh <carpeta de trabajito-admin> [dev|main]"; exit 1; }
remoto="$(git -C "$origen" remote get-url origin)"
case "$remoto" in
  *"${REPO_ORIGEN}"*) ;;
  *) echo "La carpeta no es un clon de ${REPO_ORIGEN} (origin es ${remoto})."; exit 1 ;;
esac
visibilidad="$(gh repo view "$REPO_CODIGO" --json visibility --jq .visibility)"
[ "$visibilidad" = "PRIVATE" ] || { echo "${REPO_CODIGO} no es privado (${visibilidad}): no subo el código."; exit 1; }

git -C "$origen" fetch --quiet origin "$rama"
sha="$(git -C "$origen" rev-parse "origin/${rama}")"
fecha="$(git -C "$origen" show -s --format=%cI "$sha")"
asunto="$(git -C "$origen" show -s --format=%s "$sha")"
echo "Origen: ${REPO_ORIGEN} ${rama} @ ${sha:0:7} (${fecha}) «${asunto}»"

carpeta="$(mktemp -d)"
trap 'rm -rf "$carpeta"' EXIT
destino="${carpeta}/codigo"
gh repo clone "$REPO_CODIGO" "$destino" -- --quiet 2>/dev/null || true
if [ ! -d "${destino}/.git" ]; then
  git init --quiet "$destino"
  git -C "$destino" remote add origin "https://github.com/${REPO_CODIGO}.git"
fi
# Los archivos tal cual están en trabajito-admin (sin convertir finales de línea).
git -C "$destino" config core.autocrlf false
if git -C "$destino" ls-remote --exit-code --heads origin "$rama" >/dev/null 2>&1; then
  git -C "$destino" fetch --quiet origin "$rama"
  git -C "$destino" checkout --quiet -B "$rama" "origin/${rama}"
else
  git -C "$destino" checkout --quiet --orphan "$rama"
fi
git -C "$destino" rm -r --quiet --ignore-unmatch . >/dev/null
git -c core.autocrlf=false -C "$origen" archive "$sha" motor-whatsapp | tar -x -C "$destino"
printf 'repo: %s\nrama: %s\ncommit: %s\nfecha: %s\nasunto: %s\n' "$REPO_ORIGEN" "$rama" "$sha" "$fecha" "$asunto" >"${destino}/ORIGEN.txt"
git -C "$destino" add -A
if git -C "$destino" diff --cached --quiet; then
  echo "Sin cambios: ${REPO_CODIGO} (${rama}) ya tiene motor-whatsapp de ${sha:0:7}."
  exit 0
fi
archivos="$(git -C "$destino" diff --cached --name-only | wc -l | tr -d ' ')"
git -C "$destino" commit --quiet -m "motor-whatsapp de trabajito-admin@${sha:0:7} (${rama})"
git -C "$destino" push --quiet origin "$rama"
echo "Subido a ${REPO_CODIGO} (${rama}): ${archivos} archivos cambiados, motor-whatsapp de ${sha:0:7}."
