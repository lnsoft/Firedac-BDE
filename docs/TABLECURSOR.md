# TableCursor – reading large tables without waiting

A BDE `TQuery` copies the whole result set when it is opened, so a `select *` on a table with hundreds of
thousands of rows takes seconds before the first row appears. A BDE `TTable` is a live cursor and opens at once.
The connection parameter `TableCursor=True` makes the driver use a read-only `TTable` for the simple queries
it can serve exactly, and the normal `TQuery` for everything else. The default is `False` (nothing changes).

```pascal
FDConnection1.Params.Values['TableCursor'] := 'True';
```

## What is served by a TTable

| SQL (as sent to the driver)                                              | Cursor |
|--------------------------------------------------------------------------|--------|
| `select * from "TAB.DBF"` (also `SELECT A.* FROM "TAB.DBF" A`, which is what `TFDTable.Open` sends) | TTable |
| `select f1, f2 from "TAB.DBF"` (plain, unquoted field names)             | TTable |
| `... order by f1[, f2]` ascending, when an index starts with exactly those fields (plain fields; not an expression, not descending, not case-insensitive) | TTable on that index |
| `... where f1 = :a [and f2 >= :b ...] order by f1, f2` – equalities on the first fields and at most one range (`>`, `>=`, `<`, `<=`) on the next, numeric fields only, value as a parameter or a number | TTable + `SetRange` |
| anything else: `desc`, `WHERE` without `ORDER BY`, text/date fields in the `WHERE`, joins, functions, quoted field names, NULL or non-numeric parameters | TQuery (unchanged) |

## Measurements

`DocD00.DBF`, 452,873 rows, Delphi 13.2, local disk:

| Operation                                                         | TQuery   | TTable  |
|-------------------------------------------------------------------|----------|---------|
| `select *` (first 5,000 rows identical)                           | 3,574 ms | 7 ms    |
| `TFDTable.Open`                                                   | ~3.5 s   | 14 ms   |
| `order by NUMERO` (indexed)                                       | 2,323 ms | 16 ms   |
| `where NUMERO >= x and NUMERO <= y order by NUMERO` (292,998 rows) | 2,389 ms | 4 ms    |
| `where NUMERO > x order by NUMERO` (292,996 rows)                 | 2,402 ms | 5 ms    |
| `where NUMERO < x order by NUMERO` (159,875 rows)                 | 1,304 ms | 5 ms    |

A Paradox table (`Scadenze.DB`, 13,898 rows, text primary key): `order by` the key uses the TTable and returns
every field identical to the TQuery result.

### Master-detail (300 headers, 2,625 detail rows, detail table 452,873 rows)

| Detail component                                               | Normal    | TableCursor |
|----------------------------------------------------------------|-----------|-------------|
| `TFDTable` with `MasterSource` / `MasterFields`                | 12,948 ms | 5,037 ms    |
| `TFDQuery` with `where NUMERO = :NUMERO order by NUMERO` + `MasterSource` | 4,137 ms | **902 ms** |

A `TFDTable` detail makes FireDAC read the whole detail table and filter it in memory (the driver only sees
`SELECT A.* FROM ... A`), so it stays slow. For master-detail on big tables use a **`TFDQuery` detail with a
parameter** and `TableCursor=True`: each header then costs about 3 ms.

## Where the time goes when you read every row

Reading all 452,873 rows x 32 fields of `DocD00` takes 3.3 s with FireDAC and `TableCursor`. A raw BDE `TTable` loop
needs 0.25 s just to walk the cursor and 2.5 s to read the 32 fields (the same with `Variant` or typed accessors), so
about three quarters of the time is the BDE reading field values; FireDAC and the driver add about 0.8 s. Reading
only the fields you need (`select NUMERO, RIGA, QTA from ...`) cuts the cost in proportion.

## Differences from the TQuery

* The TTable is a **live** cursor: rows changed by other users while you read may show up; a TQuery works on a copy.
* Rows with **equal keys** may come out in a different order than with TQuery (the order of equal keys is not defined in SQL).
  Add the missing fields to the `ORDER BY` (`order by NUMERO, RIGA`) if the order matters; it uses the index only if one covers them.
* A field that is a Local SQL reserved word (for example `AUTOINC`) works through the TTable, while the TQuery rejects it.
* If a parameter of a `WHERE` is NULL or not numeric when the query is opened, the driver switches to the TQuery for that command.

## Check what happened

`BDETest` has a case that runs every shape above on a normal and on a `TableCursor=True` connection, compares keys
and row counts, and verifies which cursor was used; `LocalSQLTest ... md` runs the master-detail test.
