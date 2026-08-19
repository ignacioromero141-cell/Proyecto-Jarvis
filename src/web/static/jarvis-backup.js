(function (root, factory) {
  const api = factory(root);
  if (typeof module === "object" && module.exports) module.exports = api;
  if (root) root.JarvisBackup = api;
})(typeof globalThis !== "undefined" ? globalThis : this, function (root) {
  "use strict";

  const FORMAT_VERSION = 1;
  const CRYPTO_FORMAT_VERSION = 1;
  const APP_VERSION = "0.6-phase0";
  const PBKDF2_ITERATIONS = 310000;
  const REQUIRED_FIELDS = ["format_version", "app_version", "exported_at", "source_origin", "source_protocol", "database_name", "database_version", "workspace_id", "device_id", "identity", "local_storage", "stores", "pending_changes", "conflicts", "cursors", "statistics", "checksums"];
  const REQUIRED_STORES = ["records","finance_movements","finance_categories","finance_priorities","finance_payment_methods","finance_settings","calendar_events","study_subjects","study_topics","study_evaluations","study_assignments","study_notes","study_schedules","file_assets","file_links","local_file_roots","local_file_locations","sync_changes","sync_conflicts","metadata"];
  const IDENTITY_KEYS = new Set(["jarvis_device_id", "jarvis_workspace_id", "jarvis_workspace_name", "jarvis_device_name", "jarvis_sync_secret", "jarvis_linked_devices"]);
  const KEY_FIELDS = { sync_changes:"change_id", sync_conflicts:"conflict_id", metadata:"key" };
  const NON_ENTITY_STORES = new Set(["sync_changes", "sync_conflicts", "metadata", "local_file_roots", "local_file_locations"]);
  const MIGRATORS = new Map();

  function getCrypto() {
    const value = root && root.crypto;
    if (!value || !value.subtle || !value.getRandomValues) throw new Error("Este navegador no ofrece Web Crypto. No se puede crear una copia cifrada segura.");
    return value;
  }

  function stableValue(value) {
    if (Array.isArray(value)) return value.map(stableValue);
    if (value && typeof value === "object") {
      const result = {};
      Object.keys(value).sort().forEach((key) => { result[key] = stableValue(value[key]); });
      return result;
    }
    return value;
  }

  function canonicalStringify(value) {
    return JSON.stringify(stableValue(value));
  }

  function utf8(value) { return new TextEncoder().encode(value); }
  function fromUtf8(value) { return new TextDecoder("utf-8", { fatal:true }).decode(value); }

  function toBase64(bytes) {
    const data = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    let binary = "";
    for (let offset = 0; offset < data.length; offset += 0x8000) {
      binary += String.fromCharCode(...data.subarray(offset, Math.min(offset + 0x8000, data.length)));
    }
    if (typeof btoa === "function") return btoa(binary);
    return Buffer.from(data).toString("base64");
  }

  function fromBase64(value) {
    try {
      const binary = typeof atob === "function" ? atob(value) : Buffer.from(value, "base64").toString("binary");
      const bytes = new Uint8Array(binary.length);
      for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      return bytes;
    } catch {
      throw new Error("El archivo contiene datos binarios invalidos.");
    }
  }

  async function encodeValue(value, path = "$", seen = new WeakSet()) {
    if (value === null || typeof value === "string" || typeof value === "boolean") return value;
    if (typeof value === "number") {
      if (!Number.isFinite(value)) return { $jarvis_type:"Number", value:String(value) };
      return value;
    }
    if (typeof value === "undefined") return { $jarvis_type:"Undefined" };
    if (typeof value === "bigint") return { $jarvis_type:"BigInt", value:value.toString() };
    if (typeof value === "function" || typeof value === "symbol") throw new Error(`Valor no serializable en ${path}.`);
    if (value instanceof Date) return { $jarvis_type:"Date", value:value.toISOString() };
    if (typeof Blob !== "undefined" && value instanceof Blob) {
      return { $jarvis_type:"Blob", mime_type:value.type || "application/octet-stream", value:toBase64(await value.arrayBuffer()) };
    }
    if (value instanceof ArrayBuffer) return { $jarvis_type:"ArrayBuffer", value:toBase64(value) };
    if (ArrayBuffer.isView(value)) return { $jarvis_type:"TypedArray", constructor:value.constructor.name, value:toBase64(new Uint8Array(value.buffer, value.byteOffset, value.byteLength)) };
    if (seen.has(value)) throw new Error(`Referencia circular no serializable en ${path}.`);
    seen.add(value);
    try {
      if (Array.isArray(value)) return await Promise.all(value.map((item, index) => encodeValue(item, `${path}[${index}]`, seen)));
      const output = {};
      for (const key of Object.keys(value).sort()) output[key] = await encodeValue(value[key], `${path}.${key}`, seen);
      return output;
    } finally {
      seen.delete(value);
    }
  }

  function decodeValue(value) {
    if (Array.isArray(value)) return value.map(decodeValue);
    if (!value || typeof value !== "object") return value;
    if (value.$jarvis_type === "Date") return new Date(value.value);
    if (value.$jarvis_type === "Undefined") return undefined;
    if (value.$jarvis_type === "BigInt") return BigInt(value.value);
    if (value.$jarvis_type === "Number") return Number(value.value);
    if (value.$jarvis_type === "ArrayBuffer") return fromBase64(value.value).buffer;
    if (value.$jarvis_type === "Blob") return new Blob([fromBase64(value.value)], { type:value.mime_type });
    if (value.$jarvis_type === "TypedArray") {
      const bytes = fromBase64(value.value);
      const Constructor = root[value.constructor] || Uint8Array;
      return new Constructor(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    }
    const output = {};
    Object.keys(value).forEach((key) => { output[key] = decodeValue(value[key]); });
    return output;
  }

  async function sha256(value) {
    const digest = await getCrypto().subtle.digest("SHA-256", utf8(typeof value === "string" ? value : canonicalStringify(value)));
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  }

  function requestPromise(request) {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error || new Error("Fallo una operacion de IndexedDB."));
    });
  }

  function transactionPromise(transaction) {
    return new Promise((resolve, reject) => {
      transaction.oncomplete = () => resolve();
      transaction.onabort = () => reject(transaction.error || new Error("La transaccion fue cancelada. No se modifico ningun dato."));
      transaction.onerror = () => {};
    });
  }

  function itemKey(storeName, item) {
    const field = KEY_FIELDS[storeName] || "id";
    const value = item && item[field];
    return value === undefined || value === null ? "" : String(value);
  }

  function sortStore(storeName, items) {
    return [...items].sort((a, b) => {
      const keyCompare = itemKey(storeName, a).localeCompare(itemKey(storeName, b));
      return keyCompare || canonicalStringify(a).localeCompare(canonicalStringify(b));
    });
  }

  async function readDatabase(db) {
    const names = Array.from(db.objectStoreNames).sort();
    if (!names.length) return {};
    const tx = db.transaction(names, "readonly");
    const requests = names.map((name) => requestPromise(tx.objectStore(name).getAll()).then((items) => [name, items]));
    const pairs = await Promise.all(requests);
    await transactionPromise(tx);
    const stores = {};
    for (const [name, items] of pairs) {
      const encoded = [];
      for (let index = 0; index < items.length; index++) encoded.push(await encodeValue(items[index], `stores.${name}[${index}]`));
      stores[name] = sortStore(name, encoded);
    }
    return stores;
  }

  function readJarvisLocalStorage(storage) {
    const result = {};
    for (let i = 0; i < storage.length; i++) {
      const key = storage.key(i);
      if (key && key.startsWith("jarvis_")) result[key] = storage.getItem(key);
    }
    return stableValue(result);
  }

  function identityFromStorage(values) {
    let linked = [];
    try { linked = JSON.parse(values.jarvis_linked_devices || "[]"); } catch {}
    return {
      workspace_id:values.jarvis_workspace_id || "",
      workspace_name:values.jarvis_workspace_name || "",
      device_id:values.jarvis_device_id || "",
      device_name:values.jarvis_device_name || "",
      sync_secret:values.jarvis_sync_secret || "",
      linked_devices:Array.isArray(linked) ? linked : []
    };
  }

  function buildStatistics(stores, currentDeviceId = "") {
    const counts = {};
    let total = 0;
    let entities = 0;
    let deleted = 0;
    Object.keys(stores).sort().forEach((name) => {
      counts[name] = stores[name].length;
      total += stores[name].length;
      if (!NON_ENTITY_STORES.has(name)) entities += stores[name].length;
      deleted += stores[name].filter((item) => item && item.deleted_at).length;
    });
    const changes = stores.sync_changes || [];
    const pending = changes.filter((change) => !change.synced_at);
    const confirmed = changes.filter((change) => change.synced_at);
    const received = confirmed.filter((change) => currentDeviceId && String(change.device_id || "") !== String(currentDeviceId));
    const imported = (stores.metadata || []).filter((entry) => String(entry.key || "").includes("import") || entry.source === "backup-import");
    return { store_counts:counts, total_records:total, total_entities:entities, logically_deleted:deleted, pending_changes:pending.length, confirmed_changes:confirmed.length, received_changes:received.length, imported_snapshots:imported.length, conflicts:(stores.sync_conflicts || []).length };
  }

  function extractCursors(stores) {
    const cursors = {};
    (stores.metadata || []).forEach((entry) => {
      if (entry && (entry.last_server_cursor || String(entry.key || "").includes("sync"))) cursors[String(entry.key || "unknown")] = entry.last_server_cursor || null;
    });
    return cursors;
  }

  async function attachChecksums(pkg) {
    const stores = {};
    for (const name of Object.keys(pkg.stores).sort()) stores[name] = await sha256(pkg.stores[name]);
    const localStorageHash = await sha256(pkg.local_storage);
    const without = { ...pkg };
    delete without.checksums;
    return { ...pkg, checksums:{ algorithm:"SHA-256", stores, local_storage:localStorageHash, payload:await sha256(without) } };
  }

  async function createPackage(options = {}) {
    const access = options.access || root.JarvisLocalStore?.backupAccess;
    if (!access || typeof access.openDatabase !== "function") throw new Error("Jarvis no pudo acceder a su base local.");
    const db = await access.openDatabase();
    let stores;
    try { stores = await readDatabase(db); } finally { db.close(); }
    const localValues = readJarvisLocalStorage(options.storage || root.localStorage);
    const identity = identityFromStorage(localValues);
    const pkg = {
      format_version:FORMAT_VERSION,
      app_version:APP_VERSION,
      exported_at:new Date().toISOString(),
      source_origin:options.origin || root.location?.origin || "unknown",
      source_protocol:options.protocol || root.location?.protocol || "unknown:",
      source_kind:options.sourceKind || "pwa-indexeddb",
      database_name:access.databaseName || db.name,
      database_version:Number(access.databaseVersion || db.version || 0),
      workspace_id:identity.workspace_id,
      device_id:identity.device_id,
      identity,
      local_storage:localValues,
      stores,
      pending_changes:(stores.sync_changes || []).filter((change) => !change.synced_at),
      conflicts:stores.sync_conflicts || [],
      cursors:extractCursors(stores),
      statistics:buildStatistics(stores, identity.device_id),
      serialization:{ format:"jarvis-structured-json-v1", warnings:[] },
      checksums:{}
    };
    return attachChecksums(pkg);
  }

  function cryptoHeader(salt, iv) {
    return {
      encrypted:true,
      crypto_format_version:CRYPTO_FORMAT_VERSION,
      content_format:"jarvis-export-v1",
      kdf:{ name:"PBKDF2", hash:"SHA-256", iterations:PBKDF2_ITERATIONS, salt:toBase64(salt) },
      cipher:{ name:"AES-GCM", key_length:256, tag_length:128, iv:toBase64(iv) }
    };
  }

  async function deriveKey(password, salt, iterations) {
    if (typeof password !== "string" || password.length < 10) throw new Error("Usa una contraseña de al menos 10 caracteres.");
    const cryptoApi = getCrypto();
    const material = await cryptoApi.subtle.importKey("raw", utf8(password), "PBKDF2", false, ["deriveKey"]);
    return cryptoApi.subtle.deriveKey({ name:"PBKDF2", salt, iterations, hash:"SHA-256" }, material, { name:"AES-GCM", length:256 }, false, ["encrypt", "decrypt"]);
  }

  async function encryptPackage(pkg, password) {
    await validatePackage(pkg);
    const cryptoApi = getCrypto();
    const salt = cryptoApi.getRandomValues(new Uint8Array(16));
    const iv = cryptoApi.getRandomValues(new Uint8Array(12));
    const header = cryptoHeader(salt, iv);
    const key = await deriveKey(password, salt, PBKDF2_ITERATIONS);
    const encrypted = await cryptoApi.subtle.encrypt({ name:"AES-GCM", iv, additionalData:utf8(canonicalStringify(header)), tagLength:128 }, key, utf8(canonicalStringify(pkg)));
    return { ...header, ciphertext:toBase64(encrypted) };
  }

  async function decryptEnvelope(envelope, password) {
    if (!envelope || envelope.encrypted !== true) return envelope;
    if (envelope.crypto_format_version !== CRYPTO_FORMAT_VERSION) throw new Error("Version de cifrado desconocida. No se importo ningun dato.");
    if (envelope.content_format !== "jarvis-export-v1" || envelope.kdf?.name !== "PBKDF2" || envelope.kdf?.hash !== "SHA-256" || envelope.cipher?.name !== "AES-GCM" || Number(envelope.cipher?.key_length) !== 256 || Number(envelope.cipher?.tag_length) !== 128) throw new Error("El metodo de cifrado no es compatible.");
    const iterations = Number(envelope.kdf.iterations);
    if (!Number.isInteger(iterations) || iterations < 100000 || iterations > 2000000) throw new Error("Parametros de cifrado invalidos.");
    let salt, iv, ciphertext;
    try {
      salt = fromBase64(envelope.kdf.salt || "");
      iv = fromBase64(envelope.cipher.iv || "");
      ciphertext = fromBase64(envelope.ciphertext || "");
    } catch {
      throw new Error("Contraseña incorrecta o archivo dañado. No se importo ningun dato.");
    }
    if (salt.length !== 16 || iv.length !== 12 || ciphertext.length < 17) throw new Error("Parametros de cifrado invalidos. No se importo ningun dato.");
    const header = { ...envelope };
    delete header.ciphertext;
    try {
      const key = await deriveKey(password, salt, iterations);
      const plain = await getCrypto().subtle.decrypt({ name:"AES-GCM", iv, additionalData:utf8(canonicalStringify(header)), tagLength:128 }, key, ciphertext);
      return JSON.parse(fromUtf8(plain));
    } catch {
      throw new Error("Contraseña incorrecta o archivo dañado. No se importo ningun dato.");
    }
  }

  async function validatePackage(pkg) {
    if (!pkg || typeof pkg !== "object" || Array.isArray(pkg)) throw new Error("El archivo no contiene una copia valida de Jarvis.");
    if (pkg.format_version !== FORMAT_VERSION) throw new Error(`Version de copia no compatible: ${pkg.format_version ?? "ausente"}. No se importo ningun dato.`);
    const missing = REQUIRED_FIELDS.filter((field) => !(field in pkg));
    if (missing.length) throw new Error(`La copia esta incompleta. Faltan: ${missing.join(", ")}.`);
    if (!pkg.stores || typeof pkg.stores !== "object" || Array.isArray(pkg.stores)) throw new Error("La seccion de stores es invalida.");
    const missingStores = REQUIRED_STORES.filter((name) => !(name in pkg.stores));
    if (missingStores.length) throw new Error(`La copia no contiene todos los stores obligatorios: ${missingStores.join(", ")}.`);
    if (!pkg.identity || typeof pkg.identity !== "object" || Array.isArray(pkg.identity) || !pkg.local_storage || typeof pkg.local_storage !== "object" || Array.isArray(pkg.local_storage)) throw new Error("La identidad o localStorage de la copia son invalidos.");
    if (!Array.isArray(pkg.pending_changes) || !Array.isArray(pkg.conflicts) || !pkg.cursors || typeof pkg.cursors !== "object" || Array.isArray(pkg.cursors) || !pkg.statistics || typeof pkg.statistics !== "object" || Array.isArray(pkg.statistics)) throw new Error("Las secciones historicas o estadisticas de la copia son invalidas.");
    if (pkg.checksums?.algorithm !== "SHA-256") throw new Error("La copia no contiene hashes SHA-256 compatibles.");
    for (const name of Object.keys(pkg.stores)) {
      if (!Array.isArray(pkg.stores[name])) throw new Error(`El store ${name} no es una lista.`);
      if (await sha256(pkg.stores[name]) !== pkg.checksums.stores?.[name]) throw new Error(`Fallo la integridad del store ${name}. No se importo ningun dato.`);
      const seen = new Set();
      for (const item of pkg.stores[name]) {
        const key = itemKey(name, item);
        if (!key) throw new Error(`Hay un registro sin identificador estable en ${name}.`);
        if (seen.has(key)) throw new Error(`Hay un identificador duplicado en ${name}: ${key}.`);
        seen.add(key);
      }
    }
    const declaredCounts = pkg.statistics?.store_counts || {};
    for (const name of Object.keys(pkg.stores)) {
      if (Number(declaredCounts[name]) !== pkg.stores[name].length) throw new Error(`El conteo declarado para ${name} no coincide con su contenido.`);
    }
    if (await sha256(pkg.local_storage) !== pkg.checksums.local_storage) throw new Error("Fallo la integridad de localStorage. No se importo ningun dato.");
    const without = { ...pkg };
    delete without.checksums;
    if (await sha256(without) !== pkg.checksums.payload) throw new Error("El archivo fue modificado o esta dañado. No se importo ningun dato.");
    return pkg;
  }

  async function parseFileText(text, password = "") {
    let parsed;
    try { parsed = JSON.parse(text); } catch { throw new Error("El archivo no contiene JSON valido. No se importo ningun dato."); }
    const pkg = migratePackage(await decryptEnvelope(parsed, password));
    return validatePackage(pkg);
  }

  function migratePackage(pkg) {
    if (!pkg || !Number.isInteger(pkg.format_version)) return pkg;
    if (pkg.format_version > FORMAT_VERSION) throw new Error(`Version de copia no compatible: ${pkg.format_version}. No se importo ningun dato.`);
    let current = pkg;
    while (current.format_version < FORMAT_VERSION) {
      const migrator = MIGRATORS.get(current.format_version);
      if (!migrator) throw new Error(`No existe un migrador seguro desde la version ${current.format_version}. No se importo ningun dato.`);
      current = migrator(structuredClone(current));
    }
    return current;
  }

  function compareStores(currentStores, incomingStores) {
    const result = { new_records:0, identical:0, different:0, logically_deleted:0, possible_duplicates:0, stores:{} };
    const operations = [];
    const names = Array.from(new Set([...Object.keys(currentStores), ...Object.keys(incomingStores)])).sort();
    names.forEach((name) => {
      const current = new Map((currentStores[name] || []).map((item) => [itemKey(name, item), item]));
      const summary = { current:current.size, incoming:(incomingStores[name] || []).length, new_records:0, identical:0, different:0, logically_deleted:0 };
      (incomingStores[name] || []).forEach((item) => {
        const key = itemKey(name, item);
        const local = current.get(key);
        if (!local) {
          summary.new_records++; result.new_records++;
          if (item.deleted_at) { summary.logically_deleted++; result.logically_deleted++; }
          operations.push({ action:"add", store:name, key, incoming:item });
        } else if (canonicalStringify(local) === canonicalStringify(item)) {
          summary.identical++; result.identical++;
        } else {
          summary.different++; result.different++;
          operations.push({ action:"conflict", store:name, key, current:local, incoming:item });
        }
      });
      result.stores[name] = summary;
    });
    return { summary:result, operations };
  }

  async function createPreview(pkg, options = {}) {
    await validatePackage(pkg);
    const access = options.access || root.JarvisLocalStore?.backupAccess;
    const db = await access.openDatabase();
    let currentStores;
    const availableStores = Array.from(db.objectStoreNames);
    try { currentStores = await readDatabase(db); } finally { db.close(); }
    const comparison = compareStores(currentStores, pkg.stores);
    const existingImportConflicts = new Set((currentStores.sync_conflicts || []).filter((item) => item.reason === "backup-import-different" && item.source_checksum).map((item) => `${item.source_checksum}|${item.entity}|${item.entity_id}`));
    const operations = comparison.operations.filter((operation) => operation.action !== "conflict" || !existingImportConflicts.has(`${pkg.checksums.payload}|${operation.store}|${operation.key}`));
    comparison.summary.existing_import_conflicts = comparison.operations.length - operations.length;
    const importMarkerKey = `backup_import:${pkg.checksums.payload.slice(0, 24)}`;
    const currentWorkspace = (options.storage || root.localStorage).getItem("jarvis_workspace_id") || "";
    const currentDevice = (options.storage || root.localStorage).getItem("jarvis_device_id") || "";
    return {
      package:pkg,
      summary:comparison.summary,
      operations,
      workspace_mismatch:Boolean(currentWorkspace && pkg.workspace_id && currentWorkspace !== pkg.workspace_id),
      device_mismatch:Boolean(currentDevice && pkg.device_id && currentDevice !== pkg.device_id),
      current_workspace_id:currentWorkspace,
      current_device_id:currentDevice,
      identity_action:"preserve-current",
      local_storage_action:"not-imported-in-controlled-merge",
      incompatible_stores:Object.keys(pkg.stores).filter((name) => !availableStores.includes(name)),
      import_marker_key:importMarkerKey,
      already_imported:(currentStores.metadata || []).some((item) => item.key === importMarkerKey)
    };
  }

  async function conflictFromOperation(operation, pkg) {
    const stableId = await sha256(`${pkg.checksums.payload}|${operation.store}|${operation.key}`);
    return {
      conflict_id:`conflict-import-${stableId.slice(0, 24)}`,
      entity:operation.store,
      entity_id:operation.key,
      reason:"backup-import-different",
      local_value:decodeValue(operation.current),
      remote_value:decodeValue(operation.incoming),
      source_origin:pkg.source_origin,
      source_exported_at:pkg.exported_at,
      source_checksum:pkg.checksums.payload,
      created_at:new Date().toISOString()
    };
  }

  async function applyPreview(preview, options = {}) {
    if (!preview || !preview.package || !Array.isArray(preview.operations)) throw new Error("Primero revisa una vista previa valida.");
    if (preview.workspace_mismatch) throw new Error("Este archivo pertenece a otro workspace. Fase 0 no mezcla workspaces automaticamente.");
    if (preview.incompatible_stores?.length) throw new Error(`La copia contiene stores no compatibles: ${preview.incompatible_stores.join(", ")}.`);
    if (!options.backupConfirmed) throw new Error("Descarga primero la copia de seguridad previa a la importacion.");
    const access = options.access || root.JarvisLocalStore?.backupAccess;
    const db = await access.openDatabase();
    const additions = preview.operations.filter((operation) => operation.action === "add");
    const differences = preview.operations.filter((operation) => operation.action === "conflict");
    const preparedConflicts = [];
    for (const operation of differences) preparedConflicts.push(await conflictFromOperation(operation, preview.package));
    const needsMarker = !preview.already_imported;
    const storeNames = Array.from(new Set([...additions.map((op) => op.store), ...(differences.length ? ["sync_conflicts"] : []), ...(needsMarker ? ["metadata"] : [])]));
    if (!storeNames.length) { db.close(); return { added:0, conflicts:0, identical:preview.summary.identical, imported_snapshot_recorded:false, message:"No habia cambios para importar." }; }
    const tx = db.transaction(storeNames, "readwrite");
    const completion = transactionPromise(tx);
    try {
      const ordinary = additions.filter((op) => op.store !== "metadata");
      const metadata = additions.filter((op) => op.store === "metadata");
      let index = 0;
      for (const operation of ordinary) {
        tx.objectStore(operation.store).add(decodeValue(operation.incoming));
        index++;
        if (options.failAfter && index >= options.failAfter) throw new Error("Fallo de prueba solicitado.");
      }
      for (const conflict of preparedConflicts) tx.objectStore("sync_conflicts").add(conflict);
      // Los cursores y demás metadata se agregan al final de la misma
      // transacción, después de que entidades e historial quedaron preparados.
      for (const operation of metadata) {
        tx.objectStore(operation.store).add(decodeValue(operation.incoming));
        index++;
        if (options.failAfter && index >= options.failAfter) throw new Error("Fallo de prueba solicitado.");
      }
      if (needsMarker) tx.objectStore("metadata").add({ key:preview.import_marker_key, source:"backup-import", source_origin:preview.package.source_origin, source_exported_at:preview.package.exported_at, source_checksum:preview.package.checksums.payload, workspace_id:preview.package.workspace_id, device_id:preview.package.device_id, added_records:additions.length, conflicts_created:differences.length, completed_at:new Date().toISOString() });
    } catch (error) {
      try { tx.abort(); } catch {}
      try { await completion; } catch {}
      db.close();
      throw new Error(`${error.message} La transaccion fue cancelada; no se modifico ningun dato.`);
    }
    try {
      await completion;
    } catch (error) {
      throw new Error(`${error.message || "Fallo IndexedDB"}. La transaccion fue cancelada; no se modifico ningun dato.`);
    } finally {
      db.close();
    }
    return { added:additions.length, conflicts:differences.length, identical:preview.summary.identical, identity_preserved:true, local_storage_preserved:true, imported_snapshot_recorded:needsMarker };
  }

  function inventoryFromPackage(pkg) {
    return {
      origin:pkg.source_origin,
      protocol:pkg.source_protocol,
      database_name:pkg.database_name,
      database_version:pkg.database_version,
      workspace_id:pkg.workspace_id,
      device_id:pkg.device_id,
      exported_at:pkg.exported_at,
      statistics:pkg.statistics,
      cursors:pkg.cursors,
      last_contact:pkg.local_storage?.jarvis_notebook_last_contact || null,
      last_backup:pkg.local_storage?.jarvis_last_backup_exported_at || null
    };
  }

  function comparePackages(packages) {
    if (!Array.isArray(packages) || packages.length < 2) throw new Error("Selecciona al menos dos copias para comparar.");
    const sources = packages.map((pkg, index) => ({ index, origin:pkg.source_origin, workspace_id:pkg.workspace_id, device_id:pkg.device_id, exported_at:pkg.exported_at, statistics:pkg.statistics }));
    const records = [];
    const stores = Array.from(new Set(packages.flatMap((pkg) => Object.keys(pkg.stores)))).sort();
    stores.forEach((store) => {
      const keys = new Set(packages.flatMap((pkg) => (pkg.stores[store] || []).map((item) => itemKey(store, item))));
      keys.forEach((key) => {
        const values = packages.map((pkg) => (pkg.stores[store] || []).find((item) => itemKey(store, item) === key));
        const present = values.map((value, index) => value === undefined ? null : index).filter((value) => value !== null);
        const hashes = values.filter((value) => value !== undefined).map(canonicalStringify);
        records.push({ store, key, present_in:present, status:present.length === packages.length && new Set(hashes).size === 1 ? "coincidente" : (new Set(hashes).size > 1 ? "diferente" : "exclusivo") });
      });
    });
    return { sources, records, totals:{ coincident:records.filter((r) => r.status === "coincidente").length, different:records.filter((r) => r.status === "diferente").length, exclusive:records.filter((r) => r.status === "exclusivo").length } };
  }

  function downloadJson(value, filename) {
    const blob = new Blob([JSON.stringify(value, null, 2)], { type:"application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = filename;
    link.rel = "noopener";
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return { FORMAT_VERSION, CRYPTO_FORMAT_VERSION, APP_VERSION, PBKDF2_ITERATIONS, canonicalStringify, sha256, encodeValue, decodeValue, createPackage, attachChecksums, encryptPackage, decryptEnvelope, validatePackage, migratePackage, parseFileText, compareStores, createPreview, applyPreview, inventoryFromPackage, comparePackages, downloadJson, buildStatistics, extractCursors, itemKey };
});
