#!/usr/bin/env python3
"""Genera una tabella di prova dBase III con memo (SAMPLE.DBF + SAMPLE.DBT).

Solo libreria standard di Python 3, nessun dato reale: righe sintetiche, testo
ASCII (cosi' il risultato non dipende dal language driver del BDE).

Uso:  python make_sample_dbf.py [cartella_di_destinazione]
"""
import datetime
import struct
import sys
from pathlib import Path

ROWS = 200
BLOCK = 512

# (nome, tipo, lunghezza, decimali)
FIELDS = [
    ("ID",     "N", 10, 0),   # chiave univoca
    ("NAME",   "C", 30, 0),
    ("AMOUNT", "N", 12, 2),
    ("DUE",    "D", 8,  0),
    ("PAID",   "L", 1,  0),
    ("NOTES",  "M", 10, 0),
]


def build(folder: Path) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    rec_len = 1 + sum(f[2] for f in FIELDS)
    hdr_len = 32 + 32 * len(FIELDS) + 1
    today = datetime.date(2026, 1, 1)

    memo_blocks = bytearray(BLOCK)          # blocco 0 = intestazione DBT
    next_block = 1
    records = bytearray()

    for i in range(1, ROWS + 1):
        memo_ref = ""
        if i % 3 == 0:
            text = "".join(f"Line {n} of the memo of row {i}\r\n" for n in range(1, 4 + i % 5))
            data = text.encode("ascii") + b"\x1a\x1a"
            nblocks = (len(data) + BLOCK - 1) // BLOCK
            memo_blocks += data.ljust(nblocks * BLOCK, b"\x00")
            memo_ref = str(next_block)
            next_block += nblocks
        due = today + datetime.timedelta(days=i)
        values = [
            str(i).rjust(10),
            f"Customer {i:03d}".ljust(30),
            f"{i * 12.5:.2f}".rjust(12),
            due.strftime("%Y%m%d"),
            "T" if i % 2 == 0 else "F",
            memo_ref.rjust(10),
        ]
        records += b" " + "".join(values).encode("ascii")

    struct.pack_into("<I", memo_blocks, 0, next_block)   # prossimo blocco libero

    header = bytearray(32)
    header[0] = 0x83                                     # dBase III con memo
    header[1:4] = bytes([today.year - 1900, today.month, today.day])
    struct.pack_into("<I", header, 4, ROWS)
    struct.pack_into("<H", header, 8, hdr_len)
    struct.pack_into("<H", header, 10, rec_len)
    for name, ftype, length, dec in FIELDS:
        d = bytearray(32)
        d[0:len(name)] = name.encode("ascii")
        d[11] = ord(ftype)
        d[16] = length
        d[17] = dec
        header += d
    header += b"\x0d"

    (folder / "SAMPLE.DBF").write_bytes(bytes(header) + bytes(records) + b"\x1a")
    (folder / "SAMPLE.DBT").write_bytes(bytes(memo_blocks))
    print(f"Creati SAMPLE.DBF ({ROWS} righe) e SAMPLE.DBT in {folder}")


if __name__ == "__main__":
    build(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "Demos" / "Data")
