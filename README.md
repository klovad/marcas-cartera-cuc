# marcas-cartera-cuc

Proceso de ingeniería de datos que asigna **marcas** (estado, tipo, segmento y banda de días)
a las cuentas de cartera de créditos (cuenta 14) del catálogo contable de un banco, usando
como referencia el **Catálogo Único de Cuentas (CUC)** de la Superintendencia de Bancos del
Ecuador.

Las marcas alimentan métricas como cartera bruta, cartera improductiva y morosidad.

Motor: **SQL Server** (2016 SP1 o superior por `CREATE OR ALTER`, `CONCAT_WS` requiere 2017).

## Cómo funciona

1. Las reglas del CUC se cargan en **tablas de parámetros con vigencia**
   (`fecha_desde`, `fecha_hasta`).
2. El **motor de marcas** decodifica cada cuenta `14NN` por posición
   (8 segmentos × 3 tipos × 3 estados = 1401–1472) y aplica excepciones y bandas.
3. El catálogo del banco se cruza con el CUC marcado por **prefijo más largo**
   (6 dígitos, luego 4).
4. Las **validaciones** detienen el proceso si alguna cuenta 14 queda sin marca.

El diseño completo está en [`docs/marcas_cartera_cuc.md`](docs/marcas_cartera_cuc.md).

## Principios

- Nada de lógica quemada: bloques, segmentos, excepciones y bandas viven en parámetros.
- La marca se calcula por código de cuenta, nunca por nombre; el nombre oficial solo valida.
- Excepción > regla posicional.
- Cobertura total: una cuenta 14 sin marca hace fallar el proceso.

## Estructura

| Ruta | Contenido |
|---|---|
| `docs/` | Diseño, modelo de tablas y validaciones |
| `sql/ddl/` | Esquema `marcas` y tablas de entrada, parámetros, resultado y control |
| `sql/params/` | Carga inicial de parámetros (idempotente) |
| `sql/motor/` | `fn_marcar_cuenta`, `usp_marcar_cuc`, `usp_marcar_catalogo_banco`, `usp_proceso_marcas` |
| `sql/validaciones/` | `usp_validar_parametros` (antes de marcar) y `usp_validar_resultados` (después) |
| `sql/despliegue.sql` | Ejecuta todo en orden (modo SQLCMD) |
| `tests/` | Pruebas: regla posicional, proceso de punta a punta y CUC completo |

## Uso

Desplegar (scripts idempotentes, desde la raíz del repo):

```bash
sqlcmd -S <servidor> -d <base> -E -b -i sql/despliegue.sql
```

Cargar las entradas `marcas.cuc_oficial` (CUC publicado) y `marcas.catalogo_banco`, y correr
el proceso para una fecha de corte:

```sql
EXEC marcas.usp_proceso_marcas @fecha_corte = '2026-10-31';
```

Resultado en `marcas.cuc_marcado` y `marcas.catalogo_banco_marcado`; alertas en
`marcas.control_alertas`. El proceso falla con:

| Error | Causa |
|---|---|
| 50001 | Parámetros inválidos: duplicados vigentes, ordinales faltantes, códigos inexistentes o bandas traslapadas |
| 50002 | Cobertura incompleta: una cuenta 14 del banco no tiene marca |

Las alertas `AVISO` no detienen el proceso: cuenta del CUC sin regla ni excepción, subcuenta
sin banda, nombre oficial que no coincide con el estado, hueco entre bandas.

## Pruebas

```bash
sqlcmd -S <servidor> -d <base> -E -b -i tests/01_prueba_regla_posicional.sql
```

| Prueba | Qué valida | Datos |
|---|---|---|
| `01_prueba_regla_posicional.sql` | Casos conocidos y que 1401–1472 den 72 combinaciones distintas | Solo parámetros |
| `02_prueba_proceso.sql` | Proceso completo, match por prefijo y que la falta de cobertura lo detenga | Sintéticos, con `ROLLBACK`; **solo en base de desarrollo** |
| `03_prueba_cuc_completo.sql` | Recorre el CUC cargado y compara la marca calculada con el nombre oficial | El CUC real en `marcas.cuc_oficial` |

## Estado

- [x] DDL, carga de parámetros, motor, validaciones y pruebas en SQL Server.
- [x] Pruebas 01 y 02 pasan en SQL Server 2022; la 03 probada con un CUC sintético.
- [ ] **Validar los parámetros contra el CUC vigente** corriendo `03_prueba_cuc_completo.sql`
      con el catálogo oficial: rangos 1401–1472, orden de segmentos y palabras clave. Los
      valores actuales se escribieron de memoria.
- [ ] Cargar las excepciones de cuentas > 1472 (educativo, inversión pública, ...).
- [ ] Cargar las bandas de días de cartera vencida por segmento.
- [ ] Ajustar `@vigencia_desde` en `sql/params/01_carga_inicial.sql`.
