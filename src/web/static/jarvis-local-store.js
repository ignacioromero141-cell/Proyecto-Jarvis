(function () {
  const DB_NAME = "jarvis-local-first";
  const DB_VERSION = 2;
  const DEVICE_KEY = "jarvis_device_id";

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

  function openDb() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains("records")) db.createObjectStore("records", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_movements")) db.createObjectStore("finance_movements", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_categories")) db.createObjectStore("finance_categories", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_priorities")) db.createObjectStore("finance_priorities", { keyPath:"id" });
        if (!db.objectStoreNames.contains("finance_settings")) db.createObjectStore("finance_settings", { keyPath:"id" });
        if (!db.objectStoreNames.contains("sync_changes")) db.createObjectStore("sync_changes", { keyPath:"change_id" });
        if (!db.objectStoreNames.contains("metadata")) db.createObjectStore("metadata", { keyPath:"key" });
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
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
    const settings = await get("finance_settings", "main");
    if (!settings) await put("finance_settings", defaultSettings);
  }

  async function localUserDataIsEmpty() {
    const counts = await Promise.all([
      all("records"),
      all("finance_movements")
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
      finance_settings:0
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
      device_id:deviceId(),
      created_at:nowText(),
      synced_at:null
    });
  }

  function visible(items) {
    return items.filter((item) => !item.deleted_at);
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
      payment_method:String(body.payment_method || settings.default_payment_method || "cash"),
      source:"manual",
      device_id:deviceId(),
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
    await put("finance_settings", settings);
    await track("finance_settings", "main", "targets", settings);
    return settings.monthly_targets;
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
      const settings = await get("finance_settings", "main") || defaultSettings;
      const month = url.searchParams.get("month") || monthKey();
      return { ok:true, local_only:true, movements:visible(movements), categories, priorities, summary:monthlySummary(month, movements, categories, priorities, settings) };
    }
    if (pathname === "/api/finance/movements") {
      await createMovement(body || {});
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

    throw new Error("Ruta local no disponible.");
  }

  window.JarvisLocalStore = { handle, deviceId, importNotebookSnapshotIfNeeded };
})();
