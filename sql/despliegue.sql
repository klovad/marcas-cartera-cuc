/* Despliegue completo en orden. Ejecutar en modo SQLCMD desde la raíz del repo:
     sqlcmd -S <servidor> -d <base> -E -b -i sql/despliegue.sql
   Todos los scripts son idempotentes. */
:on error exit

:r sql/ddl/01_esquema.sql
:r sql/ddl/02_tablas_entrada.sql
:r sql/ddl/03_tablas_parametros.sql
:r sql/ddl/04_tablas_resultado.sql

:r sql/params/01_carga_inicial.sql
:r sql/datos/01_cuc_oficial_grupo14.sql

:r sql/motor/01_fn_marcar_cuenta.sql
:r sql/motor/02_usp_marcar_cuc.sql
:r sql/motor/03_usp_marcar_catalogo_banco.sql
:r sql/validaciones/01_usp_validar_parametros.sql
:r sql/validaciones/02_usp_validar_resultados.sql
:r sql/motor/04_usp_proceso_marcas.sql
