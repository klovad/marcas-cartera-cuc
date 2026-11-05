/* Tablas de entrada: el CUC oficial y el catálogo contable del banco.
   Se cargan desde fuera del proceso (ETL de origen). */

/* CUC publicado por la Superintendencia de Bancos. Versionado por vigencia para poder
   reprocesar cortes pasados con el catálogo que regía en ese momento. */
IF OBJECT_ID(N'marcas.cuc_oficial', N'U') IS NULL
CREATE TABLE marcas.cuc_oficial (
    cuenta_cuc   varchar(6)    NOT NULL,
    nombre       nvarchar(300) NOT NULL,   -- solo para validar; nunca para marcar
    fecha_desde  date          NOT NULL,
    fecha_hasta  date          NULL,       -- NULL = vigente
    CONSTRAINT pk_cuc_oficial PRIMARY KEY (cuenta_cuc, fecha_desde),
    CONSTRAINT ck_cuc_oficial_codigo CHECK (cuenta_cuc NOT LIKE '%[^0-9]%' AND LEN(cuenta_cuc) IN (1, 2, 4, 6)),
    CONSTRAINT ck_cuc_oficial_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO

/* Catálogo contable interno del banco. Las cuentas pueden tener más de 6 dígitos. */
IF OBJECT_ID(N'marcas.catalogo_banco', N'U') IS NULL
CREATE TABLE marcas.catalogo_banco (
    cuenta_banco varchar(30)   NOT NULL,
    nombre       nvarchar(300) NULL,
    fecha_desde  date          NOT NULL,
    fecha_hasta  date          NULL,
    CONSTRAINT pk_catalogo_banco PRIMARY KEY (cuenta_banco, fecha_desde),
    CONSTRAINT ck_catalogo_banco_codigo CHECK (cuenta_banco NOT LIKE '%[^0-9]%'),
    CONSTRAINT ck_catalogo_banco_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO
