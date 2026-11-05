/* Prueba unitaria de marcas.fn_marcar_cuenta con los parámetros cargados.
   No escribe datos. Falla con THROW si algún caso no coincide.
   Los esperados reflejan docs/marcas_cartera_cuc.md (sin verificar contra el CUC). */
SET NOCOUNT ON;

DECLARE @fecha_corte date = CAST(GETDATE() AS date);

DECLARE @casos TABLE (
    cuenta_cuc   varchar(6) PRIMARY KEY,
    estado       varchar(20), tipo varchar(20), segmento varchar(30),
    dias_desde   int, dias_hasta int,
    marca_especial varchar(30), signo smallint, origen varchar(10)
);

INSERT INTO @casos VALUES
    ('1401',   'POR_VENCER', 'ORIGINAL',       'COMERCIAL_PRIORITARIO',    NULL, NULL, NULL, 1, 'REGLA'),
    ('1408',   'POR_VENCER', 'ORIGINAL',       'VIVIENDA_INTERES_PUBLICO', NULL, NULL, NULL, 1, 'REGLA'),
    ('1409',   'POR_VENCER', 'REFINANCIADA',   'COMERCIAL_PRIORITARIO',    NULL, NULL, NULL, 1, 'REGLA'),
    ('1424',   'POR_VENCER', 'REESTRUCTURADA', 'VIVIENDA_INTERES_PUBLICO', NULL, NULL, NULL, 1, 'REGLA'),
    ('1425',   'NO_DEVENGA', 'ORIGINAL',       'COMERCIAL_PRIORITARIO',    NULL, NULL, NULL, 1, 'REGLA'),
    ('1452',   'VENCIDA',    'ORIGINAL',       'MICROCREDITO',             NULL, NULL, NULL, 1, 'REGLA'),
    ('1472',   'VENCIDA',    'REESTRUCTURADA', 'VIVIENDA_INTERES_PUBLICO', NULL, NULL, NULL, 1, 'REGLA'),
    ('140205', 'POR_VENCER', 'ORIGINAL',       'CONSUMO_PRIORITARIO',      1,    30,   NULL, 1, 'REGLA'),
    ('142625', 'NO_DEVENGA', 'ORIGINAL',       'CONSUMO_PRIORITARIO',      361,  NULL, NULL, 1, 'REGLA'),
    ('1499',   NULL,         NULL,             NULL,                       NULL, NULL, 'PROVISION', -1, 'EXCEPCION'),
    ('149905', NULL,         NULL,             NULL,                       NULL, NULL, 'PROVISION', -1, 'EXCEPCION'),
    ('1473',   NULL,         NULL,             NULL,                       NULL, NULL, NULL, 1, NULL);

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

/* Las 72 cuentas del bloque deben dar 72 combinaciones distintas y completas */
WITH bloque AS (
    SELECT CONCAT('14', RIGHT(CONCAT('0', n), 2)) AS cuenta_cuc
    FROM (SELECT TOP (72) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects) AS t
),
marcado AS (
    SELECT f.* FROM bloque AS b CROSS APPLY marcas.fn_marcar_cuenta(b.cuenta_cuc, @fecha_corte) AS f
)
INSERT INTO @fallas
SELECT NULL, CONCAT(N'Bloque 1401-1472: ', COUNT(DISTINCT CONCAT(estado, '|', tipo, '|', segmento)),
                    N' combinaciones distintas, ', SUM(CASE WHEN origen_marca = 'REGLA' THEN 1 ELSE 0 END),
                    N' marcadas por regla (se esperan 72 y 72)')
FROM marcado
HAVING COUNT(DISTINCT CONCAT(estado, '|', tipo, '|', segmento)) <> 72
    OR SUM(CASE WHEN origen_marca = 'REGLA' THEN 1 ELSE 0 END) <> 72;

IF EXISTS (SELECT 1 FROM @fallas)
BEGIN
    SELECT * FROM @fallas;
    THROW 50100, N'Prueba de regla posicional: hay casos que no coinciden.', 1;
END;

PRINT N'OK prueba de regla posicional';
