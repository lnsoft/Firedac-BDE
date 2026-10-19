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

A dBase table (`DETAIL.DBF`, 452,873 rows, 32 fields), Delphi 13.2, local disk:

| Operation                                                         | TQuery   | TTable  |
|-------------------------------------------------------------------|----------|---------|
| `select *` (first 5,000 rows identical)                           | 3,574 ms | 7 ms    |
| `TFDTable.Open`                                                   | ~3.5 s   | 14 ms   |
| `order by NUMERO` (indexed)                                       | 2,323 ms | 16 ms   |
| `where NUMERO >= x and NUMERO <= y order by NUMERO` (292,998 rows) | 2,389 ms | 4 ms    |
| `where NUMERO > x order by NUMERO` (292,996 rows)                 | 2,402 ms | 5 ms    |
| `where NUMERO < x order by NUMERO` (159,875 rows)                 | 1,304 ms | 5 ms    |

A Paradox table (13,898 rows, text primary key): `order by` the key uses the TTable and returns
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

Reading all 452,873 rows x 32 fields of the detail table takes 3.3 s with FireDAC and `TableCursor`. A raw BDE `TTable` loop
needs 0.25 s just to walk the cursor and 2.5 s to read the 32 fields (the same with `Variant` or typed accessors), so
about three quarters of the time is the BDE reading field values; FireDAC and the driver add about 0.8 s. Reading
only the fields you need (`select NUMERO, RIGA, QTA from ...`) cuts the cost in proportion.

## Choosing the index and the range yourself: `OnBDEIndexNeeded`, `OnBDESetRange`

With `TableCursor=True` the driver can ask you two things, through optional runtime events on the connection.
**If you assign neither, nothing changes**: the driver decides alone with the rules above. They only apply to
single-table `SELECT`s; joins, functions and anything the parser does not recognise always go to the `TQuery`.

```pascal
procedure TForm1.FDConnection1AfterConnect(Sender: TObject);
begin
  FDConnection1.OnBDEIndexNeeded := IndexNeeded;   // after the connection is open
  FDConnection1.OnBDESetRange := SetRangeNeeded;
end;

procedure TForm1.IndexNeeded(Sender: TObject; const ATableName, AFieldNames, ASQL: String;
  ADescending: Boolean; var AIndexName: String; var AAccept: Boolean);
begin
  // AIndexName is the driver's proposal ('' = it has none); AAccept starts True only if it has one
  if SameText(ATableName, 'ORDERS.DBF') and SameText(AFieldNames, 'CUSTOMER;DATE') then begin
    AIndexName := 'CUSTDATE';
    AAccept := True;
  end;
end;

procedure TForm1.SetRangeNeeded(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
  const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
begin
  // ADataSet is the TTable, already open on AIndexName
  if SameText(AConditions[0].Field, 'CUSTOMER') and (AConditions[0].Op = '=') then begin
    TTable(ADataSet).SetRangeStart;
    TTable(ADataSet).FieldByName('CUSTOMER').AsString := AConditions[0].Value;
    TTable(ADataSet).SetRangeEnd;
    TTable(ADataSet).FieldByName('CUSTOMER').AsString := AConditions[0].Value;
    TTable(ADataSet).ApplyRange;
    AHandled := True;
  end;
end;
```

### `OnBDEIndexNeeded`

Called while preparing a `SELECT` that needs an index:

| Argument       | Meaning |
|----------------|---------|
| `ATableName`   | table in the `FROM`, without quotes |
| `AFieldNames`  | the `ORDER BY` fields, separated by `;`; if there is no `ORDER BY`, the fields of the `WHERE` (simple conditions joined by `AND`) |
| `ASQL`         | the statement |
| `ADescending`  | `True` if the `ORDER BY` is `DESC` (all fields descending; mixed directions are never served by a `TTable`) |
| `AIndexName`   | in: the index the driver proposes, `''` if it has none; out: the index to use. `S_BDE_PrimaryIndex` (`'(primary)'`) is the Paradox primary key |
| `AAccept`      | in: `True` if the driver has a proposal, `False` if not; set it to `True` to take the query over, to `False` to run it with the `TQuery` |

The driver has **no proposal** (empty `AIndexName`, `AAccept = False`) when it cannot serve the query by itself:
`ORDER BY ... DESC` without a descending index, a `WHERE` with text or date fields, and so on. If you do nothing,
the query runs as usual with the `TQuery`. To take it over, set the index **and** `AAccept := True`.

- **`WHERE` without `ORDER BY`**: with the index you return, the conditions are served with a `SetRange`. The rows
  come back in index order.
- **Another index than the proposed one**, including expression and case-insensitive indexes. For an index made of
  plain fields the driver checks that its first fields are the requested ones and that the direction matches; for an
  expression index (`ixExpression`) the check is yours.

### `OnBDESetRange`

Called when opening a `SELECT` with a `WHERE` served by a `TTable`, after the table is open on the index in use and
before the driver sets its own range. `AConditions` has one entry per condition (`Field`, `Op` = `=`, `>`, `>=`,
`<`, `<=`, and `Value`: the parameter value, `Null` for NULL, or the number or text written in the SQL).

- Set `AHandled := True` after calling `SetRangeStart` / `SetRangeEnd` / `ApplyRange` yourself. The driver then does
  nothing else: **you answer for the range being equivalent to the `WHERE`**. This is how text and date conditions
  can be served (note that a `SetRange` on a text field has prefix semantics, and dates must be converted).
- Leave `AHandled := False` and the standard behaviour applies: the driver's own `SetRange` if the conditions are
  numeric and fit the index, otherwise the `TQuery`.

With `OnBDESetRange` assigned the driver no longer rejects at prepare time a `WHERE` on text or date fields, or
conditions that its own `SetRange` cannot express; if you do not handle them, the query goes to the `TQuery` when
it is opened. A descending or expression index is also accepted with a `WHERE` (the range is yours).

### Notes

- An exception raised by your handlers is **not** swallowed: it reaches the caller.
- If `AAccept` is `False`, `AIndexName` is empty or unknown, or the index does not fit, the query runs with the
  `TQuery`, exactly as without the event.
- The physical connection is created at every `Connected := True`, so assign the events after connecting (for
  example in `AfterConnect`). They are a class helper declared in `FireDAC.Phys.BDEDef`.

## Differences from the TQuery

* The TTable is a **live** cursor: rows changed by other users while you read may show up; a TQuery works on a copy.
* Rows with **equal keys** may come out in a different order than with TQuery (the order of equal keys is not defined in SQL).
  Add the missing fields to the `ORDER BY` (`order by NUMERO, RIGA`) if the order matters; it uses the index only if one covers them.
* A field that is a Local SQL reserved word (for example `AUTOINC`) works through the TTable, while the TQuery rejects it.
* If a parameter of a `WHERE` is NULL or not numeric when the query is opened, the driver switches to the TQuery for that command.

## Seeing other users' changes

A `TFDQuery` keeps the rows it has fetched in memory, so a change made by another process or connection is not
shown in a result that is already open: it needs a refresh. Measured with a writer in a **separate process** that
updates a row and stays connected (dBase table on a local disk), with and without a `DbiSaveChanges` on its side:

| Reader                                   | Sees the change? |
|------------------------------------------|------------------|
| the same open query, doing nothing       | no (rows already fetched) |
| the same query after `Refresh`           | yes |
| a new query on the same connection       | yes |
| a new connection                         | yes |
| a plain `TQuery` (no `TableCursor`)      | yes |

So the BDE does not hold the change back (no flush is needed on the writing side): a reopen is enough. With
`TableCursor=True` a reopen costs milliseconds (`TFDTable.Open` 12 ms; `select *` 7 ms instead of 3.4 s), so
`Refresh` is practically free; with the `TQuery` it costs as much as the first open. To refresh a single row use
`RefreshRecord` with `UpdateOptions.KeyFields` (served by the index, about 10 ms). There is no change notification
in the BDE: if you need to know when to refresh, poll the modification time of the table file.

The figures above are for a local disk; on a network share the client cache of the share can delay the change.

## Check what happened

`BDETest` has a case that runs every shape above on a normal and on a `TableCursor=True` connection, compares keys
and row counts, and verifies which cursor was used; `LocalSQLTest ... md` runs the master-detail test.
