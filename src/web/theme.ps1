# Tema visual centralizado de Jarvis.
# Hoy solo existe "Oscuro Jarvis", pero la funcion permite sumar otros temas en el futuro.

function Get-JarvisThemeCss {
    param([string]$Theme = "jarvis-dark")

    return @'
:root,
:root[data-theme="jarvis-dark"] {
  --color-bg-main:#0B0F17;
  --color-bg-secondary:#111827;
  --color-surface:#161B2B;
  --color-surface-elevated:#1F2637;
  --color-surface-hover:#272E45;

  --color-primary:#8B5CF6;
  --color-primary-hover:#A855F7;
  --color-primary-soft:#C084FC;
  --gradient-primary:linear-gradient(135deg,#8B5CF6,#6366F1);
  --gradient-surface:linear-gradient(135deg,#0B0F17,#161B2B);

  --color-success:#22C55E;
  --color-danger:#EF4444;
  --color-investment:#3B82F6;
  --color-investment-alt:#6366F1;
  --color-warning:#F59E0B;

  --text-main:#F8FAFC;
  --text-secondary:#CBD5E1;
  --text-tertiary:#94A3B8;
  --text-disabled:#64748B;
  --text-inverted:#0B0F17;

  --border-main:#1F2637;
  --border-secondary:#2D3748;
  --divider-subtle:#334155;
  --focus-ring:#8B5CF6;

  --radius-sm:10px;
  --radius-md:14px;
  --radius-lg:20px;
  --shadow-soft:0 18px 45px rgba(0,0,0,.22);
  --shadow-panel:0 12px 30px rgba(0,0,0,.18);
}

* { box-sizing:border-box; }
html { background:var(--color-bg-main); width:100%; overflow-x:hidden; }
body {
  margin:0;
  width:100%;
  max-width:100%;
  overflow-x:hidden;
  font-family:Segoe UI, Arial, sans-serif;
  background:
    radial-gradient(circle at top left, rgba(139,92,246,.16), transparent 34rem),
    radial-gradient(circle at bottom right, rgba(59,130,246,.11), transparent 32rem),
    var(--color-bg-main);
  color:var(--text-main);
}
a { color:inherit; }
header { max-width:1180px; margin:auto; padding:24px 18px 10px; }
h1 { margin:0; color:var(--text-main); font-size:clamp(30px,5vw,46px); line-height:1; letter-spacing:-.03em; }
h2, h3 { margin-top:0; color:var(--text-main); letter-spacing:-.01em; }
main { width:100%; max-width:1180px; margin:auto; padding:14px 18px 34px; display:grid; grid-template-columns:220px minmax(0,1fr); gap:16px; }

.hero {
  background:linear-gradient(135deg, rgba(139,92,246,.95), rgba(99,102,241,.86));
  color:var(--text-main);
  border:1px solid rgba(192,132,252,.25);
  border-radius:24px;
  padding:24px;
  box-shadow:var(--shadow-soft);
}
.eyebrow { margin:0 0 6px; color:var(--text-secondary); font-weight:700; letter-spacing:.08em; text-transform:uppercase; font-size:12px; }
.subtitle { margin:10px 0 0; color:var(--text-secondary); max-width:760px; }
.muted { color:var(--text-tertiary); }
.status { margin-top:10px; min-height:22px; color:var(--text-tertiary); }

.panel {
  min-width:0;
  background:rgba(22,27,43,.94);
  border:1px solid var(--border-main);
  border-radius:var(--radius-lg);
  padding:16px;
  box-shadow:var(--shadow-panel);
}
nav { position:sticky; top:14px; align-self:start; }
.jarvis-nav { width:100%; }
.nav-toggle { display:none; }
.nav-head h3 { margin-top:0; }
.nav-menu-button { display:none; }
.nav-item {
  display:block;
  padding:12px;
  border-radius:var(--radius-md);
  margin-bottom:8px;
  text-decoration:none;
  background:var(--color-bg-secondary);
  border:1px solid var(--border-main);
  color:var(--text-secondary);
  transition:background .15s ease, color .15s ease, border-color .15s ease;
}
.nav-item:hover { background:var(--color-surface-hover); color:var(--text-main); border-color:var(--border-secondary); }
.nav-item.active { background:var(--gradient-primary); color:var(--text-main); border-color:rgba(192,132,252,.45); }
.nav-item.soon { color:var(--text-disabled); }

.card {
  min-width:0;
  background:var(--color-surface-elevated);
  border:1px solid var(--border-secondary);
  border-radius:16px;
  padding:14px;
}
.card span { color:var(--text-tertiary); font-size:13px; }
.card strong { display:block; margin-top:6px; color:var(--text-main); font-size:25px; }
.card.income strong { color:var(--color-success); }
.card.expense strong { color:var(--color-danger); }
.card.saving strong { color:var(--color-investment); }
.card.balance strong { color:var(--color-primary-soft); }

button, .button-link {
  min-width:0;
  border:0;
  border-radius:var(--radius-md);
  padding:12px 13px;
  font-weight:700;
  cursor:pointer;
  text-decoration:none;
  text-align:center;
  display:inline-flex;
  align-items:center;
  justify-content:center;
  background:var(--color-primary);
  color:var(--text-main);
  font:inherit;
  transition:background .15s ease, transform .12s ease, opacity .15s ease;
}
button:hover, .button-link:hover { background:var(--color-primary-hover); transform:translateY(-1px); }
button:disabled, .button-link.disabled { opacity:.55; cursor:not-allowed; transform:none; }
button.secondary, .button-link.secondary { background:var(--color-primary-hover); }
button.light, .button-link.light { background:var(--color-surface-hover); color:var(--text-main); }
button.danger { background:var(--color-danger); }
button.danger:hover { background:#DC2626; }
.button-link.finance { background:var(--color-primary); }
.button-link.income { background:var(--color-success); }

textarea, select, input {
  width:100%;
  max-width:100%;
  min-width:0;
  border:1px solid var(--border-secondary);
  border-radius:var(--radius-md);
  padding:11px;
  font:inherit;
  background:var(--color-bg-secondary);
  color:var(--text-main);
  outline:none;
}
textarea { min-height:84px; resize:vertical; }
textarea::placeholder, input::placeholder { color:var(--text-disabled); }
select:focus, input:focus, textarea:focus {
  border-color:var(--focus-ring);
  box-shadow:0 0 0 3px rgba(139,92,246,.18);
}

table { width:100%; max-width:100%; border-collapse:collapse; margin-top:12px; background:var(--color-surface); }
th, td { border-bottom:1px solid var(--divider-subtle); padding:10px; text-align:left; vertical-align:top; font-size:14px; color:var(--text-secondary); }
th { color:var(--text-tertiary); background:var(--color-bg-secondary); font-size:13px; }
tr:hover td { background:rgba(39,46,69,.35); }
.pill { display:inline-block; padding:4px 8px; border-radius:999px; background:var(--color-surface-hover); color:var(--text-secondary); font-size:12px; font-weight:700; }
.list { padding-left:18px; margin-bottom:0; color:var(--text-secondary); }

@media (max-width:980px) {
  main { grid-template-columns:1fr; }
  nav { position:static; }
}
@media (max-width:650px) {
  * { min-width:0; }
  header { padding:14px 12px 6px; }
  main { padding:10px 10px 24px; gap:12px; overflow-x:hidden; }
  .hero { border-radius:18px; padding:18px; }
  .hero, .panel, .card { max-width:100%; overflow-wrap:anywhere; }
  .jarvis-nav {
    position:sticky;
    top:8px;
    z-index:20;
    padding:10px;
    border-radius:18px;
  }
  .nav-head {
    display:flex;
    align-items:center;
    justify-content:space-between;
    gap:10px;
  }
  .nav-head h3 { margin:0; }
  .nav-toggle {
    position:absolute;
    opacity:0;
    pointer-events:none;
  }
  .nav-menu-button {
    width:44px;
    height:44px;
    border-radius:var(--radius-md);
    display:inline-flex;
    flex-direction:column;
    align-items:center;
    justify-content:center;
    gap:5px;
    background:var(--color-bg-secondary);
    border:1px solid var(--border-secondary);
  }
  .nav-menu-button span {
    width:20px;
    height:2px;
    border-radius:999px;
    background:var(--text-main);
  }
  .nav-links {
    display:grid;
    gap:8px;
    max-height:0;
    overflow:hidden;
    opacity:0;
    transition:max-height .18s ease, opacity .15s ease, margin-top .15s ease;
  }
  .nav-toggle:checked ~ .nav-links {
    max-height:520px;
    opacity:1;
    margin-top:10px;
  }
  .nav-item {
    margin-bottom:0;
    min-height:44px;
    display:flex;
    align-items:center;
  }
  button, .button-link {
    width:100%;
    min-height:46px;
    padding:12px;
  }
  table, thead, tbody, tr, th, td { display:block; }
  thead { display:none; }
  tr { width:100%; border:1px solid var(--border-secondary); border-radius:12px; margin-bottom:10px; padding:8px; background:var(--color-surface); }
  td { border:0; padding:5px; }
  td::before { content:attr(data-label) ": "; font-weight:700; color:var(--text-tertiary); }
}
'@
}
