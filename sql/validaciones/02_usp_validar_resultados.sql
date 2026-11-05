/* Valida el resultado de una fecha de corte DESPUÉS de marcar.
   Registra alertas en marcas.control_alertas y lanza error si hay alguna BLOQUEANTE.

   Reglas:
   - COBERTURA:             cuenta del banco sin marca (BLOQUEANTE)
   - CUENTA_CUC_SIN_MARCA:  cuenta del CUC sin regla ni excepción, p. ej. una cuenta nueva (AVISO)
   - BANDA_FALTANTE:        subcuenta de 6 dígitos con estado pero sin banda de días (AVISO)
   - CONSISTENCIA_NOMBRE:   el nombre oficial de una cuenta de 4 dígitos no contiene la
                            palabra clave del estado asignado (AVISO) */
CREATE OR ALTER PROCEDURE marcas.usp_validar_resultados
    @fecha_corte date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DELETE FROM marcas.control_alertas
    WHERE fecha_corte = @fecha_corte
      AND regla_fallida IN ('COBERTURA', 'CUENTA_CUC_SIN_MARCA', 'BANDA_FALTANTE', 'CONSISTENCIA_NOMBRE');

    /* Cobertura: toda cuenta del banco dentro de la raíz debe tener marca */
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, cb.cuenta_banco, 'COBERTURA', 'BLOQUEANTE',
           CASE WHEN m.cuenta_banco IS NULL THEN N'Sin cuenta CUC de 4 o 6 dígitos que coincida'
                ELSE CONCAT(N'La cuenta CUC ', m.cuenta_cuc_match, N' no tiene marca') END
    FROM marcas.catalogo_banco AS cb
    LEFT JOIN marcas.catalogo_banco_marcado AS m
      ON m.fecha_corte = @fecha_corte AND m.cuenta_banco = cb.cuenta_banco
    WHERE LEN(cb.cuenta_banco) >= 4
      AND cb.fecha_desde <= @fecha_corte
      AND (cb.fecha_hasta IS NULL OR cb.fecha_hasta >= @fecha_corte)
      AND EXISTS (SELECT 1 FROM marcas.param_regla_posicional AS r
                  WHERE cb.cuenta_banco LIKE r.cuenta_raiz + '%'
                    AND r.fecha_desde <= @fecha_corte
                    AND (r.fecha_hasta IS NULL OR r.fecha_hasta >= @fecha_corte))
      AND (m.cuenta_banco IS NULL OR m.origen_marca IS NULL);

    /* Cuentas del CUC sin marca (fuera del patrón y sin excepción) */
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, cm.cuenta_cuc, 'CUENTA_CUC_SIN_MARCA', 'AVISO',
           CONCAT(N'Cuenta fuera de la regla posicional y sin excepción: ', c.nombre)
    FROM marcas.cuc_marcado AS cm
    JOIN marcas.cuc_oficial AS c
      ON c.cuenta_cuc = cm.cuenta_cuc
     AND c.fecha_desde <= @fecha_corte AND (c.fecha_hasta IS NULL OR c.fecha_hasta >= @fecha_corte)
    WHERE cm.fecha_corte = @fecha_corte AND cm.origen_marca IS NULL;

    /* Subcuentas con estado pero sin banda */
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, cm.cuenta_cuc, 'BANDA_FALTANTE', 'AVISO',
           CONCAT(N'Sin banda para ', cm.estado, N'/', cm.segmento, N'/sufijo ', RIGHT(cm.cuenta_cuc, 2))
    FROM marcas.cuc_marcado AS cm
    WHERE cm.fecha_corte = @fecha_corte
      AND cm.nivel = 6
      AND cm.estado IS NOT NULL
      AND cm.marca_especial IS NULL
      AND cm.dias_desde IS NULL;

    /* Consistencia con el nombre oficial (sin distinguir mayúsculas ni tildes) */
    INSERT INTO marcas.control_alertas (fecha_corte, cuenta, regla_fallida, severidad, detalle)
    SELECT @fecha_corte, cm.cuenta_cuc, 'CONSISTENCIA_NOMBRE', 'AVISO',
           CONCAT(N'Estado ', cm.estado, N' (', e.palabra_clave, N') no aparece en: ', c.nombre)
    FROM marcas.cuc_marcado AS cm
    JOIN marcas.cuc_oficial AS c
      ON c.cuenta_cuc = cm.cuenta_cuc
     AND c.fecha_desde <= @fecha_corte AND (c.fecha_hasta IS NULL OR c.fecha_hasta >= @fecha_corte)
    JOIN marcas.param_estado AS e
      ON e.codigo = cm.estado
     AND e.fecha_desde <= @fecha_corte AND (e.fecha_hasta IS NULL OR e.fecha_hasta >= @fecha_corte)
    WHERE cm.fecha_corte = @fecha_corte
      AND cm.nivel = 4
      AND e.palabra_clave IS NOT NULL
      AND c.nombre COLLATE Latin1_General_CI_AI NOT LIKE N'%' + e.palabra_clave + N'%' COLLATE Latin1_General_CI_AI;

    IF EXISTS (SELECT 1 FROM marcas.control_alertas
               WHERE fecha_corte = @fecha_corte AND regla_fallida = 'COBERTURA')
        THROW 50002, N'Cobertura incompleta: hay cuentas 14 del banco sin marca (ver marcas.control_alertas).', 1;
END;
GO
