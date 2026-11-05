/* Carga inicial de parámetros.

   ADVERTENCIA: los valores vienen de docs/marcas_cartera_cuc.md y se escribieron de
   memoria. NO están verificados contra el CUC vigente de la Superintendencia de Bancos.
   Antes de usar en producción, validar rangos, orden de segmentos, excepciones (>1472)
   y bandas de cartera vencida, y ajustar @vigencia_desde.

   Idempotente: borra y vuelve a insertar las filas con fecha_desde = @vigencia_desde.
   Para cambiar un parámetro a futuro no se edita esta carga: se cierra la fila vigente
   (fecha_hasta) y se inserta una nueva con su propia fecha_desde. */

SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @vigencia_desde date = '1900-01-01';   -- AJUSTAR a la fecha de la versión del CUC

/* ---------- Regla posicional ---------- */
DELETE FROM marcas.param_regla_posicional WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_regla_posicional
    (cuenta_raiz, pos_inicio, longitud, rango_desde, rango_hasta, bloque_estado, bloque_tipo, fecha_desde)
VALUES ('14', 3, 2, 1, 72, 24, 8, @vigencia_desde);

/* ---------- Estados ---------- */
DELETE FROM marcas.param_estado WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_estado (codigo, ordinal, descripcion, es_improductiva, palabra_clave, fecha_desde)
VALUES
    ('POR_VENCER', 0, N'Por vencer (vigente)',      'N', N'por vencer', @vigencia_desde),
    ('NO_DEVENGA', 1, N'No devenga intereses',      'S', N'no devenga', @vigencia_desde),
    ('VENCIDA',    2, N'Vencida',                   'S', N'vencida',    @vigencia_desde);

/* ---------- Tipos ---------- */
DELETE FROM marcas.param_tipo WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_tipo (codigo, ordinal, descripcion, palabra_clave, fecha_desde)
VALUES
    ('ORIGINAL',       0, N'Original',       NULL,             @vigencia_desde),
    ('REFINANCIADA',   1, N'Refinanciada',   N'refinanciad',   @vigencia_desde),
    ('REESTRUCTURADA', 2, N'Reestructurada', N'reestructurad', @vigencia_desde);

/* ---------- Segmentos ----------
   ordinal NULL: segmentos agregados después, fuera del bloque 1401-1472 (solo por excepción). */
DELETE FROM marcas.param_segmento WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_segmento (codigo, ordinal, descripcion, palabra_clave, fecha_desde)
VALUES
    ('COMERCIAL_PRIORITARIO',    0,    N'Comercial prioritario',       N'comercial prioritario', @vigencia_desde),
    ('CONSUMO_PRIORITARIO',      1,    N'Consumo prioritario',         N'consumo prioritario',   @vigencia_desde),
    ('INMOBILIARIO',             2,    N'Inmobiliario',                N'inmobiliario',          @vigencia_desde),
    ('MICROCREDITO',             3,    N'Microcrédito',                N'microcredito',          @vigencia_desde),
    ('PRODUCTIVO',               4,    N'Productivo',                  N'productivo',            @vigencia_desde),
    ('COMERCIAL_ORDINARIO',      5,    N'Comercial ordinario',         N'comercial ordinario',   @vigencia_desde),
    ('CONSUMO_ORDINARIO',        6,    N'Consumo ordinario',           N'consumo ordinario',     @vigencia_desde),
    ('VIVIENDA_INTERES_PUBLICO', 7,    N'Vivienda de interés público', N'vivienda de interes',   @vigencia_desde),
    ('EDUCATIVO',                NULL, N'Educativo',                   N'educativo',             @vigencia_desde),
    ('INVERSION_PUBLICA',        NULL, N'Inversión pública',           N'inversion publica',     @vigencia_desde);

/* ---------- Excepciones ---------- */
DELETE FROM marcas.param_excepcion WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_excepcion (cuenta_cuc, estado, tipo, segmento, marca_especial, signo, fecha_desde)
VALUES
    ('1499', NULL, NULL, NULL, 'PROVISION', -1, @vigencia_desde);

/* PENDIENTE: cuentas > 1472 (educativo, inversión pública, ...). Completar con los códigos
   reales del CUC vigente. Plantilla:
INSERT INTO marcas.param_excepcion (cuenta_cuc, estado, tipo, segmento, marca_especial, signo, fecha_desde)
VALUES ('14XX', 'POR_VENCER', 'ORIGINAL', 'EDUCATIVO', NULL, 1, @vigencia_desde);
*/

/* ---------- Bandas ----------
   Por vencer y no devenga: bandas genéricas (segmento NULL) de plazo al vencimiento. */
DELETE FROM marcas.param_banda WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_banda (estado, segmento, sufijo, dias_desde, dias_hasta, fecha_desde)
SELECT e.estado, NULL, b.sufijo, b.dias_desde, b.dias_hasta, @vigencia_desde
FROM (VALUES ('POR_VENCER'), ('NO_DEVENGA')) AS e(estado)
CROSS JOIN (VALUES
    ('05',   1,   30),
    ('10',  31,   90),
    ('15',  91,  180),
    ('20', 181,  360),
    ('25', 361, NULL)
) AS b(sufijo, dias_desde, dias_hasta);

/* PENDIENTE: cartera vencida. El rango de días de mora depende del segmento; cargar una
   fila por (segmento, sufijo) con los valores del CUC vigente. Mientras falten, las
   subcuentas vencidas quedan marcadas sin días y generan alerta BANDA_FALTANTE. Plantilla:
INSERT INTO marcas.param_banda (estado, segmento, sufijo, dias_desde, dias_hasta, fecha_desde)
VALUES ('VENCIDA', 'MICROCREDITO', '05', 1, 30, @vigencia_desde);
*/

COMMIT TRANSACTION;
GO
