"use strict";
const assert = require("assert");
const Backup = require("../src/web/static/jarvis-backup.js");

class MemoryStorage {
  constructor(values = {}) { this.values = { ...values }; }
  get length() { return Object.keys(this.values).length; }
  key(index) { return Object.keys(this.values)[index] ?? null; }
  getItem(key) { return Object.prototype.hasOwnProperty.call(this.values, key) ? String(this.values[key]) : null; }
  setItem(key, value) { this.values[key] = String(value); }
}

class MemoryDb {
  constructor(stores = {}, version = 5) {
    this.version = version; this.name = "jarvis-local-first";
    this.data = Object.fromEntries(Object.entries(stores).map(([name, items]) => [name, items.map((item) => structuredClone(item))]));
    this.objectStoreNames = Object.keys(this.data).sort();
  }
  close() {}
  transaction(names, mode) {
    names = Array.isArray(names) ? names : [names];
    const db = this;
    const draft = Object.fromEntries(Object.entries(this.data).map(([name, items]) => [name, items.map((item) => structuredClone(item))]));
    const tx = { oncomplete:null, onabort:null, onerror:null, error:null, aborted:false, pending:0 };
    const key = (name, item) => String(item[({ sync_changes:"change_id", sync_conflicts:"conflict_id", metadata:"key" })[name] || "id"]);
    let finishTimer = null;
    const schedule = (work) => {
      clearTimeout(finishTimer);
      const request = { onsuccess:null, onerror:null, result:undefined, error:null }; tx.pending++;
      setTimeout(() => {
        if (!tx.aborted) {
          try { request.result = work(); request.onsuccess?.(); }
          catch (error) { request.error=error; tx.error=error; request.onerror?.(); tx.abort(); }
        }
        tx.pending--; finish();
      }, 0);
      return request;
    };
    const finish = () => {
      clearTimeout(finishTimer);
      if (tx.pending || tx.aborted) return;
      finishTimer = setTimeout(() => { if (!tx.aborted) { if (mode === "readwrite") db.data = draft; tx.oncomplete?.(); } }, 0);
    };
    tx.abort = () => { if (tx.aborted) return; tx.aborted=true; tx.error ||= new Error("AbortError"); setTimeout(() => tx.onabort?.(), 0); };
    tx.objectStore = (name) => ({
      getAll:() => schedule(() => draft[name].map((item) => structuredClone(item))),
      add:(item) => schedule(() => { const k=key(name,item); if(draft[name].some((x)=>key(name,x)===k)) throw new Error("ConstraintError"); draft[name].push(structuredClone(item)); return k; })
    });
    finish();
    return tx;
  }
}

const password = "contraseña-segura-123";
const storeNames = ["records","finance_movements","finance_categories","finance_priorities","finance_payment_methods","finance_settings","calendar_events","study_subjects","study_topics","study_evaluations","study_assignments","study_notes","study_schedules","file_assets","file_links","local_file_roots","local_file_locations","sync_changes","sync_conflicts","metadata"];
function accessFor(db) { return { databaseName:db.name, databaseVersion:db.version, openDatabase:async()=>db }; }
function storage(workspace="workspace-a", device="device-a") { return new MemoryStorage({ jarvis_workspace_id:workspace, jarvis_device_id:device, jarvis_workspace_name:"Mi Jarvis ñ", jarvis_device_name:"iPhone de prueba", jarvis_sync_secret:"secret-private", jarvis_linked_devices:"[]", jarvis_user_display_name:"Usuario de prueba" }); }
function storesFull() { return { ...Object.fromEntries(storeNames.map((name) => [name, []])),
  records:[{ id:"r1", text:"Árbol y café ☕", updated_at:"2026-08-19T10:00:00", deleted_at:null },{ id:"r2", text:"borrado", deleted_at:"2026-08-19T11:00:00" }],
  finance_movements:[{ id:"m1", amount:123456789.25, currency:"ARS" }],
  sync_changes:[{ change_id:"c1", workspace_id:"workspace-a", entity:"records", entity_id:"r1", synced_at:null }],
  sync_conflicts:[{ conflict_id:"x1", entity:"records", entity_id:"r9", local_value:{a:1}, remote_value:{a:2} }],
  metadata:[{ key:"notebook_sync:http://lan", last_server_cursor:"2026-08-19T12:00:00" }]
}; }

async function packageFrom(stores, workspace="workspace-a", device="device-a") {
  const db = new MemoryDb(stores);
  return Backup.createPackage({ access:accessFor(db), storage:storage(workspace,device), origin:"https://example.test", protocol:"https:" });
}

async function expectReject(promise, text) { let error; try { await promise; } catch (e) { error=e; } assert(error, `Expected rejection containing ${text}`); assert(String(error.message).includes(text), error.message); }

(async () => {
  const emptyStores = Object.fromEntries(storeNames.map((name) => [name, []]));
  const empty = await packageFrom(emptyStores);
  assert.equal(empty.statistics.total_records, 0, "base vacia");
  assert.deepEqual(Object.keys(empty.stores), [...storeNames].sort(), "todos los stores");

  const full = await packageFrom(storesFull());
  assert.equal(full.stores.records[0].text, "Árbol y café ☕", "UTF-8");
  assert.equal(full.statistics.logically_deleted, 1, "borrado logico");
  assert.equal(full.statistics.pending_changes, 1, "pendientes");
  assert.equal(full.statistics.conflicts, 1, "conflictos");
  assert.equal(full.cursors["notebook_sync:http://lan"], "2026-08-19T12:00:00", "cursor");
  await Backup.validatePackage(full);

  const fullAgain = await packageFrom({ ...storesFull(), records:[...storesFull().records].reverse() });
  assert.equal(Backup.canonicalStringify(full.stores), Backup.canonicalStringify(fullAgain.stores), "orden determinista");
  assert.equal(full.checksums.stores.records, fullAgain.checksums.stores.records, "checksum determinista");

  const large = await packageFrom({ ...emptyStores, records:[{ id:"large", text:"á".repeat(1024*1024) }] });
  await Backup.validatePackage(large); assert.equal(large.stores.records[0].text.length, 1024*1024, "valor grande");

  const envelope = await Backup.encryptPackage(full, password);
  assert.equal(envelope.cipher.name, "AES-GCM"); assert.equal(envelope.kdf.name, "PBKDF2");
  const secondEnvelope = await Backup.encryptPackage(full, password);
  assert.notEqual(secondEnvelope.kdf.salt, envelope.kdf.salt, "salt nuevo por exportacion");
  assert.notEqual(secondEnvelope.cipher.iv, envelope.cipher.iv, "IV nuevo por exportacion");
  const decrypted = await Backup.decryptEnvelope(envelope, password);
  assert.equal(decrypted.workspace_id, full.workspace_id, "descifrado");
  await expectReject(Backup.decryptEnvelope(envelope, "contraseña-equivocada"), "Contraseña incorrecta");
  const tampered = structuredClone(envelope); tampered.ciphertext = `${tampered.ciphertext.slice(0,-4)}AAAA`;
  await expectReject(Backup.decryptEnvelope(tampered, password), "archivo dañado");
  const malformedCrypto = structuredClone(envelope); malformedCrypto.cipher.iv = "AA==";
  await expectReject(Backup.decryptEnvelope(malformedCrypto, password), "Parametros de cifrado invalidos");
  const corrupted = structuredClone(full); corrupted.stores.records[0].text="manipulado";
  await expectReject(Backup.validatePackage(corrupted), "integridad");
  const future = structuredClone(full); future.format_version=99;
  await expectReject(Backup.validatePackage(future), "Version de copia no compatible");
  const incomplete = structuredClone(full); delete incomplete.stores.metadata; incomplete.checksums = (await Backup.attachChecksums({ ...incomplete, checksums:{} })).checksums;
  await expectReject(Backup.validatePackage(incomplete), "stores obligatorios");
  const invalidSections = structuredClone(full); invalidSections.pending_changes={}; invalidSections.checksums = (await Backup.attachChecksums({ ...invalidSections, checksums:{} })).checksums;
  await expectReject(Backup.validatePackage(invalidSections), "secciones historicas");
  const duplicated = structuredClone(full); duplicated.stores.records.push(structuredClone(duplicated.stores.records[0])); duplicated.checksums = (await Backup.attachChecksums({ ...duplicated, checksums:{} })).checksums;
  await expectReject(Backup.validatePackage(duplicated), "identificador duplicado");
  const circular = {}; circular.self = circular;
  await expectReject(Backup.encodeValue(circular), "Referencia circular");

  const currentDb = new MemoryDb({ ...emptyStores, records:[{ id:"same", value:1 },{ id:"different", value:"local" }], sync_conflicts:[] });
  const incoming = await packageFrom({ ...emptyStores, records:[{ id:"same", value:1 },{ id:"different", value:"remoto" },{ id:"new", value:"nuevo" }], sync_conflicts:[] });
  let preview = await Backup.createPreview(incoming, { access:accessFor(currentDb), storage:storage() });
  assert.deepEqual([preview.summary.new_records,preview.summary.identical,preview.summary.different],[1,1,1],"vista previa");
  assert.equal(currentDb.data.records.length,2,"preview no modifica");
  await expectReject(Backup.applyPreview(preview,{access:accessFor(currentDb),backupConfirmed:false}),"Descarga primero");
  const applied = await Backup.applyPreview(preview,{access:accessFor(currentDb),backupConfirmed:true});
  assert.deepEqual([applied.added,applied.conflicts],[1,1],"merge controlado");
  assert.equal(currentDb.data.records.find((x)=>x.id==="different").value,"local","no reemplaza diferente");
  assert.equal(currentDb.data.sync_conflicts.length,1,"conflicto visible");

  preview = await Backup.createPreview(incoming, { access:accessFor(currentDb), storage:storage() });
  const repeated = await Backup.applyPreview(preview,{access:accessFor(currentDb),backupConfirmed:true});
  assert.equal(repeated.added,0,"repeticion idempotente");
  assert.equal(repeated.conflicts,0,"no duplica conflictos al repetir");
  assert.equal(currentDb.data.sync_conflicts.length,1,"un solo conflicto estable");

  const rollbackDb = new MemoryDb({ ...emptyStores, records:[], sync_conflicts:[] });
  const two = await packageFrom({ ...emptyStores, records:[{id:"a"},{id:"b"}], sync_conflicts:[] });
  const rollbackPreview = await Backup.createPreview(two,{access:accessFor(rollbackDb),storage:storage()});
  await expectReject(Backup.applyPreview(rollbackPreview,{access:accessFor(rollbackDb),backupConfirmed:true,failAfter:1}),"cancelada");
  assert.equal(rollbackDb.data.records.length,0,"rollback completo");

  const otherWorkspace = await packageFrom(emptyStores,"workspace-b","device-b");
  const mismatch = await Backup.createPreview(otherWorkspace,{access:accessFor(currentDb),storage:storage()});
  assert.equal(mismatch.workspace_mismatch,true,"workspace diferente");
  await expectReject(Backup.applyPreview(mismatch,{access:accessFor(currentDb),backupConfirmed:true}),"otro workspace");
  const otherDevice = await packageFrom(emptyStores,"workspace-a","device-b");
  const devicePreview = await Backup.createPreview(otherDevice,{access:accessFor(currentDb),storage:storage()});
  assert.equal(devicePreview.device_mismatch,true,"device ID diferente se informa");

  const comparison = Backup.comparePackages([full,incoming]);
  assert(comparison.totals.exclusive > 0 && comparison.sources.length===2,"comparacion de origenes");
  console.log("backup-tests: 39 escenarios OK");
})().catch((error) => { console.error(error); process.exit(1); });
