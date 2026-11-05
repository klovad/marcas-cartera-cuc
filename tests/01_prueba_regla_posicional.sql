/* Prueba unitaria de marcas.fn_marcar_cuenta con los parámetros cargados.
   No escribe datos. Falla con THROW si algún caso no coincide.
   Los esperados salen del CUC oficial (Resolución SB-2021-0403). */
SET NOCOUNT ON;

DECLARE @fecha_corte date = CAST(GETDATE() AS date);

DECLARE @casos TABLE (
    cuenta_cuc   varchar(6) PRIMARY KEY,
    estado       varchar(20), tipo varchar(20), segmento varchar(30),
    dias_desde   int, dias_hasta int,
    marca_especial varchar(30), signo smallint, origen varchar(10)
);

INSERT INTO @casos VALUES
    -- Regla posicional
    ('1401',   'POR_VENCER', 'ORIGINAL',       'PRODUCTIVO',                     NULL, NULL, NULL, 1, 'REGLA'),
    ('1404',   'POR_VENCER', 'ORIGINAL',       'MICROCREDITO',                   NULL, NULL, NULL, 1, 'REGLA'),
    ('1408',   'POR_VENCER', 'ORIGINAL',       'VIVIENDA_INTERES_SOCIAL', NULL, NULL, NULL, 1, 'REGLA'),
    ('1410',   'POR_VENCER', 'REFINANCIADA',   'CONSUMO',                        NULL, NULL, NULL, 1, 'REGLA'),
    ('1427',   'NO_DEVENGA', 'ORIGINAL',       'INMOBILIARIO',                   NULL, NULL, NULL, 1, 'REGLA'),
    ('1452',   'VENCIDA',    'ORIGINAL',       'MICROCREDITO',                   NULL, NULL, NULL, 1, 'REGLA'),
    ('1472',   'VENCIDA',    'REESTRUCTURADA', 'VIVIENDA_INTERES_SOCIAL', NULL, NULL, NULL, 1, 'REGLA'),
    -- Bandas de por vencer
    ('140205', 'POR_VENCER', 'ORIGINAL',       'CONSUMO',                        1,    30,   NULL, 1, 'REGLA'),
    ('141725', 'POR_VENCER', 'REESTRUCTURADA', 'PRODUCTIVO',                     361,  NULL, NULL, 1, 'REGLA'),
    -- Posición sin segmento en el CUC
    ('1405',   NULL,         NULL,             NULL,                             NULL, NULL, NULL, 1, NULL),
    -- Educativo e inversión pública (excepción de 4 dígitos; la subcuenta toma la banda)
    ('1473',   'POR_VENCER', 'ORIGINAL',       'EDUCATIVO',                      NULL, NULL, NULL, 1, 'EXCEPCION'),
    ('147615', 'POR_VENCER', 'REFINANCIADA',   'INVERSION_PUBLICA',              91,   180,  NULL, 1, 'EXCEPCION'),
    ('1485',   'VENCIDA',    'ORIGINAL',       'EDUCATIVO',                      NULL, NULL, NULL, 1, 'EXCEPCION'),
    ('1490',   'VENCIDA',    'REESTRUCTURADA', 'INVERSION_PUBLICA',              NULL, NULL, NULL, 1, 'EXCEPCION'),
    -- COVID-19: la subcuenta es un segmento, no una banda
    ('1492',   'NO_DEVENGA', 'REFINANCIADA',   NULL,                             NULL, NULL, 'COVID19', 1, 'EXCEPCION'),
    ('149440', 'POR_VENCER', 'REESTRUCTURADA', 'MICROCREDITO',                   NULL, NULL, 'COVID19', 1, 'EXCEPCION'),
    -- Provisiones
    ('1499',   NULL,         NULL,             NULL,                             NULL, NULL, 'PROVISION', -1, 'EXCEPCION'),
    ('149905', NULL,         NULL,             'PRODUCTIVO',                     NULL, NULL, 'PROVISION', -1, 'EXCEPCION'),
    ('149945', NULL,         'REFINANCIADA',   NULL,                             NULL, NULL, 'PROVISION', -1, 'EXCEPCION'),
    ('149985', NULL,         NULL,             NULL,                             NULL, NULL, 'PROVISION', -1, 'EXCEPCION'),
    -- Fuera de todo
    ('1497',   NULL,         NULL,             NULL,                             NULL, NULL, NULL, 1, NULL);

DECLARE @fallas TABLE (cuenta_cuc varchar(6), detalle nvarchar(400));

INSERT INTO @fallas
SELECT c.cuenta_cuc,
       CONCAT(N'esperado ', CONCAT_WS('/', c.estado, c.tipo, c.segmento, c.dias_desde, c.dias_hasta, c.marca_especial, c.signo, c.origen),
              N' | obtenido ', CONCAT_WS('/', f.estado, f.tipo, f.segmento, f.dias_desde, f.dias_hasta, f.marca_especial, f.signo, f.origen_marca))
FROM @casos AS c
CROSS APPLY marcas.fn_marcar_cuenta(c.cuenta_cuc, @fecha_corte) AS f
WHERE EXISTS (
    SELECT c.estado, c.tipo, c.segmento, c.dias_desde, c.dias_hasta, c.marca_especial, c.signo, c.origen
    EXCEPT
    SELECT f.estado, f.tipo, f.segmento, f.dias_desde, f.dias_hasta, f.marca_especial, f.signo, f.origen_marca
);

/* Bloque 1401-1472: 9 combinaciones de estado y tipo × 5 segmentos con ordinal = 45
   cuentas marcadas por regla, todas con combinación distinta (las otras 27 son huecos) */
WITH bloque AS (
    SELECT CONCAT('14', RIGHT(CONCAT('0', n), 2)) AS cuenta_cuc
    FROM (SELECT TOP (72) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) AS t
),
marcado AS (
    SELECT f.* FROM bloque AS b CROSS APPLY marcas.fn_marcar_cuenta(b.cuenta_cuc, @fecha_corte) AS f
)
INSERT INTO @fallas
SELECT NULL, CONCAT(N'Bloque 1401-1472: ', COUNT(DISTINCT CASE WHEN origen_marca = 'REGLA' THEN CONCAT(estado, '|', tipo, '|', segmento) END),
                    N' combinaciones distintas, ', SUM(CASE WHEN origen_marca = 'REGLA' THEN 1 ELSE 0 END),
                    N' marcadas por regla (se esperan 45 y 45)')
FROM marcado
HAVING COUNT(DISTINCT CASE WHEN origen_marca = 'REGLA' THEN CONCAT(estado, '|', tipo, '|', segmento) END) <> 45
    OR SUM(CASE WHEN origen_marca = 'REGLA' THEN 1 ELSE 0 END) <> 45;

IF EXISTS (SELECT 1 FROM @fallas)
BEGIN
    SELECT * FROM @fallas;
    THROW 50100, N'Prueba de regla posicional: hay casos que no coinciden.', 1;
END;

PRINT N'OK prueba de regla posicional';
