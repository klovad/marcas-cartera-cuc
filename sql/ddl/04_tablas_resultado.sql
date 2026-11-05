/* Tablas de resultado y control. Se recalculan por fecha_corte (borrar e insertar). */

IF OBJECT_ID(N'marcas.cuc_marcado', N'U') IS NULL
CREATE TABLE marcas.cuc_marcado (
    fecha_corte      date        NOT NULL,
    cuenta_cuc       varchar(6)  NOT NULL,
    nivel            tinyint     NOT NULL,     -- 4 o 6 dígitos
    estado           varchar(20) NULL,
    tipo             varchar(20) NULL,
    segmento         varchar(30) NULL,
    dias_desde       int         NULL,
    dias_hasta       int         NULL,
    es_improductiva  char(1)     NULL,
    marca_especial   varchar(30) NULL,
    signo            smallint    NOT NULL,
    origen_marca     varchar(10) NULL,         -- REGLA / EXCEPCION; NULL = sin marca
    fecha_proceso    datetime2(0) NOT NULL CONSTRAINT df_cuc_marcado_proceso DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_cuc_marcado PRIMARY KEY (fecha_corte, cuenta_cuc),
    CONSTRAINT ck_cuc_marcado_origen CHECK (origen_marca IN ('REGLA', 'EXCEPCION'))
);
GO

IF OBJECT_ID(N'marcas.catalogo_banco_marcado', N'U') IS NULL
CREATE TABLE marcas.catalogo_banco_marcado (
    fecha_corte       date        NOT NULL,
    cuenta_banco      varchar(30) NOT NULL,
    cuenta_cuc_match  varchar(6)  NOT NULL,
    nivel_match       tinyint     NOT NULL,     -- 6 o 4: gana el prefijo más largo
    estado            varchar(20) NULL,
    tipo              varchar(20) NULL,
    segmento          varchar(30) NULL,
    dias_desde        int         NULL,
    dias_hasta        int         NULL,
    es_improductiva   char(1)     NULL,
    marca_especial    varchar(30) NULL,
    signo             smallint    NOT NULL,
    origen_marca      varchar(10) NULL,
    fecha_proceso     datetime2(0) NOT NULL CONSTRAINT df_banco_marcado_proceso DEFAULT (SYSDATETIME()),
    CONSTRAINT pk_catalogo_banco_marcado PRIMARY KEY (fecha_corte, cuenta_banco)
);
GO

IF OBJECT_ID(N'marcas.control_alertas', N'U') IS NULL
CREATE TABLE marcas.control_alertas (
    id_alerta      bigint IDENTITY(1,1) NOT NULL CONSTRAINT pk_control_alertas PRIMARY KEY,
    fecha_corte    date          NOT NULL,
    cuenta         varchar(30)   NULL,
    regla_fallida  varchar(50)   NOT NULL,
    severidad      varchar(10)   NOT NULL,   -- BLOQUEANTE detiene el proceso; AVISO no
    detalle        nvarchar(400) NULL,
    fecha_proceso  datetime2(0)  NOT NULL CONSTRAINT df_alertas_proceso DEFAULT (SYSDATETIME()),
    CONSTRAINT ck_alertas_severidad CHECK (severidad IN ('BLOQUEANTE', 'AVISO'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_control_alertas_corte'
               AND object_id = OBJECT_ID(N'marcas.control_alertas'))
    CREATE INDEX ix_control_alertas_corte ON marcas.control_alertas (fecha_corte, severidad);
GO
