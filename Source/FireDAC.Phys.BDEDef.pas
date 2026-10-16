{*******************************************************}
{  FireDAC BDE driver (non ufficiale) - parametri       }
{  Modello: FireDAC.Phys.SQLiteDef / ODBCDef            }
{*******************************************************}
{$I FireDAC.inc}

unit FireDAC.Phys.BDEDef;

interface

uses
  System.SysUtils, System.Classes, FireDAC.Stan.Intf;

const
  S_FD_BDEId = 'BDE';

  // Parametri specifici del driver BDE
  S_FD_ConnParam_BDE_BDEDriver = 'BDEDriver';   // default STANDARD (DBF + Paradox)
  S_FD_ConnParam_BDE_NetFileDir = 'NetFileDir'; // dir di PDOXUSRS.NET (Paradox condiviso)
  S_FD_ConnParam_BDE_PrivateDir = 'PrivateDir'; // dir temporanea per sessione
  S_FD_ConnParam_BDE_LockRetry = 'LockRetry';   // secondi di attesa su record bloccato (BDE: ~6)

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
  published
    property DriverID: String read GetDriverID write SetDriverID stored False;
    // Database (ereditato): alias BDE oppure percorso della cartella con DBF/DB
    property BDEDriver: String read GetBDEDriver write SetBDEDriver stored False;
    property NetFileDir: String read GetNetFileDir write SetNetFileDir stored False;
    property PrivateDir: String read GetPrivateDir write SetPrivateDir stored False;
    // -1 = non impostato (default del BDE); 0 = nessuna attesa
    property LockRetry: Integer read GetLockRetry write SetLockRetry stored False;
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

end.
