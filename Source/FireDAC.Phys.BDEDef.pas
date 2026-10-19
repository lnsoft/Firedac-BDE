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

end.
