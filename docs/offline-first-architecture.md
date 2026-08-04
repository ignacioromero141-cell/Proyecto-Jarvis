# Arquitectura offline-first de Jarvis

## Objetivo

Jarvis debe poder instalarse y usarse en el celular sin depender de que la
notebook este encendida.

La notebook deja de ser el centro obligatorio del sistema. Pasa a ser un punto
de sincronizacion opcional: si esta disponible en la misma red Wi-Fi, intercambia
cambios con el celular; si esta apagada, Jarvis sigue funcionando normalmente en
el telefono.

## Problema actual

Hoy el uso desde el celular depende de una direccion como:

```text
http://192.168.0.89:8765
```

Esa direccion apunta al servidor local PowerShell que corre en la notebook. Si
la notebook esta apagada, si el servidor no esta abierto o si cambia la IP,
Safari no puede conectarse.

El proyecto ya tiene una base importante para resolverlo:

- `src/web/static/manifest.webmanifest`: permite instalar Jarvis como PWA.
- `src/web/static/service-worker.js`: guarda pantallas y archivos estaticos en
  cache.
- `src/web/static/jarvis-local-store.js`: guarda datos en IndexedDB del
  navegador y replica varias rutas `/api/...` sin servidor.
- Los datos actuales ya tienen campos utiles para sincronizacion:
  `device_id`, `revision`, `synced_at`, `created_at`, `updated_at` y
  `deleted_at`.

Lo que falta es convertir esta base en la arquitectura principal, no en un
rescate cuando falla `fetch`.

## Principio nuevo

Jarvis debe ser local-first:

1. La interfaz se carga desde el propio telefono despues de instalarse.
2. Las lecturas y escrituras diarias van primero a IndexedDB local.
3. Cada cambio se registra en una cola local de sincronizacion.
4. La sincronizacion con la notebook ocurre en segundo plano cuando se puede.
5. La app nunca debe bloquear el uso diario por no encontrar la notebook.

## Arquitectura propuesta

```text
Celular
  PWA instalada
  UI HTML/CSS/JS
  JarvisData API
  IndexedDB local
  Cola de cambios
  Sync client opcional

Notebook
  Servidor local PowerShell
  Archivos data/*.json
  Sync endpoint
  Import/export de snapshots
```

### Celular

El celular debe tener todo lo necesario para el uso diario:

- Pantallas: Dashboard, Finanzas, Organizacion y futuros modulos.
- Base local: IndexedDB.
- Reglas basicas de negocio en JavaScript.
- Cola local de cambios pendientes.
- Estado visual de sincronizacion: local, pendiente, sincronizado o error.

### Notebook

La notebook mantiene valor, pero deja de ser obligatoria:

- Puede servir la PWA para instalarla o actualizarla.
- Mantiene compatibilidad con los archivos JSON actuales.
- Expone endpoints de sincronizacion.
- Puede importar cambios hechos en el celular.
- Puede exportar cambios hechos en la notebook.

## Capas nuevas

### 1. App shell

La app shell es la parte instalable:

```text
src/web/static/app/
  index.html
  finance.html
  organization.html
  assets/
  app.js
```

Idealmente, las paginas dejan de ser HTML generado solo por PowerShell y pasan a
ser archivos estaticos instalables. PowerShell puede seguir sirviendolos, pero
la app no depende de PowerShell para renderizar.

### 2. API local del cliente

Crear una capa JavaScript unica:

```text
src/web/static/jarvis-data.js
```

Responsabilidad:

- Leer datos desde IndexedDB.
- Guardar datos en IndexedDB.
- Validar datos simples.
- Registrar cambios en `sync_changes`.
- Exponer funciones como:

```text
JarvisData.records.list()
JarvisData.records.create(...)
JarvisData.records.update(...)
JarvisData.records.delete(...)
JarvisData.finance.movements.create(...)
JarvisData.finance.summary(...)
JarvisData.sync.status()
JarvisData.sync.run()
```

La UI no deberia llamar directamente a `fetch("/api/...")` para operaciones
diarias. Primero llama a `JarvisData`.

### 3. Adaptador de servidor

El servidor PowerShell queda como adaptador:

```text
src/web/server.ps1
```

Responsabilidad:

- Servir archivos estaticos de la PWA.
- Mantener endpoints viejos durante la migracion.
- Exponer endpoints nuevos de sincronizacion.
- Leer y escribir los JSON actuales.

### 4. Protocolo de sincronizacion

Cada dispositivo tiene:

- `device_id`: identifica el aparato.
- `last_seen_change_id`: ultimo cambio remoto aplicado.
- `sync_changes`: cola de cambios locales.

Formato base de un cambio:

```json
{
  "change_id": "change-uuid",
  "entity": "records",
  "entity_id": "record-uuid",
  "operation": "create",
  "value": {},
  "device_id": "pwa-iphone",
  "created_at": "2026-07-18T04:11:00",
  "synced_at": null
}
```

Entidades iniciales:

- `records`
- `finance_movements`
- `finance_categories`
- `finance_priorities`
- `finance_settings`

## Flujo diario esperado

### Notebook apagada

1. El usuario abre Jarvis instalado en el celular.
2. La PWA carga desde cache.
3. Los datos se leen desde IndexedDB.
4. El usuario crea tareas, recuerdos o movimientos financieros.
5. Jarvis guarda todo localmente.
6. Los cambios quedan como pendientes de sincronizacion.

Resultado: Jarvis funciona.

### Notebook encendida y misma Wi-Fi

1. Jarvis detecta la notebook.
2. El celular envia sus cambios pendientes.
3. La notebook aplica esos cambios a sus JSON.
4. La notebook devuelve cambios propios que el celular no tenga.
5. El celular aplica esos cambios en IndexedDB.
6. Ambos actualizan `synced_at`.

Resultado: misma informacion en ambos aparatos.

## Deteccion de notebook

Para una primera version simple, usar configuracion manual:

```text
http://192.168.0.89:8765
```

Pero esa direccion no debe ser necesaria para abrir la app. Solo sirve para
sincronizar.

Despues se puede mejorar con:

- Pantalla de configuracion para guardar la IP de la notebook.
- Boton "Buscar notebook".
- QR generado por la notebook para emparejar el celular.
- Nombre local tipo `jarvis.local` si la red lo permite.

## Resolucion de conflictos

Como primera regla simple:

- Si dos cambios editan campos distintos, se combinan.
- Si dos cambios editan el mismo campo, gana el cambio con `updated_at` mas
  reciente.
- Los borrados usan `deleted_at` y no eliminan fisicamente al principio.
- Si hay duda, conservar ambas versiones y marcar conflicto.

Para Jarvis actual, esta regla alcanza porque los datos son simples:

- Tareas e ideas.
- Recuerdos.
- Movimientos financieros.
- Configuracion financiera.

## Migracion propuesta

### Fase 1: Hacer real el modo offline

Objetivo: instalar y usar Jarvis en el celular aunque la notebook se apague.

Tareas:

- Cambiar la UI para que use `JarvisLocalStore` o `JarvisData` primero.
- Usar el servidor solo como fallback, no como dependencia principal.
- Asegurar que `/`, `/finance` y `/organization` queden cacheadas.
- Agregar una pantalla o mensaje de estado: "Modo local" / "Pendiente de sync".
- Probar instalacion en iPhone: abrir con servidor una vez, agregar a inicio y
  luego apagar la notebook.

### Fase 2: Separar UI estatica de PowerShell

Objetivo: que la app instalada no dependa de HTML generado en runtime.

Tareas:

- Extraer el HTML de `dashboard.ps1`, `finance.ps1` y `organization.ps1` a
  archivos estaticos.
- Dejar PowerShell sirviendo esos archivos.
- Mantener el tema CSS compartido.
- Mover scripts de pantalla a archivos `.js` versionados.

### Fase 3: Sincronizacion manual segura

Objetivo: poder sincronizar cuando ambos dispositivos estan disponibles.

Tareas:

- Crear endpoint `GET /api/sync/changes`.
- Crear endpoint `POST /api/sync/apply`.
- Crear endpoint `POST /api/sync/ack`.
- En el celular, enviar `sync_changes` pendientes.
- En la notebook, aplicar cambios a JSON actuales.
- En el celular, aplicar cambios recibidos en IndexedDB.
- Mostrar cantidad de cambios pendientes.

### Fase 4: Sincronizacion automatica en Wi-Fi

Objetivo: sincronizar sin tocar nada cuando la notebook aparezca.

Tareas:

- Guardar URL de sincronizacion de la notebook en IndexedDB/localStorage.
- Intentar sync al abrir la app.
- Intentar sync cada cierto tiempo si hay pendientes.
- Reintentar sin molestar si falla.
- Mostrar ultima sincronizacion exitosa.

### Fase 5: Emparejamiento y seguridad

Objetivo: que solo tus dispositivos puedan sincronizar.

Tareas:

- Generar un token local en la notebook.
- Mostrar QR para emparejar el celular.
- Guardar token en el celular.
- Exigir token en endpoints `/api/sync/*`.
- Evitar exponer datos personales a cualquiera en la misma Wi-Fi.

## Reutilizacion de codigo existente

Se puede reutilizar mucho:

- `jarvis-local-store.js` como semilla de la base local offline.
- `service-worker.js` como base de cache de app.
- `manifest.webmanifest` e iconos actuales.
- `records.ps1` para mantener compatibilidad con datos de notebook.
- `finance-core.ps1` y `finance-summary.ps1` para el lado notebook.
- `sync.ps1` como base del estado y exportacion de cambios pendientes.
- Las pantallas actuales como primera version visual.

La parte que mas conviene cambiar es la dependencia de la UI respecto de
`fetch("/api/...")`. El contrato debe pasar a ser:

```text
UI -> JarvisData -> IndexedDB
              \-> Sync opcional con notebook
```

## Decision recomendada

Si el objetivo es probar Jarvis en la universidad, la mejor ruta es:

1. Primero hacer que la PWA instalada funcione 100% offline en el celular.
2. Despues agregar sincronizacion manual con la notebook.
3. Recien despues automatizar la sincronizacion.

Esto evita construir sincronizacion compleja antes de resolver lo mas importante:
que Jarvis sea usable aunque la notebook este apagada.
