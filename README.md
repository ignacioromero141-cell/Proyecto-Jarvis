# Jarvis 0.5

Esta es la primera base de tu asistente personal local. Todavia no usa
inteligencia artificial ni internet. Guarda datos simples en tu computadora.

## Como abrirlo

Hace doble clic en `iniciar-jarvis.cmd`. Se abrira una pantalla simple:

- Escribi lo que quieras guardar.
- Elegi si es una idea, una tarea o un recuerdo.
- Apreta `Guardar`.
- Si queres escribir mas natural, usa `Captura rapida`.
- Usa la lista para completar tareas, editar registros o borrar registros.
- Usa `Buscar` para encontrar algo por texto, tipo o estado.
- Mira el panel `Hoy` para ver pendientes y ultimos movimientos.
- Usa `Backup` para crear una copia manual de la memoria local.

Ejemplos para `Captura rapida`:

```text
tengo que estudiar matematica
recorda que tengo dentista el viernes
idea armar un control de gastos simple
```

## Modo web local

Tambien podes abrir Jarvis desde navegador. Esta es la version recomendada para
seguir creciendo por modulos:

1. Hace doble clic en `iniciar-jarvis-web.cmd`.
2. En la notebook, entra a `http://localhost:8765`.
3. Si queres probar desde iPhone, dejalo en la misma red Wi-Fi y usa una de las
   direcciones que aparezcan en la ventana.

Importante: si Windows pregunta por firewall, hay que permitir red privada para
que el iPhone pueda verlo. Si no lo permitis, igual deberia funcionar en la
notebook con `localhost`.

## Arquitectura modular

Desde `0.4`, Jarvis empezo a separarse en capas:

- `src/core/`: logica principal y memoria.
- `src/web/`: servidor web local.
- `src/web/static/index.html`: Dashboard estatico principal.
- `src/web/static/finance.html`: modulo Finanzas estatico.
- `src/web/static/organization.html`: modulo Organizacion estatico.
- `docs/architecture.md`: explicacion de la arquitectura.

El objetivo es que futuros modulos como Finanzas, Calendario, Estudio o IA se
puedan agregar sin romper Tareas, Ideas o Recuerdos.

## Dashboard

El Dashboard ahora funciona como centro de la aplicacion:

- Saludo dinamico segun la hora.
- Resumen financiero del mes actual.
- Resumen de tareas, ideas y recuerdos.
- Acciones rapidas para ir a Finanzas o capturar tareas/ideas.
- Diseno responsive para notebook y celular.

## Identidad visual

Jarvis usa el tema `Oscuro Jarvis` como apariencia predeterminada. La paleta y
variables CSS estan centralizadas en:

```text
src/web/static/jarvis-theme.css
```

Esto permite mantener Dashboard y Finanzas con una identidad visual coherente y
deja preparada la base para futuros temas como claro o automatico.

## Modulo Finanzas

Finanzas ya tiene definido su primer contrato de datos:

- `data/finance/movements.json`: movimientos de dinero.
- `data/finance/categories.json`: categorias personalizables.
- `data/finance/priorities.json`: Necesario, Inversion personal o Prescindible.
- `data/finance/settings.json`: configuracion base.
- `docs/finance-module.md`: explicacion del diseno.

Ya existe una primera pantalla web del modulo en:

```text
http://localhost:8765/finance
```

Desde ahi podes cargar movimientos, ver resumen mensual, borrar movimientos y
usar categorias/prioridades configurables.
Tambien incluye analisis por porcentaje de ingresos, objetivos mensuales,
comparacion ideal vs real, evolucion mensual, comparacion con el mes anterior y
exportacion CSV.

## Consola opcional

La primera version por comandos sigue disponible en
`iniciar-jarvis-consola.cmd`. No es necesario usarla normalmente.

Algunos comandos que acepta son:

```text
idea crear un registro semanal de gastos
tarea leer el capitulo 1
recorda que estudio LOI
ver ideas
ver tareas
ver recuerdos
```

Cada registro recibe un codigo corto. Ese codigo permite completar tareas o
borrar datos:

```text
completar a1b2c3
borrar a1b2c3
```

Escribi `ayuda` para ver los comandos y `salir` para cerrar Jarvis.

## Donde se guardan tus datos

Tus datos viven en `data/records.json`. Es un archivo local y legible. No se
envia informacion a internet.

Jarvis tambien puede crear copias en `data/backups/`. Ademas, antes de guardar
cambios importantes, crea un backup automatico.

Cada registro tiene:

- `id`: un codigo unico.
- `type`: idea, tarea o recuerdo.
- `text`: lo que escribiste.
- `status`: su estado actual.
- `created_at`: fecha de creacion.
- `updated_at`: fecha de la ultima modificacion.

Esta estructura es intencionalmente sencilla. Mas adelante podremos migrarla a
una base de datos y conectarla con una interfaz para iPhone sin perder la idea
central.
