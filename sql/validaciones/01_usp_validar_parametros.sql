/* Valida los parámetros vigentes a la fecha de corte ANTES de marcar.
   Registra alertas en marcas.control_alertas y lanza error si hay alguna BLOQUEANTE.

   Reglas:
   - UNICIDAD_*:            más de una fila vigente para la misma clave (BLOQUEANTE)
   - ORDINAL_FALTANTE:      falta un ordinal que la regla posicional necesita (BLOQUEANTE)
   - CODIGO_INVALIDO:       excepción o banda que apunta a un código inexistente (BLOQUEANTE)
   - BANDA_TRASLAPE:        bandas de días que se pisan dentro de estado+segmento (BLOQUEANTE)
   - BANDA_HUECO:           días sin banda entre dos bandas consecutivas (AVISO) */
CREATE OR ALTER PROCEDURE marcas.usp_validar_parametros
    @fecha_corte date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DELETE FROM marcas.control_alertas
    WHERE fecha_corte = @fecha_corte AND regla_fallida IN
        ('UNICIDAD_REGLA', 'UNICIDAD_ESTADO', 'UNICIDAD_TIPO', 'UNICIDAD_SEGMENTO',
         'UNICIDAD_EXCEPCION', 'UNICIDAD_BANDA', 'ORDINAL_FALTANTE', 'CODIGO_INVALIDO',
         'BANDA_TRASLAPE', 'BANDA_HUECO');

    /* Parámetros vigentes */
    WITH regla AS (
        SELECT * FROM marcas.param_regla_posicional
        WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
    )
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, cuenta_raiz, 'UNICIDAD_REGLA', 'BLOQUEANTE',
           CONCAT(N'Reglas posicionales vigentes: ', COUNT(*))
    FROM regla GROUP BY cuenta_raiz HAVING COUNT(*) > 1;

    /* Unicidad por código y por ordinal en estado / tipo / segmento */
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, NULL, u.regla, 'BLOQUEANTE', u.detalle
    FROM (
        SELECT 'UNICIDAD_ESTADO' AS regla, CONCAT(N'Código ', codigo, N' vigente ', COUNT(*), N' veces') AS detalle
        FROM marcas.param_estado
        WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        GROUP BY codigo HAVING COUNT(*) > 1
        UNION ALL
        SELECT 'UNICIDAD_ESTADO', CONCAT(N'Ordinal ', ordinal, N' asignado a ', COUNT(*), N' estados')
        FROM marcas.param_estado
        WHERE ordinal IS NOT NULL AND fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        GROUP BY ordinal HAVING COUNT(*) > 1
        UNION ALL
        SELECT 'UNICIDAD_TIPO', CONCAT(N'Código ', codigo, N' vigente ', COUNT(*), N' veces')
        FROM marcas.param_tipo
        WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        GROUP BY codigo HAVING COUNT(*) > 1
        UNION ALL
        SELECT 'UNICIDAD_TIPO', CONCAT(N'Ordinal ', ordinal, N' asignado a ', COUNT(*), N' tipos')
        FROM marcas.param_tipo
        WHERE ordinal IS NOT NULL AND fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        GROUP BY ordinal HAVING COUNT(*) > 1
        UNION ALL
        SELECT 'UNICIDAD_SEGMENTO', CONCAT(N'Código ', codigo, N' vigente ', COUNT(*), N' veces')
        FROM marcas.param_segmento
        WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        GROUP BY codigo HAVING COUNT(*) > 1
        UNION ALL
        SELECT 'UNICIDAD_SEGMENTO', CONCAT(N'Ordinal ', ordinal, N' asignado a ', COUNT(*), N' segmentos')
        FROM marcas.param_segmento
        WHERE ordinal IS NOT NULL AND fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        GROUP BY ordinal HAVING COUNT(*) > 1
    ) AS u;

    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, cuenta_cuc, 'UNICIDAD_EXCEPCION', 'BLOQUEANTE',
           CONCAT(N'Excepciones vigentes: ', COUNT(*))
    FROM marcas.param_excepcion
    WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
    GROUP BY cuenta_cuc HAVING COUNT(*) > 1;

    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, NULL, 'UNICIDAD_BANDA', 'BLOQUEANTE',
           CONCAT(N'Banda ', estado, N'/', COALESCE(segmento, N'(genérica)'), N'/', sufijo, N' vigente ', COUNT(*), N' veces')
    FROM marcas.param_banda
    WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
    GROUP BY estado, segmento, sufijo HAVING COUNT(*) > 1;

    /* Ordinales que la regla necesita: estados = ceil(rango / bloque_estado),
       tipos = bloque_estado / bloque_tipo, segmentos = bloque_tipo */
    WITH regla AS (
        SELECT cuenta_raiz, rango_desde, rango_hasta, bloque_estado, bloque_tipo
        FROM marcas.param_regla_posicional
        WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
    ),
    numeros AS (
        SELECT TOP (1000) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS smallint) AS k
        FROM sys.all_objects
    ),
    requeridos AS (
        SELECT r.cuenta_raiz, 'ESTADO' AS dimension, n.k
        FROM regla AS r JOIN numeros AS n
          ON n.k < ((r.rango_hasta - r.rango_desde) / r.bloque_estado) + 1
        UNION ALL
        SELECT r.cuenta_raiz, 'TIPO', n.k
        FROM regla AS r JOIN numeros AS n ON n.k < r.bloque_estado / r.bloque_tipo
        UNION ALL
        SELECT r.cuenta_raiz, 'SEGMENTO', n.k
        FROM regla AS r JOIN numeros AS n ON n.k < r.bloque_tipo
    )
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, q.cuenta_raiz, 'ORDINAL_FALTANTE', 'BLOQUEANTE',
           CONCAT(N'Falta ', q.dimension, N' con ordinal ', q.k)
    FROM requeridos AS q
    WHERE NOT EXISTS (
        SELECT 1 FROM marcas.param_estado AS e
        WHERE q.dimension = 'ESTADO' AND e.ordinal = q.k
          AND e.fecha_desde <= @fecha_corte AND (e.fecha_hasta IS NULL OR e.fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT 1 FROM marcas.param_tipo AS t
        WHERE q.dimension = 'TIPO' AND t.ordinal = q.k
          AND t.fecha_desde <= @fecha_corte AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT 1 FROM marcas.param_segmento AS s
        WHERE q.dimension = 'SEGMENTO' AND s.ordinal = q.k
          AND s.fecha_desde <= @fecha_corte AND (s.fecha_hasta IS NULL OR s.fecha_hasta >= @fecha_corte)
    );

    /* Excepciones y bandas que apuntan a códigos inexistentes */
    WITH referencias AS (
        SELECT CAST(cuenta_cuc AS varchar(30)) AS cuenta, 'ESTADO' AS dimension, estado AS codigo
        FROM marcas.param_excepcion
        WHERE estado IS NOT NULL AND fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT cuenta_cuc, 'TIPO', tipo
        FROM marcas.param_excepcion
        WHERE tipo IS NOT NULL AND fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT cuenta_cuc, 'SEGMENTO', segmento
        FROM marcas.param_excepcion
        WHERE segmento IS NOT NULL AND fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT CONCAT('banda ', sufijo), 'ESTADO', estado
        FROM marcas.param_banda
        WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT CONCAT('banda ', sufijo), 'SEGMENTO', segmento
        FROM marcas.param_banda
        WHERE segmento IS NOT NULL AND fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
    )
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, r.cuenta, 'CODIGO_INVALIDO', 'BLOQUEANTE',
           CONCAT(r.dimension, N' ', r.codigo, N' no existe o no está vigente')
    FROM referencias AS r
    WHERE NOT EXISTS (
        SELECT 1 FROM marcas.param_estado AS e
        WHERE r.dimension = 'ESTADO' AND e.codigo = r.codigo
          AND e.fecha_desde <= @fecha_corte AND (e.fecha_hasta IS NULL OR e.fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT 1 FROM marcas.param_tipo AS t
        WHERE r.dimension = 'TIPO' AND t.codigo = r.codigo
          AND t.fecha_desde <= @fecha_corte AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= @fecha_corte)
        UNION ALL
        SELECT 1 FROM marcas.param_segmento AS s
        WHERE r.dimension = 'SEGMENTO' AND s.codigo = r.codigo
          AND s.fecha_desde <= @fecha_corte AND (s.fecha_hasta IS NULL OR s.fecha_hasta >= @fecha_corte)
    );

    /* Traslapes y huecos de bandas dentro de cada estado + segmento */
    WITH bandas AS (
        SELECT estado, segmento, sufijo, dias_desde, dias_hasta,
               LAG(dias_hasta) OVER (PARTITION BY estado, segmento ORDER BY dias_desde, sufijo) AS hasta_anterior,
               LAG(sufijo)     OVER (PARTITION BY estado, segmento ORDER BY dias_desde, sufijo) AS sufijo_anterior,
               ROW_NUMBER()    OVER (PARTITION BY estado, segmento ORDER BY dias_desde, sufijo) AS orden
        FROM marcas.param_banda
        WHERE fecha_desde <= @fecha_corte AND (fecha_hasta IS NULL OR fecha_hasta >= @fecha_corte)
    )
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, NULL,
           CASE WHEN hasta_anterior IS NULL OR dias_desde <= hasta_anterior THEN 'BANDA_TRASLAPE' ELSE 'BANDA_HUECO' END,
           CASE WHEN hasta_anterior IS NULL OR dias_desde <= hasta_anterior THEN 'BLOQUEANTE' ELSE 'AVISO' END,
           CONCAT(estado, N'/', COALESCE(segmento, N'(genérica)'), N': sufijo ', sufijo_anterior,
                  N' termina en ', COALESCE(CAST(hasta_anterior AS nvarchar(10)), N'(sin tope)'),
                  N' y sufijo ', sufijo, N' empieza en ', dias_desde)
    FROM bandas
    WHERE orden > 1
      AND (hasta_anterior IS NULL OR dias_desde <> hasta_anterior + 1);

    IF EXISTS (SELECT 1 FROM marcas.control_alertas
               WHERE fecha_corte = @fecha_corte AND severidad = 'BLOQUEANTE'
                 AND regla_fallida IN ('UNICIDAD_REGLA', 'UNICIDAD_ESTADO', 'UNICIDAD_TIPO', 'UNICIDAD_SEGMENTO',
                                       'UNICIDAD_EXCEPCION', 'UNICIDAD_BANDA', 'ORDINAL_FALTANTE',
                                       'CODIGO_INVALIDO', 'BANDA_TRASLAPE'))
        THROW 50001, N'Parámetros inválidos: revisar marcas.control_alertas (severidad BLOQUEANTE).', 1;
END;
GO
