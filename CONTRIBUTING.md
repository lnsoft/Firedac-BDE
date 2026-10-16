# Contributing

Thanks for your interest! This is a small, unofficial driver; the most useful
contributions are **test results** and **bug reports with a reproducible case**.

## Reporting a problem

Open an issue and include:

- Delphi version and update level, Windows version, BDE version/`bdertl` package.
- Table type (dBase III/IV, Paradox version), whether it has memo/BLOB fields,
  whether other programs use the files at the same time.
- Connection parameters (alias or folder; **no passwords**).
- The exact exception text and, for access violations, the **Call Stack**.
- Preferably the output of `Demos\BDETest` on a synthetic table
  (`Tools/make_sample_dbf.py`). **Never attach real customer data.**

## Sending code

1. Fork and create a branch.
2. Keep the style of the existing units (FireDAC naming, `F` fields, `o`/`s`/`i` prefixes).
3. Run `BDETest` on both a DBF and a Paradox table (with key, text and memo fields) before
   and after your change, and paste the result in the pull request.
4. Don't add Embarcadero source or binaries (FireDAC, BDE, `FireDAC.inc`) to the repository.
5. Update `CHANGELOG.md` and, if the behaviour changes, the README.

## Ideas that would help

- Tests on other Delphi versions.
- Paradox with password, BLOB/OLE/graphic fields, AutoInc, other language drivers.
- A Win64 story is not possible with the BDE; alternatives are out of scope.
- English translation of source comments and test messages.
