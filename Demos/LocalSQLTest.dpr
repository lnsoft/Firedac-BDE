program LocalSQLTest;

{ Esperimento: FireDAC Local SQL (tabelle virtuali SQLite) sopra il driver BDE.

  Uso:
    LocalSQLTest <cartella|alias> <TABELLA_A.DB|DBF> <TABELLA_B.DB|DBF> <chiave A> <chiave B>
                  [campo testo di A | -] [campo join A] [campo join B]
                  [campo memo | -] [campo data | -] [campo booleano | -] [safe]

  chiave A / chiave B: campi UNICI (usati per WHERE e UPDATE); i campi di join
  (7o e 8o parametro) sono quelli del join a.<join A> = b.<join B>; se omessi
  si usano le chiavi. 'safe' (in qualsiasi posizione) registra le tabelle virtuali in anticipo;
  '-' come campo testo = nessun test di UPDATE.

  Le tabelle A e B possono anche coincidere (auto-join). Nelle query SQL
  compaiono come "a" e "b". Un dataset BDE NUOVO e DEDICATO viene creato
  dall'evento OnGetDataSet di TFDLocalSQL ogni volta che SQLite lo richiede.

  Con il campo testo (6o parametro) viene provato anche un UPDATE sulla tabella
  virtuale: eseguirlo SOLO su una COPIA dei dati (il valore viene ripristinato).

  Esempio (dati di esempio):
    LocalSQLTest .\Data SAMPLE.DBF SAMPLE.DBF ID ID NAME ID ID NOTES DUE PAID safe }

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.Classes, System.Diagnostics, System.Variants,
  Data.DB,
  FireDAC.Stan.Intf, FireDAC.Stan.Option, FireDAC.Stan.Error, FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Stan.Param, FireDAC.Stan.ExprFuncs,
  FireDAC.DatS, FireDAC.Phys.Intf, FireDAC.Phys, FireDAC.DApt.Intf, FireDAC.DApt,
  FireDAC.UI.Intf, FireDAC.ConsoleUI.Wait,
  FireDAC.Comp.Client, FireDAC.Comp.DataSet,
  FireDAC.Phys.SQLite, FireDAC.Phys.SQLiteDef, FireDAC.Phys.SQLiteVDataSet,
  FireDAC.Phys.BDEDef in '..\Source\FireDAC.Phys.BDEDef.pas',
  FireDAC.Phys.BDEMeta in '..\Source\FireDAC.Phys.BDEMeta.pas',
  FireDAC.Phys.BDE in '..\Source\FireDAC.Phys.BDE.pas';

type
  THelper = class
    procedure GetDS(ASender: TObject; const ASchemaName, AName: String;
      var ADataSet: TDataSet; var AOwned: Boolean);
  end;

var
  BdeConn, LiteConn: TFDConnection;
  LocalSQL: TFDLocalSQL;
  Helper: THelper;
  Folder, TabA, TabB, KeyA, KeyB, TextA: String;
  KeyVal: Variant;
  GetCalls, Retries: Integer;
  VaQuery: TFDQuery;
  SafeMode: Boolean;
  JoinA, JoinB: String;   // campi di join (default = chiavi)
  MemoF, DateF, BoolF: String;   // campi per la prova dei tipi
  GetNames: String;
  FailCount: Integer;

var
  Args: TArray<String>;

procedure ParseArgs;
var
  i: Integer;
begin
  SafeMode := False;
  SetLength(Args, 0);
  for i := 1 to ParamCount do
    if SameText(ParamStr(i), 'safe') then
      SafeMode := True
    else begin
      SetLength(Args, Length(Args) + 1);
      Args[High(Args)] := ParamStr(i);
    end;
end;

function Arg(I: Integer): String;
begin
  Result := Args[I - 1];
end;

function ArgCount: Integer;
begin
  Result := Length(Args);
end;

function QuoteTab(const AName: String): String;
var
  i: Integer;
begin
  Result := AName;
  for i := 1 to Length(AName) do
    if not CharInSet(AName[i], ['a'..'z', 'A'..'Z', '0'..'9', '_']) then begin
      Result := '"' + AName + '"';
      Break;
    end;
end;

procedure THelper.GetDS(ASender: TObject; const ASchemaName, AName: String;
  var ADataSet: TDataSet; var AOwned: Boolean);
var
  Q: TFDQuery;
begin
  Inc(GetCalls);
  GetNames := GetNames + AName + ' ';
  Q := TFDQuery.Create(nil);
  try
    if SameText(AName, 'a') then begin
      Q.Connection := BdeConn;
      Q.SQL.Text := 'select * from ' + QuoteTab(TabA);
    end
    else if SameText(AName, 'b') then begin
      Q.Connection := BdeConn;
      Q.SQL.Text := 'select * from ' + QuoteTab(TabB);
    end
    else if SameText(AName, 'va') then begin
      // un dataset che a sua volta e' una query Local SQL (dataset su dataset)
      Q.Connection := LiteConn;
      Q.SQL.Text := 'select ' + KeyA + ' as ' + KeyA + ' from a';
      VaQuery := Q;   // lo liberiamo noi, prima di chiudere la connessione
    end
    else begin
      Q.Free;
      Exit;
    end;
    Q.Open;
  except
    Q.Free;
    raise;
  end;
  ADataSet := Q;
  AOwned := Q <> VaQuery;
end;

procedure Run(const AName: String; AProc: TProc);
var
  sw: TStopwatch;
begin
  Write(AName, ' ... ');
  GetCalls := 0;
  Retries := 0;
  GetNames := '';
  sw := TStopwatch.StartNew;
  try
    AProc();
    Writeln('OK  [', sw.ElapsedMilliseconds, ' ms, OnGetDataSet x', GetCalls,
      ': ', GetNames, ', retry=', Retries, ']');
  except
    on E: Exception do begin
      Inc(FailCount);
      Writeln('FALLITO  [', sw.ElapsedMilliseconds, ' ms, OnGetDataSet x', GetCalls, ']');
      Writeln('    ', E.ClassName, ': ', E.Message);
    end;
  end;
end;

function Lite(const ASql: String; const AParams: array of Variant): Variant;
begin
  try
    Result := LiteConn.ExecSQLScalar(ASql, AParams);
  except
    on E: EFDException do
      if E.FDCode = 308 then begin
        // prima richiesta di una tabella virtuale nuova: riprova una volta
        Inc(Retries);
        Result := LiteConn.ExecSQLScalar(ASql, AParams);
      end
      else
        raise;
  end;
end;

function JoinOn: String;
begin
  Result := 'a join b on a.' + JoinA + ' = b.' + JoinB;
end;

procedure WarmUp(const AName: String);
var
  Q: TFDQuery;
begin
  // registra la tabella virtuale con TFDQuery.Open (evita il -308 di ExecSQLScalar)
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := LiteConn;
    Q.Open('select count(*) from ' + AName);
  finally
    Q.Free;
  end;
end;

procedure TestFirstUseOpen;
var
  Q: TFDQuery;
begin
  // prima richiesta di 'a' con TFDQuery.Open (non ExecSQLScalar)
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := LiteConn;
    Q.Open('select count(*) from a');
    Write('(righe=', Q.Fields[0].AsString, ') ');
  finally
    Q.Free;
  end;
end;

procedure TestFirstUseScalarNoRetry;
begin
  // prima richiesta di 'b' con ExecSQLScalar SENZA riprova
  Write('(righe=', VarToStr(LiteConn.ExecSQLScalar('select count(*) from b')), ') ');
end;

procedure TestSameNameTwice;
var
  n1, n2: Variant;
begin
  // la stessa tabella virtuale due volte nella stessa query (stesso dataset?)
  n1 := Lite('select count(*) from a', []);
  n2 := Lite('select count(*) from a x join a y on x.' + KeyA + ' = y.' + KeyA, []);
  Write('(a=', VarToStr(n1), ' a x join a y=', VarToStr(n2), ') ');
  if n1 <> n2 then
    raise Exception.Create('Auto-join sulla stessa tabella virtuale: conteggio diverso');
end;

procedure TestRefresh;
var
  vOld: Variant;
  sTab, sWhere, sSee: String;
begin
  if TextA = '' then begin
    Write('(saltato: serve il campo testo) ');
    Exit;
  end;
  sTab := QuoteTab(TabA);
  sWhere := ' where ' + KeyA + ' = :k';
  vOld := BdeConn.ExecSQLScalar('select ' + TextA + ' from ' + sTab + sWhere, [KeyVal]);
  try
    BdeConn.ExecSQL('update ' + sTab + ' set ' + TextA + ' = ''REFRESH1''' + sWhere, [KeyVal]);
    sSee := VarToStr(Lite('select ' + TextA + ' from a' + sWhere, [KeyVal]));
    Write('(modifica fatta fuori dal Local SQL, letta dentro: "', sSee, '") ');
    if sSee <> 'REFRESH1' then
      Write('(NON vede la modifica: dataset gia'' aperto) ');
  finally
    BdeConn.ExecSQL('update ' + sTab + ' set ' + TextA + ' = :v' + sWhere,
      [VarToStr(vOld), KeyVal]);
  end;
end;

procedure TestBaseCount;
var
  nBde, nLite: Variant;
begin
  nBde := BdeConn.ExecSQLScalar('select count(*) from ' + QuoteTab(TabA));
  nLite := Lite('select count(*) from a', []);
  Write('(BDE=', VarToStr(nBde), ' LocalSQL=', VarToStr(nLite), ') ');
  if nBde <> nLite then
    raise Exception.Create('Conteggi diversi');
end;

procedure TestJoinAll;
begin
  Write('(righe=', VarToStr(Lite('select count(*) from ' + JoinOn, [])), ') ');
end;

procedure TestNativeJoin;
var
  sw: TStopwatch;
  nNative, nLite: Variant;
  msNative, msLite: Int64;
begin
  // stesso join eseguito dal Local SQL nativo del BDE e dal Local SQL di FireDAC
  sw := TStopwatch.StartNew;
  nNative := BdeConn.ExecSQLScalar('select count(*) from ' + QuoteTab(TabA) + ' a join ' +
    QuoteTab(TabB) + ' b on a.' + JoinA + ' = b.' + JoinB);
  msNative := sw.ElapsedMilliseconds;
  sw := TStopwatch.StartNew;
  nLite := Lite('select count(*) from ' + JoinOn, []);
  msLite := sw.ElapsedMilliseconds;
  Write('(BDE nativo: ', VarToStr(nNative), ' righe in ', msNative, ' ms; ',
    'FireDAC Local SQL: ', VarToStr(nLite), ' righe in ', msLite, ' ms) ');
  if nNative <> nLite then
    raise Exception.Create('Risultato diverso tra join nativo BDE e Local SQL FireDAC');
end;

procedure TestJoinWhere;
begin
  Write('(righe=', VarToStr(Lite('select count(*) from ' + JoinOn +
    ' where a.' + KeyA + ' = :k', [KeyVal])), ') ');
end;

procedure TestCaseCoalesceLimit;
var
  Q: TFDQuery;
  n: Integer;
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := LiteConn;
    Q.Open('select case when a.' + JoinA + ' is null then ''n'' else ''y'' end as f, ' +
      'coalesce(cast(b.' + JoinB + ' as text), ''-'') as kb ' +
      'from a left join b on a.' + JoinA + ' = b.' + JoinB + ' limit 5');
    n := 0;
    while not Q.Eof do begin
      Inc(n);
      Q.Next;
    end;
    Write('(righe=', n, ') ');
    if (n < 1) or (n > 5) then
      raise Exception.Create('LIMIT non rispettato');
  finally
    Q.Free;
  end;
end;

procedure TestSubquery;
begin
  Write('(righe=', VarToStr(Lite('select count(*) from (select a.' + KeyA +
    ' as k from ' + JoinOn + ') x where x.k = :k', [KeyVal])), ') ');
end;

procedure TestTempView;
begin
  LiteConn.ExecSQL('drop view if exists temp.v1');
  LiteConn.ExecSQL('create temp view v1 as select a.' + KeyA + ' as k, b.' + KeyB +
    ' as kb from ' + JoinOn);
  try
    Write('(righe=', VarToStr(Lite('select count(*) from v1 where k = :k', [KeyVal])), ') ');
  finally
    LiteConn.ExecSQL('drop view if exists temp.v1');
  end;
end;

procedure TestDatasetOnDataset;
begin
  Write('(righe=', VarToStr(Lite('select count(*) from va where ' + KeyA + ' = :k',
    [KeyVal])), ') ');
end;

procedure TestRepeat;
var
  i: Integer;
begin
  for i := 1 to 20 do begin
    Lite('select count(*) from ' + JoinOn + ' where a.' + KeyA + ' = :k', [KeyVal]);
    TestTempView;
  end;
  Write('(20 giri ok) ');
end;

procedure TestTypes;
var
  QB, QL, QD: TFDQuery;
  sList: String;
  vKey: Variant;
  iScan: Integer;
  bFound: Boolean;
  sMemoB, sMemoL: String;
  dB, dL: TDateTime;
  bB, bL: Boolean;
  nHit: Integer;
  sInfo: String;
  iDiff: Integer;
begin
  if (MemoF = '') and (DateF = '') and (BoolF = '') then begin
    Write('(saltato: indica memo/data/booleano come parametri 9-11) ');
    Exit;
  end;
  sList := KeyA;
  if MemoF <> '' then sList := sList + ', ' + MemoF;
  if DateF <> '' then sList := sList + ', ' + DateF;
  if BoolF <> '' then sList := sList + ', ' + BoolF;
  QB := TFDQuery.Create(nil);
  QL := TFDQuery.Create(nil);
  QD := TFDQuery.Create(nil);
  try
    // 1) riga di riferimento letta direttamente dal BDE (prima con memo valorizzato)
    QB.Connection := BdeConn;
    QB.Open('select ' + sList + ' from ' + QuoteTab(TabA));
    bFound := False;
    iScan := 0;
    while (not QB.Eof) and (iScan < 20000) do begin
      if (MemoF = '') or (QB.FieldByName(MemoF).AsString <> '') then begin
        bFound := True;
        Break;
      end;
      Inc(iScan);
      QB.Next;
    end;
    if not bFound then
      raise Exception.Create('Nessuna riga con memo valorizzato nelle prime 20000');
    vKey := QB.FieldByName(KeyA).Value;
    sInfo := '(riga ' + VarToStr(vKey) + ') ';
    // 2) stessa riga letta attraverso la tabella virtuale
    QL.Connection := LiteConn;
    QL.Open('select ' + sList + ' from a where ' + KeyA + ' = :k', [vKey]);
    if QL.RecordCount < 1 then
      raise Exception.Create('Riga non trovata nella tabella virtuale');
    Write(sInfo);
    if MemoF <> '' then begin
      sMemoB := QB.FieldByName(MemoF).AsString;
      sMemoL := QL.FieldByName(MemoF).AsString;
      Write('(memo ', Length(sMemoB), ' car., tipo ',
        FieldTypeNames[QL.FieldByName(MemoF).DataType], ', uguale=',
        BoolToStr(sMemoB = sMemoL, True), ') ');
      if sMemoB <> sMemoL then begin
        iDiff := 1;
        while (iDiff <= Length(sMemoB)) and (iDiff <= Length(sMemoL)) and
              (sMemoB[iDiff] = sMemoL[iDiff]) do
          Inc(iDiff);
        Writeln;
        Writeln('    DIAGNOSI memo: BDE=', Length(sMemoB), ' car., virtuale=', Length(sMemoL),
          ' car., primo carattere diverso alla posizione ', iDiff);
        Writeln('    BDE      : "', Copy(sMemoB, 1, 60), '"');
        Writeln('    virtuale : "', Copy(sMemoL, 1, 60), '"');
        if iDiff <= Length(sMemoB) then
          Writeln('    codice BDE=', Ord(sMemoB[iDiff]));
        if iDiff <= Length(sMemoL) then
          Writeln('    codice virtuale=', Ord(sMemoL[iDiff]));
        try
          Writeln('    SQLite: typeof=', VarToStr(Lite('select typeof(' + MemoF +
            ') from a where ' + KeyA + ' = :k', [vKey])), ' length=',
            VarToStr(Lite('select length(' + MemoF + ') from a where ' + KeyA +
            ' = :k', [vKey])));
        except
          on E: Exception do Writeln('    SQLite typeof/length: ', E.Message);
        end;
        // misure indipendenti: coda del testo in SQLite (esadecimale) e lettura scalare
        try
          Writeln('    SQLite, ultimi 4 caratteri in esadecimale: ',
            VarToStr(Lite('select hex(substr(' + MemoF + ', length(' + MemoF +
            ') - 3)) from a where ' + KeyA + ' = :k', [vKey])));
          Writeln('    lettura scalare (ExecSQLScalar): ',
            Length(VarToStr(Lite('select ' + MemoF + ' from a where ' + KeyA +
            ' = :k', [vKey]))), ' car.');
        except
          on E: Exception do Writeln('    misure SQLite: ', E.Message);
        end;
        // ipotesi: FormatOptions.StrsTrim (default True) elimina i fine riga finali;
        // query NUOVA con l'opzione impostata PRIMA di Open
        QD.Close;
        QD.Connection := LiteConn;
        QD.FormatOptions.StrsTrim := False;
        QD.Open('select ' + MemoF + ' from a where ' + KeyA + ' = :k', [vKey]);
        sMemoL := QD.Fields[0].AsString;
        Writeln('    query nuova con StrsTrim=False: ', Length(sMemoL), ' car.');
        if sMemoB = sMemoL then
          Writeln('    CAUSA: FormatOptions.StrsTrim=True (default) elimina i fine riga finali del memo')
        else
          raise Exception.Create('Memo diverso attraverso la tabella virtuale anche con StrsTrim=False');
      end;
    end;
    if DateF <> '' then begin
      if QB.FieldByName(DateF).IsNull then
        Write('(data nulla nel BDE) ')
      else begin
        dB := QB.FieldByName(DateF).AsDateTime;
        dL := QL.FieldByName(DateF).AsDateTime;
        Write('(data BDE=', DateTimeToStr(dB), ' virtuale=', DateTimeToStr(dL),
          ', tipo ', FieldTypeNames[QL.FieldByName(DateF).DataType], ') ');
        if Abs(dB - dL) > 1 / 86400 then
          raise Exception.Create('Data diversa attraverso la tabella virtuale');
        // filtro con parametro data
        QD.Connection := LiteConn;
        QD.SQL.Text := 'select count(*) from a where ' + DateF + ' = :d';
        QD.ParamByName('d').DataType := ftDate;
        QD.ParamByName('d').AsDate := dB;
        QD.Open;
        nHit := QD.Fields[0].AsInteger;
        Write('(WHERE data = parametro: ', nHit, ' righe) ');
        if nHit < 1 then
          raise Exception.Create('Il filtro su data con parametro non trova nulla');
      end;
    end;
    if BoolF <> '' then begin
      if QB.FieldByName(BoolF).IsNull then
        Write('(booleano nullo nel BDE) ')
      else begin
        bB := QB.FieldByName(BoolF).AsBoolean;
        bL := QL.FieldByName(BoolF).AsBoolean;
        Write('(booleano BDE=', BoolToStr(bB, True), ' virtuale=', BoolToStr(bL, True),
          ', tipo ', FieldTypeNames[QL.FieldByName(BoolF).DataType], ') ');
        if bB <> bL then
          raise Exception.Create('Booleano diverso attraverso la tabella virtuale');
      end;
    end;
  finally
    QD.Free;
    QL.Free;
    QB.Free;
  end;
end;

procedure TestUpdate;
var
  vOld, vNow: Variant;
  sTab, sWhere: String;
begin
  if TextA = '' then begin
    Write('(saltato: serve il campo testo) ');
    Exit;
  end;
  sTab := QuoteTab(TabA);
  sWhere := ' where ' + KeyA + ' = :k';
  vOld := BdeConn.ExecSQLScalar('select ' + TextA + ' from ' + sTab + sWhere, [KeyVal]);
  try
    LiteConn.ExecSQL('update a set ' + TextA + ' = ''ZZTEST'' where ' + KeyA + ' = :k',
      [KeyVal]);
    vNow := BdeConn.ExecSQLScalar('select ' + TextA + ' from ' + sTab + sWhere, [KeyVal]);
    Write('(dopo update virtuale, letto dal BDE: "', VarToStr(vNow), '") ');
    if VarToStr(vNow) <> 'ZZTEST' then
      raise Exception.Create('L''UPDATE non e'' arrivato al BDE');
  finally
    BdeConn.ExecSQL('update ' + sTab + ' set ' + TextA + ' = :v' + sWhere,
      [VarToStr(vOld), KeyVal]);
  end;
end;

begin
  ParseArgs;
  if ArgCount < 5 then begin
    Writeln('Uso: LocalSQLTest <cartella|alias> <TABELLA_A> <TABELLA_B> <chiave A> <chiave B> [campo testo A]');
    Halt(1);
  end;
  Folder := Arg(1);
  TabA := Arg(2);
  TabB := Arg(3);
  KeyA := Arg(4);
  KeyB := Arg(5);
  TextA := '';
  if ArgCount >= 6 then
    TextA := Arg(6);
  if TextA = '-' then
    TextA := '';
  JoinA := KeyA;
  JoinB := KeyB;
  if ArgCount >= 8 then begin
    JoinA := Arg(7);
    JoinB := Arg(8);
  end;
  MemoF := '';
  DateF := '';
  BoolF := '';
  if ArgCount >= 9 then MemoF := Arg(9);
  if ArgCount >= 10 then DateF := Arg(10);
  if ArgCount >= 11 then BoolF := Arg(11);
  if MemoF = '-' then MemoF := '';
  if DateF = '-' then DateF := '';
  if BoolF = '-' then BoolF := '';
  FailCount := 0;
  VaQuery := nil;
  KeyVal := Null;

  Helper := THelper.Create;
  BdeConn := TFDConnection.Create(nil);
  LiteConn := TFDConnection.Create(nil);
  LocalSQL := TFDLocalSQL.Create(nil);
  try
    BdeConn.DriverName := 'BDE';
    BdeConn.LoginPrompt := False;
    BdeConn.Params.Database := Folder;
    BdeConn.Connected := True;

    LiteConn.DriverName := 'SQLite';
    LiteConn.LoginPrompt := False;
    LiteConn.Params.Database := ':memory:';
    LiteConn.Connected := True;

    LocalSQL.Connection := LiteConn;
    LocalSQL.OnGetDataSet := Helper.GetDS;
    LocalSQL.Active := True;

    // prima riga con chiave valorizzata (la chiave della prima riga puo' essere vuota)
    try
      KeyVal := BdeConn.ExecSQLScalar('select ' + KeyA + ' from ' + QuoteTab(TabA) +
        ' where ' + KeyA + ' is not null');
    except
      KeyVal := BdeConn.ExecSQLScalar('select ' + KeyA + ' from ' + QuoteTab(TabA));
    end;
    Writeln('=== Local SQL sopra BDE: ', TabA, ' / ', TabB, ' (chiave di prova: ',
      VarToStr(KeyVal), '; join a.', JoinA, ' = b.', JoinB, ') ===');
    Writeln('righe: a=', VarToStr(BdeConn.ExecSQLScalar('select count(*) from ' + QuoteTab(TabA))),
      ' b=', VarToStr(BdeConn.ExecSQLScalar('select count(*) from ' + QuoteTab(TabB))));

    if SafeMode then begin
      // nessun comando fallito: tutte le tabelle virtuali registrate con TFDQuery.Open
      Writeln('(modo safe: registrazione preventiva di a, b, va con TFDQuery.Open)');
      WarmUp('a');
      WarmUp('b');
      WarmUp('va');
    end
    else begin
      Run('Prima apertura di a con TFDQuery.Open', TestFirstUseOpen);
      Run('Prima apertura di b con ExecSQLScalar (senza riprova)', TestFirstUseScalarNoRetry);
    end;
    Run('Conteggio tabella virtuale a', TestBaseCount);
    Run('Stessa tabella virtuale due volte (auto-join)', TestSameNameTwice);
    Run('Join a-b (tutte le righe)', TestJoinAll);
    Run('Confronto con il join nativo del BDE', TestNativeJoin);
    Run('Join a-b con WHERE selettivo', TestJoinWhere);
    Run('CASE / COALESCE / LIMIT', TestCaseCoalesceLimit);
    Run('Sottoquery', TestSubquery);
    Run('Vista temporanea', TestTempView);
    Run('Dataset su dataset (Local SQL come sorgente)', TestDatasetOnDataset);
    Run('Ripetizione 20 volte', TestRepeat);
    Run('Memo, data e booleano attraverso la tabella virtuale', TestTypes);
    Run('UPDATE sulla tabella virtuale', TestUpdate);
    Run('Modifica esterna visibile?', TestRefresh);

    Write('Chiusura: ');
    if VaQuery <> nil then
      try
        VaQuery.Close;
        FreeAndNil(VaQuery);
        Write('VaQuery liberata; ');
      except
        on E: Exception do Write('ERRORE liberando VaQuery: ', E.Message, '; ');
      end;
    try
      LocalSQL.Active := False;
      Write('LocalSQL.Active=False ok; ');
    except
      on E: Exception do Write('ERRORE in LocalSQL.Active=False: ', E.Message, '; ');
    end;
    try
      LiteConn.Close;
      Write('LiteConn.Close ok; ');
    except
      on E: Exception do Write('ERRORE in LiteConn.Close: ', E.Message, '; ');
    end;
    Writeln;
  finally
    try LocalSQL.Free; except on E: Exception do Writeln('ERRORE LocalSQL.Free: ', E.Message); end;
    try LiteConn.Free; except on E: Exception do Writeln('ERRORE LiteConn.Free: ', E.Message); end;
    try BdeConn.Free; except on E: Exception do Writeln('ERRORE BdeConn.Free: ', E.Message); end;
    Helper.Free;
  end;

  Writeln;
  Writeln('Test falliti: ', FailCount);
  Readln;
end.
