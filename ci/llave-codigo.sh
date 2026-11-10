#!/usr/bin/env bash
# Crea la llave de SOLO LECTURA con la que el robot de armado lee el repo privado
# FreddyLeon02/trabajito-motor-codigo (la copia de motor-whatsapp). Se corre UNA vez.
#   - La parte pública queda como «deploy key» de solo lectura de ese repo privado.
#   - La parte privada va directo al secreto CODIGO_MOTOR_SSH de FreddyLeon02/trabajito-motor y se borra
#     de esta computadora: nunca se muestra.
# Uso (Git Bash): bash ci/llave-codigo.sh               (no hace nada si el secreto ya existe)
#                 bash ci/llave-codigo.sh --reemplazar  (otra llave; borra la deploy key anterior)
set -euo pipefail
readonly REPO_PUBLICO="FreddyLeon02/trabajito-motor"
readonly REPO_CODIGO="FreddyLeon02/trabajito-motor-codigo"
readonly SECRETO="CODIGO_MOTOR_SSH"
readonly TITULO="Armado de instaladores (solo lectura)"

reemplazar=0
if [ "${1:-}" = "--reemplazar" ]; then reemplazar=1; fi
command -v ssh-keygen >/dev/null 2>&1 || { echo "Falta ssh-keygen (viene con Git para Windows)."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Primero inicia sesión en GitHub: gh auth login"; exit 1; }
[ "$(gh repo view "$REPO_CODIGO" --json visibility --jq .visibility)" = "PRIVATE" ] || { echo "${REPO_CODIGO} tiene que existir y ser privado."; exit 1; }

# Si no se pueden leer los secretos (red, sesión vencida), no se hace nada: si no, se cambiaría una llave
# que funciona sin haberlo pedido.
secretos="$(gh secret list --repo "$REPO_PUBLICO")" ||
  { echo "No pude leer los secretos de ${REPO_PUBLICO} (¿red o sesión de gh?): no hice nada."; exit 1; }
if grep -q "^${SECRETO}[[:space:]]" <<<"$secretos" && [ "$reemplazar" -ne 1 ]; then
  echo "El secreto ${SECRETO} ya existe en ${REPO_PUBLICO}: no hice nada (para otra llave: --reemplazar)."
  exit 1
fi
if [ "$reemplazar" -eq 1 ]; then
  for id in $(gh api "repos/${REPO_CODIGO}/keys" --jq ".[] | select(.title == \"${TITULO}\") | .id"); do
    gh api -X DELETE "repos/${REPO_CODIGO}/keys/${id}" >/dev/null
    echo "Borré la deploy key anterior (${id})."
  done
fi

carpeta="$(mktemp -d)"
trap 'rm -rf "$carpeta"' EXIT
ssh-keygen -q -t ed25519 -N "" -C "trabajito-motor: armado de instaladores (solo lectura)" -f "${carpeta}/llave"
gh repo deploy-key add "${carpeta}/llave.pub" --repo "$REPO_CODIGO" --title "$TITULO" >/dev/null
gh secret set "$SECRETO" --repo "$REPO_PUBLICO" <"${carpeta}/llave"
rm -f "${carpeta}/llave"
solo_lectura="$(gh api "repos/${REPO_CODIGO}/keys" --jq ".[] | select(.title == \"${TITULO}\") | .read_only")"
echo "Listo: deploy key de ${REPO_CODIGO} (solo lectura: ${solo_lectura}) y secreto ${SECRETO} en ${REPO_PUBLICO}."
echo "La parte privada no se mostró y ya no está en esta computadora."
