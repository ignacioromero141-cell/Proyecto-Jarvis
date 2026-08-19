# Formato de respaldo Jarvis v1

## Separación de capas

La copia usa dos capas independientes:

1. Paquete interno `jarvis-export-v1`, que representa datos y metadata.
2. Envoltorio criptográfico versionado, que protege el paquete completo.

Esto permite cambiar el transporte futuro sin acoplar los respaldos a Supabase.

## Paquete interno

Campos obligatorios:

```json
{
  "format_version": 1,
  "app_version": "0.6-phase0",
  "exported_at": "ISO-8601",
  "source_origin": "https://...",
  "source_protocol": "https:",
  "source_kind": "pwa-indexeddb",
  "database_name": "jarvis-local-first",
  "database_version": 5,
  "workspace_id": "...",
  "device_id": "...",
  "identity": {},
  "local_storage": {},
  "stores": {},
  "pending_changes": [],
  "conflicts": [],
  "cursors": {},
  "statistics": {},
  "serialization": {},
  "checksums": {}
}
```

Todos los stores se leen dentro de una transacción IndexedDB de solo lectura. Los registros se ordenan por su clave estable y los objetos por nombre de campo. Se preservan IDs, UUID, timestamps, `deleted_at`, historial, conflictos, cursores y configuraciones.

El serializador admite JSON, `Date`, números especiales, `BigInt`, `undefined`, `ArrayBuffer`, typed arrays y `Blob`. Rechaza funciones, símbolos y referencias circulares antes de descargar el archivo.

Los hashes son SHA-256 del JSON canónico:

- uno por store;
- uno para `local_storage`;
- uno para todo el payload sin el propio bloque `checksums`.

Un conteo declarado que no coincide con el contenido también invalida la copia.

## Cifrado PWA predeterminado

- KDF: PBKDF2-HMAC-SHA-256.
- Iteraciones: 310.000.
- Salt: 16 bytes aleatorios.
- Cifrado autenticado: AES-256-GCM.
- IV: 12 bytes aleatorios por copia.
- Tag: 128 bits.
- AAD: encabezado criptográfico canónico.
- Contraseña mínima: 10 caracteres; nunca se guarda.

AES-GCM detecta contraseña incorrecta y cualquier alteración antes de analizar o importar datos. La opción sin cifrar es avanzada y muestra una advertencia porque deja legibles los datos y el secreto LAN.

## Importación controlada v1

- La selección y la vista previa son de solo lectura.
- Un workspace distinto bloquea la importación.
- Un store desconocido bloquea la importación.
- Los IDs nuevos se agregan.
- Los IDs idénticos se conservan.
- Los IDs con contenido diferente mantienen la versión local y generan un registro en `sync_conflicts`.
- El historial se deduplica por `change_id`, que ya está asociado al workspace.
- La identidad, el `device_id` y `localStorage` actuales no se reemplazan en este modo.
- Antes de aplicar se exige descargar un respaldo cifrado del estado actual.
- Todos los `add` y conflictos se escriben en una sola transacción; `metadata` (incluidos cursores) se procesa al final. Cualquier error aborta la transacción completa.
- Una marca estable `backup_import:<checksum>` registra el snapshot importado y evita duplicar esa marca o sus conflictos al repetir la misma copia.

Limitación consciente: v1 no ofrece “reemplazar todo” ni restauración automática de identidad. El paquete sí conserva esa información para una futura restauración guiada, pero la combinación inicial evita cambiarla silenciosamente.

`backup-sandbox.html` permite una prueba completa en la base separada `jarvis-backup-restore-sandbox-v1`. Adopta la identidad de la copia solamente dentro de un adaptador en memoria, restaura los stores y compara el conteo de entidades. No abre `jarvis-local-first` ni escribe `localStorage`, por lo que sirve para verificar una copia sin afectar la instalación real.

## Backup de notebook

`Backup-Jarvis.ps1` crea una instantánea verificando hashes antes y después de copiar. Si los JSON cambian, reintenta hasta tres veces y, si no logra estabilidad, pide detener Jarvis.

El ZIP interno contiene:

- `data/**` relevante;
- `manifest.json` con tamaño y SHA-256 de cada archivo;
- `comparison/jarvis-notebook-export-v1.json`, compatible con el comparador web.

Los códigos y tokens temporales de vinculación (`pairing_code`,
`pairing_token`, `pairing_expires_at`) se excluyen porque no son necesarios
para restaurar la identidad. La credencial LAN estable sí se conserva dentro
del contenedor cifrado. El manifest tampoco guarda la ruta completa del perfil
de Windows.

El modo predeterminado cifra el ZIP mediante una construcción estándar encrypt-then-MAC compatible con Windows PowerShell:

- PBKDF2-HMAC-SHA-256, 310.000 iteraciones, salt aleatorio;
- AES-256-CBC con IV aleatorio y PKCS#7;
- HMAC-SHA-256 sobre `salt || IV || ciphertext`, con una clave separada derivada.

La autenticación se valida antes de descifrar. `Restore-JarvisNotebookBackup.ps1` solo restaura en un directorio vacío, verifica todos los hashes y limpia ese destino si la validación falla. No escribe sobre `data/` real.

`-AllowUnencrypted` produce un ZIP normal únicamente como opción avanzada y emite una advertencia explícita.

## Evolución

Versiones futuras deben agregar migradores explícitos. Una versión desconocida se rechaza sin escribir datos. Campos adicionales pueden tolerarse si no cambian las secciones obligatorias ni la verificación de integridad.
