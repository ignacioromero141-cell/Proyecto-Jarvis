"use strict";
const fs = require("fs");
for (const file of process.argv.slice(2)) {
  const html = fs.readFileSync(file, "utf8");
  const pattern = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/gi;
  let match; let count=0;
  while ((match = pattern.exec(html))) { new Function(match[1]); count++; }
  console.log(`${file}: ${count} inline script(s) OK`);
}
