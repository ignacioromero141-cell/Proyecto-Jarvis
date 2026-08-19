"use strict";
const fs = require("fs");
const Backup = require("../src/web/static/jarvis-backup.js");
(async () => {
  const path = process.argv[2];
  if (!path) throw new Error("Falta path");
  const pkg = JSON.parse(fs.readFileSync(path, "utf8"));
  await Backup.validatePackage(pkg);
  console.log(`notebook comparison package: OK (${pkg.statistics.total_records} registros)`);
})().catch((error) => { console.error(error.message); process.exit(1); });
