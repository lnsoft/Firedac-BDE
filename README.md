# FireDAC-BDE

**FireDAC driver for the BDE**

A **FireDAC physical driver (`DriverID=BDE`)** that lets modern FireDAC code
read and write legacy **dBase III/IV (`.DBF`)** and **Paradox 7+ (`.DB`)**
tables through the Borland Database Engine (BDE).

You keep using `TFDConnection`, `TFDQuery`, `TFDTable`, transactions and
parameters as with any other FireDAC database; the driver takes care of
talking to the BDE underneath.

> Unofficial, community project. Not affiliated with or endorsed by Embarcadero.
> Developed and tested with **Delphi 13.2**, Windows 32-bit only (the BDE is 32-bit).
> 🇮🇹 [Leggi in italiano](README.it.md)

## Why

Migrating an application from BDE to FireDAC is easy; migrating the *data*
usually isn't (shared DBF/Paradox files used by other legacy programs). This
driver lets new FireDAC code work **directly on the legacy files** while the old
programs keep running, with no hybrid infrastructure and no code that is
specific to a database.

## Features

- Connection through a BDE alias **or** a plain folder path (no alias needed).
- Metadata: table list, fields, indexes, primary key (`TFDMetaInfoQuery`,
  `GetTableNames`, `GetFieldNames`, ...).
- `TFDQuery` / `TFDTable` / `TFDCommand` with named parameters, fetch of all
  field types including memo and BLOB.
- Updates through `Edit/Post`, `Append`, `Delete`, and direct `UPDATE/INSERT/DELETE`.
- Transactions (`StartTransaction/Commit/Rollback`) – tested with rollback on both DBF and Paradox.
- Shared access with other applications, record-lock errors mapped to
  `ekRecordLocked`, configurable lock wait (`LockRetry`).
- DBF and Paradox files with the **same base name** coexisting in one folder.
- Design-time package (component `TFDPhysBDEDriverLink`).

## Requirements

- Delphi with FireDAC (developed on 13.2; other versions untested – reports welcome).
- A working **BDE** installation (`bdertl` package, Borland Database Engine on the
  machine). The BDE is a legacy Embarcadero product; obtain it according to your
  own license. Nothing from the BDE or FireDAC sources is included here.
- Build target: **Windows 32-bit**.

## Installation

1. Clone the repository (`git clone https://github.com/<your-user>/Firedac-BDE.git`) and open `FDBDE_D132.groupproj` (target platform **Win32**).
2. Build `FDBDERun` (runtime package, requires `bdertl`).
3. Build and **Install** `FDBDEDesign` (design-time package).
4. In your projects either add `FDBDERun` to the runtime packages, or just add
   `FireDAC.Phys.BDEDef` and `FireDAC.Phys.BDE` to a `uses` clause: the driver
   registers itself in the `initialization` section.

If the compiler cannot find `FireDAC.inc`, add `$(BDS)\source\data\firedac` to
the library/search path (do **not** copy that file into the repository, it belongs to Embarcadero).

## Usage

```pascal
FDConnection1.DriverName := 'BDE';
FDConnection1.Params.Database := 'C:\Data\Legacy';   // folder with .DBF/.DB, or a BDE alias
FDConnection1.Params.Values['LockRetry'] := '1';     // optional
FDConnection1.Open;

// Table names must carry the extension and be double-quoted in SQL
FDQuery1.Open('select * from "CUSTOMERS.DBF" where ID = :id', [42]);

// Updating a DBF needs a UNIQUE key field (DBF has no primary key)
FDQuery1.UpdateOptions.UpdateTableName := 'CUSTOMERS.DBF';
FDQuery1.UpdateOptions.KeyFields := 'ID';
FDQuery1.Edit;
FDQuery1.FieldByName('NAME').AsString := 'New name';
FDQuery1.Post;
```

### Connection parameters

| Parameter    | Meaning |
|--------------|---------|
| `DriverID`   | `BDE` |
| `Database`   | BDE alias, **or** folder containing the DBF/Paradox files |
| `BDEDriver`  | BDE driver used with a folder path. Default `STANDARD` (DBF + Paradox) |
| `NetFileDir` | Folder of `PDOXUSRS.NET` for shared Paradox access (must be the same for all users) |
| `PrivateDir` | Temporary folder of the BDE session. Default: an automatic temp folder removed on disconnect |
| `LockRetry`  | Seconds to wait on a locked record. `0` = don't wait. Not set = BDE default (about 6 s) |
| `Password`   | Paradox table password (`AddPassword`) |

## Things to know (limitations)

- **Windows 32-bit only.** The BDE does not exist for 64-bit.
- **SQL dialect = BDE Local SQL**: no `LIMIT/TOP`, limited functions, limited joins/subqueries.
  FireDAC does skip/limit on the client side.
- **File extensions.** A folder can hold `CLIENTS.DB` and `CLIENTS.DBF`. Always use the
  extension and double quotes in SQL (`"CLIENTS.DBF"`); without it the BDE picks Paradox.
- **DBF has no primary key.** Set `UpdateOptions.KeyFields` to a field that is really unique,
  otherwise FireDAC reports *"Exact update affected [N] rows"*.
- **Memo parameters.** To write a memo with hand-written SQL, give the parameter a memo type
  (`DataType := ftWideMemo; AsWideMemo := ...`). A plain string parameter on a memo column
  raises no error on Paradox but writes nothing. `Edit/Post` is not affected.
- **Locks.** Waiting time on a locked record is governed by the BDE; use `LockRetry`.
  In the tests a row modified inside an open transaction stayed locked for other connections
  until commit/rollback, on both DBF and Paradox.
- **One BDE session per connection**; the BDE is not designed for heavy multi-threading.
- Strings are exposed as Unicode; the conversion uses the table's language driver, so
  characters outside the table's code page may not survive a round trip.
- Not implemented: DDL helpers (create/alter table through FireDAC), stored procedures,
  event alerts, array DML optimisation (arrays are executed row by row).

## What has been tested

Real-world dBase IV (≈3,600 rows, 119 fields, memo) and Paradox tables, Delphi 13.2, with
`Demos\BDETest`:

| Area | DBF | Paradox |
|---|---|---|
| Connect, tables, fields, indexes | ✅ | ✅ |
| Select, count, fetch, parameters, `Locate` | ✅ | ✅ |
| Update / insert / delete with rollback | ✅ | ✅ |
| Memo read/write (dataset and parameter) | ✅ | ✅ |
| Concurrent access from two applications | ✅ | ✅ |
| Record lock between two connections | ✅ | ✅ |
| Table password | – | not tested |
| BLOB / OLE / graphic fields | not tested | not tested |
| Other Delphi versions | not tested | not tested |

## Trying it

```
python Tools/make_sample_dbf.py            # creates Demos/Data/SAMPLE.DBF + .DBT (synthetic data)
Demos\BDETest.exe Demos\Data SAMPLE.DBF ID NAME NOTES
```

`BDETest <folder|alias> <TABLE.DB|DBF> [key field] [text field] [memo field]`

With a key, text and memo field the test also performs update, insert, delete and memo writes
inside a transaction that is rolled back, and a lock test with a second connection.
**Run the write tests on a copy of your data.**
A Paradox sample can be created with `Tools\MakeSampleParadox.dpr` (untested).

## Repository layout

```
Source/      driver units (BDEDef, BDEMeta, BDE) + design-time registration (BDEReg)
Packages/    Delphi packages (d132 = Delphi 13.2)
Demos/       BDETest console program + synthetic sample data
Tools/       sample data generators
docs/        architecture notes
```

Source comments and the test program messages are in Italian.

## Contributing

Bug reports and test results on other Delphi versions or table types are very welcome –
see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE). FireDAC, the BDE and Delphi are products of Embarcadero Technologies.
