# Arquitectura de Jarvis

Jarvis se esta organizando por capas. Una capa es una parte del sistema con una
responsabilidad clara.

## Estructura actual

```text
Proyecto Jarvis/
├── data/
│   ├── records.json
│   └── backups/
├── docs/
│   └── architecture.md
├── src/
│   ├── core/
│   │   ├── storage.ps1
│   │   └── records.ps1
│   └── web/
│       ├── server.ps1
│       ├── static/
│       │   ├── index.html
│       │   ├── finance.html
│       │   └── organization.html
│       └── modules/
├── jarvis-gui.ps1
├── jarvis-web.ps1
├── jarvis.ps1
├── iniciar-jarvis.cmd
├── iniciar-jarvis-web.cmd
└── iniciar-jarvis-consola.cmd
```

## Que hace cada parte

### `data/`

Guarda la memoria local de Jarvis.

- `records.json`: ideas, tareas y recuerdos.
- `backups/`: copias de seguridad.

Esta carpeta debe mantenerse compatible entre versiones.

### `src/core/`

Es el nucleo del sistema. No deberia depender de una pantalla especifica.

- `storage.ps1`: leer, escribir y respaldar datos.
- `records.ps1`: reglas para crear registros, completar tareas y captura rapida.

Si mas adelante existe app movil, web o escritorio, todas deberian reutilizar el
mismo core.

### `src/web/`

Es la version web local.

- `server.ps1`: servidor HTTP y rutas API.
- `static/jarvis-theme.css`: tema visual compartido entre pantallas web.
- `static/index.html`: Dashboard estatico principal.
- `static/finance.html`: modulo Finanzas estatico.
- `static/organization.html`: modulo Organizacion estatico.

Dashboard, Finanzas y Organizacion ya viven como paginas estaticas en `src/web/static/`.

La idea es que cada modulo futuro tenga su propio archivo o carpeta:

```text
src/web/modules/
├── tasks.ps1
├── memory.ps1
├── calendar.ps1
├── study.ps1
├── ai.ps1
└── settings.ps1
```

## Regla de crecimiento

Cada modulo nuevo deberia tener:

- Una responsabilidad clara.
- Sus propias funciones.
- La menor dependencia posible de otros modulos.
- Datos compatibles con el core.

Ejemplo: Finanzas no deberia romper Tareas. Calendario no deberia depender de
Ideas. IA deberia ser una capa opcional, no el centro de todo.

## Estado actual

Version `0.5`:

- Dashboard web modular.
- Dashboard como centro de la aplicacion.
- Resumen de Finanzas en la pagina principal.
- Resumen de Organizacion en la pagina principal.
- Core compartido para el modo web.
- Compatibilidad con `data/records.json`.
- Accesos viejos conservados.
- App de escritorio clasica todavia disponible.

La ventana clasica `jarvis-gui.ps1` todavia tiene logica propia. En una version
futura se puede migrar para que tambien use `src/core/`.

## Objetivo offline-first

El siguiente objetivo de arquitectura es que Jarvis deje de depender del servidor
local de la notebook para funcionar en el celular. La app instalada debe guardar
sus datos en el telefono y la notebook debe quedar como punto de sincronizacion
opcional.

La propuesta completa esta en:

```text
docs/offline-first-architecture.md
```

## Modulo Finanzas

Finanzas tiene su propio espacio de datos:

```text
data/finance/
├── movements.json
├── settings.json
├── categories.json
├── priorities.json
└── backups/
```

No se mezcla con `data/records.json` porque los datos financieros necesitan
campos distintos: monto, moneda, fecha, categoria, prioridad y tipo de
movimiento.

El contrato inicial esta documentado en `docs/finance-module.md`.

La logica inicial del modulo vive en:

```text
src/modules/finance/
├── finance-storage.ps1
├── finance-core.ps1
└── finance-summary.ps1
```

- `finance-storage.ps1`: lee/escribe archivos financieros.
- `finance-core.ps1`: valida y crea movimientos.
- `finance-summary.ps1`: calcula resumen mensual.

La primera interfaz web esta en:

```text
src/web/static/finance.html
```

Y se abre desde:

```text
http://localhost:8765/finance
```
