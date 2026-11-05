/* Marca una cuenta CUC (4 o 6 dígitos) a una fecha de corte usando solo parámetros vigentes.

   Orden de decisión:
   1. Excepción vigente (la de 6 dígitos gana a la de 4). Si existe, sus valores mandan.
   2. Regla posicional: si NN cae en el rango, n = NN - rango_desde y
        estado   = n / bloque_estado
        tipo     = (n % bloque_estado) / bloque_tipo
        segmento = n % bloque_tipo
   3. Banda (solo 6 dígitos): sufijo 14NNSS buscado por (estado, segmento, sufijo);
      si no hay, la genérica del estado (segmento NULL).

   La unicidad de filas vigentes la garantiza marcas.usp_validar_parametros; los TOP 1
   solo hacen el resultado determinista. */
CREATE OR ALTER FUNCTION marcas.fn_marcar_cuenta (@cuenta_cuc varchar(6), @fecha_corte date)
RETURNS TABLE
AS
RETURN
SELECT
    @cuenta_cuc                                                   AS cuenta_cuc,
    CAST(LEN(@cuenta_cuc) AS tinyint)                             AS nivel,
    m.estado,
    m.tipo,
    m.segmento,
    b.dias_desde,
    b.dias_hasta,
    pe.es_improductiva,
    x.marca_especial,
    CAST(COALESCE(x.signo, 1) AS smallint)                        AS signo,
    CASE WHEN x.cuenta_cuc IS NOT NULL THEN 'EXCEPCION'
         WHEN m.estado IS NOT NULL AND m.tipo IS NOT NULL AND m.segmento IS NOT NULL THEN 'REGLA'
    END                                                           AS origen_marca
FROM (SELECT 1 AS uno) AS d
/* Regla posicional vigente cuya raíz coincide con la cuenta */
OUTER APPLY (
    SELECT TOP (1) r.*
    FROM marcas.param_regla_posicional AS r
    WHERE @cuenta_cuc LIKE r.cuenta_raiz + '%'
      AND r.fecha_desde <= @fecha_corte
      AND (r.fecha_hasta IS NULL OR r.fecha_hasta >= @fecha_corte)
    ORDER BY LEN(r.cuenta_raiz) DESC, r.fecha_desde DESC
) AS r
/* Posición NN dentro del bloque (NULL si no es numérica o está fuera de rango) */
OUTER APPLY (
    SELECT n = CASE WHEN v.nn BETWEEN r.rango_desde AND r.rango_hasta THEN v.nn - r.rango_desde END
    FROM (SELECT nn = TRY_CAST(SUBSTRING(@cuenta_cuc, r.pos_inicio, r.longitud) AS int)) AS v
) AS p
/* Excepción vigente: gana la de prefijo más largo */
OUTER APPLY (
    SELECT TOP (1) x.*
    FROM marcas.param_excepcion AS x
    WHERE x.cuenta_cuc IN (@cuenta_cuc, LEFT(@cuenta_cuc, 4))
      AND x.fecha_desde <= @fecha_corte
      AND (x.fecha_hasta IS NULL OR x.fecha_hasta >= @fecha_corte)
    ORDER BY LEN(x.cuenta_cuc) DESC, x.fecha_desde DESC
) AS x
/* Códigos por regla posicional */
OUTER APPLY (
    SELECT TOP (1) e.codigo FROM marcas.param_estado AS e
    WHERE e.ordinal = p.n / r.bloque_estado
      AND e.fecha_desde <= @fecha_corte AND (e.fecha_hasta IS NULL OR e.fecha_hasta >= @fecha_corte)
    ORDER BY e.fecha_desde DESC
) AS re
OUTER APPLY (
    SELECT TOP (1) t.codigo FROM marcas.param_tipo AS t
    WHERE t.ordinal = (p.n % r.bloque_estado) / r.bloque_tipo
      AND t.fecha_desde <= @fecha_corte AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= @fecha_corte)
    ORDER BY t.fecha_desde DESC
) AS rt
OUTER APPLY (
    SELECT TOP (1) s.codigo FROM marcas.param_segmento AS s
    WHERE s.ordinal = p.n % r.bloque_tipo
      AND s.fecha_desde <= @fecha_corte AND (s.fecha_hasta IS NULL OR s.fecha_hasta >= @fecha_corte)
    ORDER BY s.fecha_desde DESC
) AS rs
/* Marca final: excepción > regla */
CROSS APPLY (
    SELECT
        estado   = CASE WHEN x.cuenta_cuc IS NOT NULL THEN x.estado   ELSE re.codigo END,
        tipo     = CASE WHEN x.cuenta_cuc IS NOT NULL THEN x.tipo     ELSE rt.codigo END,
        segmento = CASE WHEN x.cuenta_cuc IS NOT NULL THEN x.segmento ELSE rs.codigo END
) AS m
OUTER APPLY (
    SELECT TOP (1) e.es_improductiva FROM marcas.param_estado AS e
    WHERE e.codigo = m.estado
      AND e.fecha_desde <= @fecha_corte AND (e.fecha_hasta IS NULL OR e.fecha_hasta >= @fecha_corte)
    ORDER BY e.fecha_desde DESC
) AS pe
/* Banda: específica del segmento > genérica */
OUTER APPLY (
    SELECT TOP (1) b.dias_desde, b.dias_hasta
    FROM marcas.param_banda AS b
    WHERE LEN(@cuenta_cuc) = 6
      AND b.estado = m.estado
      AND b.sufijo = RIGHT(@cuenta_cuc, 2)
      AND (b.segmento = m.segmento OR b.segmento IS NULL)
      AND b.fecha_desde <= @fecha_corte AND (b.fecha_hasta IS NULL OR b.fecha_hasta >= @fecha_corte)
    ORDER BY CASE WHEN b.segmento IS NULL THEN 1 ELSE 0 END, b.fecha_desde DESC
) AS b;
GO
