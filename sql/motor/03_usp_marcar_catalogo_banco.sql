/* Recalcula marcas.catalogo_banco_marcado para una fecha de corte.
   Cada cuenta del banco (4 o más dígitos, dentro de una raíz vigente) toma la marca de la
   cuenta CUC con el prefijo más largo: primero 6 dígitos, luego 4.
   Las cuentas sin match no se insertan: las detecta la validación de cobertura.
   Requiere haber ejecutado marcas.usp_marcar_cuc para la misma fecha. */
CREATE OR ALTER PROCEDURE marcas.usp_marcar_catalogo_banco
    @fecha_corte date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DELETE FROM marcas.catalogo_banco_marcado WHERE fecha_corte = @fecha_corte;

    INSERT INTO marcas.catalogo_banco_marcado
        (fecha_corte, cuenta_banco, cuenta_cuc_match, nivel_match, estado, tipo, segmento,
         dias_desde, dias_hasta, es_improductiva, marca_especial, signo, origen_marca)
    SELECT @fecha_corte, cb.cuenta_banco, m.cuenta_cuc, m.nivel, m.estado, m.tipo, m.segmento,
           m.dias_desde, m.dias_hasta, m.es_improductiva, m.marca_especial, m.signo, m.origen_marca
    FROM marcas.catalogo_banco AS cb
    CROSS APPLY (
        SELECT TOP (1) cm.*
        FROM marcas.cuc_marcado AS cm
        WHERE cm.fecha_corte = @fecha_corte
          AND cm.cuenta_cuc IN (LEFT(cb.cuenta_banco, 6), LEFT(cb.cuenta_banco, 4))
          AND LEN(cm.cuenta_cuc) <= LEN(cb.cuenta_banco)
        ORDER BY cm.nivel DESC
    ) AS m
    WHERE LEN(cb.cuenta_banco) >= 4
      AND cb.fecha_desde <= @fecha_corte
      AND (cb.fecha_hasta IS NULL OR cb.fecha_hasta >= @fecha_corte)
      AND EXISTS (SELECT 1 FROM marcas.param_regla_posicional AS r
                  WHERE cb.cuenta_banco LIKE r.cuenta_raiz + '%'
                    AND r.fecha_desde <= @fecha_corte
                    AND (r.fecha_hasta IS NULL OR r.fecha_hasta >= @fecha_corte));

    COMMIT TRANSACTION;
END;
GO
