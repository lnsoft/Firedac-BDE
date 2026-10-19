# Changelog

## 0.1.0 – 2026-10-19

First public release.

- FireDAC physical driver `BDE` on top of the BDE (`TSession` / `TDatabase` / `TQuery`).
- dBase III/IV and Paradox 7+ support; DBF and Paradox files with the same base name in one folder.
- Metadata: tables, fields, indexes, primary key.
- Reading of all common field types including memo and BLOB.
- Update/insert/delete, transactions, record-lock errors mapped to `ekRecordLocked`.
- Connection parameters `BDEDriver`, `NetFileDir`, `PrivateDir`, `LockRetry`, `Password`
  (`Password` for protected Paradox tables is not tested yet).
- Automatic private temp folder per connection (no `_QSQLxxx` files left in the data folder).
- Local SQL: official reserved-word list; escape functions `UCASE/LCASE/LTRIM/RTRIM/SUBSTRING/CONCAT`,
  `CONVERT` (maps `INT`, `DATETIME`, `CHAR`) and `YEAR/MONTH/DAYOFMONTH/HOUR/MINUTE/SECOND` (via `EXTRACT`).
- Documentation: README (EN/IT), `docs/ARCHITECTURE.md`, `docs/LOCAL_SQL.md` / `LOCAL_SQL.it.md`.
- Experimental: FireDAC Local SQL (SQLite virtual tables) on top of the driver; `docs/LOCAL_SQL_ON_BDE.md` (EN/IT)
  and `Demos\LocalSQLTest.dpr`.
- Optional performance feature, off by default:
  New connection parameter `TableCursor` (default `False`): plain `select * from TAB` / `select fields from TAB`
  are read through a BDE `TTable` (immediate open on large tables) instead of a `TQuery`. Other SELECTs are unchanged.
  Also `ORDER BY` (ascending) on the leading fields of a plain index. Measured on a 452,873-row DBF:
  `select *` opens in 3.5 s with `TQuery`, 7 ms with `TTable`; `order by` an indexed field 2.2 s vs 16 ms;
  a key range returning 293k rows 2.4 s vs 1 ms. `WHERE` is served by the `TTable` only together with an
  `ORDER BY` on the same leading index fields (equalities plus at most one numeric range).
  `TFDTable.Open` (`SELECT A.* FROM "TAB" A`, table alias accepted) opens in 14 ms instead of ~3.5 s on that table.
  Master-detail with a `TFDQuery` detail and a parameter: 4.1 s -> 0.9 s for 300 headers.
  Guide: `docs/TABLECURSOR.md` / `docs/TABLECURSOR.it.md`.
- Known limit documented: rollback of a previously empty memo (dBase III).
- Design-time and runtime packages for Delphi 13.2; command line scripts `build.bat`, `test.bat`,
  `clean.bat`, `install-ide.bat`; `BDETest` console test program; synthetic sample data generators.
- Tested with Delphi 13.2 on real dBase IV and Paradox tables and on the bundled `SAMPLE.DBF`.
