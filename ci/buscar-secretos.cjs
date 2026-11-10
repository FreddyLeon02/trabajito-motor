// Revisa el app.asar de un instalador y falla si trae una clave secreta real de Supabase: una sb_secret_…
// o un JWT con role service_role. El texto suelto «service_role» de las librerías no cuenta. Nunca
// imprime una clave: de cada coincidencia muestra solo el archivo, el tipo y el largo.
// Uso (desde motor-whatsapp, para usar su @electron/asar): node buscar-secretos.cjs <app.asar>
"use strict";
const path = require("path");

const archivoAsar = path.resolve(process.argv[2] ?? "");
const asar = require(require.resolve("@electron/asar", { paths: [process.cwd()] }));

function rolDeJwt(token) {
  try {
    const carga = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
    return { rol: carga.role ?? "(sin role)", ref: String(carga.ref ?? carga.iss ?? "").slice(0, 40) };
  } catch {
    return null;
  }
}

const carpetaDe = (f) => {
  const partes = f.split(/[\\/]/);
  return partes[0] === "node_modules" ? partes.slice(0, partes[1]?.startsWith("@") ? 3 : 2).join("/") : partes.slice(0, 3).join("/");
};

const lista = asar.listPackage(archivoAsar).map((f) => f.replace(/^[\\/]/, ""));
const clavesSecret = [];
const jwts = [];
for (const f of lista) {
  let contenido;
  try {
    contenido = asar.extractFile(archivoAsar, f);
  } catch {
    continue; // carpetas
  }
  if (!contenido || contenido.length === 0) continue;
  const texto = contenido.toString("latin1");
  for (const m of texto.matchAll(/sb_secret_[A-Za-z0-9_-]{16,}/g)) clavesSecret.push(`${f} (${m[0].length})`);
  for (const m of texto.matchAll(/eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/g)) {
    const info = rolDeJwt(m[0]);
    if (info) jwts.push({ f, ...info });
  }
}

const peligrosos = jwts.filter((j) => j.rol === "service_role");
console.log(`app.asar: ${lista.length} archivos revisados.`);
console.log(`JWT encontrados: ${jwts.length ? jwts.map((j) => `${carpetaDe(j.f)} role=${j.rol}`).join(" | ") : "ninguno"}.`);
if (clavesSecret.length > 0 || peligrosos.length > 0) {
  console.log(`::error::El instalador trae claves secretas: ${[...clavesSecret, ...peligrosos.map((j) => `${j.f} (service_role)`)].join(" | ")}`);
  process.exit(1);
}
console.log("Sin claves secretas ni service_role.");
