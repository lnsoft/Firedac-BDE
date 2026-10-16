# Architecture notes

The driver follows the structure of the stock FireDAC drivers (SQLite, ODBC):
the BDE plays the role of the "client library".

| Unit | Role |
|---|---|
| `FireDAC.Phys.BDEDef` | `TFDPhysBDEConnectionDefParams`: connection parameters (`BDEDriver`, `NetFileDir`, `PrivateDir`, `LockRetry`) |
| `FireDAC.Phys.BDEMeta` | `TFDPhysBDEMetadata` (capabilities, naming rules, escape functions) and `TFDPhysBDECommandGenerator` |
| `FireDAC.Phys.BDE` | driver, connection, transaction and command; `TFDPhysBDEDriverLink` |
| `FireDAC.Phys.BDEReg` | design-time registration of the driver link (design package only) |

## Classes (`FireDAC.Phys.BDE`)

- **`TFDPhysBDEDriver`** – loads once, exposes the connection parameter list.
- **`TFDPhysBDEConnection`** – owns a private `TSession` (`AutoSessionName`) and a `TDatabase`
  (alias, or `PATH=` folder with the BDE driver `STANDARD`). `TransIsolation` is `tiDirtyRead`
  (the only level local tables support). Creates a private `PrivateDir` unless one is given.
- **`TFDPhysBDETransaction`** – `StartTransaction/Commit/Rollback` of the `TDatabase`.
- **`TFDPhysBDECommand`** – wraps a unidirectional `TQuery`. Parameters are bound by name
  (the BDE only understands `:name`), strings are passed to the BDE as ANSI, memo parameters as
  `ftMemo`. Rows are copied from the dataset into FireDAC's `TFDDatSTable` in
  `FetchQueryRows`. Metadata requests (`mkTables`, `mkTableFields`, ...) are built directly from
  `TSession.GetTableNames` and `TTable.FieldDefs/IndexDefs` instead of SQL.
- **`EFDBDENativeException`** – converts `EDBEngineError` into FireDAC errors; `DBIERR_KEYVIOL`
  becomes `ekUKViolated`, `DBIERR_LOCKED`/`FILELOCKED`/`RECLOCKFAILED` become `ekRecordLocked`.

## Decisions worth knowing

- **Table names include the extension.** `.DB` and `.DBF` may coexist; `InternalDecodeObjName`
  treats a name ending in `.DB`/`.DBF` as a single object name (no catalog/schema splitting) and
  `QuoteNameIfReq` quotes it because of the dot.
- **Parameter marks are always `:name`.** `GetPositionedParamMark` returns `prName`, otherwise
  FireDAC would emit `?` and the BDE raises *"Parameter not set in query string"*.
- **No `LIMIT`/`TOP`.** `GetLimitOptions = []`, so FireDAC skips/limits on the client.
- **Memo fetch** uses the Variant overload of `TFDDatSRow.SetData`; passing a raw `PChar` crashed
  inside `InternalSetData`.
- **Exact updates.** FireDAC's default is to require that an UPDATE touches exactly one row
  (error 312). On DBF this means `KeyFields` must be unique.
- **`LockRetry`** calls `DbiSetCurrSession` + `DbiSetLockRetry`; the effective wait is a
  multiple of the value because the BDE retries more than once per statement.
- **Win32 only**: the unit stops compilation on other platforms.
