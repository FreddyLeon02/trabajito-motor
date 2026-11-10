// Revisa la config.json que va dentro del instalador: un instalador (entorno prod, protocolo
// trabajito-motor, WhatsApp real) con el Supabase del entorno y su clave PÚBLICA. Nunca imprime la clave.
// Uso: node revisar-config.cjs <config.json> <url de Supabase esperada>
"use strict";
const fs = require("fs");

const [archivo, urlEsperada] = process.argv.slice(2);
if (!archivo || !urlEsperada) {
  console.error("Uso: node revisar-config.cjs <config.json> <url de Supabase esperada>");
  process.exit(2);
}
const config = JSON.parse(fs.readFileSync(archivo, "utf8"));
const clave = String(config.supabaseAnonKey ?? "");
const errores = [];
if (config.entorno !== "prod") errores.push(`entorno es «${config.entorno}» (un instalador siempre es prod)`);
if (config.protocolo !== "trabajito-motor") errores.push(`protocolo es «${config.protocolo}»`);
if (config.whatsapp !== "real") errores.push(`whatsapp es «${config.whatsapp}»`);
if (config.supabaseUrl !== urlEsperada) errores.push(`supabaseUrl es «${config.supabaseUrl}» y se esperaba «${urlEsperada}»`);
if (!/^sb_publishable_\S+$/.test(clave)) errores.push("la clave no es la pública (sb_publishable_…)");

const { supabaseAnonKey, ...resto } = config;
console.log(`config.json: ${JSON.stringify(resto)}; clave pública de ${clave.length} caracteres (no se muestra).`);
if (errores.length > 0) {
  for (const e of errores) console.log(`::error::config.json: ${e}.`);
  process.exit(1);
}
