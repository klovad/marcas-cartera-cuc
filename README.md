# marcas-cartera-cuc

Proceso de ingeniería de datos que asigna **marcas** (estado, tipo, segmento y banda de días)
a las cuentas de cartera de créditos (cuenta 14) del catálogo contable de un banco, usando
como referencia el **Catálogo Único de Cuentas (CUC)** de la Superintendencia de Bancos del
Ecuador.

Las marcas alimentan métricas como cartera bruta, cartera improductiva y morosidad.

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

| Carpeta | Contenido |
|---|---|
| `docs/` | Diseño, modelo de tablas y validaciones |
| `sql/ddl/` | Creación de tablas |
| `sql/params/` | Carga de parámetros |
| `sql/motor/` | Cálculo de marcas |
| `sql/validaciones/` | Controles de calidad |

## Estado

Diseño documentado; SQL pendiente.

- [ ] Confirmar el motor de base de datos y escribir el SQL en ese dialecto.
- [ ] Validar contra el CUC vigente: rangos 1401–1472, orden de segmentos, cuentas fuera del
      patrón (>1472, 1499) y bandas de 6 dígitos en cartera vencida.
- [ ] DDL, carga inicial de parámetros, motor y validaciones.
- [ ] Prueba que recorra todo el CUC comparando marca calculada vs nombre oficial.
