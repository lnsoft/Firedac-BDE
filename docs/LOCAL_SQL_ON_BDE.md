# FireDAC Local SQL on top of the BDE driver (experimental)

The BDE's own Local SQL is limited (see [LOCAL_SQL.md](LOCAL_SQL.md)). FireDAC has its own
*Local SQL* (`TFDLocalSQL`): any `TDataSet` is exposed as a SQLite **virtual table**, so you can
run full SQLite SQL (`CASE`, `COALESCE`, `LIMIT`, CTEs, window functions, views, joins across
several sources) on top of datasets opened through this driver.

```
TFDQuery (SQLite :memory: connection with TFDLocalSQL)
   └─ virtual tables  ←  OnGetDataSet  ←  TFDQuery on the BDE connection  →  TQuery  →  DBF / Paradox
```

No change to the driver is needed: a `TFDQuery` on the `BDE` driver is just a dataset.
The experiment lives in `Demos\LocalSQLTest.dpr` (built by `build.bat`).

## Minimal code

```pascal
uses FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteVDataSet, FireDAC.Stan.ExprFuncs;

procedure TDm.GetDS(ASender: TObject; const ASchemaName, AName: String;
  var ADataSet: TDataSet; var AOwned: Boolean);
var
  Q: TFDQuery;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := BdeConn;                       // DriverID=BDE
    Q.SQL.Text := 'select * from "' + FileFor(AName) + '"';   // e.g. "CUSTOMERS.DBF"
    Q.Open;
  except
    Q.Free;
    raise;
  end;
  ADataSet := Q;
  AOwned := True;                                  // FireDAC frees it
end;

// setup
LiteConn.DriverName := 'SQLite';
LiteConn.Params.Database := ':memory:';
LiteConn.Connected := True;
LocalSQL.Connection := LiteConn;
LocalSQL.OnGetDataSet := DM.GetDS;
LocalSQL.Active := True;

// then, on LiteConn:
//   select c.name, coalesce(sum(o.amount), 0) from a c left join b o on ... group by ... limit 10
```

## Rules learned

1. **Register each virtual table with `TFDQuery.Open`**, e.g. `select count(*) from a`.
   A first reference through `ExecSQLScalar` fails with FireDAC error -308 and leaves an unfinalized
   statement, so `LiteConn.Close` later fails ("unable to close due to unfinalized statements").
   Registering all virtual tables up front with `TFDQuery.Open` avoids both.
2. **`OnGetDataSet` is called once per table name per SQLite connection.** The dataset stays open
   and is shared by every reference to that name (an auto-join `a x join a y` works).
3. **The dataset is a snapshot.** Changes made by others (or directly on the BDE connection) are
   not seen until the sources are recreated (toggle `LocalSQL.Active`, or close the connection).
   Changes made *through* the virtual table are seen.
4. **Writing works:** an `UPDATE` on a virtual table reaches the DBF/Paradox file. Use a unique key
   in the `WHERE`.
5. **Nesting works:** sub-queries, CTEs, temporary views, and a Local SQL query registered as the source
   of another virtual table. Prefer sub-queries/views: they are planned as one statement.
6. **Free dataset-on-dataset sources yourself** (`AOwned := False`) and before closing the connection.
7. **Memo columns lose their trailing line breaks by default.** Reading a memo from the virtual table
   with a `TFDQuery` returned 172 characters instead of 174: `FormatOptions.StrsTrim` (default `True`)
   strips the trailing CR LF. SQLite itself holds the full text. Confirmed on a real dBase IV memo (62 vs 61 characters). Set `Query.FormatOptions.StrsTrim := False`
   **before** `Open` (changing it on an already prepared query has no effect) for queries that read memos.
   Setting it on the connection was not tested.
8. **Dates and booleans map correctly:** a dBase date column is seen as `Date` and a logical column as
   `Boolean`, and `WHERE date_field = :param` with a `ftDate` parameter finds the rows.

## Measurements (Delphi 13.2, Win32, one run, real tables on a local disk)

| Test | Result |
|---|---|
| `count(*)` of a Paradox table, 13,898 rows | 12 ms (BDE and Local SQL counts equal) |
| Join Paradox 13,898 rows x dBase 3,590 rows on one field | 3,385 rows: **FireDAC Local SQL 187 ms**, BDE native Local SQL 249 ms (same result) |
| Self-join of the 13,898-row table on its unique key | 124 ms |
| Self-join of a 3,590-row dBase IV table | 3,590 rows: FireDAC Local SQL 63 ms, BDE native 57 ms (same result) |
| Self-join on a non-unique field | 16.7 million pairs in 2.1 s |
| Selective `WHERE` on the main table + join | about 10 ms |

The self-join figures are far too fast for a full scan of the inner table for every outer row, so
the join lookups appear to be efficient; this is an inference from timings, not a documented
guarantee. A `WHERE` on the main table costs about one full scan of it.

## Not tested yet

Paradox memo/BLOB/date columns through virtual tables (memo, date and boolean were verified on a dBase III
sample only, with ASCII text), accented text in memos (the real memo tested contained UTF-8 XML, not accented text), concurrent users, very large tables,
other Delphi versions. Treat this feature as **experimental**.
