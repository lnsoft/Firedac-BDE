Second release of **Firedac-BDE**: more control over how `TableCursor=True` reads tables, a fix for paging, and notes on a BDE bug that can look like a driver problem.

**Highlights**
- Fix: `FetchOptions.RecsMax` / `RecsSkip` no longer fail with *"Invalid use of keyword"*; paging is also much faster (407,585 rows skipped: 3,031 ms -> 243 ms).
- New runtime events `OnBDEIndexNeeded` and `OnBDESetRange`: the program chooses the index and sets the key range itself (text and date conditions included), or rejects a query. Without the events nothing changes.
- New public functions `BDEFindIndex`, `BDEIndexServesOrder` and `BDEExpressionFields`: find the index for equalities in any order, one range and the `ORDER BY`. The driver's own proposal is better too (`WHERE A = 1 AND B > 5` now picks the index on `(A, B)`).
- dBase expression indexes made of text fields (`ANNO+TIPODOC+NUMDOC`): the driver proposes them and calls `OnBDESetRange`, where a partial key can be built (measured: same rows as the `TQuery`, 4-10 times faster). The driver never applies its own `SetRange` to them, because the BDE returns no rows and no error for a partial key.
- New guide `docs/BDE_4GB_BUG.md` and optional unit `Demos/FixBDE4GbBug.pas` (Delphi Unicode, Win32) for the random *"Insufficient disk space"* error of the BDE.

**Requirements:** Delphi 13.2 (other versions untested), BDE installed, Win32.

**Known limits:** see the README ("Things to know (limitations)"). Not tested yet: password-protected Paradox, BLOB/OLE/AutoInc fields, the new events on Paradox tables, expression indexes with numeric fields or functions (the driver never proposes them), `#255` as the upper limit of a key with language drivers other than the one of the test table.
