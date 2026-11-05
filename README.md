# marcas-cartera-cuc

Proceso de ingeniería de datos que asigna **marcas** (estado, tipo, segmento y banda de días)
a las cuentas de cartera de créditos (cuenta 14) del catálogo contable de un banco, usando
como referencia el **Catálogo Único de Cuentas (CUC)** de la Superintendencia de Bancos del
Ecuador.

Las marcas alimentan métricas como cartera bruta, cartera improductiva y morosidad.

Motor: **SQL Server** (2016 SP1 o superior por `CREATE OR ALTER`, `CONCAT_WS` requiere 2017).

## Cómo funciona

1. Las reglas del CUC se cargan en **tablas de parámetros con vigencia**
   (`fecha_desde`, `fecha_hasta`), tomadas del
   [CUC oficial](https://www.superbancos.gob.ec/bancos/wp-content/uploads/downloads/2022/01/CUC-plan-cuentas-activos-28-dic-21.pdf)
   (Resolución SB-2021-0403).
2. El **motor de marcas** decodifica cada cuenta `14NN` por posición (bloques de
   3 estados × 3 tipos × 8 posiciones en 1401–1472) y aplica excepciones (educativo,
   inversión pública, COVID-19, provisiones) y bandas de días (solo por vencer).
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
| `sql/datos/` | Carga del grupo 14 del CUC oficial en `marcas.cuc_oficial` |
| `datos/` | Grupo 14 del CUC extraído del PDF (CSV, para revisión) |
| `scripts/extraer_cuc_pdf.py` | Regenera `datos/` y `sql/datos/` desde un PDF nuevo del CUC (requiere `pypdf`) |
| `sql/motor/` | `fn_marcar_cuenta`, `usp_marcar_cuc`, `usp_marcar_catalogo_banco`, `usp_proceso_marcas` |
| `sql/validaciones/` | `usp_validar_parametros` (antes de marcar) y `usp_validar_resultados` (después) |
| `sql/despliegue.sql` | Ejecuta todo en orden (modo SQLCMD) |
| `tests/` | Pruebas: regla posicional, proceso de punta a punta y CUC completo |

## Uso

Desplegar (scripts idempotentes, desde la raíz del repo):

```bash
sqlcmd -S <servidor> -d <base> -E -b -i sql/despliegue.sql
```

El despliegue ya carga el grupo 14 del CUC en `marcas.cuc_oficial`. Cargar
`marcas.catalogo_banco` con el catálogo interno y correr el proceso para una fecha de corte:

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
| `02_prueba_proceso.sql` | Proceso completo, match por prefijo y que la falta de cobertura lo detenga | Catálogo de banco sintético sobre el CUC oficial, con `ROLLBACK`; **solo en base de desarrollo** |
| `03_prueba_cuc_completo.sql` | Recorre el CUC cargado y compara la marca calculada con el nombre oficial | El CUC oficial en `marcas.cuc_oficial` |

## Estado

- [x] DDL, carga de parámetros, motor, validaciones y pruebas en SQL Server.
- [x] Parámetros validados contra el CUC oficial (SB-2021-0403): las 230 cuentas del grupo 14
      quedan marcadas y coinciden con su nombre. Las tres pruebas pasan en SQL Server 2022.
- [ ] Revisar si hay resoluciones posteriores a la SB-2021-0403 que reformen el grupo 14.
- [ ] Subsegmentos de crédito: el CUC no les asigna código; se podrán marcar si el catálogo
      interno del banco los separa en cuentas propias.
