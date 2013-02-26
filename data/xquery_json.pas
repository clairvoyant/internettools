unit xquery_json;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, xquery;


implementation

uses jsonscanner, simplehtmltreeparser, int65math;


function xqFunctionIsNull(const args: TXQVArray): IXQValue;
begin
  requiredArgCount(args, 1, 1);
  result := args[0];
  xqvalueSeqSqueeze(result);
  result := xqvalue(result is TXQValueJSONNull);
end;

function xqFunctionNull(const args: TXQVArray): IXQValue;
begin
  requiredArgCount(args, 0, 0);
  result := TXQValueJSONNull.create;
end;

function xqFunctionObject(const args: TXQVArray): IXQValue;
var resobj: TXQValueObject;
    procedure merge(another: TXQValueObject);
    var
      i: Integer;
    begin
      if another.prototype <> nil then merge(another.prototype as TXQValueObject);
      for i := 0 to another.values.count-1 do begin
        if resobj.values.hasVariable(another.values.getName(i),nil) then raise EXQEvaluationException.create('jerr:JNDY0003', 'Duplicated key names in '+resobj.jsonSerialize(tnsText)+' and '+another.jsonSerialize(tnsText));
        resobj.values.add(another.values.getName(i), another.values.get(i));
      end;
    end;

var v: IXQValue;
begin
  requiredArgCount(args, 1);
  resobj := TXQValueObject.create();
  for v in args[0] do begin
    if not (v is TXQValueObject) then raise EXQEvaluationException.create('XPTY0004', 'Expected object, got: '+v.debugAsStringWithTypeAnnotation());
    if resobj.prototype = nil then resobj.prototype := v
    else merge(v as TXQValueObject);
  end;
  result := resobj;
end;

function xqFunctionParseJson(const args: TXQVArray): IXQValue;

  {function convert(data: TJSONData): IXQValue;
  var
    seq: TXQValueJSONArray;
    obj: TXQValueObject;
    i: Integer;
  begin
    if data is TJSONFloatNumber then exit(xqvalue(decimal(data.AsFloat)));
    if data is TJSONIntegerNumber then exit(xqvalue(data.AsInteger));
    if data is TJSONInt64Number then exit(xqvalue(data.AsInt64));
    if data is TJSONString then exit(xqvalue(data.AsString));
    if data is TJSONBoolean then exit(xqvalue(data.AsBoolean));
    if data is TJSONNull then exit(TXQValueJSONNull.create);
    if data is TJSONArray then begin
      seq := TXQValueJSONArray.create();
      for i := 0 to data.Count - 1 do seq.addChild(convert(TJSONArray(data)[i]));
      exit(seq);
    end;
    if data is TJSONObject then begin
      obj := TXQValueObject.create();
      for i := 0 to data.Count-1 do obj.setMutable(TJSONObject(data).Names[i], convert(TJSONObject(data).Elements[TJSONObject(data).Names[i]]));//todo optimize
      exit(obj);
    end;
    if data = nil then raise EXQEvaluationException.create('pxp:OBJ', 'Invalid JSON: "'+args[0].toString+'"')
    else raise EXQEvaluationException.create('pxp:OBJ', 'Unknown JSON value: '+data.AsJSON);
  end;}

var
  scanner: TJSONScanner;

  function nextToken: TJSONToken;
  begin
    while scanner.FetchToken = tkWhitespace do ;
    result := scanner.CurToken;
  end;

  procedure raiseError(message: string);
  begin
    raise EXQEvaluationException.create('jerr:JNDY002', message+' at ' + scanner.CurTokenString + ' in '+scanner.CurLine);
  end;

  function parse(repeatCurToken: boolean = false): IXQValue;


    function parseNumber: Ixqvalue;
    var
      temp65: Int65;
      tempFloat: Extended;
    begin
      if TryStrToInt65(scanner.CurTokenString, temp65) then exit(xqvalue(temp65));
      if TryStrToFloat(scanner.CurTokenString, tempFloat) then exit(xqvalue(tempFloat));
      raiseError('Invalid number');
    end;

    function parseArray: TXQValueJSONArray;
    begin
      Result := TXQValueJSONArray.create();
      if nextToken = tkSquaredBraceClose then exit;
      result.addChild(parse(true));
      while true do begin
        case nextToken of
          tkSquaredBraceClose: exit;
          tkComma: ; //ok
          else raiseError('Unexpected token in array');
        end;
        result.addChild(parse());
      end;
    end;

    function parseObject: TXQValueObject;
    var obj: TXQValueObject;
      procedure parseProperty(rep: boolean);
      var
        token: TJSONToken;
        name: String;
      begin
        token := scanner.CurToken;
        if not rep then token := nextToken;
        if not (token in [tkString, tkIdentifier]) then raiseError('Expected property name');
        name := scanner.CurTokenString;
        if nextToken <> tkColon then raiseError('Expected : between property name and value');
        obj.setMutable(name, parse());
      end;

    begin
      obj := TXQValueObject.create();
      result := obj;
      if nextToken = tkCurlyBraceClose then exit;
      parseProperty(true);
      while true do begin
        case nextToken of
          tkCurlyBraceClose: exit;
          tkComma: ; //ok
          else raiseError('Unexpected token in object');
        end;
        parseProperty(false);
      end;
    end;

  begin
    if not repeatCurToken then nextToken;
    case scanner.CurToken of
      tkEOF: exit;
      tkWhitespace: result := parse();
      tkString: result := xqvalue(scanner.CurTokenString);
      tkNumber: result := parseNumber;
      tkFalse: result := xqvalueFalse;
      tkTrue: result := xqvalueTrue;
      tkCurlyBraceOpen: result := parseObject;
      tkSquaredBraceOpen: result := parseArray;
      tkComma, tkColon, tkCurlyBraceClose, tkSquaredBraceClose, tkIdentifier, tkUnknown: raise EXQEvaluationException.create('jerr:JNDY002', 'JSON parsing failed at: '+scanner.CurLine);
    end;
  end;

var
  data: TJSONData;
  multipleTopLevelItems: Boolean;


begin
  requiredArgCount(args, 1, 2);

  multipleTopLevelItems := true;
  if length(args) = 2 then begin
    if (args[1].getProperty('jsoniq-multiple-top-level-items').getSequenceCount > 2) or not (args[1].getProperty('jsoniq-multiple-top-level-items').getChild(1) is TXQValueBoolean) then
      raise EXQEvaluationException.create('jerr:JNTY0020', 'Expected true/false got: '+args[1].getProperty('jsoniq-multiple-top-level-items').debugAsStringWithTypeAnnotation()+' for property jsoniq-multiple-top-level-items');
    multipleTopLevelItems:=args[1].getProperty('jsoniq-multiple-top-level-items').toBoolean;
  end;

  scanner := TJSONScanner.Create(args[0].toString);
  try
    result := parse();
    if multipleTopLevelItems then begin
      while nextToken <> tkEOF do
        xqvalueSeqAdd(result, parse(true));
    end else if nextToken <> tkEOF then
      raiseError('Unexpected values after json data');
  finally
    scanner.free;
  end;
end;

function xqFunctionSerialize_Json(const args: TXQVArray): IXQValue;
var
  a: IXQValue;
begin
  requiredArgCount(args, 1);
  a := args[0];
  result := xqvalue(a.jsonSerialize(tnsXML));
end;

function xqFunctionKeys(const args: TXQVArray): IXQValue;
var
  a: IXQValue;
  obj: TXQValueObject;
  i: Integer;
  resseq: TXQValueSequence;
begin
  requiredArgCount(args, 1);
  a := args[0];
  if (a is TXQValueSequence) and (a.getSequenceCount = 1) then a := a.getChild(1);
  if not (a is TXQValueObject) then raise EXQEvaluationException.create('pxp:OBJ', 'Expected object, got: '+a.debugAsStringWithTypeAnnotation());
  obj := a as TXQValueObject;

  resseq := TXQValueSequence.create();
  while obj <> nil do begin
    for i := obj.values.count - 1 downto 0 do
      resseq.seq.insert(0, xqvalue(obj.values.getName(i))); //TODO: optimize
    obj := obj.prototype as TXQValueObject;
  end;
  result := resseq;
end;


function xqFunctionMembers(const args: TXQVArray): IXQValue;
var
  a: IXQValue;
  ara: TXQValueJSONArray;
  i: Integer;
begin
  requiredArgCount(args, 1);
  a := args[0];
  if (a is TXQValueSequence) and (a.getSequenceCount = 1) then a := a.getChild(1);
  if not (a is TXQValueJSONArray) then raise EXQEvaluationException.create('pxp:ARRAY', 'Expected array, got: '+a.debugAsStringWithTypeAnnotation());
  ara := a as TXQValueJSONArray;;
  result := xqvalue();
  for i := 0 to ara.seq.Count-1 do
    xqvalueSeqAdd(result, ara.seq[i]);
end;

function xqFunctionSize(const args: TXQVArray): IXQValue;
var
  a: IXQValue;
begin
  requiredArgCount(args, 1);
  a := args[0];
  if (a is TXQValueSequence) and (a.getSequenceCount = 1) then a := a.getChild(1);
  if not (a is TXQValueJSONArray) then raise EXQEvaluationException.create('pxp:ARRAY', 'Expected array, got: '+a.debugAsStringWithTypeAnnotation());
  result := xqvalue((a as TXQValueJSONArray).seq.Count);
end;


var jn, pxp: TXQNativeModule;
    XMLNamespace_JSONiqFunctions: INamespace;
initialization
  AllowJSONDefaultInternal := true;
  XMLNamespace_JSONiqFunctions:=TNamespace.create('http://jsoniq.org/functions', 'jn');
  GlobalStaticNamespaces.add(XMLNamespace_JSONiqFunctions);
  //XMLNamespace_JSONiqTypes:=TNamespace.create('http://jsoniq.org/types', 'js');
  //XMLNamespace_JSONiqTypes:=TNamespace.create('http://jsoniq.org/function-library', 'libjn');
  //XMLNamespace_JSONiqTypes:=TNamespace.create('http://jsoniq.org/errors', 'jerr');
  //XMLNamespace_JSONiqTypes:=TNamespace.create('http://jsoniq.org/updates', 'jupd');


  jn := TXQNativeModule.Create(XMLNamespace_JSONiqFunctions);
  TXQueryEngine.registerNativeModule(jn);
  jn.registerFunction('keys', @xqFunctionKeys, ['($arg as xs:object) as xs:string*']);
  jn.registerFunction('members', @xqFunctionMembers, ['($arg as xs:array) as item()*']);

  //TODO:   6.6. jn:decode-from-roundtrip 6.7. jn:encode-for-roundtrip
  //TODO:  6.9. jn:json-doc
  jn.registerFunction('is-null', @xqFunctionIsNull, ['($arg as item()) as xs:boolean']);
  jn.registerFunction('null', @xqFunctionNull, ['() as xs:null']);
  jn.registerFunction('object', @xqFunctionObject, ['($arg as xs:object*) as object()']);
  jn.registerFunction('parse-json', @xqFunctionParseJson, ['($arg as xs:string) as item()', '($arg as xs:string, $options as xs:object) as item()*']);
  jn.registerFunction('size', @xqFunctionSize, ['($arg as xs:array) as xs:integer']);

  pxp := TXQueryEngine.findNativeModule(XMLNamespaceURL_MyExtensions);
  pxp.registerFunction('json', @xqFunctionParseJson, ['($arg as xs:string) as item()*']);
  pxp.registerFunction('serialize-json', @xqFunctionSerialize_Json, ['($arg as xs:anyAtomicType*) as xs:string']);

finalization
  jn.free;
end.

