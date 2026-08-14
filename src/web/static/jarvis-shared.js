const $ = (id) => document.getElementById(id);

function jarvisPageUrl(page) {
  return new URL(page, new URL("./", document.baseURI)).pathname;
}

function jarvisNavHtml(active = "dashboard") {
  const itemClass = (name) => name === active ? "nav-item active" : "nav-item";
  return `
    <nav class="panel jarvis-nav">
      <input class="nav-toggle" id="jarvis-nav-toggle" type="checkbox" aria-label="Abrir menu de modulos">
      <div class="nav-head">
        <h3>Modulos</h3>
        <label class="nav-menu-button" for="jarvis-nav-toggle" aria-label="Abrir menu de modulos">
          <span></span>
          <span></span>
          <span></span>
        </label>
      </div>
      <div class="nav-links">
        <a class="${itemClass("dashboard")}" href="${jarvisPageUrl("index.html")}">Inicio</a>
        <span class="nav-divider"></span>
        <a class="${itemClass("organization")}" href="${jarvisPageUrl("organization.html")}">Organizacion</a>
        <a class="${itemClass("calendar")}" href="${jarvisPageUrl("calendar.html")}">Calendario</a>
        <a class="${itemClass("study")}" href="${jarvisPageUrl("study.html")}">Estudio</a>
        <a class="${itemClass("finance")}" href="${jarvisPageUrl("finance.html")}">Finanzas</a>
        <a class="${itemClass("wellbeing")}" href="${jarvisPageUrl("wellbeing.html")}">Bienestar</a>
        <a class="${itemClass("work")}" href="${jarvisPageUrl("work.html")}">Trabajo</a>
        <a class="${itemClass("personal")}" href="${jarvisPageUrl("personal.html")}">Personal</a>
        <span class="nav-divider"></span>
        <a class="${itemClass("settings")}" href="${jarvisPageUrl("settings.html")}">Configuracion</a>
      </div>
    </nav>
  `;
}

function renderJarvisShell() {
  document.querySelectorAll("[data-jarvis-nav]").forEach((target) => {
    target.outerHTML = jarvisNavHtml(target.dataset.jarvisNav);
  });
}

function safeText(value, fallback = "") {
  if (value === null || value === undefined || String(value).trim() === "") return fallback;
  return String(value);
}

function escapeHtml(value, fallback = "") {
  return safeText(value, fallback)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

async function serverApi(path, body) {
  const options = body ? { method:"POST", headers:{ "Content-Type":"application/json" }, body:JSON.stringify(body) } : {};
  const response = await fetch(path, options);
  const data = await readJsonResponse(response, path);
  if (!response.ok || data.ok === false) throw new Error(data.error || "Error desconocido");
  return data;
}

async function readJsonResponse(response, label = "endpoint") {
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

function normalizeJarvisPeerUrl(value, fallback = "") {
  const raw = safeText(value, fallback).trim();
  if (!raw) return "";

  const withProtocol = /^https?:\/\//i.test(raw) ? raw : `http://${raw}`;
  try {
    return new URL(withProtocol).origin.replace(/\/+$/, "");
  } catch {
    throw new Error("La URL/IP de sincronizacion no es valida.");
  }
}

async function api(path, body) {
  if (window.JarvisLocalStore) {
    try {
      return await window.JarvisLocalStore.handle(path, body);
    } catch (error) {
      if (!String(error.message || "").includes("Ruta local no disponible")) throw error;
    }
  }

  return serverApi(path, body);
}

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    const scriptUrl = new URL("service-worker.js", new URL("./", document.baseURI));
    const scope = new URL("./", document.baseURI).pathname;
    navigator.serviceWorker.register(scriptUrl, { scope }).catch((error) => {
      console.warn("No se pudo registrar el service worker de Jarvis.", error);
    });
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", renderJarvisShell);
} else {
  renderJarvisShell();
}
