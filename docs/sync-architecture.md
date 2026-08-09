# Sincronizacion local-first

Este documento explica la base de sincronizacion entre dispositivos de Jarvis.

## Objetivo

Cada dispositivo tiene su propia copia local de datos. Puede crear, editar y
eliminar registros sin depender de otro dispositivo.

Cuando dos dispositivos pueden comunicarse, intercambian cambios incrementales.
No se reemplaza toda la base local.

## Identidad de workspace y dispositivo

Jarvis separa dos identidades:

- `workspace_id`: identifica un Jarvis personal. Ejemplo: el Jarvis de Nacho.
- `device_id`: identifica una instalacion/dispositivo dentro de ese Jarvis.

Una instalacion nueva crea su propio `workspace_id`, `device_id` y
`sync_secret`. Por eso, si otra persona instala Jarvis, sus datos nacen en un
workspace distinto.

Los datos de sincronizacion viajan con:

- `workspace_id`;
- `device_id`;
- `entity`;
- `entity_id`;
- `operation`;
- `created_at`.

Un cambio cuyo `workspace_id` no coincide se rechaza. Un dispositivo cuyo
`device_id` no esta vinculado tambien se rechaza.

En la notebook, la identidad persistente vive en:

```text
data/identity.json
```

En la PWA, la identidad vive en `localStorage` y los datos viven en IndexedDB.

## Entidades sincronizables

La sincronizacion trabaja por entidad. Las entidades iniciales son:

- `records`: tareas, ideas y recuerdos.
- `finance_movements`: movimientos financieros.
- `finance_settings`: metas y configuracion financiera.

La idea es que futuros modulos como Proyectos, Calendario, Universidad,
Entrenamiento o Habitos agreguen su propia entidad sin cambiar el mecanismo
general.

## Campos necesarios

Cada elemento sincronizable debe tener:

- `id`: identificador global unico.
- `device_id`: dispositivo que lo creo o modifico.
- `revision`: contador simple de cambios locales.
- `created_at`: fecha de creacion.
- `updated_at`: fecha de ultima modificacion.
- `deleted_at`: fecha de eliminacion logica, o `null`.
- `synced_at`: estado heredado para compatibilidad.

Las eliminaciones no borran fisicamente el registro al principio. Se marca
`deleted_at` para que el borrado tambien pueda viajar a otros dispositivos.

## Historial de cambios

La notebook guarda un historial incremental en:

```text
data/sync/changes.json
```

Cada cambio tiene:

```json
{
  "change_id": "change-uuid",
  "entity": "records",
  "entity_id": "record-uuid",
  "operation": "create",
  "value": {},
  "workspace_id": "workspace-uuid",
  "device_id": "notebook-abc",
  "created_at": "2026-08-09T10:00:00",
  "applied_at": "2026-08-09T10:00:00"
}
```

En la PWA, el historial vive en IndexedDB dentro del object store
`sync_changes`.

## Flujo de sincronizacion

1. El dispositivo A crea, edita o elimina algo.
2. Jarvis guarda el dato localmente.
3. Jarvis agrega un cambio pendiente a `sync_changes`.
4. Cuando se ejecuta sync contra la notebook, la PWA envia sus cambios
   pendientes a `POST /api/sync/apply`.
5. La notebook aplica los cambios que correspondan.
6. La notebook responde con cambios propios posteriores al ultimo cursor que la
   PWA conoce.
7. La PWA aplica esos cambios localmente.
8. Los cambios aceptados se marcan como sincronizados.

## Vinculacion

La vinculacion es explicita. Un dispositivo no se suma a otro Jarvis solo por
estar en la misma red.

Flujo inicial:

1. En el dispositivo que ya pertenece al Jarvis, abrir
   `Configuracion -> Sincronizacion`.
2. Generar un codigo corto de vinculacion.
3. En el dispositivo nuevo, abrir `Configuracion -> Sincronizacion`.
4. Configurar la URL/IP del peer.
5. Pegar el codigo y confirmar.
6. El peer registra el nuevo `device_id` como vinculado.
7. El nuevo dispositivo adopta el `workspace_id` y la credencial de sync de ese
   Jarvis.

El codigo actual es numerico, temporal y de un solo uso. Dura 10 minutos. El
codigo no contiene `workspace_id` ni `sync_secret`; solo sirve para que el
servidor de la notebook valide la solicitud y entregue la credencial al
dispositivo que se esta vinculando.

QR queda como mejora futura. La base actual usa codigo manual corto para evitar
dependencias extra.

## Autenticacion

Los endpoints de sync validan:

- `workspace_id`;
- `device_id`;
- `sync_secret`.

La PWA envia estos valores en headers:

```text
X-Jarvis-Workspace-Id
X-Jarvis-Device-Id
X-Jarvis-Sync-Secret
```

Si el workspace es incorrecto, el token es incorrecto o el dispositivo no esta
vinculado, la solicitud se rechaza y no se aplica ningun cambio.

## Endpoints actuales

```text
GET  /api/sync/status
GET  /api/sync/changes?since=...&exclude_device_id=...
POST /api/sync/apply
POST /api/sync/settings
POST /api/sync/pairing/start
POST /api/sync/pairing/complete
GET  /api/sync/conflicts
POST /api/sync/conflicts/resolve
```

`POST /api/sync/apply` recibe:

```json
{
  "device_id": "pwa-abc",
  "since": "2026-08-09T10:00:00",
  "changes": []
}
```

Y responde con:

- cambios aceptados;
- resultados de aplicacion;
- cambios que el cliente todavia no recibio;
- estado general de sincronizacion.

## Conflictos

Regla inicial:

- Si el cambio remoto es mas nuevo por `updated_at`, se aplica.
- Si el dato local es mas nuevo, no se pisa.
- Si no se puede resolver con seguridad, se registra un conflicto.

Los conflictos de la notebook se guardan en:

```text
data/sync/conflicts.json
```

Los conflictos de la PWA se guardan en IndexedDB, object store
`sync_conflicts`.

Esta regla evita perder informacion silenciosamente. Todavia falta crear una
pantalla para revisar conflictos.

## Eliminaciones

Un borrado es un cambio normal con `operation = delete` y el valor completo del
registro con `deleted_at`.

Cuando otro dispositivo recibe ese cambio, conserva el registro marcado como
eliminado. Las pantallas usan solo elementos visibles, es decir, elementos sin
`deleted_at`.

## Mecanismo recomendado entre notebook y celular

La opcion elegida para esta etapa es HTTP local en la misma red:

- La notebook expone el servidor local de Jarvis.
- La PWA guarda la URL de la notebook.
- Cuando ambos estan disponibles, la PWA ejecuta sync manual contra esa URL.

Alternativas consideradas:

- Cloud permanente: mas comodo, pero no respeta la prioridad local-first actual.
- GitHub como transporte de datos: util para codigo, riesgoso para datos
  personales.
- WebRTC/Bluetooth: interesante, pero agrega complejidad alta para esta etapa.
- HTTP local: simple, compatible con la arquitectura actual y suficiente para
  notebook-celular en la misma red.

## Limitaciones actuales

- El QR todavia no esta implementado; se usa codigo manual.
- La sincronizacion automatica en segundo plano queda pendiente.
- La pantalla de conflictos permite conservar local o aceptar remota; merge
  manual queda pendiente.
- El servidor local sigue siendo un peer HTTP simple, no un servidor multiusuario
  endurecido para redes no confiables.
- Las categorias y prioridades financieras se leen como configuracion base; si
  luego se vuelven editables, deben entrar formalmente como entidades de sync.

## Prueba manual notebook-celular

### Preparacion

1. En la notebook, abrir Jarvis web.
2. Entrar a `Configuracion -> Sincronizacion`.
3. Confirmar o editar el nombre del Jarvis y del dispositivo.
4. Copiar una de las URLs locales que muestra la ventana del servidor, por
   ejemplo `http://192.168.1.50:8765`.
5. En el celular, abrir Jarvis y entrar a `Configuracion -> Sincronizacion`.
6. Pegar esa URL en `URL/IP para sincronizar`.
7. En la notebook, generar codigo de vinculacion.
8. En el celular, pegar el codigo y tocar `Vincular con Jarvis existente`.

### Escenario A

Notebook: crear un registro. Luego tocar `Sincronizar ahora`.

Resultado esperado: el registro aparece en el celular despues de sincronizar.

### Escenario B

Celular: crear un registro. Luego tocar `Sincronizar ahora`.

Resultado esperado: el registro aparece en la notebook despues de sincronizar.

### Escenario C

Sin conexion entre dispositivos:

- Notebook: crear elemento A.
- Celular: crear elemento B.
- Luego sincronizar.

Resultado esperado:

- Notebook: A + B.
- Celular: A + B.

### Escenario D

Modificar el mismo registro desde ambos dispositivos antes de sincronizar.

Resultado esperado: Jarvis registra un conflicto y permite conservar local o
aceptar remota.

### Escenario E

Eliminar un registro desde celular estando offline. Luego sincronizar.

Resultado esperado: la notebook recibe el `deleted_at` y el registro deja de
aparecer.

### Escenario F

Apagar la notebook y usar Jarvis desde el celular durante varios dias.

Resultado esperado: el celular sigue funcionando con IndexedDB. Al volver la
notebook y tocar `Sincronizar ahora`, los cambios pendientes se envian.

### Escenario G

Intentar sincronizar sin token valido.

Resultado esperado: respuesta rechazada y ningun dato aplicado.

### Escenario H

Intentar sincronizar dos instalaciones de workspace distinto.

Resultado esperado: respuesta rechazada por `workspace_id` incorrecto y ningun
dato intercambiado.
