"use strict";
const fs = require("fs");
const path = require("path");
const root = path.resolve(__dirname, "../src/web/static");
const source = fs.readFileSync(path.join(root, "service-worker.js"), "utf8");
const shellMatch = source.match(/const APP_SHELL = \[([\s\S]*?)\];/);
if (!shellMatch) throw new Error("APP_SHELL ausente");
const entries = [...shellMatch[1].matchAll(/"\.\/(.*?)"/g)].map((match) => match[1]);
for (const entry of entries) {
  const relative = entry || "index.html";
  if (!fs.existsSync(path.join(root, relative))) throw new Error(`Recurso offline ausente: ${entry}`);
}
if (!source.includes("jarvis-pwa-v24-phase0-backup")) throw new Error("cache version no actualizada");
if (!entries.includes("jarvis-backup.js") || !entries.includes("backup-compare.html")) throw new Error("herramientas de backup fuera del app shell");
if (/indexedDB|deleteDatabase/.test(source)) throw new Error("el service worker no debe tocar IndexedDB");
if (!source.includes('url.pathname.includes("/api/")')) throw new Error("las API privadas no se excluyen del cache");
if (!source.includes("request.destination")) throw new Error("falta lista permitida de recursos publicos");
console.log(`service-worker-tests: ${entries.length} recursos offline OK; IndexedDB no se toca`);
