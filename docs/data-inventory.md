# Inventario de datos de Jarvis — Fase 0

Este inventario describe el estado persistente actual. No depende de Supabase ni de un proveedor de sincronización.

## PWA: IndexedDB

- Base: `jarvis-local-first`
- Versión actual: `5`
- Clave normal: `id`
- Excepciones: `sync_changes.change_id`, `sync_conflicts.conflict_id` y `metadata.key`

Object stores:

| Grupo | Stores |
|---|---|
| General | `records` |
| Finanzas | `finance_movements`, `finance_categories`, `finance_priorities`, `finance_payment_methods`, `finance_settings` |
| Calendario y estudio | `calendar_events`, `study_subjects`, `study_topics`, `study_evaluations`, `study_assignments`, `study_notes`, `study_schedules` |
| Archivos | `file_assets`, `file_links`, `local_file_roots`, `local_file_locations` |
| Sincronización | `sync_changes`, `sync_conflicts`, `metadata` |

`file_assets` y `file_links` guardan metadata. Los binarios de fotos y archivos externos no están dentro de IndexedDB en la implementación actual. `local_file_roots` y `local_file_locations` describen rutas propias del dispositivo y no deben considerarse portables sin revisión.

## PWA: localStorage

El exportador incluye solamente claves con prefijo `jarvis_`, para no copiar datos de otros sitios que pudieran compartir el mismo origen de GitHub Pages. Actualmente se detectaron:

- `jarvis_device_id`, `jarvis_device_name`;
- `jarvis_workspace_id`, `jarvis_workspace_name`;
- `jarvis_sync_secret`;
- `jarvis_linked_devices`;
- `jarvis_notebook_sync_url`, `jarvis_notebook_last_contact`;
- `jarvis_user_display_name`;
- preferencias visuales de Estudio con prefijo `jarvis_`;
- `jarvis_last_backup_exported_at` desde esta fase.

La credencial `jarvis_sync_secret` es necesaria para una restauración LAN fiel. Por eso se guarda dentro del paquete interno, pero la exportación cifrada es la opción predeterminada. Nunca debe publicarse en GitHub Pages ni subirse al repositorio.

## Notebook: JSON

| Área | Archivos principales |
|---|---|
| Identidad | `data/identity.json`, `data/device-id.txt` |
| General | `data/records.json` |
| Finanzas | `data/finance/*.json` |
| Calendario | `data/calendar/events.json` |
| Estudio | `data/study/*.json` |
| Archivos | `data/files/*.json` |
| Sincronización | `data/sync/changes.json`, `data/sync/conflicts.json` |
| Históricos | `data/backups/**`, `data/finance/backups/**` |

`data/identity.json` incluye workspace, dispositivo notebook, dispositivos vinculados, secreto LAN y, cuando existe, un código/token de emparejamiento temporal. El backup conserva la identidad y el secreto LAN estable dentro del contenedor cifrado, pero elimina de la instantánea `pairing_code`, `pairing_token` y `pairing_expires_at` porque son credenciales efímeras innecesarias para restaurar.

Se excluyen deliberadamente `data/runtime/**`, PID, locks, temporales y logs. Son estado de ejecución, no datos restaurables.

## Significado de sincronización

- Registro local: existe en un store de entidad, tenga o no cambios pendientes.
- Cambio pendiente: entrada de `sync_changes` sin `synced_at` en PWA.
- Cambio confirmado/histórico: entrada de `sync_changes` con `synced_at`; en notebook el historial aplicado usa `applied_at`.
- Cambio recibido: historial confirmado cuyo `device_id` no es el dispositivo actual.
- Snapshot importado: se marca en `metadata`; no implica que cada registro tenga un cambio pendiente.
- Cursor: `last_server_cursor` dentro de una entrada `metadata` de sincronización.
- Borrado lógico: el registro sigue presente y tiene `deleted_at`.

Por eso una sincronización con `Enviados: 0 / Recibidos: 0` puede ser correcta: cuenta cambios incrementales de esa ejecución, no todos los registros existentes.

## Separación por origen

Safari separa IndexedDB por origen exacto (`protocolo + host + puerto`). La aplicación de GitHub Pages y cada IP LAN son instalaciones distintas. Por seguridad, una página no puede enumerar ni leer IndexedDB de otros orígenes. Para respaldar una IP LAN anterior hay que abrir exactamente ese origen y exportar desde su Configuración; si ya no es accesible, primero debe recuperarse temporalmente ese host/IP de manera controlada. La Fase 0 no intenta escanear la red ni fusionar esos orígenes.
