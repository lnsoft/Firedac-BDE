{*******************************************************}
{  FireDAC BDE driver (non ufficiale) - parametri       }
{  Modello: FireDAC.Phys.SQLiteDef / ODBCDef            }
{*******************************************************}
{$I FireDAC.inc}

unit FireDAC.Phys.BDEDef;

interface

uses
  System.SysUtils, System.Classes, Data.DB, FireDAC.Stan.Intf, FireDAC.Comp.Client;

const
  S_FD_BDEId = 'BDE';

  // Parametri specifici del driver BDE
  S_FD_ConnParam_BDE_BDEDriver = 'BDEDriver';   // default STANDARD (DBF + Paradox)
  S_FD_ConnParam_BDE_NetFileDir = 'NetFileDir'; // dir di PDOXUSRS.NET (Paradox condiviso)
  S_FD_ConnParam_BDE_PrivateDir = 'PrivateDir'; // dir temporanea per sessione
  S_FD_ConnParam_BDE_LockRetry = 'LockRetry';   // secondi di attesa su record bloccato (BDE: ~6)
  S_FD_ConnParam_BDE_TableCursor = 'TableCursor'; // True = select semplici (select * from TAB) con cursore TTable

  // nome con cui l'evento OnBDEIndexNeeded indica l'indice primario di una tabella Paradox
  // (che nel BDE ha nome vuoto)
  S_BDE_PrimaryIndex = '(primary)';

type
  // Evento OnBDEIndexNeeded (solo con TableCursor=True). Il driver lo chiama in preparazione
  // di una SELECT su una sola tabella quando serve un indice:
  //   ATableName  tabella del FROM (senza virgolette)
  //   AFieldNames campi richiesti, separati da ';': i campi dell'ORDER BY, oppure, se manca
  //               l'ORDER BY, i campi del WHERE (condizioni semplici con AND)
  //   ASQL        testo della SELECT
  //   ADescending True se l'ORDER BY e' discendente
  //   AIndexName  in ingresso: indice proposto dal driver ('' se non ne ha uno: caso non gestito
  //               dal driver, ad esempio campi testo o data nel WHERE, o ORDER BY DESC);
  //               in uscita: indice da usare (S_BDE_PrimaryIndex = indice primario Paradox)
  //   AAccept     in ingresso True se c'e' una proposta, altrimenti False: per prendere in carico
  //               la query bisogna impostarlo a True. A False la query va al TQuery.
  // Se AAccept e' False oppure AIndexName e' vuoto, la query va al TQuery.
  TBDEIndexNeededEvent = procedure(Sender: TObject; const ATableName, AFieldNames,
    ASQL: String; ADescending: Boolean; var AIndexName: String;
    var AAccept: Boolean) of object;

  // Condizione del WHERE passata a OnBDESetRange
  TBDECondition = record
    Field: String;
    Op: String;       // '=', '>', '>=', '<', '<='
    Value: Variant;   // valore del parametro (Null se NULL), numero o testo scritto nella SQL
  end;

  // Evento OnBDESetRange (solo con TableCursor=True). Chiamato all'apertura di una SELECT con
  // WHERE servita da una TTable, DOPO l'apertura della tabella sull'indice AIndexName e PRIMA
  // del SetRange del driver. ADataSet e' la TTable (TTable(ADataSet).SetRangeStart ... ApplyRange).
  // AHandled in ingresso False: se lo si porta a True il driver non fa altro (il programma
  // risponde che l'intervallo sia equivalente al WHERE); se resta False vale il comportamento
  // standard (SetRange numerico del driver, oppure TQuery se le condizioni non sono numeriche).
  TBDESetRangeEvent = procedure(Sender: TObject; ADataSet: TDataSet;
    const AIndexName: String; const AConditions: TArray<TBDECondition>;
    var AHandled: Boolean) of object;

  // Implementata dalla connessione fisica del driver (vedi TFDConnectionBDEHelper)
  IFDPhysBDEHooks = interface
    ['{6B1E1F4A-3C52-4C0D-9E1B-5F3A7C2D8E91}']
    function GetOnIndexNeeded: TBDEIndexNeededEvent;
    procedure SetOnIndexNeeded(const AValue: TBDEIndexNeededEvent);
    function GetOnSetRange: TBDESetRangeEvent;
    procedure SetOnSetRange(const AValue: TBDESetRangeEvent);
    property OnIndexNeeded: TBDEIndexNeededEvent read GetOnIndexNeeded write SetOnIndexNeeded;
    property OnSetRange: TBDESetRangeEvent read GetOnSetRange write SetOnSetRange;
  end;

  // FDConnection1.OnBDEIndexNeeded := ...   (da assegnare DOPO la connessione, ad esempio
  // in AfterConnect: la connessione fisica nasce a ogni Connected := True)
  TFDConnectionBDEHelper = class helper for TFDCustomConnection
  private
    function GetOnBDEIndexNeeded: TBDEIndexNeededEvent;
    procedure SetOnBDEIndexNeeded(const AValue: TBDEIndexNeededEvent);
    function GetOnBDESetRange: TBDESetRangeEvent;
    procedure SetOnBDESetRange(const AValue: TBDESetRangeEvent);
  public
    property OnBDEIndexNeeded: TBDEIndexNeededEvent
      read GetOnBDEIndexNeeded write SetOnBDEIndexNeeded;
    property OnBDESetRange: TBDESetRangeEvent
      read GetOnBDESetRange write SetOnBDESetRange;
  end;

type
  // Esito di BDEFindIndex
  //   ilNone    nessun indice utile
  //   ilCovers  l'indice rispetta l'ordinamento richiesto e ha come primi campi quelli del WHERE,
  //             ma le condizioni non sono servibili da un SetRange (uguaglianze poi intervallo)
  //   ilFull    l'indice serve tutta la richiesta: uguaglianze sui primi campi (in qualunque
  //             ordine), al piu' un intervallo sul campo successivo, poi l'ordinamento
  TBDEIndexLevel = (ilNone, ilCovers, ilFull);

  TBDEIndexMatch = record
    IndexName: String;         // nome per OnBDEIndexNeeded (S_BDE_PrimaryIndex = primario Paradox)
    Fields: TArray<String>;    // tutti i campi dell'indice
    KeyFields: Integer;        // primi campi usati da uguaglianze e intervallo (ilFull)
    Level: TBDEIndexLevel;
  end;

// Campi di un indice (da TIndexDef.Fields, separati da ';')
function BDEIndexFieldList(ADef: TIndexDef): TArray<String>;

// True se l'indice (a campi, non espressione) restituisce le righe nell'ordine AOrderBy,
// sapendo che i campi AEquals hanno un valore costante (WHERE campo = valore): i campi
// costanti in testa all'indice si possono saltare. Il verso non e' controllato.
function BDEIndexServesOrder(ADef: TIndexDef; const AEquals, AOrderBy: array of String): Boolean;

// Cerca tra gli indici semplici (campi; niente espressioni ne' maiuscole/minuscole indifferenti)
// del verso richiesto quello che serve la richiesta. Equivale a provare tutte le permutazioni
// dei campi del WHERE, senza enumerarle: per ogni indice si scorrono i suoi primi campi.
//   AEquals   campi con condizione '=' (in qualunque ordine)
//   ARanges   campo con condizioni >, >=, <, <= (al piu' uno per ilFull)
//   AOrderBy  campi dell'ORDER BY (l'ordine conta)
// Preferisce il primo indice ilFull; altrimenti il primo ilCovers.
function BDEFindIndex(AIndexDefs: TIndexDefs; const AEquals, ARanges, AOrderBy: array of String;
  ADescending: Boolean; out AMatch: TBDEIndexMatch): Boolean; overload;

// Solo un elenco di campi: AAnyOrder True = l'indice ha come primi campi quelli dell'elenco in
// qualunque ordine (tutte le permutazioni); False = nello stesso ordine dell'elenco.
// Il risultato e' ilFull.
function BDEFindIndex(AIndexDefs: TIndexDefs; const AFields: array of String;
  ADescending, AAnyOrder: Boolean; out AMatch: TBDEIndexMatch): Boolean; overload;

var
  // diagnostica (test): numero di aperture fatte con il cursore TTable (TableCursor=True)
  BDEStatTableCursorOpens: Integer = 0;
  // diagnostica (test): testi delle SELECT che TableCursor non ha riconosciuto (max ~4000 caratteri)
  BDEStatRejectedSelects: String = '';
  // diagnostica (test): ultimo testo SQL passato al TQuery del BDE
  BDEStatLastSQL: String = '';

type
  TFDPhysBDEConnectionDefParams = class(TFDConnectionDefParams)
  private
    function GetDriverID: String;
    procedure SetDriverID(const AValue: String);
    function GetBDEDriver: String;
    procedure SetBDEDriver(const AValue: String);
    function GetNetFileDir: String;
    procedure SetNetFileDir(const AValue: String);
    function GetPrivateDir: String;
    procedure SetPrivateDir(const AValue: String);
    function GetLockRetry: Integer;
    procedure SetLockRetry(const AValue: Integer);
    function GetTableCursor: Boolean;
    procedure SetTableCursor(const AValue: Boolean);
  published
    property DriverID: String read GetDriverID write SetDriverID stored False;
    // Database (ereditato): alias BDE oppure percorso della cartella con DBF/DB
    property BDEDriver: String read GetBDEDriver write SetBDEDriver stored False;
    property NetFileDir: String read GetNetFileDir write SetNetFileDir stored False;
    property PrivateDir: String read GetPrivateDir write SetPrivateDir stored False;
    // -1 = non impostato (default del BDE); 0 = nessuna attesa
    property LockRetry: Integer read GetLockRetry write SetLockRetry stored False;
    // False (default): ogni SELECT passa dal TQuery del BDE (copia dei risultati all'apertura).
    // True: 'select * from TAB' e 'select campi from TAB' (senza WHERE/ORDER BY/join/parametri)
    // aprono una TTable: apertura immediata anche su tabelle grandi, dati in lettura 'vivi'.
    property TableCursor: Boolean read GetTableCursor write SetTableCursor stored False;
  end;

implementation

uses
  FireDAC.Stan.Consts;

function TFDPhysBDEConnectionDefParams.GetDriverID: String;
begin
  Result := FDef.AsString[S_FD_ConnParam_Common_DriverID];
end;

procedure TFDPhysBDEConnectionDefParams.SetDriverID(const AValue: String);
begin
  FDef.AsString[S_FD_ConnParam_Common_DriverID] := AValue;
end;

function TFDPhysBDEConnectionDefParams.GetBDEDriver: String;
begin
  if not FDef.HasValue(S_FD_ConnParam_BDE_BDEDriver) then
    Result := 'STANDARD'
  else
    Result := FDef.AsString[S_FD_ConnParam_BDE_BDEDriver];
end;

procedure TFDPhysBDEConnectionDefParams.SetBDEDriver(const AValue: String);
begin
  FDef.AsString[S_FD_ConnParam_BDE_BDEDriver] := AValue;
end;

function TFDPhysBDEConnectionDefParams.GetNetFileDir: String;
begin
  Result := FDef.AsString[S_FD_ConnParam_BDE_NetFileDir];
end;

procedure TFDPhysBDEConnectionDefParams.SetNetFileDir(const AValue: String);
begin
  FDef.AsString[S_FD_ConnParam_BDE_NetFileDir] := AValue;
end;

function TFDPhysBDEConnectionDefParams.GetPrivateDir: String;
begin
  Result := FDef.AsString[S_FD_ConnParam_BDE_PrivateDir];
end;

procedure TFDPhysBDEConnectionDefParams.SetPrivateDir(const AValue: String);
begin
  FDef.AsString[S_FD_ConnParam_BDE_PrivateDir] := AValue;
end;

function TFDPhysBDEConnectionDefParams.GetLockRetry: Integer;
begin
  if not FDef.HasValue(S_FD_ConnParam_BDE_LockRetry) then
    Result := -1
  else
    Result := StrToIntDef(FDef.AsString[S_FD_ConnParam_BDE_LockRetry], -1);
end;

procedure TFDPhysBDEConnectionDefParams.SetLockRetry(const AValue: Integer);
begin
  FDef.AsString[S_FD_ConnParam_BDE_LockRetry] := IntToStr(AValue);
end;

function TFDPhysBDEConnectionDefParams.GetTableCursor: Boolean;
begin
  if not FDef.HasValue(S_FD_ConnParam_BDE_TableCursor) then
    Result := False
  else
    Result := SameText(FDef.AsString[S_FD_ConnParam_BDE_TableCursor], 'True');
end;

procedure TFDPhysBDEConnectionDefParams.SetTableCursor(const AValue: Boolean);
begin
  if AValue then
    FDef.AsString[S_FD_ConnParam_BDE_TableCursor] := 'True'
  else
    FDef.AsString[S_FD_ConnParam_BDE_TableCursor] := 'False';
end;

{ TFDConnectionBDEHelper }
function TFDConnectionBDEHelper.GetOnBDEIndexNeeded: TBDEIndexNeededEvent;
var
  oHooks: IFDPhysBDEHooks;
begin
  Result := nil;
  if (ConnectionIntf <> nil) and Supports(ConnectionIntf, IFDPhysBDEHooks, oHooks) then
    Result := oHooks.OnIndexNeeded;
end;

procedure TFDConnectionBDEHelper.SetOnBDEIndexNeeded(const AValue: TBDEIndexNeededEvent);
var
  oHooks: IFDPhysBDEHooks;
begin
  if (ConnectionIntf <> nil) and Supports(ConnectionIntf, IFDPhysBDEHooks, oHooks) then
    oHooks.OnIndexNeeded := AValue
  else if Assigned(AValue) then
    raise Exception.Create('OnBDEIndexNeeded: la connessione deve essere aperta e usare il driver BDE');
end;

function TFDConnectionBDEHelper.GetOnBDESetRange: TBDESetRangeEvent;
var
  oHooks: IFDPhysBDEHooks;
begin
  Result := nil;
  if (ConnectionIntf <> nil) and Supports(ConnectionIntf, IFDPhysBDEHooks, oHooks) then
    Result := oHooks.OnSetRange;
end;

procedure TFDConnectionBDEHelper.SetOnBDESetRange(const AValue: TBDESetRangeEvent);
var
  oHooks: IFDPhysBDEHooks;
begin
  if (ConnectionIntf <> nil) and Supports(ConnectionIntf, IFDPhysBDEHooks, oHooks) then
    oHooks.OnSetRange := AValue
  else if Assigned(AValue) then
    raise Exception.Create('OnBDESetRange: la connessione deve essere aperta e usare il driver BDE');
end;

{ Ricerca dell'indice }
function InList(const AName: String; const AList: array of String): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(AList) do
    if SameText(AList[i], AName) then begin
      Result := True;
      Exit;
    end;
end;

// elenco senza vuoti e senza doppioni (maiuscole/minuscole ininfluenti), stesso ordine
function Distinct(const AList: array of String): TArray<String>;
var
  i, n: Integer;
begin
  SetLength(Result, Length(AList));
  n := 0;
  for i := 0 to High(AList) do
    if (AList[i] <> '') and not InList(AList[i], Copy(Result, 0, n)) then begin
      Result[n] := AList[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function Union(const A, B: TArray<String>): TArray<String>;
var
  i, n: Integer;
begin
  SetLength(Result, Length(A) + Length(B));
  n := 0;
  for i := 0 to High(A) do
    if not InList(A[i], Copy(Result, 0, n)) then begin
      Result[n] := A[i];
      Inc(n);
    end;
  for i := 0 to High(B) do
    if not InList(B[i], Copy(Result, 0, n)) then begin
      Result[n] := B[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function BDEIndexFieldList(ADef: TIndexDef): TArray<String>;
var
  i: Integer;
begin
  Result := ADef.Fields.Split([';']);
  for i := 0 to High(Result) do
    Result[i] := Trim(Result[i]);
end;

function IndexNameOf(ADef: TIndexDef): String;
begin
  if ADef.Name = '' then
    Result := S_BDE_PrimaryIndex
  else
    Result := ADef.Name;
end;

function SimpleIndex(ADef: TIndexDef; ADesc: Boolean): Boolean;
begin
  Result := (ADef.Options * [ixExpression, ixCaseInsensitive] = []) and
    ((ixDescending in ADef.Options) = ADesc) and (Trim(ADef.Fields) <> '');
end;

// ordinamento che resta da garantire: i campi con '=' sono costanti
function EffectiveOrder(const AEq, AOrd: TArray<String>): TArray<String>;
var
  i, n: Integer;
begin
  SetLength(Result, Length(AOrd));
  n := 0;
  for i := 0 to High(AOrd) do
    if not InList(AOrd[i], AEq) then begin
      Result[n] := AOrd[i];
      Inc(n);
    end;
  SetLength(Result, n);
end;

function ServesOrder(const F, AEq, AOrd: TArray<String>): Boolean;
var
  aEff: TArray<String>;
  p, i: Integer;
begin
  Result := False;
  aEff := EffectiveOrder(AEq, AOrd);
  p := 0;
  while (p < Length(F)) and InList(F[p], AEq) do
    Inc(p);
  if p + Length(aEff) > Length(F) then
    Exit;
  for i := 0 to High(aEff) do
    if not SameText(F[p + i], aEff[i]) then
      Exit;
  Result := True;
end;

// i primi campi dell'indice sono quelli di AW, in qualunque ordine
function SetCovers(const F, AW: TArray<String>): Boolean;
var
  i: Integer;
begin
  Result := False;
  if Length(F) < Length(AW) then
    Exit;
  for i := 0 to High(AW) do
    if not InList(AW[i], Copy(F, 0, Length(AW))) then
      Exit;
  Result := True;
end;

// i primi campi dell'indice sono quelli di AW, nello stesso ordine
function SeqLeads(const F, AW: TArray<String>): Boolean;
var
  i: Integer;
begin
  Result := False;
  if Length(F) < Length(AW) then
    Exit;
  for i := 0 to High(AW) do
    if not SameText(F[i], AW[i]) then
      Exit;
  Result := True;
end;

// uguaglianze sui primi campi (qualunque ordine), poi l'eventuale intervallo, poi l'ordinamento
function FullMatch(const F, AEq, ARng, AOrd: TArray<String>; out AKey: Integer): Boolean;
var
  aEff: TArray<String>;
  p, nLeft, i: Integer;
begin
  Result := False;
  AKey := 0;
  if Length(ARng) > 1 then
    Exit;
  if (Length(ARng) = 1) and InList(ARng[0], AEq) then
    Exit;
  p := 0;
  nLeft := Length(AEq);
  while (nLeft > 0) and (p < Length(F)) and InList(F[p], AEq) do begin
    Inc(p);
    Dec(nLeft);
  end;
  if nLeft > 0 then
    Exit;
  AKey := p;
  aEff := EffectiveOrder(AEq, AOrd);
  if Length(ARng) = 1 then begin
    if (p >= Length(F)) or not SameText(F[p], ARng[0]) then
      Exit;
    AKey := p + 1;
  end;
  if p + Length(aEff) > Length(F) then
    Exit;
  for i := 0 to High(aEff) do
    if not SameText(F[p + i], aEff[i]) then
      Exit;
  Result := True;
end;

function BDEIndexServesOrder(ADef: TIndexDef; const AEquals, AOrderBy: array of String): Boolean;
begin
  Result := not (ixExpression in ADef.Options) and
    ServesOrder(BDEIndexFieldList(ADef), Distinct(AEquals), Distinct(AOrderBy));
end;

function BDEFindIndex(AIndexDefs: TIndexDefs; const AEquals, ARanges, AOrderBy: array of String;
  ADescending: Boolean; out AMatch: TBDEIndexMatch): Boolean;
var
  aEq, aRng, aOrd, aAll, aF: TArray<String>;
  i, iKey: Integer;
  oDef: TIndexDef;
begin
  AMatch := Default(TBDEIndexMatch);
  AMatch.Level := ilNone;
  aEq := Distinct(AEquals);
  aRng := Distinct(ARanges);
  aOrd := Distinct(AOrderBy);
  aAll := Union(aEq, aRng);
  if Length(aAll) + Length(aOrd) = 0 then begin
    Result := False;
    Exit;
  end;
  for i := 0 to AIndexDefs.Count - 1 do begin
    oDef := AIndexDefs[i];
    if not SimpleIndex(oDef, ADescending) then
      Continue;
    aF := BDEIndexFieldList(oDef);
    if FullMatch(aF, aEq, aRng, aOrd, iKey) then begin
      AMatch.IndexName := IndexNameOf(oDef);
      AMatch.Fields := aF;
      AMatch.KeyFields := iKey;
      AMatch.Level := ilFull;
      Break;
    end
    else if AMatch.Level = ilNone then
      if ((Length(aOrd) > 0) and ServesOrder(aF, aEq, aOrd)) or
         ((Length(aOrd) = 0) and SetCovers(aF, aAll)) then begin
        AMatch.IndexName := IndexNameOf(oDef);
        AMatch.Fields := aF;
        AMatch.KeyFields := 0;
        AMatch.Level := ilCovers;
      end;
  end;
  Result := AMatch.Level <> ilNone;
end;

function BDEFindIndex(AIndexDefs: TIndexDefs; const AFields: array of String;
  ADescending, AAnyOrder: Boolean; out AMatch: TBDEIndexMatch): Boolean;
var
  aW, aF: TArray<String>;
  i: Integer;
  oDef: TIndexDef;
begin
  AMatch := Default(TBDEIndexMatch);
  AMatch.Level := ilNone;
  aW := Distinct(AFields);
  if Length(aW) = 0 then begin
    Result := False;
    Exit;
  end;
  for i := 0 to AIndexDefs.Count - 1 do begin
    oDef := AIndexDefs[i];
    if not SimpleIndex(oDef, ADescending) then
      Continue;
    aF := BDEIndexFieldList(oDef);
    if (AAnyOrder and SetCovers(aF, aW)) or (not AAnyOrder and SeqLeads(aF, aW)) then begin
      AMatch.IndexName := IndexNameOf(oDef);
      AMatch.Fields := aF;
      AMatch.KeyFields := Length(aW);
      AMatch.Level := ilFull;
      Break;
    end;
  end;
  Result := AMatch.Level <> ilNone;
end;

end.
