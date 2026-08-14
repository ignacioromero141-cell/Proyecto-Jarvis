(function () {
  const DB_NAME = "jarvis-local-first";
  const DB_VERSION = 5;
  const DEVICE_KEY = "jarvis_device_id";
  const WORKSPACE_KEY = "jarvis_workspace_id";
  const WORKSPACE_NAME_KEY = "jarvis_workspace_name";
  const DEVICE_NAME_KEY = "jarvis_device_name";
  const SYNC_SECRET_KEY = "jarvis_sync_secret";
  const NOTEBOOK_URL_KEY = "jarvis_notebook_sync_url";

  const defaultCategories = [
    { id:"income", label:"Ingreso", kind:"income", color:"#2176ae", enabled:true, sort_order:10 },
    { id:"food", label:"Comida", kind:"expense", color:"#f97316", enabled:true, sort_order:20 },
    { id:"health", label:"Salud", kind:"expense", color:"#16a34a", enabled:true, sort_order:30 },
    { id:"education", label:"Educacion", kind:"expense", color:"#2563eb", enabled:true, sort_order:40 },
    { id:"transport", label:"Transporte", kind:"expense", color:"#64748b", enabled:true, sort_order:50 },
    { id:"leisure", label:"Ocio", kind:"expense", color:"#7c3aed", enabled:true, sort_order:60 },
    { id:"savings", label:"Ahorro / inversion", kind:"saving", color:"#0f766e", enabled:true, sort_order:70 },
    { id:"other", label:"Otros", kind:"expense", color:"#94a3b8", enabled:true, sort_order:999 }
  ];

  const defaultPriorities = [
    { id:"necessary", label:"Necesario", description:"Gasto importante para vivir, estudiar, trabajar o cuidar la salud.", color:"#16a34a", sort_order:10 },
    { id:"personal_investment", label:"Inversion personal", description:"Gasto que puede mejorar tu futuro: educacion, libros, cursos, salud, deporte.", color:"#2563eb", sort_order:20 },
    { id:"optional", label:"Prescindible", description:"Gusto o compra que podrias recortar si necesitas ahorrar.", color:"#dc2626", sort_order:30 }
  ];

  const defaultPaymentMethods = [
    { id:"cash", label:"Efectivo", enabled:true, built_in:true, sort_order:10, deleted_at:null, created_at:null, updated_at:null },
    { id:"debit", label:"Debito", enabled:true, built_in:true, sort_order:20, deleted_at:null, created_at:null, updated_at:null },
    { id:"credit", label:"Credito", enabled:true, built_in:true, sort_order:30, deleted_at:null, created_at:null, updated_at:null },
    { id:"transfer", label:"Transferencia", enabled:true, built_in:true, sort_order:40, deleted_at:null, created_at:null, updated_at:null },
    { id:"wallet", label:"Billetera virtual", enabled:true, built_in:true, sort_order:50, deleted_at:null, created_at:null, updated_at:null }
  ];

  const defaultSettings = {
    id:"main",
    currency:"ARS",
    default_payment_method:"cash",
    monthly_targets:{ saving:30, necessary:20, optional:40, personal_investment:10 },
    updated_at:null
  };

  function nowText() {
    return new Date().toISOString().slice(0, 19);
  }

  function newId(prefix = "") {
    const value = crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    return `${prefix}${value}`;
  }

  function deviceId() {
    let id = localStorage.getItem(DEVICE_KEY);
    if (!id) {
      id = `pwa-${newId()}`;
      localStorage.setItem(DEVICE_KEY, id);
    }
    return id;
  }

  function workspaceId() {
    let id = localStorage.getItem(WORKSPACE_KEY);
    if (!id) {
      id = `workspace-${newId()}`;
      localStorage.setItem(WORKSPACE_KEY, id);
    }
    return id;
  }

  function workspaceName() {
    const name = localStorage.getItem(WORKSPACE_NAME_KEY);
    return name && name.trim() ? name.trim() : "Mi Jarvis";
  }

  function deviceName() {
    const name = localStorage.getItem(DEVICE_NAME_KEY);
    return name && name.trim() ? name.trim() : "Este dispositivo";
  }

  function syncSecret() {
    let secret = localStorage.getItem(SYNC_SECRET_KEY);
    if (!secret) {
      secret = newId("secret-");
      localStorage.setItem(SYNC_SECRET_KEY, secret);
    }
    return secret;
  }

  function setIdentity({ workspace_id, workspace_name, sync_secret, device_name } = {}) {
    if (workspace_id) localStorage.setItem(WORKSPACE_KEY, workspace_id);
    if (workspace_name) localStorage.setItem(WORKSPACE_NAME_KEY, workspace_name);
    if (sync_secret) localStorage.setItem(SYNC_SECRET_KEY, sync_secret);
    if (device_name) localStorage.setItem(DEVICE_NAME_KEY, device_name);
  }

  function openDb() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      let settled = false;
      const fail = (error) => {
        if (settled) return;
        settled = true;
        reject(error);
      };
      const timer = setTimeout(() => {
        fail(new Error("No se pudo abrir la base local de Jarvis. Cierra otras pestanas de Jarvis y vuelve a intentarlo."));
      }, 10000);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains("records")) db.createObjectStore("records", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_movements")) db.createObjectStore("finance_movements", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_categories")) db.createObjectStore("finance_categories", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_priorities")) db.createObjectStore("finance_priorities", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_payment_methods")) db.createObjectStore("finance_payment_methods", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_settings")) db.createObjectStore("finance_settings", { keyPath:"id" });
        if (!db.objectStoreNames.contains("calendar_events")) db.createObjectStore("calendar_events", { keyPath:"id" });
        if (!db.objectStoreNames.contains("study_subjects")) db.createObjectStore("study_subjects", { keyPath:"id" });
        if (!db.objectStoreNames.contains("study_topics")) db.createObjectStore("study_topics", { keyPath:"id" });
        if (!db.objectStoreNames.contains("study_evaluations")) db.createObjectStore("study_evaluations", { keyPath:"id" });
        if (!db.objectStoreNames.contains("study_assignments")) db.createObjectStore("study_assignments", { keyPath:"id" });
        if (!db.objectStoreNames.contains("study_notes")) db.createObjectStore("study_notes", { keyPath:"id" });
        if (!db.objectStoreNames.contains("study_schedules")) db.createObjectStore("study_schedules", { keyPath:"id" });
        if (!db.objectStoreNames.contains("file_assets")) db.createObjectStore("file_assets", { keyPath:"id" });
        if (!db.objectStoreNames.contains("file_links")) db.createObjectStore("file_links", { keyPath:"id" });
        if (!db.objectStoreNames.contains("local_file_roots")) db.createObjectStore("local_file_roots", { keyPath:"id" });
        if (!db.objectStoreNames.contains("local_file_locations")) db.createObjectStore("local_file_locations", { keyPath:"id" });
        if (!db.objectStoreNames.contains("sync_changes")) db.createObjectStore("sync_changes", { keyPath:"change_id" });
        if (!db.objectStoreNames.contains("sync_conflicts")) db.createObjectStore("sync_conflicts", { keyPath:"conflict_id" });
        if (!db.objectStoreNames.contains("metadata")) db.createObjectStore("metadata", { keyPath:"key" });
      };
      request.onsuccess = () => {
        clearTimeout(timer);
        const db = request.result;
        db.onversionchange = () => {
          db.close();
        };
        if (settled) {
          db.close();
          return;
        }
        settled = true;
        resolve(db);
      };
      request.onerror = () => {
        clearTimeout(timer);
        fail(request.error || new Error("No se pudo abrir la base local de Jarvis."));
      };
      request.onblocked = () => {
        clearTimeout(timer);
        fail(new Error("Jarvis necesita actualizar la base local. Cierra otras pestanas de Jarvis y abre Estudio nuevamente."));
      };
    });
  }

  function requestToPromise(request) {
    return new Promise((resolve, reject) => {
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async function store(name, mode = "readonly") {
    const db = await openDb();
    return db.transaction(name, mode).objectStore(name);
  }

  async function all(name) {
    return requestToPromise((await store(name)).getAll());
  }

  async function put(name, value) {
    return requestToPromise((await store(name, "readwrite")).put(value));
  }

  async function get(name, id) {
    return requestToPromise((await store(name)).get(id));
  }

  async function remove(name, id) {
    return requestToPromise((await store(name, "readwrite")).delete(id));
  }

  async function ensureDefaults() {
    await importNotebookSnapshotIfNeeded();

    const categories = await all("finance_categories");
    if (!categories.length) {
      for (const category of defaultCategories) await put("finance_categories", category);
    }
    const priorities = await all("finance_priorities");
    if (!priorities.length) {
      for (const priority of defaultPriorities) await put("finance_priorities", priority);
    }
    const paymentMethods = await all("finance_payment_methods");
    if (!paymentMethods.length) {
      const time = nowText();
      for (const method of defaultPaymentMethods) await put("finance_payment_methods", { ...method, created_at:time, updated_at:time });
    }
    const settings = await get("finance_settings", "main");
    if (!settings) await put("finance_settings", defaultSettings);
  }

  async function localUserDataIsEmpty() {
    const counts = await Promise.all([
      all("records"),
      all("finance_movements"),
      all("study_subjects"),
      all("calendar_events")
    ]);
    return counts.every((items) => !items.length);
  }

  async function importList(storeName, items) {
    let imported = 0;
    for (const item of Array.isArray(items) ? items : []) {
      if (!item || !item.id) continue;
      await put(storeName, item);
      imported += 1;
    }
    return imported;
  }

  function normalizeSettings(settings) {
    if (!settings || typeof settings !== "object") return null;
    return { id:"main", ...settings };
  }

  async function importNotebookSnapshotIfNeeded() {
    const metadata = await get("metadata", "notebook_bootstrap_v1");
    if (metadata?.completed_at) return metadata;
    if (!(await localUserDataIsEmpty())) return null;
    if (!["localhost", "127.0.0.1"].includes(location.hostname) && !/^192\.168\.|^10\.|^172\.(1[6-9]|2\d|3[0-1])\./.test(location.hostname)) return null;

    let response;
    try {
      response = await fetch("/api/bootstrap/export", { cache:"no-store" });
    } catch {
      return null;
    }
    if (!response.ok) return null;

    const data = await response.json();
    const snapshot = data?.snapshot;
    if (!data?.ok || !snapshot) return null;

    const imported = {
      records:await importList("records", snapshot.records),
      finance_movements:await importList("finance_movements", snapshot.finance?.movements),
      finance_categories:await importList("finance_categories", snapshot.finance?.categories),
      finance_priorities:await importList("finance_priorities", snapshot.finance?.priorities),
      finance_payment_methods:await importList("finance_payment_methods", snapshot.finance?.payment_methods),
      finance_settings:0,
      calendar_events:await importList("calendar_events", snapshot.calendar?.events),
      study_subjects:await importList("study_subjects", snapshot.study?.subjects),
      study_topics:await importList("study_topics", snapshot.study?.topics),
      study_evaluations:await importList("study_evaluations", snapshot.study?.evaluations),
      study_assignments:await importList("study_assignments", snapshot.study?.assignments),
      study_notes:await importList("study_notes", snapshot.study?.notes),
      study_schedules:await importList("study_schedules", snapshot.study?.schedules),
      file_assets:await importList("file_assets", snapshot.files?.assets),
      file_links:await importList("file_links", snapshot.files?.links)
    };

    const settings = normalizeSettings(snapshot.finance?.settings);
    if (settings) {
      await put("finance_settings", settings);
      imported.finance_settings = 1;
    }

    const result = {
      key:"notebook_bootstrap_v1",
      source:snapshot.source || "notebook-json",
      schema_version:snapshot.schema_version || 1,
      generated_at:snapshot.generated_at || null,
      completed_at:nowText(),
      imported
    };
    await put("metadata", result);
    return result;
  }

  async function track(entity, entityId, operation, value) {
    await put("sync_changes", {
      change_id:newId("change-"),
      entity,
      entity_id:entityId,
      operation,
      value,
      workspace_id:workspaceId(),
      device_id:deviceId(),
      created_at:nowText(),
      synced_at:null
    });
  }

  async function pendingChanges() {
    return (await all("sync_changes")).filter((change) => change.device_id === deviceId() && !change.synced_at);
  }

  async function markChangesSynced(changeIds) {
    const syncedAt = nowText();
    const ids = new Set(Array.isArray(changeIds) ? changeIds : []);
    for (const change of await all("sync_changes")) {
      if (!ids.has(change.change_id)) continue;
      change.synced_at = syncedAt;
      await put("sync_changes", change);
    }
  }

  async function rememberRemoteChange(change) {
    await put("sync_changes", { ...change, synced_at:nowText() });
  }

  function dateValue(value, field) {
    const text = value && value[field] ? String(value[field]) : "";
    const time = Date.parse(text);
    return Number.isFinite(time) ? time : 0;
  }

  function remoteWins(localValue, remoteValue) {
    const localDeleted = dateValue(localValue, "deleted_at");
    const remoteDeleted = dateValue(remoteValue, "deleted_at");
    if (remoteDeleted > localDeleted && remoteDeleted > dateValue(localValue, "updated_at")) return true;
    return dateValue(remoteValue, "updated_at") > dateValue(localValue, "updated_at");
  }

  function storeForEntity(entity) {
    const stores = {
      records:"records",
      finance_movements:"finance_movements",
      finance_categories:"finance_categories",
      finance_priorities:"finance_priorities",
      finance_payment_methods:"finance_payment_methods",
      finance_settings:"finance_settings",
      calendar_events:"calendar_events",
      study_subjects:"study_subjects",
      study_topics:"study_topics",
      study_evaluations:"study_evaluations",
      study_assignments:"study_assignments",
      study_notes:"study_notes",
      study_schedules:"study_schedules",
      file_assets:"file_assets",
      file_links:"file_links"
    };
    return stores[entity] || null;
  }

  async function addConflict(change, localValue, remoteValue, reason) {
    const conflict = {
      conflict_id:newId("conflict-"),
      entity:change.entity,
      entity_id:change.entity_id,
      remote_change_id:change.change_id,
      reason,
      local_value:localValue,
      remote_value:remoteValue,
      created_at:nowText()
    };
    await put("sync_conflicts", conflict);
    return conflict;
  }

  async function applyRemoteChange(change) {
    if (!change || !change.change_id || change.device_id === deviceId()) {
      return { status:"skipped", reason:"own-or-invalid-change", change_id:change?.change_id || "" };
    }
    if (change.workspace_id && change.workspace_id !== workspaceId()) {
      return { status:"rejected", reason:"workspace-mismatch", change_id:change.change_id };
    }

    if (await get("sync_changes", change.change_id)) {
      return { status:"skipped", reason:"already-seen", change_id:change.change_id };
    }

    const storeName = storeForEntity(change.entity);
    if (!storeName) {
      await addConflict(change, null, change.value || {}, "unsupported-entity");
      await rememberRemoteChange(change);
      return { status:"conflict", reason:"unsupported-entity", change_id:change.change_id };
    }

    const remoteValue = { ...(change.value || {}) };
    if (!remoteValue.id) remoteValue.id = change.entity_id;
    const localValue = await get(storeName, change.entity_id);

    if (!localValue) {
      await put(storeName, remoteValue);
      await rememberRemoteChange(change);
      return { status:"accepted", reason:"created", change_id:change.change_id };
    }

    if (remoteWins(localValue, remoteValue)) {
      await put(storeName, remoteValue);
      await rememberRemoteChange(change);
      return { status:"accepted", reason:"updated", change_id:change.change_id };
    }

    if (dateValue(remoteValue, "updated_at") < dateValue(localValue, "updated_at")) {
      const conflict = await addConflict(change, localValue, remoteValue, "local-newer-than-remote");
      await rememberRemoteChange(change);
      return { status:"conflict", reason:conflict.reason, change_id:change.change_id, conflict_id:conflict.conflict_id };
    }

    await rememberRemoteChange(change);
    return { status:"skipped", reason:"duplicate-or-same-version", change_id:change.change_id };
  }

  function normalizeNotebookUrl(value) {
    const text = String(value || "").trim();
    if (!text) return "";
    const withProtocol = /^https?:\/\//i.test(text) ? text : `http://${text}`;
    try {
      return new URL(withProtocol).origin.replace(/\/+$/, "");
    } catch {
      throw new Error("La URL/IP de sincronizacion no es valida.");
    }
  }

  async function readJsonResponse(response, label) {
    const contentType = response.headers.get("Content-Type") || "";
    const text = await response.text();
    if (!contentType.includes("application/json")) {
      const preview = text.trim().slice(0, 80).replace(/\s+/g, " ");
      throw new Error(`El endpoint ${label} no devolvio JSON. Verifica la URL/IP configurada. Respuesta: ${preview || response.status}`);
    }
    try {
      return JSON.parse(text);
    } catch {
      throw new Error(`El endpoint ${label} devolvio JSON invalido.`);
    }
  }

  function networkErrorMessage(error, url) {
    const message = String(error?.message || error || "");
    if (/load failed|failed to fetch|networkerror/i.test(message)) {
      return `No se pudo conectar con la notebook en ${url}. Verifica que Jarvis este abierto, que ambos dispositivos esten en la misma Wi-Fi y que la URL/IP sea correcta.`;
    }
    return message || "No se pudo completar la conexion.";
  }

  function defaultNotebookUrl() {
    if (["localhost", "127.0.0.1"].includes(location.hostname) || /^192\.168\.|^10\.|^172\.(1[6-9]|2\d|3[0-1])\./.test(location.hostname)) {
      return location.origin;
    }
    return "";
  }

  function syncMetadataKey(baseUrl) {
    return `notebook_sync:${baseUrl}`;
  }

  async function syncStatus() {
    await ensureDefaults();
    const pending = await pendingChanges();
    const conflicts = await all("sync_conflicts");
    const notebookUrl = normalizeNotebookUrl(localStorage.getItem(NOTEBOOK_URL_KEY)) || defaultNotebookUrl();
    const metadata = notebookUrl ? await get("metadata", syncMetadataKey(notebookUrl)) : null;
    return {
      ok:true,
      local_only:true,
      workspace_id:workspaceId(),
      workspace_name:workspaceName(),
      device_id:deviceId(),
      device_name:deviceName(),
      pending_total:pending.length,
      conflict_count:conflicts.length,
      notebook_url:notebookUrl,
      last_sync_at:metadata?.last_sync_at || null,
      last_server_cursor:metadata?.last_server_cursor || null,
      linked_devices:JSON.parse(localStorage.getItem("jarvis_linked_devices") || "[]")
    };
  }

  function authHeaders() {
    return {
      "Content-Type":"application/json",
      "X-Jarvis-Workspace-Id":workspaceId(),
      "X-Jarvis-Device-Id":deviceId(),
      "X-Jarvis-Sync-Secret":syncSecret()
    };
  }

  async function syncWithNotebook(body = {}) {
    await ensureDefaults();
    const notebookUrl = normalizeNotebookUrl(body.notebook_url || localStorage.getItem(NOTEBOOK_URL_KEY) || defaultNotebookUrl());
    if (!notebookUrl) throw new Error("Configura la URL de la notebook para sincronizar.");
    localStorage.setItem(NOTEBOOK_URL_KEY, notebookUrl);

    const metadataKey = syncMetadataKey(notebookUrl);
    const metadata = await get("metadata", metadataKey);
    const localChanges = (await pendingChanges()).map((change) => ({ ...change, workspace_id:change.workspace_id || workspaceId() }));
    let response;
    try {
      response = await fetch(`${notebookUrl}/api/sync/apply`, {
        method:"POST",
        headers:authHeaders(),
        body:JSON.stringify({
          workspace_id:workspaceId(),
          device_id:deviceId(),
          device_name:deviceName(),
          since:metadata?.last_server_cursor || "",
          changes:localChanges
        })
      });
    } catch (error) {
      throw new Error(networkErrorMessage(error, notebookUrl));
    }
    const data = await readJsonResponse(response, `${notebookUrl}/api/sync/apply`);
    if (!response.ok || data.ok === false) throw new Error(data.error || "No se pudo sincronizar.");

    await markChangesSynced(data.accepted_change_ids || []);
    const remoteResults = [];
    for (const change of Array.isArray(data.changes) ? data.changes : []) {
      remoteResults.push(await applyRemoteChange(change));
    }

    const completedAt = nowText();
    await put("metadata", {
      key:metadataKey,
      notebook_url:notebookUrl,
      last_sync_at:completedAt,
      last_server_cursor:data.generated_at || completedAt,
      server_device_id:data.device_id || null
    });
    if (Array.isArray(data.linked_devices)) {
      localStorage.setItem("jarvis_linked_devices", JSON.stringify(data.linked_devices));
    }

    return {
      ok:true,
      notebook_url:notebookUrl,
      sent:localChanges.length,
      accepted:data.accepted_change_ids?.length || 0,
      received:Array.isArray(data.changes) ? data.changes.length : 0,
      remote_results:remoteResults,
      server_results:data.results || [],
      status:await syncStatus()
    };
  }

  async function createPairingCode() {
    const payload = {
      workspace_id:workspaceId(),
      workspace_name:workspaceName(),
      sync_secret:syncSecret(),
      created_by_device_id:deviceId(),
      created_by_device_name:deviceName(),
      created_at:nowText()
    };
    const json = JSON.stringify(payload);
    const bytes = new TextEncoder().encode(json);
    let binary = "";
    bytes.forEach((byte) => binary += String.fromCharCode(byte));
    return {
      ok:true,
      local_only:true,
      pairing_code:btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""),
      workspace_id:payload.workspace_id,
      workspace_name:payload.workspace_name
    };
  }

  async function joinWorkspace(body = {}) {
    const notebookUrl = normalizeNotebookUrl(body.notebook_url || localStorage.getItem(NOTEBOOK_URL_KEY) || defaultNotebookUrl());
    if (!notebookUrl) throw new Error("Configura la URL/IP del dispositivo a vincular.");
    const pairingCode = String(body.pairing_code || "").replace(/\s/g, "");
    if (!pairingCode) throw new Error("Ingresa el codigo de vinculacion.");
    let response;
    try {
      response = await fetch(`${notebookUrl}/api/sync/pairing/complete`, {
        method:"POST",
        headers:{ "Content-Type":"application/json" },
        body:JSON.stringify({
          pairing_code:pairingCode,
          device_id:deviceId(),
          device_name:body.device_name || deviceName()
        })
      });
    } catch (error) {
      throw new Error(networkErrorMessage(error, notebookUrl));
    }
    const data = await readJsonResponse(response, `${notebookUrl}/api/sync/pairing/complete`);
    if (!response.ok || data.ok === false) throw new Error(data.error || "No se pudo vincular el dispositivo.");
    setIdentity({
      workspace_id:data.workspace_id,
      workspace_name:data.workspace_name,
      sync_secret:data.sync_secret,
      device_name:body.device_name || deviceName()
    });
    localStorage.setItem(NOTEBOOK_URL_KEY, notebookUrl);
    if (Array.isArray(data.linked_devices)) {
      localStorage.setItem("jarvis_linked_devices", JSON.stringify(data.linked_devices));
    }
    return { ok:true, status:await syncStatus() };
  }

  async function saveSyncSettings(body = {}) {
    setIdentity({ workspace_name:body.workspace_name, device_name:body.device_name });
    if (body.notebook_url !== undefined) {
      localStorage.setItem(NOTEBOOK_URL_KEY, normalizeNotebookUrl(body.notebook_url));
    }
    return syncStatus();
  }

  async function listConflicts() {
    return { ok:true, conflicts:await all("sync_conflicts") };
  }

  async function resolveConflict(body = {}) {
    const conflict = await get("sync_conflicts", body.conflict_id);
    if (!conflict) throw new Error("No encontre ese conflicto.");
    const storeName = storeForEntity(conflict.entity);
    if (!storeName) throw new Error("Entidad no soportada.");
    if (body.resolution === "remote") {
      await put(storeName, conflict.remote_value);
      await track(conflict.entity, conflict.entity_id, "resolve-remote", conflict.remote_value);
    }
    await remove("sync_conflicts", body.conflict_id);
    return listConflicts();
  }

  function visible(items) {
    return items.filter((item) => !item.deleted_at);
  }

  function sortedMethods(methods) {
    return visible(methods).sort((a, b) => (Number(a.sort_order) || 999) - (Number(b.sort_order) || 999) || String(a.label || "").localeCompare(String(b.label || "")));
  }

  function recordsSummary(records) {
    const visibleRecords = visible(records);
    const pending = visibleRecords.filter((r) => r.type === "tarea" && (r.status || "pendiente") === "pendiente");
    const today = new Date().toISOString().slice(0, 10);
    return {
      total:visibleRecords.length,
      pending_tasks:pending.length,
      today_records:visibleRecords.filter((r) => String(r.created_at || "").slice(0, 10) === today).length,
      ideas:visibleRecords.filter((r) => r.type === "idea").length,
      memories:visibleRecords.filter((r) => r.type === "recuerdo").length
    };
  }

  function safeType(type) {
    return ["idea", "tarea", "recuerdo"].includes(type) ? type : "idea";
  }

  function tags(value) {
    if (Array.isArray(value)) return value.filter(Boolean);
    if (!value) return [];
    return String(value).split(",").map((item) => item.trim()).filter(Boolean);
  }

  function quickCapture(text) {
    if (!text || !String(text).trim()) throw new Error("Escribi algo antes de guardar.");
    let clean = String(text).trim();
    const lower = clean.toLowerCase();
    let type = "idea";
    if (/^(tarea|tengo que|debo|hacer|comprar|estudiar|leer)\b/.test(lower)) type = "tarea";
    else if (/^(recorda|recordar|recuerdo|dato)\b/.test(lower)) type = "recuerdo";
    clean = clean.replace(/^(idea|tarea|recuerdo|dato)\s*:\s*/i, "");
    clean = clean.replace(/^(recorda que|recordar que|recorda|recordar)\s+/i, "");
    clean = clean.replace(/^(tengo que|debo)\s+/i, "");
    return { type, text:clean.trim() };
  }

  async function createRecord(body) {
    const type = safeType(body.type);
    const text = String(body.text || "").trim();
    if (!text) throw new Error("Escribi algo antes de guardar.");
    const time = nowText();
    const record = {
      id:newId("record-"),
      type,
      text,
      status:type === "tarea" ? "pendiente" : "activo",
      title:String(body.title || ""),
      description:String(body.description || ""),
      priority:["baja", "media", "alta"].includes(body.priority) ? body.priority : "",
      due_date:String(body.due_date || ""),
      tags:tags(body.tags),
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("records", record);
    await track("records", record.id, "create", record);
    return record;
  }

  async function updateRecord(body) {
    const existing = await get("records", body.id);
    if (!existing) throw new Error("No encontre un registro con ese codigo.");
    const type = safeType(body.type || existing.type);
    const text = String(body.text || "").trim();
    if (!text) throw new Error("El contenido no puede estar vacio.");
    const record = {
      ...existing,
      type,
      text,
      status:type === "tarea" ? (["pendiente", "completada"].includes(existing.status) ? existing.status : "pendiente") : "activo",
      title:String(body.title || ""),
      description:String(body.description || ""),
      priority:["baja", "media", "alta"].includes(body.priority) ? body.priority : "",
      due_date:String(body.due_date || ""),
      tags:tags(body.tags),
      revision:(Number(existing.revision) || 1) + 1,
      updated_at:nowText(),
      synced_at:null
    };
    await put("records", record);
    await track("records", record.id, "update", record);
    return record;
  }

  async function setTaskStatus(body) {
    const record = await get("records", body.id);
    if (!record || record.type !== "tarea") throw new Error("No encontre una tarea con ese codigo.");
    if (!["pendiente", "completada"].includes(body.status)) throw new Error("Estado de tarea invalido.");
    record.status = body.status;
    record.revision = (Number(record.revision) || 1) + 1;
    record.updated_at = nowText();
    record.synced_at = null;
    await put("records", record);
    await track("records", record.id, "status", record);
  }

  async function deleteRecord(body) {
    const record = await get("records", body.id);
    if (!record) return;
    record.deleted_at = nowText();
    record.updated_at = record.deleted_at;
    record.synced_at = null;
    record.revision = (Number(record.revision) || 1) + 1;
    await put("records", record);
    await track("records", record.id, "delete", record);
  }

  function monthKey() {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
  }

  function monthTotals(movements) {
    const totals = { income:0, expense:0, saving:0, balance:0, necessary:0, optional:0, personal_investment:0 };
    movements.forEach((movement) => {
      const amount = Number(movement.amount) || 0;
      if (movement.kind === "income") totals.income += amount;
      if (movement.kind === "expense") totals.expense += amount;
      if (movement.kind === "saving") totals.saving += amount;
      if (movement.kind === "expense" && totals[movement.priority] !== undefined) totals[movement.priority] += amount;
    });
    totals.balance = totals.income - totals.expense - totals.saving;
    return totals;
  }

  function percent(value, income) {
    return income <= 0 ? 0 : Math.round((value / income) * 1000) / 10;
  }

  function targetStatus(group, real, target) {
    if (group === "saving") {
      if (real >= target) return "cumplido";
      if (real >= target - 5) return "cerca";
      return "bajo";
    }
    if (real <= target) return "cumplido";
    if (real <= target + 5) return "cerca";
    return "excedido";
  }

  function monthlySummary(month, movements, categories, priorities, settings) {
    const monthMovements = visible(movements).filter((movement) => String(movement.date || "").startsWith(month));
    const totals = monthTotals(monthMovements);
    const targets = settings.monthly_targets || defaultSettings.monthly_targets;
    const groups = [
      { id:"saving", label:"Ahorro e inversiones", total:totals.saving, target:targets.saving },
      { id:"necessary", label:"Gastos necesarios", total:totals.necessary, target:targets.necessary },
      { id:"optional", label:"Salidas o prescindibles", total:totals.optional, target:targets.optional },
      { id:"personal_investment", label:"Inversion personal", total:totals.personal_investment, target:targets.personal_investment }
    ];
    return {
      month,
      income_total:totals.income,
      expense_total:totals.expense,
      saving_total:totals.saving,
      balance:totals.balance,
      movement_count:monthMovements.length,
      by_category:categories.map((category) => {
        const items = monthMovements.filter((movement) => movement.category_id === category.id);
        return { id:category.id, label:category.label, kind:category.kind, total:items.reduce((sum, item) => sum + Number(item.amount || 0), 0), count:items.length };
      }),
      by_priority:priorities.map((priority) => {
        const items = monthMovements.filter((movement) => movement.priority === priority.id);
        return { id:priority.id, label:priority.label, total:items.reduce((sum, item) => sum + Number(item.amount || 0), 0), count:items.length };
      }),
      analysis:groups.map((group) => {
        const real = percent(group.total, totals.income);
        return { id:group.id, label:group.label, total:group.total, percent:real, target:Number(group.target), status:targetStatus(group.id, real, Number(group.target)) };
      }),
      targets,
      month_series:[],
      previous_comparison:{ previous_month:null, has_previous:false, message:"Sin comparacion local offline." }
    };
  }

  async function createMovement(body) {
    await ensureDefaults();
    if (!["income", "expense", "saving"].includes(body.kind)) throw new Error("Tipo invalido. Usa income, expense o saving.");
    const amount = Number(body.amount);
    if (!amount || amount <= 0) throw new Error("El monto debe ser mayor que cero.");
    const settings = await get("finance_settings", "main") || defaultSettings;
    const methods = await all("finance_payment_methods");
    let method = methods.find((item) => item.id === body.payment_method_id && !item.deleted_at);
    if (!method) method = methods.find((item) => item.id === settings.default_payment_method && !item.deleted_at);
    const paymentMethodId = method?.id || "";
    const paymentMethodLabel = method?.label || String(body.payment_method || "Efectivo");
    const time = nowText();
    const movement = {
      id:newId("movement-"),
      kind:body.kind,
      category_id:body.category_id,
      priority:body.priority,
      amount,
      currency:settings.currency || "ARS",
      date:body.date || time.slice(0, 10),
      note:String(body.note || "").trim(),
      payment_method_id:paymentMethodId,
      payment_method:paymentMethodLabel,
      source:"manual",
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("finance_movements", movement);
    await track("finance_movements", movement.id, "create", movement);
    return movement;
  }

  async function updateMovement(body) {
    await ensureDefaults();
    const movement = await get("finance_movements", body.id);
    if (!movement) throw new Error("No encontre ese movimiento.");
    if (!["income", "expense", "saving"].includes(body.kind)) throw new Error("Tipo invalido. Usa income, expense o saving.");
    const amount = Number(body.amount);
    if (!amount || amount <= 0) throw new Error("El monto debe ser mayor que cero.");
    const methods = await all("finance_payment_methods");
    const method = methods.find((item) => item.id === body.payment_method_id && !item.deleted_at);

    movement.kind = body.kind;
    movement.category_id = body.category_id;
    movement.priority = body.priority;
    movement.amount = amount;
    movement.date = body.date || movement.date;
    movement.note = String(body.note || "").trim();
    movement.payment_method_id = method?.id || "";
    movement.payment_method = method?.label || String(body.payment_method || movement.payment_method || "Efectivo");
    movement.revision = (Number(movement.revision) || 1) + 1;
    movement.updated_at = nowText();
    movement.synced_at = null;

    await put("finance_movements", movement);
    await track("finance_movements", movement.id, "update", movement);
    return movement;
  }

  async function deleteMovement(body) {
    const movement = await get("finance_movements", body.id);
    if (!movement) return;
    movement.deleted_at = nowText();
    movement.updated_at = movement.deleted_at;
    movement.synced_at = null;
    movement.revision = (Number(movement.revision) || 1) + 1;
    await put("finance_movements", movement);
    await track("finance_movements", movement.id, "delete", movement);
  }

  async function updateTargets(body) {
    const total = Number(body.saving) + Number(body.necessary) + Number(body.optional) + Number(body.personal_investment);
    if (total !== 100) throw new Error(`Las metas deben sumar 100%. Ahora suman ${total}%.`);
    const settings = await get("finance_settings", "main") || defaultSettings;
    settings.monthly_targets = {
      saving:Number(body.saving),
      necessary:Number(body.necessary),
      optional:Number(body.optional),
      personal_investment:Number(body.personal_investment)
    };
    settings.updated_at = nowText();
    settings.device_id = deviceId();
    settings.revision = (Number(settings.revision) || 0) + 1;
    settings.synced_at = null;
    await put("finance_settings", settings);
    await track("finance_settings", "main", "targets", settings);
    return settings.monthly_targets;
  }

  async function createPaymentMethod(body) {
    const label = String(body.label || "").trim();
    if (!label) throw new Error("Escribi un nombre para el metodo.");
    const methods = await all("finance_payment_methods");
    const time = nowText();
    const method = {
      id:newId("method-"),
      label,
      enabled:true,
      built_in:false,
      sort_order:100 + methods.length,
      deleted_at:null,
      workspace_id:workspaceId(),
      device_id:deviceId(),
      revision:1,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("finance_payment_methods", method);
    await track("finance_payment_methods", method.id, "create", method);
    return method;
  }

  async function updatePaymentMethod(body) {
    const method = await get("finance_payment_methods", body.id);
    if (!method) throw new Error("No encontre ese metodo.");
    if (method.built_in) throw new Error("Los metodos iniciales no se editan desde esta pantalla.");
    const label = String(body.label || method.label || "").trim();
    if (!label) throw new Error("El nombre del metodo no puede estar vacio.");
    method.label = label;
    method.enabled = body.enabled !== false;
    method.revision = (Number(method.revision) || 1) + 1;
    method.updated_at = nowText();
    method.synced_at = null;
    await put("finance_payment_methods", method);
    await track("finance_payment_methods", method.id, "update", method);
    return method;
  }

  async function deletePaymentMethod(body) {
    const method = await get("finance_payment_methods", body.id);
    if (!method) return;
    if (method.built_in) throw new Error("Los metodos iniciales no se eliminan.");
    method.enabled = false;
    method.deleted_at = nowText();
    method.updated_at = method.deleted_at;
    method.revision = (Number(method.revision) || 1) + 1;
    method.synced_at = null;
    await put("finance_payment_methods", method);
    await track("finance_payment_methods", method.id, "delete", method);
  }

  function clampProgress(value) {
    const number = Number(value || 0);
    if (!Number.isFinite(number)) return 0;
    return Math.max(0, Math.min(100, Math.round(number)));
  }

  function dateTimeText(date, time = "") {
    const safeDate = String(date || "").trim();
    if (!safeDate) throw new Error("Carga una fecha.");
    const safeTime = String(time || "").trim();
    return `${safeDate}T${safeTime || "00:00"}:00`;
  }

  async function studySummary() {
    return {
      subjects:visible(await all("study_subjects")),
      topics:visible(await all("study_topics")),
      evaluations:visible(await all("study_evaluations")),
      assignments:visible(await all("study_assignments")),
      notes:visible(await all("study_notes")),
      schedules:visible(await all("study_schedules"))
    };
  }

  async function filesSummary() {
    return {
      assets:visible(await all("file_assets")),
      links:visible(await all("file_links")),
      roots:await all("local_file_roots"),
      locations:(await all("local_file_locations")).map((location) => ({
        id:location.id,
        file_id:location.file_id,
        root_id:location.root_id,
        relative_path:location.relative_path,
        device_id:location.device_id,
        available:location.available,
        last_seen_at:location.last_seen_at
      }))
    };
  }

  async function createSubject(body) {
    const name = String(body.name || "").trim();
    if (!name) throw new Error("La materia necesita un nombre.");
    const time = nowText();
    const subject = {
      id:newId("subject-"),
      name,
      status:body.status || "cursando",
      year:String(body.year || ""),
      term:String(body.term || ""),
      professors:String(body.professors || ""),
      classroom:String(body.classroom || ""),
      evaluation_method:String(body.evaluation_method || ""),
      schedule_notes:String(body.schedule_notes || ""),
      color:body.color || "#8B5CF6",
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      archived_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("study_subjects", subject);
    await track("study_subjects", subject.id, "create", subject);
    return subject;
  }

  async function updateSubject(body) {
    const subject = await get("study_subjects", body.id);
    if (!subject) throw new Error("No encontre esa materia.");
    const time = nowText();
    Object.assign(subject, {
      name:String(body.name || subject.name || "").trim(),
      status:body.status || subject.status || "cursando",
      year:String(body.year || ""),
      term:String(body.term || ""),
      professors:String(body.professors || ""),
      classroom:String(body.classroom || ""),
      evaluation_method:String(body.evaluation_method || ""),
      schedule_notes:String(body.schedule_notes || ""),
      color:body.color || subject.color || "#8B5CF6",
      archived_at:body.status === "archivada" ? (subject.archived_at || time) : null,
      updated_at:time,
      revision:Number(subject.revision || 0) + 1,
      synced_at:null,
      device_id:subject.device_id || deviceId(),
      workspace_id:workspaceId()
    });
    await put("study_subjects", subject);
    await track("study_subjects", subject.id, "update", subject);
    return subject;
  }

  async function archiveSubject(body) {
    const subject = await get("study_subjects", body.id);
    if (!subject) throw new Error("No encontre esa materia.");
    subject.status = "archivada";
    subject.archived_at = nowText();
    subject.updated_at = subject.archived_at;
    subject.revision = Number(subject.revision || 0) + 1;
    subject.synced_at = null;
    await put("study_subjects", subject);
    await track("study_subjects", subject.id, "archive", subject);
    return subject;
  }

  async function createTopic(body) {
    if (!(await get("study_subjects", body.subject_id))) throw new Error("Materia invalida.");
    const title = String(body.title || "").trim();
    if (!title) throw new Error("El tema necesita un titulo.");
    const time = nowText();
    const topic = {
      id:newId("topic-"),
      subject_id:body.subject_id,
      title,
      status:body.status || "pendiente",
      progress:clampProgress(body.progress),
      notes:String(body.notes || ""),
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("study_topics", topic);
    await track("study_topics", topic.id, "create", topic);
    return topic;
  }

  async function updateTopic(body) {
    const topic = await get("study_topics", body.id);
    if (!topic) throw new Error("No encontre ese tema.");
    Object.assign(topic, {
      title:String(body.title || topic.title || "").trim(),
      status:body.status || "pendiente",
      progress:clampProgress(body.progress),
      notes:String(body.notes || ""),
      updated_at:nowText(),
      revision:Number(topic.revision || 0) + 1,
      synced_at:null
    });
    await put("study_topics", topic);
    await track("study_topics", topic.id, "update", topic);
    return topic;
  }

  async function softDelete(storeName, entity, id) {
    const item = await get(storeName, id);
    if (!item) return null;
    item.deleted_at = nowText();
    item.updated_at = item.deleted_at;
    item.revision = Number(item.revision || 0) + 1;
    item.synced_at = null;
    await put(storeName, item);
    await track(entity, item.id, "delete", item);
    return item;
  }

  async function createCalendarEvent(body) {
    const title = String(body.title || "").trim();
    if (!title) throw new Error("El evento necesita un titulo.");
    const time = nowText();
    const event = {
      id:newId("event-"),
      title,
      type:body.type || "recordatorio",
      starts_at:dateTimeText(body.date, body.time),
      ends_at:String(body.ends_at || ""),
      all_day:Boolean(body.all_day),
      importance:body.importance || "media",
      subject_id:String(body.subject_id || ""),
      linked_entity_type:String(body.linked_entity_type || ""),
      linked_entity_id:String(body.linked_entity_id || ""),
      status:body.status || "pendiente",
      notes:String(body.notes || ""),
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("calendar_events", event);
    await track("calendar_events", event.id, "create", event);
    return event;
  }

  async function updateCalendarEvent(body) {
    const event = await get("calendar_events", body.id);
    if (!event) throw new Error("No encontre ese evento.");
    Object.assign(event, {
      title:String(body.title || event.title || "").trim(),
      type:body.type || event.type || "recordatorio",
      starts_at:dateTimeText(body.date, body.time),
      ends_at:String(body.ends_at || ""),
      all_day:Boolean(body.all_day),
      importance:body.importance || "media",
      subject_id:String(body.subject_id || ""),
      linked_entity_type:String(body.linked_entity_type || event.linked_entity_type || ""),
      linked_entity_id:String(body.linked_entity_id || event.linked_entity_id || ""),
      status:body.status || event.status || "pendiente",
      notes:String(body.notes || ""),
      updated_at:nowText(),
      revision:Number(event.revision || 0) + 1,
      synced_at:null
    });
    await put("calendar_events", event);
    await track("calendar_events", event.id, "update", event);
    return event;
  }

  async function createCalendarBackedItem(kind, body) {
    const subject = await get("study_subjects", body.subject_id);
    if (!subject) throw new Error("Materia invalida.");
    const title = String(body.title || "").trim();
    if (!title) throw new Error("Necesita un titulo.");
    const isEvaluation = kind === "evaluation";
    const id = newId(isEvaluation ? "evaluation-" : "assignment-");
    const event = await createCalendarEvent({
      title:`${subject.name}: ${title}`,
      type:isEvaluation ? (body.type || "parcial") : "tp",
      date:body.date,
      time:body.time,
      importance:body.importance || (isEvaluation ? "alta" : "media"),
      subject_id:subject.id,
      linked_entity_type:isEvaluation ? "study_evaluation" : "study_assignment",
      linked_entity_id:id,
      status:body.status || "pendiente",
      notes:body.notes || ""
    });
    const time = nowText();
    const item = {
      id,
      subject_id:subject.id,
      title,
      type:isEvaluation ? (body.type || "parcial") : "tp",
      calendar_event_id:event.id,
      topic_ids:[],
      status:body.status || "pendiente",
      progress:clampProgress(body.progress),
      notes:String(body.notes || ""),
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    const storeName = isEvaluation ? "study_evaluations" : "study_assignments";
    const entity = isEvaluation ? "study_evaluations" : "study_assignments";
    await put(storeName, item);
    await track(entity, item.id, "create", item);
    return item;
  }

  async function updateCalendarBackedItem(kind, body) {
    const isEvaluation = kind === "evaluation";
    const storeName = isEvaluation ? "study_evaluations" : "study_assignments";
    const entity = isEvaluation ? "study_evaluations" : "study_assignments";
    const item = await get(storeName, body.id);
    if (!item) throw new Error("No encontre ese registro academico.");
    const subject = await get("study_subjects", item.subject_id);
    const title = String(body.title || item.title || "").trim();
    const eventBody = {
      id:item.calendar_event_id,
      title:`${subject?.name || "Materia"}: ${title}`,
      type:isEvaluation ? (body.type || item.type || "parcial") : "tp",
      date:body.date,
      time:body.time,
      importance:body.importance || "media",
      subject_id:item.subject_id,
      linked_entity_type:isEvaluation ? "study_evaluation" : "study_assignment",
      linked_entity_id:item.id,
      status:body.status || item.status || "pendiente",
      notes:body.notes || ""
    };
    let event = item.calendar_event_id ? await get("calendar_events", item.calendar_event_id) : null;
    if (event) await updateCalendarEvent(eventBody);
    else {
      event = await createCalendarEvent(eventBody);
      item.calendar_event_id = event.id;
    }
    Object.assign(item, {
      title,
      type:isEvaluation ? (body.type || item.type || "parcial") : "tp",
      status:body.status || item.status || "pendiente",
      progress:clampProgress(body.progress),
      notes:String(body.notes || ""),
      updated_at:nowText(),
      revision:Number(item.revision || 0) + 1,
      synced_at:null
    });
    await put(storeName, item);
    await track(entity, item.id, "update", item);
    return item;
  }

  async function deleteCalendarBackedItem(kind, id) {
    const isEvaluation = kind === "evaluation";
    const storeName = isEvaluation ? "study_evaluations" : "study_assignments";
    const entity = isEvaluation ? "study_evaluations" : "study_assignments";
    const item = await get(storeName, id);
    if (item?.calendar_event_id) await softDelete("calendar_events", "calendar_events", item.calendar_event_id);
    return softDelete(storeName, entity, id);
  }

  async function createNote(body) {
    if (!(await get("study_subjects", body.subject_id))) throw new Error("Materia invalida.");
    const text = String(body.text || "").trim();
    if (!text) throw new Error("La nota no puede estar vacia.");
    const time = nowText();
    const note = {
      id:newId("note-"),
      subject_id:body.subject_id,
      title:String(body.title || "Nota").trim(),
      text,
      linked_entity_type:String(body.linked_entity_type || ""),
      linked_entity_id:String(body.linked_entity_id || ""),
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("study_notes", note);
    await track("study_notes", note.id, "create", note);
    return note;
  }

  async function updateNote(body) {
    const note = await get("study_notes", body.id);
    if (!note) throw new Error("No encontre esa nota.");
    note.title = String(body.title || note.title || "Nota").trim();
    note.text = String(body.text || "");
    note.updated_at = nowText();
    note.revision = Number(note.revision || 0) + 1;
    note.synced_at = null;
    await put("study_notes", note);
    await track("study_notes", note.id, "update", note);
    return note;
  }

  async function createSchedule(body) {
    if (!(await get("study_subjects", body.subject_id))) throw new Error("Materia invalida.");
    if (!String(body.day_of_week || "").trim() || !String(body.starts_at || "").trim()) throw new Error("El horario necesita dia y hora.");
    const time = nowText();
    const schedule = {
      id:newId("schedule-"),
      subject_id:body.subject_id,
      day_of_week:String(body.day_of_week || ""),
      starts_at:String(body.starts_at || ""),
      ends_at:String(body.ends_at || ""),
      location:String(body.location || ""),
      notes:String(body.notes || ""),
      device_id:deviceId(),
      workspace_id:workspaceId(),
      revision:1,
      deleted_at:null,
      synced_at:null,
      created_at:time,
      updated_at:time
    };
    await put("study_schedules", schedule);
    await track("study_schedules", schedule.id, "create", schedule);
    return schedule;
  }

  function daysBetween(dateText) {
    const date = Date.parse(String(dateText || "").slice(0, 10));
    if (!Number.isFinite(date)) return null;
    const today = new Date();
    const start = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
    return Math.round((date - start) / 86400000);
  }

  async function localInsights() {
    const study = await studySummary();
    const events = visible(await all("calendar_events")).sort((a, b) => String(a.starts_at || "").localeCompare(String(b.starts_at || "")));
    const insights = [];
    const academicTypes = new Set(["parcial", "final", "tp", "entrega", "exposicion"]);
    const upcoming = events.map((event) => ({ event, days:daysBetween(event.starts_at) })).filter((item) => item.days !== null && item.days >= 0 && item.days <= 14);
    upcoming.slice(0, 4).forEach((item) => {
      const when = item.days === 0 ? "hoy" : item.days === 1 ? "manana" : `en ${item.days} dias`;
      insights.push({ id:`insight-calendar-${item.event.id}`, type:"calendar_upcoming", message:`${item.event.title} ${when}.`, severity:item.days <= 2 ? "alta" : "media", source_entity:"calendar_events", source_id:item.event.id, action:"open_calendar" });
    });
    const academic = upcoming.filter((item) => academicTypes.has(item.event.type));
    if (academic.length >= 3) insights.push({ id:"insight-academic-density", type:"academic_density", message:`Tenes ${academic.length} fechas academicas importantes durante los proximos 14 dias.`, severity:"alta", source_entity:"calendar_events", source_id:"academic-density", action:"open_calendar" });
    for (const evaluation of study.evaluations) {
      const event = events.find((item) => item.id === evaluation.calendar_event_id);
      const days = daysBetween(event?.starts_at);
      if (days !== null && days >= 0 && days <= 21) {
        const pendingTopics = study.topics.filter((topic) => topic.subject_id === evaluation.subject_id && !["hecho", "completado", "aprobado"].includes(topic.status)).length;
        if (pendingTopics > 0) insights.push({ id:`insight-eval-${evaluation.id}`, type:"evaluation_preparation", message:`Faltan ${days} dias para ${evaluation.title} y quedan ${pendingTopics} temas pendientes.`, severity:"media", source_entity:"study_evaluations", source_id:evaluation.id, action:"open_study" });
      }
    }
    study.subjects.filter((subject) => subject.status === "final_pendiente").slice(0, 2).forEach((subject) => {
      if (!events.some((event) => event.subject_id === subject.id && daysBetween(event.starts_at) >= 0)) {
        insights.push({ id:`insight-final-${subject.id}`, type:"pending_final", message:`${subject.name} tiene final pendiente y todavia no tiene fecha cargada.`, severity:"media", source_entity:"study_subjects", source_id:subject.id, action:"open_study" });
      }
    });
    return insights.slice(0, 8);
  }

  async function handle(path, body) {
    await ensureDefaults();
    const url = new URL(path, location.origin);
    const pathname = url.pathname;

    if (pathname === "/api/records" && !body) {
      const records = visible(await all("records"));
      return { ok:true, local_only:true, records, summary:recordsSummary(records) };
    }
    if (pathname === "/api/records") {
      await createRecord(body || {});
      const records = visible(await all("records"));
      return { ok:true, local_only:true, records };
    }
    if (pathname === "/api/records/update") {
      await updateRecord(body || {});
      return { ok:true, local_only:true, records:visible(await all("records")) };
    }
    if (pathname === "/api/records/status" || pathname === "/api/complete") {
      await setTaskStatus(pathname === "/api/complete" ? { id:body.id, status:"completada" } : body);
      return { ok:true, local_only:true, records:visible(await all("records")) };
    }
    if (pathname === "/api/delete") {
      await deleteRecord(body || {});
      return { ok:true, local_only:true, records:visible(await all("records")) };
    }
    if (pathname === "/api/quick") {
      await createRecord(quickCapture(body?.text));
      return { ok:true, local_only:true, records:visible(await all("records")) };
    }
    if (pathname === "/api/backup") {
      return { ok:true, local_only:true, file:"indexeddb-local" };
    }
    if (pathname === "/api/finance/summary") {
      const movements = await all("finance_movements");
      const categories = await all("finance_categories");
      const priorities = await all("finance_priorities");
      const paymentMethods = sortedMethods(await all("finance_payment_methods"));
      const settings = await get("finance_settings", "main") || defaultSettings;
      const month = url.searchParams.get("month") || monthKey();
      return { ok:true, local_only:true, movements:visible(movements), categories, priorities, payment_methods:paymentMethods, summary:monthlySummary(month, movements, categories, priorities, settings) };
    }
    if (pathname === "/api/finance/movements") {
      await createMovement(body || {});
      return { ok:true, local_only:true, movements:visible(await all("finance_movements")) };
    }
    if (pathname === "/api/finance/movements/update") {
      await updateMovement(body || {});
      return { ok:true, local_only:true, movements:visible(await all("finance_movements")) };
    }
    if (pathname === "/api/finance/delete") {
      await deleteMovement(body || {});
      return { ok:true, local_only:true, movements:visible(await all("finance_movements")) };
    }
    if (pathname === "/api/finance/targets") {
      const targets = await updateTargets(body || {});
      return { ok:true, local_only:true, targets };
    }
    if (pathname === "/api/finance/payment-methods") {
      await createPaymentMethod(body || {});
      return { ok:true, local_only:true, payment_methods:sortedMethods(await all("finance_payment_methods")) };
    }
    if (pathname === "/api/finance/payment-methods/update") {
      await updatePaymentMethod(body || {});
      return { ok:true, local_only:true, payment_methods:sortedMethods(await all("finance_payment_methods")) };
    }
    if (pathname === "/api/finance/payment-methods/delete") {
      await deletePaymentMethod(body || {});
      return { ok:true, local_only:true, payment_methods:sortedMethods(await all("finance_payment_methods")) };
    }
    if (pathname === "/api/study/summary") {
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")), files:await filesSummary() };
    }
    if (pathname === "/api/study/subjects") {
      await createSubject(body || {});
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/subjects/update") {
      await updateSubject(body || {});
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/subjects/archive") {
      await archiveSubject(body || {});
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/topics") {
      await createTopic(body || {});
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/study/topics/update") {
      await updateTopic(body || {});
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/study/topics/delete") {
      await softDelete("study_topics", "study_topics", body?.id);
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/study/evaluations") {
      await createCalendarBackedItem("evaluation", body || {});
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/evaluations/update") {
      await updateCalendarBackedItem("evaluation", body || {});
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/evaluations/delete") {
      await deleteCalendarBackedItem("evaluation", body?.id);
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/assignments") {
      await createCalendarBackedItem("assignment", body || {});
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/assignments/update") {
      await updateCalendarBackedItem("assignment", body || {});
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/assignments/delete") {
      await deleteCalendarBackedItem("assignment", body?.id);
      return { ok:true, local_only:true, study:await studySummary(), events:visible(await all("calendar_events")) };
    }
    if (pathname === "/api/study/notes") {
      await createNote(body || {});
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/study/notes/update") {
      await updateNote(body || {});
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/study/notes/delete") {
      await softDelete("study_notes", "study_notes", body?.id);
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/study/schedules") {
      await createSchedule(body || {});
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/study/schedules/delete") {
      await softDelete("study_schedules", "study_schedules", body?.id);
      return { ok:true, local_only:true, study:await studySummary() };
    }
    if (pathname === "/api/calendar/events" && !body) {
      return { ok:true, local_only:true, events:visible(await all("calendar_events")), study:await studySummary() };
    }
    if (pathname === "/api/calendar/events") {
      await createCalendarEvent(body || {});
      return { ok:true, local_only:true, events:visible(await all("calendar_events")), study:await studySummary() };
    }
    if (pathname === "/api/calendar/events/update") {
      await updateCalendarEvent(body || {});
      return { ok:true, local_only:true, events:visible(await all("calendar_events")), study:await studySummary() };
    }
    if (pathname === "/api/calendar/events/delete") {
      await softDelete("calendar_events", "calendar_events", body?.id);
      return { ok:true, local_only:true, events:visible(await all("calendar_events")), study:await studySummary() };
    }
    if (pathname === "/api/files/summary") {
      return { ok:true, local_only:true, files:await filesSummary() };
    }
    if (pathname === "/api/files/roots" || pathname === "/api/files/scan" || pathname === "/api/files/open") {
      throw new Error("Ruta local no disponible: archivos locales requieren backend notebook.");
    }
    if (pathname === "/api/insights") {
      return { ok:true, local_only:true, insights:await localInsights() };
    }
    if (pathname === "/api/sync/status") {
      return syncStatus();
    }
    if (pathname === "/api/sync/run") {
      return syncWithNotebook(body || {});
    }
    if (pathname === "/api/sync/settings") {
      return saveSyncSettings(body || {});
    }
    if (pathname === "/api/sync/pairing/start") {
      return createPairingCode();
    }
    if (pathname === "/api/sync/pairing/join") {
      return joinWorkspace(body || {});
    }
    if (pathname === "/api/sync/conflicts") {
      return listConflicts();
    }
    if (pathname === "/api/sync/conflicts/resolve") {
      return resolveConflict(body || {});
    }

    throw new Error("Ruta local no disponible.");
  }

  window.JarvisLocalStore = { handle, deviceId, workspaceId, importNotebookSnapshotIfNeeded, syncStatus, syncWithNotebook };
})();
