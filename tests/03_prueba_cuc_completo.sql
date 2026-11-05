/* Recorre el CUC oficial cargado en marcas.cuc_oficial y compara la marca calculada
   (por código) contra el nombre oficial. Es la prueba que confirma que los parámetros
   (rangos, orden de segmentos, bandas y excepciones) coinciden con el CUC vigente.

   No escribe datos. Lista las discrepancias y falla con THROW si hay alguna.
   La comparación ignora mayúsculas y tildes. */
SET NOCOUNT ON;

DECLARE @fecha_corte date = CAST(GETDATE() AS date);   -- AJUSTAR al corte a validar

WITH cuc AS (
    SELECT c.cuenta_cuc, c.nombre COLLATE Latin1_General_CI_AI AS nombre
    FROM marcas.cuc_oficial AS c
    WHERE LEN(c.cuenta_cuc) IN (4, 6)
      AND c.fecha_desde <= @fecha_corte AND (c.fecha_hasta IS NULL OR c.fecha_hasta >= @fecha_corte)
      AND EXISTS (SELECT 1 FROM marcas.param_regla_posicional AS r
                  WHERE c.cuenta_cuc LIKE r.cuenta_raiz + '%'
                    AND r.fecha_desde <= @fecha_corte AND (r.fecha_hasta IS NULL OR r.fecha_hasta >= @fecha_corte))
),
vig_estado AS (
    SELECT * FROM marcas.param_estado
    WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
),
vig_tipo AS (
    SELECT * FROM marcas.param_tipo
    WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
),
vig_segmento AS (
    SELECT * FROM marcas.param_segmento
    WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
),
marcado AS (
    SELECT c.nombre, f.*
    FROM cuc AS c
    CROSS APPLY marcas.fn_marcar_cuenta(c.cuenta_cuc, @fecha_corte) AS f
),
discrepancias AS (
    /* Sin marca */
    SELECT cuenta_cuc, nombre, N'SIN_MARCA' AS prueba, N'Ni regla ni excepción' AS detalle
    FROM marcado WHERE origen_marca IS NULL

    UNION ALL
    /* Estado: el nombre de la cuenta de 4 dígitos contiene la palabra clave */
    SELECT m.cuenta_cuc, m.nombre, N'ESTADO', CONCAT(m.estado, N' (', e.palabra_clave, N')')
    FROM marcado AS m JOIN vig_estado AS e ON e.codigo = m.estado
    WHERE m.nivel = 4 AND e.palabra_clave IS NOT NULL
      AND m.nombre NOT LIKE N'%' + e.palabra_clave + N'%' COLLATE Latin1_General_CI_AI

    UNION ALL
    /* Tipo: contiene su palabra clave y no la de otro tipo (original no lleva ninguna) */
    SELECT m.cuenta_cuc, m.nombre, N'TIPO', CONCAT(m.tipo, N' vs palabra de ', o.codigo)
    FROM marcado AS m
    JOIN vig_tipo AS o ON o.palabra_clave IS NOT NULL
    WHERE m.nivel = 4 AND m.tipo IS NOT NULL
      AND (   (o.codigo =  m.tipo AND m.nombre NOT LIKE N'%' + o.palabra_clave + N'%' COLLATE Latin1_General_CI_AI)
           OR (o.codigo <> m.tipo AND m.nombre     LIKE N'%' + o.palabra_clave + N'%' COLLATE Latin1_General_CI_AI))

    UNION ALL
    /* Segmento: contiene su palabra clave */
    SELECT m.cuenta_cuc, m.nombre, N'SEGMENTO', CONCAT(m.segmento, N' (', s.palabra_clave, N')')
    FROM marcado AS m JOIN vig_segmento AS s ON s.codigo = m.segmento
    WHERE m.nivel = 4 AND s.palabra_clave IS NOT NULL
      AND m.nombre NOT LIKE N'%' + s.palabra_clave + N'%' COLLATE Latin1_General_CI_AI

    UNION ALL
    /* Banda: subcuenta con estado debe tener días, y el nombre debe citar el límite
       superior (o el inferior - 1 en la banda abierta: "más de 360 días") */
    SELECT m.cuenta_cuc, m.nombre, N'BANDA',
           CASE WHEN m.dias_desde IS NULL THEN N'Sin banda'
                ELSE CONCAT(m.dias_desde, N'-', COALESCE(CAST(m.dias_hasta AS nvarchar(10)), N'...')) END
    FROM marcado AS m
    WHERE m.nivel = 6 AND m.estado IS NOT NULL AND m.marca_especial IS NULL
      AND (   m.dias_desde IS NULL
           OR m.nombre NOT LIKE CONCAT(N'%', COALESCE(m.dias_hasta, m.dias_desde - 1), N'%'))
)
SELECT * INTO #discrepancias FROM discrepancias;

IF EXISTS (SELECT 1 FROM #discrepancias)
BEGIN
    SELECT prueba, cuenta_cuc, nombre, detalle FROM #discrepancias ORDER BY cuenta_cuc, prueba;
    DROP TABLE #discrepancias;
    THROW 50300, N'El CUC oficial no coincide con los parámetros: revisar discrepancias.', 1;
END;

DROP TABLE #discrepancias;
PRINT N'OK el CUC completo coincide con los parámetros';
