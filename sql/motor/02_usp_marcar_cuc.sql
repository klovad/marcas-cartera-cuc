/* Recalcula marcas.cuc_marcado para una fecha de corte: una fila por cuenta CUC vigente
   de 4 y 6 dígitos cuya raíz está en una regla posicional vigente. */
CREATE OR ALTER PROCEDURE marcas.usp_marcar_cuc
    @fecha_corte date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRANSACTION;

    DELETE FROM marcas.cuc_marcado WHERE fecha_corte = @fecha_corte;

    INSERT INTO marcas.cuc_marcado
        (fecha_corte, cuenta_cuc, nivel, estado, tipo, segmento, dias_desde, dias_hasta,
         es_improductiva, marca_especial, signo, origen_marca)
    SELECT @fecha_corte, f.cuenta_cuc, f.nivel, f.estado, f.tipo, f.segmento, f.dias_desde, f.dias_hasta,
           f.es_improductiva, f.marca_especial, f.signo, f.origen_marca
    FROM marcas.cuc_oficial AS c
    CROSS APPLY marcas.fn_marcar_cuenta(c.cuenta_cuc, @fecha_corte) AS f
    WHERE LEN(c.cuenta_cuc) IN (4, 6)
      AND c.fecha_desde <= @fecha_corte
      AND (c.fecha_hasta IS NULL OR c.fecha_hasta >= @fecha_corte)
      AND EXISTS (SELECT 1 FROM marcas.param_regla_posicional AS r
                  WHERE c.cuenta_cuc LIKE r.cuenta_raiz + '%'
                    AND r.fecha_desde <= @fecha_corte
                    AND (r.fecha_hasta IS NULL OR r.fecha_hasta >= @fecha_corte));

    COMMIT TRANSACTION;
END;
GO
