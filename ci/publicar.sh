#!/usr/bin/env bash
# Sube a Releases los instaladores armados y probados que todavía no están publicados:
#   - PROD (Trabajito-Motor-Setup.exe y Trabajito-Motor-mac.dmg) van a la release v<versión>. Si no
#     existe, se crea como BORRADOR: nadie la ve ni cambia el enlace «latest» hasta que alguien la
#     publique. Si ya existe y es pública, lo que falte queda a la vista al instante (con un aviso).
#   - DEV (…-DEV.exe y …-DEV.dmg) van a la pre-release «dev».
# Nunca reemplaza un archivo ya publicado: para rearmar uno, primero hay que borrarlo de la release.
# Antes de subir nada exige que estén todos los instaladores pedidos y que salieran del mismo commit.
# Uso: bash ci-repo/ci/publicar.sh <carpeta>   (con GH_TOKEN, GH_REPO, ENTORNOS y SISTEMAS)
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/comun.sh"

carpeta="${1:-}"
[ -d "$carpeta" ] || falla "Uso: publicar.sh <carpeta con los instaladores>"
cd "$carpeta"

# 1. Todos los instaladores pedidos, del mismo commit y la misma versión.
for entorno in $(entornos_de "${ENTORNOS:-}"); do
  case "${SISTEMAS:-}" in *mac*) [ -f "$(nombre_final mac "$entorno")" ] || falla "Falta el .dmg de ${entorno}: no se publica nada." ;; esac
  case "${SISTEMAS:-}" in *windows*) [ -f "$(nombre_final win "$entorno")" ] || falla "Falta el .exe de ${entorno}: no se publica nada." ;; esac
done
commits="$(cat commit-*.txt | tr -d '\r' | sort -u)"
versiones="$(cat version-*.txt | tr -d '\r' | sort -u)"
[ "$(printf '%s\n' "$commits" | grep -c .)" = "1" ] || falla "Los instaladores salieron de commits distintos: $(printf '%s' "$commits" | tr '\n' ' ')"
[ "$(printf '%s\n' "$versiones" | grep -c .)" = "1" ] || falla "Los instaladores tienen versiones distintas: $(printf '%s' "$versiones" | tr '\n' ' ')"
commit="$commits"
version="$versiones"
titulo "Trabajito Motor ${version} (commit ${commit:0:7} de trabajito-admin)"

# 2. Las sumas que anotó cada armado tienen que coincidir con los archivos que llegaron.
cat SHA256SUMS-*.txt >SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt
resumen "### Publicación: Trabajito Motor ${version} (commit \`${commit:0:7}\`)"

subir() {
  local archivo="$1" etiqueta="$2" suma fila estado digest borrador nota=""
  [ -f "$archivo" ] || return 0
  suma="$(sha256sum "$archivo" | cut -d' ' -f1)"
  if ! gh release view "$etiqueta" >/dev/null 2>&1; then
    [ "$etiqueta" != "dev" ] || falla "No existe la pre-release «dev»."
    gh release create "$etiqueta" --draft --title "Trabajito Motor ${version}" \
      --notes "Borrador armado por GitHub Actions desde el commit ${commit} de trabajito-admin. Revísalo y publícalo a mano."
    aviso "Creé el BORRADOR ${etiqueta}: no es público hasta que alguien lo publique."
    resumen "- 📝 Se creó el borrador ${etiqueta} (no es público todavía)."
  fi
  # Ya publicado: no se reemplaza, pero se revisa que esté completo y si es el mismo que se probó.
  fila="$(gh release view "$etiqueta" --json assets --jq '.assets[] | [.name, .state, (.digest // "")] | @tsv' | awk -F'\t' -v n="$archivo" '$1 == n')"
  if [ -n "$fila" ]; then
    estado="$(cut -f2 <<<"$fila")"
    digest="$(cut -f3 <<<"$fila")"
    [ "$estado" = "uploaded" ] || falla "${archivo} quedó a medio subir en ${etiqueta} (estado ${estado}): bórralo de la release y vuelve a correr."
    if [ "$digest" = "sha256:${suma}" ]; then
      aviso "Ya estaba publicado, idéntico: ${archivo} en ${etiqueta}."
      resumen "- ⏭️ ${archivo}: ya estaba en ${etiqueta}, idéntico."
    else
      aviso "::notice::${archivo} ya estaba en ${etiqueta} (${digest:-sin huella}) y no es el que se acaba de probar (sha256:${suma}). No se reemplaza."
      resumen "- ⏭️ ${archivo}: ya estaba en ${etiqueta} (${digest:-sin huella}); no se tocó."
    fi
    return 0
  fi
  borrador="$(gh release view "$etiqueta" --json isDraft --jq .isDraft)"
  if [ "$borrador" = "true" ]; then
    nota=" (borrador)"
  else
    aviso "::warning::${etiqueta} ya es pública: ${archivo} queda descargable al instante."
  fi
  gh release upload "$etiqueta" "$archivo"
  aviso "Subido: ${archivo} → ${etiqueta}${nota} (sha256 ${suma})"
  resumen "- ⬆️ **${archivo}** → ${etiqueta}${nota} · sha256 \`${suma}\`"
}

# Solo lo que se pidió en esta corrida (entornos y sistemas), aunque haya otros archivos en la carpeta.
for entorno in $(entornos_de "${ENTORNOS:-}"); do
  if [ "$entorno" = "dev" ]; then etiqueta="dev"; else etiqueta="v${version}"; fi
  case "${SISTEMAS:-}" in *windows*) subir "$(nombre_final win "$entorno")" "$etiqueta" ;; esac
  case "${SISTEMAS:-}" in *mac*) subir "$(nombre_final mac "$entorno")" "$etiqueta" ;; esac
done

# 3. A una release PROD le tienen que quedar los dos instaladores: publicada con uno solo, «latest»
# deja sin descarga al otro sistema.
if gh release view "v${version}" >/dev/null 2>&1; then
  hay="$(gh release view "v${version}" --json assets --jq '.assets[].name')"
  for f in Trabajito-Motor-Setup.exe Trabajito-Motor-mac.dmg; do
    if ! grep -qxF -- "$f" <<<"$hay"; then
      aviso "::warning::A v${version} le falta ${f}: si se publica así, «latest» deja sin descarga a ese sistema."
      resumen "- ⚠️ A v${version} le falta ${f}: no la publiques todavía."
    fi
  done
fi
