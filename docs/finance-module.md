# Modulo Finanzas

Este documento define el contrato de datos del modulo Finanzas de Jarvis.

Un contrato de datos es el acuerdo sobre como se guarda la informacion. Si el
contrato es claro, despues podemos crear pantallas, resumenes, graficos,
exportaciones e IA sin reescribir todo.

## Objetivo

El modulo Finanzas ayuda a registrar movimientos personales y entender habitos
de gasto. La prioridad no es juzgar tus decisiones, sino darte claridad.

El modelo anterior de "4 zonas" queda reemplazado por un modelo mas flexible:

- categorias personalizables: Salud, Educacion, Transporte, Ocio, etc.
- prioridad del movimiento: Necesario, Inversion personal o Prescindible.
- tipo de movimiento: ingreso, gasto o ahorro/inversion.

Esto permite agregar categorias nuevas sin modificar el codigo.

## Archivos de datos

```text
data/
└── finance/
    ├── movements.json
    ├── categories.json
    ├── priorities.json
    ├── settings.json
    └── backups/
```

### `movements.json`

Guarda cada movimiento de dinero.

Ejemplo:

```json
{
  "id": "abc123",
  "kind": "expense",
  "category_id": "food",
  "priority": "necessary",
  "amount": 3500,
  "currency": "ARS",
  "date": "2026-07-06",
  "note": "almuerzo en la facultad",
  "payment_method": "cash",
  "source": "manual",
  "created_at": "2026-07-06T15:30:00",
  "updated_at": "2026-07-06T15:30:00"
}
```

Campos:

- `id`: codigo unico del movimiento.
- `kind`: tipo general. Valores permitidos: `income`, `expense`, `saving`.
- `category_id`: categoria configurable. Ejemplo: `food`, `health`,
  `education`.
- `priority`: clasificacion del gasto. Valores iniciales: `necessary`,
  `personal_investment`, `optional`.
- `amount`: monto numerico positivo.
- `currency`: moneda. Por ahora `ARS`.
- `date`: fecha real del movimiento en formato `YYYY-MM-DD`.
- `note`: detalle corto escrito por el usuario.
- `payment_method`: metodo de pago. Por ahora texto simple.
- `source`: origen del registro. Por ahora `manual`; futuro: `import`, `ai`,
  `recurring`.
- `created_at`: fecha en que Jarvis guardo el dato.
- `updated_at`: ultima modificacion.

Regla importante:

- `amount` siempre se guarda positivo.
- El significado lo da `kind`, no un numero negativo.

### `categories.json`

Guarda categorias editables. La app no debe tener categorias escritas de forma
fija en el codigo.

Ejemplo:

```json
{
  "id": "health",
  "label": "Salud",
  "kind": "expense",
  "color": "#16a34a",
  "enabled": true,
  "sort_order": 30
}
```

Campos:

- `id`: identificador tecnico estable. No deberia tener espacios.
- `label`: nombre visible.
- `kind`: tipo sugerido: `income`, `expense` o `saving`.
- `color`: color para la interfaz.
- `enabled`: permite ocultar categorias sin borrar historico.
- `sort_order`: orden visual.

Para agregar una categoria futura, se agrega un objeto nuevo al JSON. El codigo
debe leer ese archivo y mostrarla automaticamente.

### `priorities.json`

Guarda las clasificaciones de prioridad.

Prioridades iniciales:

- `necessary`: Necesario.
- `personal_investment`: Inversion personal.
- `optional`: Prescindible.

La prioridad responde esta pregunta:

> Que tan importante fue este movimiento para mi vida?

Ejemplos:

- Necesario: comida basica, transporte, salud, alquiler.
- Inversion personal: curso, libro, gimnasio, educacion.
- Prescindible: gustos, compras impulsivas, salidas no planificadas.

### `settings.json`

Guarda configuracion general del modulo.

Ejemplo:

```json
{
  "currency": "ARS",
  "default_payment_method": "cash",
  "monthly_targets": {
    "saving": 30,
    "necessary": 20,
    "optional": 40,
    "personal_investment": 10
  },
  "updated_at": null
}
```

`monthly_targets` guarda los objetivos ideales del mes. Deben sumar 100%.

## Calculos principales

Para un mes seleccionado:

- ingresos totales: suma de `kind = income`.
- gastos totales: suma de `kind = expense`.
- ahorro/inversion total: suma de `kind = saving`.
- balance: `income - expense - saving`.
- gasto por categoria.
- gasto por prioridad.
- porcentaje de cada grupo respecto de ingresos.
- comparacion entre real y objetivo.
- evolucion mensual.
- comparacion con el mes anterior.

Estos calculos permiten responder preguntas utiles:

- En que categoria gasto mas?
- Cuanto de mi gasto fue necesario?
- Cuanto fue inversion personal?
- Cuanto fue prescindible?
- Estoy gastando mas de lo que ingresa?
- Como cambie respecto del mes anterior?
- Estoy cerca o lejos de mis objetivos?

## Diferencia con `records.json`

`records.json` guarda memoria general de Jarvis:

- ideas
- tareas
- recuerdos

Finanzas necesita datos mas especificos, por eso vive en `data/finance/`.

No mezclamos ambos mundos porque eso haria mas dificil mantener el proyecto.

## Etapas recomendadas

### Finanzas 0.1

- Crear contrato de datos flexible.
- Crear funciones para leer/escribir movimientos.
- Crear resumen mensual basico por categoria y prioridad.

### Finanzas 0.2

- Pantalla `/finance`.
- Registrar movimientos.
- Borrar movimientos.
- Ver resumen mensual.

### Finanzas 0.3

- Editar categorias desde la interfaz.
- Exportar CSV.
- Historial mensual.

### Finanzas 0.4+

- Graficos.
- Gastos recurrentes.
- Presupuestos.
- Analisis con IA.
