# Componentes web compartidos de Jarvis.
# Mantienen consistencia entre modulos sin cambiar la experiencia visual.

function Get-JarvisSidebarHtml {
    param([string]$Active = "dashboard")

    $dashboardClass = if ($Active -eq "dashboard") { "nav-item active" } else { "nav-item" }
    $financeClass = if ($Active -eq "finance") { "nav-item active" } else { "nav-item" }
    $organizationClass = if ($Active -eq "organization") { "nav-item active" } else { "nav-item" }
    $studyClass = if ($Active -eq "study") { "nav-item active" } else { "nav-item" }
    $calendarClass = if ($Active -eq "calendar") { "nav-item active" } else { "nav-item" }
    $wellbeingClass = if ($Active -eq "wellbeing") { "nav-item active" } else { "nav-item" }
    $workClass = if ($Active -eq "work") { "nav-item active" } else { "nav-item" }
    $personalClass = if ($Active -eq "personal") { "nav-item active" } else { "nav-item" }
    $settingsClass = if ($Active -eq "settings") { "nav-item active" } else { "nav-item" }

    return @"
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
        <a class="$dashboardClass" href="/">Inicio</a>
        <span class="nav-divider"></span>
        <a class="$organizationClass" href="/organization">Organizacion</a>
        <a class="$calendarClass" href="/calendar">Calendario</a>
        <a class="$studyClass" href="/study">Estudio</a>
        <a class="$financeClass" href="/finance">Finanzas</a>
        <a class="$wellbeingClass" href="/wellbeing">Bienestar</a>
        <a class="$workClass" href="/work">Trabajo</a>
        <a class="$personalClass" href="/personal">Personal</a>
        <span class="nav-divider"></span>
        <a class="$settingsClass" href="/settings">Configuracion</a>
      </div>
    </nav>
"@
}

function Get-JarvisPwaHead {
    return @'
  <meta name="theme-color" content="#8B5CF6">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-title" content="Jarvis">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <link rel="manifest" href="/manifest.webmanifest">
  <link rel="icon" href="/static/icons/icon.svg" type="image/svg+xml">
  <link rel="apple-touch-icon" href="/static/icons/apple-touch-icon.png">
  <link rel="stylesheet" href="/static/jarvis-theme.css">
  <script src="/static/jarvis-local-store.js"></script>
  <script src="/static/jarvis-shared.js"></script>
'@
}

function Get-JarvisSharedScript {
    return ""
}
