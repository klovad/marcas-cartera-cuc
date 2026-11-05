/* Tablas de parámetros. Todas llevan vigencia (fecha_desde, fecha_hasta): el proceso
   usa la fila vigente a la fecha de corte. La unicidad de la fila vigente la controla
   marcas.usp_validar_parametros (no se puede expresar como constraint simple). */

/* Regla posicional: cómo decodificar 14NN. Con n = NN - 1:
   estado = n / bloque_estado, tipo = (n % bloque_estado) / bloque_tipo, segmento = n % bloque_tipo */
IF OBJECT_ID(N'marcas.param_regla_posicional', N'U') IS NULL
CREATE TABLE marcas.param_regla_posicional (
    id_regla       int IDENTITY(1,1) NOT NULL CONSTRAINT pk_param_regla_posicional PRIMARY KEY,
    cuenta_raiz    varchar(4) NOT NULL,   -- '14'
    pos_inicio     tinyint    NOT NULL,   -- 3 (1-based, como SUBSTRING)
    longitud       tinyint    NOT NULL,   -- 2
    rango_desde    smallint   NOT NULL,   -- 1
    rango_hasta    smallint   NOT NULL,   -- 72
    bloque_estado  smallint   NOT NULL,   -- 24
    bloque_tipo    smallint   NOT NULL,   -- 8
    fecha_desde    date       NOT NULL,
    fecha_hasta    date       NULL,
    CONSTRAINT ck_regla_rango CHECK (rango_desde >= 1 AND rango_hasta >= rango_desde),
    CONSTRAINT ck_regla_bloques CHECK (bloque_tipo > 0 AND bloque_estado >= bloque_tipo AND bloque_estado % bloque_tipo = 0),
    CONSTRAINT ck_regla_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO

IF OBJECT_ID(N'marcas.param_estado', N'U') IS NULL
CREATE TABLE marcas.param_estado (
    codigo           varchar(20)   NOT NULL,
    ordinal          smallint      NULL,      -- NULL = solo asignable por excepción
    descripcion      nvarchar(100) NOT NULL,
    es_improductiva  char(1)       NOT NULL,
    palabra_clave    nvarchar(50)  NULL,      -- solo validación contra el nombre oficial
    fecha_desde      date          NOT NULL,
    fecha_hasta      date          NULL,
    CONSTRAINT pk_param_estado PRIMARY KEY (codigo, fecha_desde),
    CONSTRAINT ck_estado_improductiva CHECK (es_improductiva IN ('S', 'N')),
    CONSTRAINT ck_estado_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO

IF OBJECT_ID(N'marcas.param_tipo', N'U') IS NULL
CREATE TABLE marcas.param_tipo (
    codigo         varchar(20)   NOT NULL,
    ordinal        smallint      NULL,
    descripcion    nvarchar(100) NOT NULL,
    palabra_clave  nvarchar(50)  NULL,        -- NULL = el nombre oficial no lo menciona (original)
    fecha_desde    date          NOT NULL,
    fecha_hasta    date          NULL,
    CONSTRAINT pk_param_tipo PRIMARY KEY (codigo, fecha_desde),
    CONSTRAINT ck_tipo_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO

IF OBJECT_ID(N'marcas.param_segmento', N'U') IS NULL
CREATE TABLE marcas.param_segmento (
    codigo         varchar(30)   NOT NULL,
    ordinal        smallint      NULL,        -- NULL = segmento fuera del patrón (solo por excepción)
    descripcion    nvarchar(100) NOT NULL,
    palabra_clave  nvarchar(50)  NULL,
    fecha_desde    date          NOT NULL,
    fecha_hasta    date          NULL,
    CONSTRAINT pk_param_segmento PRIMARY KEY (codigo, fecha_desde),
    CONSTRAINT ck_segmento_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO

/* Excepciones: ganan sobre la regla posicional. Pueden definirse a 4 o 6 dígitos; una
   excepción de 4 dígitos cubre también sus subcuentas, salvo que exista una de 6. */
IF OBJECT_ID(N'marcas.param_excepcion', N'U') IS NULL
CREATE TABLE marcas.param_excepcion (
    cuenta_cuc      varchar(6)  NOT NULL,
    estado          varchar(20) NULL,
    tipo            varchar(20) NULL,
    segmento        varchar(30) NULL,
    marca_especial  varchar(30) NULL,         -- p. ej. PROVISION
    signo           smallint    NOT NULL CONSTRAINT df_excepcion_signo DEFAULT (1),
    fecha_desde     date        NOT NULL,
    fecha_hasta     date        NULL,
    CONSTRAINT pk_param_excepcion PRIMARY KEY (cuenta_cuc, fecha_desde),
    CONSTRAINT ck_excepcion_codigo CHECK (cuenta_cuc NOT LIKE '%[^0-9]%' AND LEN(cuenta_cuc) IN (4, 6)),
    CONSTRAINT ck_excepcion_signo CHECK (signo IN (1, -1)),
    CONSTRAINT ck_excepcion_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO

/* Bandas de días para subcuentas 14NNSS. segmento NULL = banda genérica del estado;
   una fila con segmento informado gana sobre la genérica. dias_hasta NULL = sin tope. */
IF OBJECT_ID(N'marcas.param_banda', N'U') IS NULL
CREATE TABLE marcas.param_banda (
    id_banda     int IDENTITY(1,1) NOT NULL CONSTRAINT pk_param_banda PRIMARY KEY,
    estado       varchar(20) NOT NULL,
    segmento     varchar(30) NULL,
    sufijo       char(2)     NOT NULL,
    dias_desde   int         NOT NULL,
    dias_hasta   int         NULL,
    fecha_desde  date        NOT NULL,
    fecha_hasta  date        NULL,
    CONSTRAINT ck_banda_sufijo CHECK (sufijo NOT LIKE '%[^0-9]%'),
    CONSTRAINT ck_banda_dias CHECK (dias_desde >= 0 AND (dias_hasta IS NULL OR dias_hasta >= dias_desde)),
    CONSTRAINT ck_banda_vigencia CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO
