/* Esquema del proceso de marcas de cartera. Idempotente. */
IF SCHEMA_ID(N'marcas') IS NULL
    EXEC (N'CREATE SCHEMA marcas AUTHORIZATION dbo;');
GO
