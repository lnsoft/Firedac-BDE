program MakeSampleParadox;

{ Crea due tabelle di prova con il BDE (solo Win32, serve il BDE installato):
    SAMPLEPX.DB   Paradox, chiave primaria ID, campo memo NOTES
    SAMPLEDB.DBF  dBase IV, stessi campi (senza chiave primaria)
  Dati sintetici, nessun dato reale.

  Uso:  MakeSampleParadox [cartella]     (default: .\Data accanto all'exe)

  NOTA: questo programma non e' stato compilato ne' provato dall'autore. Se non
  funziona sul tuo BDE, usa Tools\make_sample_dbf.py per la tabella dBase e
  crea una tabella Paradox con il Database Desktop o con il tuo strumento. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, Data.DB, Bde.DBTables;

procedure CreateSample(const AFolder, AName: String; AType: TTableType);
var
  T: TTable;
  i: Integer;
begin
  T := TTable.Create(nil);
  try
    T.DatabaseName := AFolder;
    T.TableName := AName;
    T.TableType := AType;
    T.FieldDefs.Add('ID', ftInteger, 0, True);
    T.FieldDefs.Add('NAME', ftString, 30, False);
    T.FieldDefs.Add('AMOUNT', ftFloat, 0, False);
    T.FieldDefs.Add('DUE', ftDate, 0, False);
    T.FieldDefs.Add('PAID', ftBoolean, 0, False);
    T.FieldDefs.Add('NOTES', ftMemo, 0, False);
    if AType = ttParadox then
      T.IndexDefs.Add('', 'ID', [ixPrimary, ixUnique]);
    T.CreateTable;
    T.Open;
    for i := 1 to 200 do begin
      T.Append;
      T.FieldByName('ID').AsInteger := i;
      T.FieldByName('NAME').AsString := Format('Customer %.3d', [i]);
      T.FieldByName('AMOUNT').AsFloat := i * 12.5;
      T.FieldByName('DUE').AsDateTime := EncodeDate(2026, 1, 1) + i;
      T.FieldByName('PAID').AsBoolean := Odd(i);
      if i mod 3 = 0 then
        T.FieldByName('NOTES').AsString := Format('Memo of row %d', [i]);
      T.Post;
    end;
    T.Close;
    Writeln('Creata ', AName, ' in ', AFolder);
  finally
    T.Free;
  end;
end;

var
  sFolder: String;
begin
  try
    if ParamCount >= 1 then
      sFolder := ExpandFileName(ParamStr(1))
    else
      sFolder := ExtractFilePath(ParamStr(0)) + 'Data';
    ForceDirectories(sFolder);
    CreateSample(sFolder, 'SAMPLEPX.DB', ttParadox);
    CreateSample(sFolder, 'SAMPLEDB.DBF', ttDBase);
  except
    on E: Exception do begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
