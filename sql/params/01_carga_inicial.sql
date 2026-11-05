/* Carga inicial de parámetros.

   Fuente: CUC de la Superintendencia de Bancos, plan de cuentas de activos actualizado
   con la Resolución SB-2021-0403 (22-feb-2021):
   https://www.superbancos.gob.ec/bancos/wp-content/uploads/downloads/2022/01/CUC-plan-cuentas-activos-28-dic-21.pdf
   Validado con tests/03_prueba_cuc_completo.sql contra sql/datos/01_cuc_oficial_grupo14.sql.

   Idempotente: borra y vuelve a insertar las filas con fecha_desde = @vigencia_desde.
   Para cambiar un parámetro a futuro no se edita esta carga: se cierra la fila vigente
   (fecha_hasta) y se inserta una nueva con su propia fecha_desde. */

SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @vigencia_desde date = '2021-02-22';   -- Resolución SB-2021-0403

/* ---------- Regla posicional ----------
   1401-1472: bloques de 24 por estado y de 8 por tipo; la posición dentro del bloque de 8
   es el segmento. */
DELETE FROM marcas.param_regla_posicional WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_regla_posicional
    (cuenta_raiz, pos_inicio, longitud, rango_desde, rango_hasta, bloque_estado, bloque_tipo, fecha_desde)
VALUES ('14', 3, 2, 1, 72, 24, 8, @vigencia_desde);

/* ---------- Estados ---------- */
DELETE FROM marcas.param_estado WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_estado (codigo, ordinal, descripcion, es_improductiva, palabra_clave, fecha_desde)
VALUES
    ('POR_VENCER', 0, N'Por vencer',           'N', N'por vencer', @vigencia_desde),
    ('NO_DEVENGA', 1, N'No devenga intereses', 'S', N'no devenga', @vigencia_desde),
    ('VENCIDA',    2, N'Vencida',              'S', N'vencida',    @vigencia_desde);

/* ---------- Tipos ---------- */
DELETE FROM marcas.param_tipo WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_tipo (codigo, ordinal, descripcion, palabra_clave, fecha_desde)
VALUES
    ('ORIGINAL',       0, N'Original',       NULL,             @vigencia_desde),
    ('REFINANCIADA',   1, N'Refinanciada',   N'refinanciad',   @vigencia_desde),
    ('REESTRUCTURADA', 2, N'Reestructurada', N'reestructurad', @vigencia_desde);

/* ---------- Segmentos ----------
   Posiciones 4, 5 y 6 del bloque (p. ej. 1405-1407) no existen en esta versión del CUC.
   ordinal NULL: segmentos fuera del bloque 1401-1472 (solo por excepción). */
DELETE FROM marcas.param_segmento WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_segmento (codigo, ordinal, descripcion, palabra_clave, fecha_desde)
VALUES
    ('PRODUCTIVO',                     0,    N'Productivo',                           N'productivo',                 @vigencia_desde),
    ('CONSUMO',                        1,    N'Consumo',                              N'consumo',                    @vigencia_desde),
    ('INMOBILIARIO',                   2,    N'Inmobiliario',                         N'inmobiliario',               @vigencia_desde),
    ('MICROCREDITO',                   3,    N'Microcrédito',                         N'microcredito',               @vigencia_desde),
    ('VIVIENDA_INTERES_SOCIAL',        7,    N'Vivienda de interés social y público', N'vivienda de interes social', @vigencia_desde),
    ('EDUCATIVO',                      NULL, N'Educativo',                            N'educativ',                   @vigencia_desde),
    ('INVERSION_PUBLICA',              NULL, N'Inversión pública',                    N'inversion publica',          @vigencia_desde);

/* ---------- Excepciones ---------- */
DELETE FROM marcas.param_excepcion WHERE fecha_desde = @vigencia_desde;

/* 1473-1490: educativo e inversión pública, alternados, por estado y tipo.
   Las subcuentas 1473xx-1478xx heredan la marca y toman la banda por sufijo. */
INSERT INTO marcas.param_excepcion (cuenta_cuc, estado, tipo, segmento, marca_especial, signo, fecha_desde)
SELECT CONCAT('14', 73 + (e.ord * 6) + (t.ord * 2) + s.ord), e.codigo, t.codigo, s.codigo, NULL, 1, @vigencia_desde
FROM (VALUES (0, 'POR_VENCER'), (1, 'NO_DEVENGA'), (2, 'VENCIDA')) AS e(ord, codigo)
CROSS JOIN (VALUES (0, 'ORIGINAL'), (1, 'REFINANCIADA'), (2, 'REESTRUCTURADA')) AS t(ord, codigo)
CROSS JOIN (VALUES (0, 'EDUCATIVO'), (1, 'INVERSION_PUBLICA')) AS s(ord, codigo);

/* 1491-1496: cartera refinanciada y reestructurada COVID-19, por estado. La cuenta de 4
   dígitos mezcla segmentos; cada subcuenta de 6 dígitos es un segmento (no una banda). */
INSERT INTO marcas.param_excepcion (cuenta_cuc, estado, tipo, segmento, marca_especial, signo, fecha_desde)
SELECT c.cuenta, c.estado, c.tipo, NULL, 'COVID19', 1, @vigencia_desde
FROM (VALUES
    ('1491', 'POR_VENCER', 'REFINANCIADA'),
    ('1492', 'NO_DEVENGA', 'REFINANCIADA'),
    ('1493', 'VENCIDA',    'REFINANCIADA'),
    ('1494', 'POR_VENCER', 'REESTRUCTURADA'),
    ('1495', 'NO_DEVENGA', 'REESTRUCTURADA'),
    ('1496', 'VENCIDA',    'REESTRUCTURADA')
) AS c(cuenta, estado, tipo);

INSERT INTO marcas.param_excepcion (cuenta_cuc, estado, tipo, segmento, marca_especial, signo, fecha_desde)
SELECT CONCAT(x.cuenta_cuc, s.sufijo), x.estado, x.tipo, s.segmento, 'COVID19', 1, @vigencia_desde
FROM marcas.param_excepcion AS x
CROSS JOIN (VALUES
    ('05', 'PRODUCTIVO'),
    ('20', 'CONSUMO'),
    ('30', 'INMOBILIARIO'),
    ('35', 'VIVIENDA_INTERES_SOCIAL'),
    ('40', 'MICROCREDITO'),
    ('45', 'INVERSION_PUBLICA'),
    ('50', 'EDUCATIVO')
) AS s(sufijo, segmento)
WHERE x.fecha_desde = @vigencia_desde AND x.marca_especial = 'COVID19' AND LEN(x.cuenta_cuc) = 4;

/* 1499: provisiones (signo -1). Las subcuentas por segmento o tipo se marcan con ese
   atributo; las demás (genérica, anticíclica, ...) heredan la de 4 dígitos. */
INSERT INTO marcas.param_excepcion (cuenta_cuc, estado, tipo, segmento, marca_especial, signo, fecha_desde)
VALUES
    ('1499',   NULL, NULL,             NULL,                             'PROVISION', -1, @vigencia_desde),
    ('149905', NULL, NULL,             'PRODUCTIVO',                     'PROVISION', -1, @vigencia_desde),
    ('149910', NULL, NULL,             'CONSUMO',                        'PROVISION', -1, @vigencia_desde),
    ('149915', NULL, NULL,             'INMOBILIARIO',                   'PROVISION', -1, @vigencia_desde),
    ('149920', NULL, NULL,             'MICROCREDITO',                   'PROVISION', -1, @vigencia_desde),
    ('149940', NULL, NULL,             'VIVIENDA_INTERES_SOCIAL', 'PROVISION', -1, @vigencia_desde),
    ('149945', NULL, 'REFINANCIADA',   NULL,                             'PROVISION', -1, @vigencia_desde),
    ('149950', NULL, 'REESTRUCTURADA', NULL,                             'PROVISION', -1, @vigencia_desde),
    ('149955', NULL, NULL,             'EDUCATIVO',                      'PROVISION', -1, @vigencia_desde),
    ('149960', NULL, NULL,             'INVERSION_PUBLICA',              'PROVISION', -1, @vigencia_desde);

/* ---------- Bandas ----------
   Solo la cartera por vencer tiene subcuentas de plazo al vencimiento (05-25). En esta
   versión del CUC las cuentas que no devengan intereses y las vencidas no tienen
   subcuentas de días. */
DELETE FROM marcas.param_banda WHERE fecha_desde = @vigencia_desde;
INSERT INTO marcas.param_banda (estado, segmento, sufijo, dias_desde, dias_hasta, fecha_desde)
VALUES
    ('POR_VENCER', NULL, '05',   1,   30, @vigencia_desde),
    ('POR_VENCER', NULL, '10',  31,   90, @vigencia_desde),
    ('POR_VENCER', NULL, '15',  91,  180, @vigencia_desde),
    ('POR_VENCER', NULL, '20', 181,  360, @vigencia_desde),
    ('POR_VENCER', NULL, '25', 361, NULL, @vigencia_desde);

COMMIT TRANSACTION;
GO
