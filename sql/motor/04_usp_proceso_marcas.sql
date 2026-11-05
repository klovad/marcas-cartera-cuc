/* Orquestador: valida parámetros, marca el CUC, marca el catálogo del banco y valida el
   resultado. Falla (THROW) si hay parámetros inválidos o cobertura incompleta; las
   alertas quedan registradas en marcas.control_alertas.

   Uso: EXEC marcas.usp_proceso_marcas @fecha_corte = '2026-10-31'; */
CREATE OR ALTER PROCEDURE marcas.usp_proceso_marcas
    @fecha_corte date
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC marcas.usp_validar_parametros    @fecha_corte = @fecha_corte;
    EXEC marcas.usp_marcar_cuc            @fecha_corte = @fecha_corte;
    EXEC marcas.usp_marcar_catalogo_banco @fecha_corte = @fecha_corte;
    EXEC marcas.usp_validar_resultados    @fecha_corte = @fecha_corte;
END;
GO
