"""Extrae las cuentas de un grupo del CUC (por defecto el 14) desde el PDF oficial de la
Superintendencia de Bancos y genera:

- un CSV (cuenta_cuc;nombre) para revisión, y
- un script SQL idempotente que carga marcas.cuc_oficial con esa versión.

Uso:
    python scripts/extraer_cuc_pdf.py <pdf> --desde 2021-02-22 \
        --csv datos/cuc_grupo14_sb_2021_0403.csv \
        --sql sql/datos/01_cuc_oficial_grupo14.sql

Requiere pypdf. El nombre de cada cuenta se toma de su primera aparición en el PDF
(el listado del catálogo); los nombres partidos en varias líneas se unen.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

from pypdf import PdfReader

COLUMNAS_USUARIOS = re.compile(r"(\s+(X|-|XX|XXX|XXXX|XXXXX|XXXXXX)){3,}\s*$")
SOLO_MARCAS = re.compile(r"^[\sX\-]+$")


def limpiar(texto: str) -> str:
    texto = COLUMNAS_USUARIOS.sub("", texto)
    return re.sub(r"\s+", " ", texto).strip()


def extraer(pdf: Path, grupo: str) -> dict[str, str]:
    lineas = "\n".join(p.extract_text() or "" for p in PdfReader(str(pdf)).pages).splitlines()
    inicio = re.compile(rf"^\s*({grupo}\d{{2}}|{grupo}\d{{4}})(\s+(.*))?$")
    cuentas: dict[str, str] = {}
    i = 0
    while i < len(lineas):
        m = inicio.match(lineas[i])
        if not m:
            i += 1
            continue
        codigo, partes = m.group(1), [m.group(3) or ""]
        cerrada = bool(COLUMNAS_USUARIOS.search(lineas[i]))
        j = i + 1
        # Continúa el nombre mientras no empiece otra cuenta ni aparezca una línea vacía
        # o de solo marcas de usuarios.
        while not cerrada and j < len(lineas):
            sig = lineas[j]
            if not sig.strip() or SOLO_MARCAS.match(sig) or inicio.match(sig):
                break
            partes.append(sig)
            cerrada = bool(COLUMNAS_USUARIOS.search(sig))
            j += 1
        nombre = limpiar(" ".join(partes))
        if nombre and codigo not in cuentas:
            cuentas[codigo] = nombre
        i = j
    return dict(sorted(cuentas.items()))


def sql_literal(texto: str) -> str:
    return "N'" + texto.replace("'", "''") + "'"


def escribir_sql(cuentas: dict[str, str], desde: str, origen: str, destino: Path) -> None:
    filas = ",\n".join(f"    ('{c}', {sql_literal(n)})" for c, n in cuentas.items())
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text(
        f"""/* Carga de marcas.cuc_oficial generada por scripts/extraer_cuc_pdf.py.
   Fuente: {origen}
   Vigencia desde: {desde}. Idempotente: reemplaza las filas de esa fecha_desde. */
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @desde date = '{desde}';

DELETE FROM marcas.cuc_oficial WHERE fecha_desde = @desde;

INSERT INTO marcas.cuc_oficial (cuenta_cuc, nombre, fecha_desde)
SELECT v.cuenta_cuc, v.nombre, @desde
FROM (VALUES
{filas}
) AS v(cuenta_cuc, nombre);

COMMIT TRANSACTION;
GO
""",
        encoding="utf-8",
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf", type=Path)
    ap.add_argument("--grupo", default="14")
    ap.add_argument("--desde", required=True, help="fecha_desde de la versión (AAAA-MM-DD)")
    ap.add_argument("--origen", default="", help="URL o referencia de la fuente, para el encabezado")
    ap.add_argument("--csv", type=Path, required=True)
    ap.add_argument("--sql", type=Path, required=True)
    args = ap.parse_args()

    cuentas = extraer(args.pdf, args.grupo)
    args.csv.parent.mkdir(parents=True, exist_ok=True)
    with args.csv.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, delimiter=";")
        w.writerow(["cuenta_cuc", "nombre"])
        w.writerows(cuentas.items())
    escribir_sql(cuentas, args.desde, args.origen or args.pdf.name, args.sql)
    print(f"{len(cuentas)} cuentas del grupo {args.grupo}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
