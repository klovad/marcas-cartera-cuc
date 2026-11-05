/* Prueba de punta a punta de marcas.usp_proceso_marcas con un catálogo de banco sintético
   sobre el CUC oficial cargado (sql/datos/01_cuc_oficial_grupo14.sql).
   EJECUTAR SOLO EN UNA BASE DE DESARROLLO: dentro de una transacción vacía catalogo_banco,
   carga cuentas de prueba y al final hace ROLLBACK (no deja rastro). */
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @fecha_corte date = CAST(GETDATE() AS date);

/* ---------- Caso 1: proceso completo con cobertura total ---------- */
BEGIN TRANSACTION;

DELETE FROM marcas.catalogo_banco;

INSERT INTO marcas.catalogo_banco (cuenta_banco, nombre, fecha_desde) VALUES
    ('1402051001', N'Consumo por vencer 1-30 días, agencia 1',  '1900-01-01'),  -- match 6 dígitos
    ('1452059001', N'Microcrédito vencido, producto X',         '1900-01-01'),  -- 145205 no existe: match 4
    ('14010101',   N'Productivo por vencer',                    '1900-01-01'),  -- 140101 no existe: match 4
    ('1494400001', N'Microcrédito reestructurado COVID-19',     '1900-01-01'),  -- excepción de 6 dígitos
    ('149905',     N'Provisión cartera productiva',             '1900-01-01');  -- provisión por segmento

EXEC marcas.usp_proceso_marcas @fecha_corte = @fecha_corte;

DECLARE @esperado TABLE (
    cuenta_banco varchar(30), cuenta_cuc_match varchar(6), nivel_match tinyint,
    estado varchar(20), tipo varchar(20), segmento varchar(30), dias_desde int,
    marca_especial varchar(30), signo smallint
);
INSERT INTO @esperado VALUES
    ('1402051001', '140205', 6, 'POR_VENCER', 'ORIGINAL',       'CONSUMO',      1,    NULL,        1),
    ('1452059001', '1452',   4, 'VENCIDA',    'ORIGINAL',       'MICROCREDITO', NULL, NULL,        1),
    ('14010101',   '1401',   4, 'POR_VENCER', 'ORIGINAL',       'PRODUCTIVO',   NULL, NULL,        1),
    ('1494400001', '149440', 6, 'POR_VENCER', 'REESTRUCTURADA', 'MICROCREDITO', NULL, 'COVID19',   1),
    ('149905',     '149905', 6, NULL,         NULL,             'PRODUCTIVO',   NULL, 'PROVISION', -1);

DECLARE @fallas TABLE (detalle nvarchar(400));

INSERT INTO @fallas
SELECT CONCAT(N'Cuenta ', e.cuenta_banco, N': esperado ',
              CONCAT_WS('/', e.cuenta_cuc_match, e.nivel_match, e.estado, e.tipo, e.segmento, e.dias_desde, e.marca_especial, e.signo),
              N' | obtenido ',
              CONCAT_WS('/', m.cuenta_cuc_match, m.nivel_match, m.estado, m.tipo, m.segmento, m.dias_desde, m.marca_especial, m.signo))
FROM @esperado AS e
LEFT JOIN marcas.catalogo_banco_marcado AS m
  ON m.fecha_corte = @fecha_corte AND m.cuenta_banco = e.cuenta_banco
WHERE EXISTS (
    SELECT e.cuenta_cuc_match, e.nivel_match, e.estado, e.tipo, e.segmento, e.dias_desde, e.marca_especial, e.signo
    EXCEPT
    SELECT m.cuenta_cuc_match, m.nivel_match, m.estado, m.tipo, m.segmento, m.dias_desde, m.marca_especial, m.signo
);

/* Con el CUC oficial no debe haber cuentas sin marca, bandas faltantes ni nombres inconsistentes */
INSERT INTO @fallas
SELECT CONCAT(N'Alerta inesperada ', regla_fallida, N' en ', cuenta, N': ', detalle)
FROM marcas.control_alertas
WHERE fecha_corte = @fecha_corte;

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

    INSERT INTO marcas.catalogo_banco (cuenta_banco, nombre, fecha_desde) VALUES
        ('14010101', N'Productivo por vencer',                         '1900-01-01'),
        ('14050101', N'Cuenta en una posición que no existe en el CUC', '1900-01-01');

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
