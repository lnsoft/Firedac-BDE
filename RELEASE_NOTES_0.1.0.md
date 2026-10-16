First public release of **Firedac-BDE**: a real FireDAC physical driver (`DriverID=BDE`) that
reads and writes legacy BDE tables (dBase III/IV, Paradox 7+) with `TFDConnection`, `TFDQuery`,
`TFDTable`, transactions and metadata, without the BDE data-access components in your forms.

**Highlights**
- Reading and writing of DBF and Paradox, memo/BLOB included; record locks mapped to `ekRecordLocked`.
- Local SQL aware: reserved words and escape functions (`UCASE`, `SUBSTRING`, `CONVERT`, `YEAR`, ...).
- Private temp folder per connection; `LockRetry`, `NetFileDir`, `PrivateDir` parameters.
- Packages for Delphi 13.2, `build.bat` / `test.bat`, console test program and sample data.

**Requirements:** Delphi 13.2 (other versions untested), BDE installed, Win32.

**Known limits:** see the README ("Things to know (limitations)"). Password-protected Paradox, BLOB/OLE/AutoInc
fields and other Delphi versions are not tested yet; feedback welcome (issue template: *Test report*).
