# Changelog

## Unreleased

- Reserved word list taken from the Local SQL reference (was partial).
- Escape functions `YEAR/MONTH/DAYOFMONTH/HOUR/MINUTE/SECOND` mapped to `EXTRACT`;
  `CONVERT` maps common type names (`INT`, `DATETIME`, `CHAR`).
- `docs/LOCAL_SQL.md` / `LOCAL_SQL.it.md`: Local SQL cheat sheet (EN/IT).
- Command line scripts: `build.bat`, `test.bat`, `clean.bat`, `install-ide.bat`.

## 0.1.0 – 2026-10-16

First public release.

- FireDAC physical driver `BDE` on top of the BDE (`TSession` / `TDatabase` / `TQuery`).
- dBase III/IV and Paradox 7+ support; DBF and Paradox files with the same base name in one folder.
- Metadata: tables, fields, indexes, primary key.
- Reading of all common field types including memo and BLOB.
- Update/insert/delete, transactions, record-lock errors mapped to `ekRecordLocked`.
- Connection parameters `BDEDriver`, `NetFileDir`, `PrivateDir`, `LockRetry`, `Password`.
- Automatic private temp folder per connection (no `_QSQLxxx` files left in the data folder).
- Design-time and runtime packages for Delphi 13.2, `BDETest` console test program,
  synthetic sample data generators.
