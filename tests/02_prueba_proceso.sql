/* Prueba de punta a punta de marcas.usp_proceso_marcas con datos sintéticos.
   EJECUTAR SOLO EN UNA BASE DE DESARROLLO: dentro de una transacción vacía cuc_oficial y
   catalogo_banco, carga datos de prueba y al final hace ROLLBACK (no deja rastro).
   Requiere los parámetros de sql/params cargados. */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @fecha_corte date = CAST(GETDATE() AS date);

/* ---------- Caso 1: proceso completo con cobertura total ---------- */
BEGIN TRANSACTION;

DELETE FROM marcas.catalogo_banco;
DELETE FROM marcas.cuc_oficial;

/* CUC sintético: bloque 1401-1472 con nombres armados desde los parámetros,
   algunas subcuentas y la 1499 */
INSERT INTO marcas.cuc_oficial (cuenta_cuc, nombre, fecha_desde)
SELECT f.cuenta_cuc,
       CONCAT(N'Cartera de créditos ', s.descripcion, N' ', t.descripcion, N' ', e.descripcion),
       '1900-01-01'
FROM (SELECT TOP (72) CONCAT('14', RIGHT(CONCAT('0', ROW_NUMBER() OVER (ORDER BY (SELECT NULL))), 2)) AS cuenta_cuc
      FROM sys.all_objects) AS b
CROSS APPLY marcas.fn_marcar_cuenta(b.cuenta_cuc, @fecha_corte) AS f
JOIN marcas.param_estado   AS e ON e.codigo = f.estado
JOIN marcas.param_tipo     AS t ON t.codigo = f.tipo
JOIN marcas.param_segmento AS s ON s.codigo = f.segmento;

INSERT INTO marcas.cuc_oficial (cuenta_cuc, nombre, fecha_desde) VALUES
    ('140205', N'De 1 a 30 días',               '1900-01-01'),
    ('145205', N'De 1 a 30 días',               '1900-01-01'),
    ('1499',   N'(Provisiones para créditos incobrables)', '1900-01-01');

INSERT INTO marcas.catalogo_banco (cuenta_banco, nombre, fecha_desde) VALUES
    ('1402051001', N'Consumo prioritario por vencer 1-30 días, agencia 1', '1900-01-01'),
    ('1452059001', N'Microcrédito vencido, producto X',                   '1900-01-01'),
    ('14010101',   N'Comercial prioritario por vencer',                    '1900-01-01'),
    ('149905',     N'Provisión cartera consumo',                           '1900-01-01');

EXEC marcas.usp_proceso_marcas @fecha_corte = @fecha_corte;

DECLARE @esperado TABLE (
    cuenta_banco varchar(30), cuenta_cuc_match varchar(6), nivel_match tinyint,
    estado varchar(20), segmento varchar(30), dias_desde int, marca_especial varchar(30), signo smallint
);
INSERT INTO @esperado VALUES
    ('1402051001', '140205', 6, 'POR_VENCER', 'CONSUMO_PRIORITARIO',   1,    NULL,        1),
    ('1452059001', '145205', 6, 'VENCIDA',    'MICROCREDITO',          NULL, NULL,        1),
    ('14010101',   '1401',   4, 'POR_VENCER', 'COMERCIAL_PRIORITARIO', NULL, NULL,        1),
    ('149905',     '1499',   4, NULL,         NULL,                    NULL, 'PROVISION', -1);

DECLARE @fallas TABLE (detalle nvarchar(400));

INSERT INTO @fallas
SELECT CONCAT(N'Cuenta ', e.cuenta_banco, N': esperado ',
              CONCAT_WS('/', e.cuenta_cuc_match, e.nivel_match, e.estado, e.segmento, e.dias_desde, e.marca_especial, e.signo),
              N' | obtenido ',
              CONCAT_WS('/', m.cuenta_cuc_match, m.nivel_match, m.estado, m.segmento, m.dias_desde, m.marca_especial, m.signo))
FROM @esperado AS e
LEFT JOIN marcas.catalogo_banco_marcado AS m
  ON m.fecha_corte = @fecha_corte AND m.cuenta_banco = e.cuenta_banco
WHERE EXISTS (
    SELECT e.cuenta_cuc_match, e.nivel_match, e.estado, e.segmento, e.dias_desde, e.marca_especial, e.signo
    EXCEPT
    SELECT m.cuenta_cuc_match, m.nivel_match, m.estado, m.segmento, m.dias_desde, m.marca_especial, m.signo
);

/* 145205 (vencida) no tiene banda cargada: debe quedar alerta BANDA_FALTANTE */
IF NOT EXISTS (SELECT 1 FROM marcas.control_alertas
               WHERE fecha_corte = @fecha_corte AND regla_fallida = 'BANDA_FALTANTE' AND cuenta = '145205')
    INSERT INTO @fallas VALUES (N'No se generó la alerta BANDA_FALTANTE para 145205');

/* Los nombres sintéticos salen de los parámetros: no debe haber inconsistencias */
IF EXISTS (SELECT 1 FROM marcas.control_alertas
           WHERE fecha_corte = @fecha_corte AND regla_fallida = 'CONSISTENCIA_NOMBRE')
    INSERT INTO @fallas VALUES (N'Alertas CONSISTENCIA_NOMBRE inesperadas');

-- Las variables de tabla sobreviven al ROLLBACK (las tablas temporales no)
ROLLBACK TRANSACTION;

IF EXISTS (SELECT 1 FROM @fallas)
BEGIN
    SELECT * FROM @fallas;
    THROW 50200, N'Prueba de proceso (caso 1): resultados inesperados.', 1;
END;
PRINT N'OK caso 1: proceso completo';

/* ---------- Caso 2: una cuenta del banco sin match detiene el proceso ---------- */
DECLARE @error int = NULL;

BEGIN TRY
    BEGIN TRANSACTION;

    DELETE FROM marcas.catalogo_banco;
    DELETE FROM marcas.cuc_oficial;

    INSERT INTO marcas.cuc_oficial (cuenta_cuc, nombre, fecha_desde)
    VALUES ('1401', N'Cartera de créditos comercial prioritario por vencer', '1900-01-01');

    INSERT INTO marcas.catalogo_banco (cuenta_banco, nombre, fecha_desde) VALUES
        ('14010101', N'Comercial prioritario por vencer', '1900-01-01'),
        ('14800101', N'Cuenta sin equivalente en el CUC',  '1900-01-01');

    EXEC marcas.usp_proceso_marcas @fecha_corte = @fecha_corte;

    ROLLBACK TRANSACTION;
END TRY
BEGIN CATCH
    SET @error = ERROR_NUMBER();
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
END CATCH;

IF @error IS NULL OR @error <> 50002
BEGIN
    DECLARE @msg nvarchar(200) = CONCAT(N'Prueba de proceso (caso 2): se esperaba el error 50002 y se obtuvo ',
                                         COALESCE(CAST(@error AS nvarchar(10)), N'ninguno'));
    THROW 50201, @msg, 1;
END;

PRINT N'OK caso 2: la falta de cobertura detiene el proceso';
