# Changelog

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
