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
| `... order by f1[, f2]` ascending, when an index serves that order: its first fields are those fields, after any leading fields that the `WHERE` fixes with `=` (plain fields; not an expression, not descending, not case-insensitive) | TTable on that index |
| `... where f1 = :a [and f2 >= :b ...] order by ...` – equalities on the first fields of an index (in any order), at most one range (`>`, `>=`, `<`, `<=`) on the next field, then the `ORDER BY` fields; numeric fields only, value as a parameter or a number | TTable + `SetRange` |
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
  plain fields the driver checks that the index serves the `ORDER BY` (or has the `WHERE` fields in front, in any
  order) and that the direction matches; for an expression index (`ixExpression`) the check is yours.

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

**dBase expression indexes** (for example `ANNO+TIPODOC+NUMDOC`; `TIndexDef.Fields` is empty and the text is in
`Expression`), measured on a table of 22,323 rows:

- The `TTable` opens on them and reads in index order.
- A key made of **all** the fields, assigned field by field (`SetRangeStart; FieldByName('ANNO').AsString := ...;
  ... ApplyRange`), finds the row (1 row, same as the `TQuery`).
- A **partial** key (only `ANNO`, or `ANNO` and `TIPODOC`) finds **no rows and raises no error**: the BDE builds the
  key from the whole expression with the missing fields empty. So the driver never uses its own `SetRange` on an
  expression index: without `OnBDESetRange` (or with `AHandled := False`) the query goes to the `TQuery`.
- A partial key **works if you complete it yourself**: start of the range with the missing fields empty, end of the
  range with the missing fields filled with `#255` for their whole width (measured on a test table of 22,323 rows: 1317 and 449 rows,
  the same as the `TQuery`). See the handler below.
- `SetRange([...])`, `FindKey` and `FindNearest` with arrays are refused by Delphi
  ("Cannot use array of Field values with Expression Indices").
- Text fields are compared as stored: `NUMDOC` is right-aligned with leading spaces, so the value must be
  `'                   245/12'`; the `TQuery` behaves the same (`NUMDOC = '245/12'` finds nothing).

**Proposal and event.** With `OnBDESetRange` assigned, a `WHERE` without `ORDER BY` on the first fields of an
expression index made only of **text** fields joined by `+` (`ANNO+TIPODOC+NUMDOC`) is served by the `TTable`: the
driver proposes that index (`Accept = True` in `OnBDEIndexNeeded`, which you may change or refuse) and calls
`OnBDESetRange` with all the conditions, whatever they are (text, partial key, ranges), so the key is yours to
build. Without `OnBDESetRange` nothing changes (`TQuery`). The proposal is not made for expressions with
functions (`STR(N,5)+X`, `UPPER(A)`), for numeric fields (`+` would be a sum), or together with an `ORDER BY`
(the order of a concatenated key equals the order of the fields only for text fields: choose the index yourself
in `OnBDEIndexNeeded`). `BDEExpressionFields(ADef)` and the `AExpressions` form of `BDEFindIndex` expose the same
logic.

A handler that accepts equalities on the first fields of the index, partial keys included (the driver passes the
index name and the conditions; `BDEExpressionFields` returns the fields of the expression):

```pascal
procedure TForm1.BDESetRange(Sender: TObject; ADataSet: TDataSet; const AIndexName: String;
  const AConditions: TArray<TBDECondition>; var AHandled: Boolean);
var
  T: TTable;
  aF: TArray<String>;
  sV: String;
  i: Integer;

  function CondValue(const AField: String; out AValue: String): Boolean;
  var
    j: Integer;
  begin
    Result := False;
    for j := 0 to High(AConditions) do
      if SameText(AConditions[j].Field, AField) then begin
        AValue := VarToStr(AConditions[j].Value);
        Exit(True);
      end;
  end;

  // the key: fields with '=' at their value; the others empty (start) or #255 (end)
  procedure Fill(AHigh: Boolean);
  var
    j: Integer;
    F: TField;
  begin
    for j := 0 to High(aF) do begin
      F := T.FieldByName(aF[j]);
      if CondValue(aF[j], sV) then
        F.AsString := sV
      else if AHigh then
        F.AsString := StringOfChar(#255, F.Size);
    end;
    T.KeyFieldCount := Length(aF);
  end;

begin
  T := TTable(ADataSet);
  for i := 0 to T.IndexDefs.Count - 1 do
    if SameText(T.IndexDefs[i].Name, AIndexName) then
      aF := BDEExpressionFields(T.IndexDefs[i]);   // ANNO, TIPODOC, NUMDOC
  if (Length(aF) = 0) or (Length(AConditions) > Length(aF)) then
    Exit;                                   // not our case: standard behaviour (TQuery)
  for i := 0 to High(AConditions) do
    if (AConditions[i].Op <> '=') or not SameText(AConditions[i].Field, aF[i]) then
      Exit;                                 // only equalities on the first fields, in order
  T.SetRangeStart;
  Fill(False);
  T.SetRangeEnd;
  Fill(True);
  T.ApplyRange;
  AHandled := True;
end;
```

Measured with a handler like this on a table of 22,323 rows (`WHERE` on the first 1, 2 and 3 fields of
`ANNO+TIPODOC+NUMDOC`): 1317, 449 and 1 rows, always the same as the `TQuery`, in 43, 17 and 6 ms against 177, 120 and
92 ms. Valid for text fields of fixed width; `#255` as the upper limit was verified only with the language driver of
that table.

### Finding an index in your own code: `BDEFindIndex`

The function the driver uses for its proposal is public (`FireDAC.Phys.BDEDef`), so a handler can call it too. It
works on a `TIndexDefs` (for example `TTable.IndexDefs` after `Update`) and considers only plain-field indexes of the
requested direction (no expression, not case-insensitive).

```pascal
function BDEFindIndex(AIndexDefs: TIndexDefs; const AEquals, ARanges, AOrderBy: array of String;
  ADescending: Boolean; out AMatch: TBDEIndexMatch): Boolean; overload;
function BDEFindIndex(AIndexDefs: TIndexDefs; const AFields: array of String;
  ADescending, AAnyOrder: Boolean; out AMatch: TBDEIndexMatch): Boolean; overload;
function BDEIndexServesOrder(ADef: TIndexDef; const AEquals, AOrderBy: array of String): Boolean;
```

- **Full form** (`AEquals`, `ARanges`, `AOrderBy`): the fields with `=` may be in any order, so `where A = 1 and B = 2`
  finds an index on `(B, A)` as well as `(A, B)`. This is the same as trying every permutation of the `WHERE` fields,
  without generating them: for each index its first fields are checked once. A field with a range (`>`, `<`...) must
  come right after the equalities, and the `ORDER BY` fields after that. The `ORDER BY` order matters, but a field fixed
  by `=` can be skipped: `where C = 1 order by A, B` uses an index on `(C, A, B)`.
- **`AMatch.Level`**: `ilFull` = the index serves everything, so the driver's `SetRange` can be used; `ilCovers` = it
  respects the `ORDER BY` (or has the `WHERE` fields in front) but the conditions need your `OnBDESetRange`; `ilNone`
  = nothing. The first `ilFull` index wins, otherwise the first `ilCovers`.
- **List form** (`AFields`): `AAnyOrder = True` finds an index whose first fields are those fields in any order,
  `False` in the same order. Handy with `AFieldNames.Split([';'])` inside `OnBDEIndexNeeded`.

```pascal
// text fields in the WHERE: the driver has no proposal, look for an index on them (any order)
if BDEFindIndex(FOrders.IndexDefs, AFieldNames.Split([';']), ADescending, True, oMatch) then begin
  AIndexName := oMatch.IndexName;
  AAccept := True;                 // the conditions on text need OnBDESetRange as well
end;
```

Note: in dBase tables an index on more than one field is normally an expression index (`ixExpression`), which the
driver and `BDEFindIndex` leave to you; plain multi-field indexes are typical of Paradox. Look at `IndexDefs` of your
table to see which case you have.

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

## Limiting rows: `RecsMax` and paging

The Local SQL has no `TOP`/`LIMIT`, so FireDAC applies `FetchOptions.RecsMax` and `RecsSkip` on the client. What
that costs depends on the cursor (dBase table of 452,873 rows, `RecsMax = 50`):

| Query                              | Time to get 50 rows |
|------------------------------------|---------------------|
| `select *` with the `TQuery`       | 3,557 ms (the BDE copies the whole result first) |
| `select *` with `TableCursor=True` | 7 ms |
| `... order by <indexed field>` with `TableCursor=True` | 4 ms |

So for lists and grids on large tables, `TableCursor=True` with `RecsMax` (or `fmOnDemand` fetching) shows the first
rows at once.

`RecsSkip` (paging) is applied by the driver with the cursor only: it moves over the skipped rows without reading
their fields, and tells FireDAC that nothing is left to skip. Same table, 50 rows after the skip:

| Rows skipped | natural order | `order by` indexed field | before (FireDAC skipping) |
|--------------|---------------|--------------------------|---------------------------|
| 4,528        | 4 ms          | 15 ms                    | 32 ms / 45 ms             |
| 113,218      | 70 ms         | 369 ms                   | 824 ms / 1,189 ms         |
| 407,585      | 243 ms        | 1,325 ms                 | 3,031 ms / 4,339 ms       |

The cost still grows with the number of rows skipped, because the BDE steps over them one by one (`MoveBy` is only
5-10% faster than `Next`; on an index the steps are slower). For deep paging, **page by key** instead: ask for the
rows after the last one shown, with a unique key field, and no skip is needed:

```sql
select * from DETAIL where KEYFIELD > :last order by KEYFIELD
```

with `RecsMax = 50` this takes 4 ms at any position, because the `TTable` goes straight to the key with `SetRange`.

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
