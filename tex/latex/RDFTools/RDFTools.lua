#!/usr/bin/env texlua
-- RDFTools build-time parser and cache generator.
-- Run with: texlua RDFTools.lua parse|prepare-sources|sort-index|finalize-used|init-index|append-index ...
-- Author: Robert Warren

local function fail(message)
  error(message, 0)
end

local function read_file(path)
  local file, message = io.open(path, "rb")
  if not file then fail(message or ("cannot read " .. path)) end
  local value = file:read("*a")
  file:close()
  if value:sub(1, 3) == "\239\187\191" then value = value:sub(4) end
  return value
end

local function write_file(path, value, mode)
  local file, message = io.open(path, mode or "wb")
  if not file then fail(message or ("cannot write " .. path)) end
  local ok, write_message = file:write(value)
  file:close()
  if not ok then fail(write_message or ("cannot write " .. path)) end
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ensure_directory(path)
  local lfs=require("lfs")
  local mode=lfs.attributes(path,"mode")
  if mode=="directory" then return end
  if mode then fail("RDF cache path is not a directory: "..path) end
  local parent=path:match("^(.*)/[^/]+$")
  if parent and parent~="" and parent~=path then ensure_directory(parent) end
  local ok,message=lfs.mkdir(path)
  if not ok and lfs.attributes(path,"mode")~="directory" then
    fail("cannot create RDF cache directory "..path..": "..tostring(message))
  end
end

-- Preserve the requested output's parent directory, but keep every generated
-- RDFTools file inside its rdfCache child. Already-qualified paths are stable.
local function cache_path(path)
  local directory,name=path:match("^(.*)/([^/]+)$")
  directory=directory or "."
  name=name or path
  if name=="" or name=="." or name==".." then fail("invalid RDF cache filename") end
  if directory~="rdfCache" and not directory:match("/rdfCache$") then
    directory=directory.."/rdfCache"
  end
  ensure_directory(directory)
  return directory.."/"..name
end

local function curl_fetch(source)
  local command="curl --fail --location --silent --show-error --max-time 30"
    .." --user-agent 'RDFTools/1.0 TeX Lua helper' "
    .." --header 'Accept: text/turtle, application/rdf+xml;q=0.9, application/ld+json;q=0.8, application/json;q=0.7' "
    .." --write-out '\\nRDFTOOLS_CONTENT_TYPE:%{content_type}\\n' "
    .."'"..source:gsub("'","'\\''").."'"
  local pipe=io.popen(command.." 2>&1","r")
  if not pipe then fail("HTTPS source requires curl on this TeX Live installation") end
  local response=pipe:read("*a")
  local ok,reason,code=pipe:close()
  if not ok then
    fail("could not retrieve HTTPS source (curl "..tostring(code or reason).."): "..trim(response))
  end
  local body,content_type=response:match("^(.*)\nRDFTOOLS_CONTENT_TYPE:([^\r\n]*)\n$")
  if not body then fail("curl did not report the remote source media type") end
  return body,trim(content_type):lower()
end

local RDF = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
local RDFS = "http://www.w3.org/2000/01/rdf-schema#"
local SKOS = "http://www.w3.org/2004/02/skos/core#"
local FOAF = "http://xmlns.com/foaf/0.1/"
local XML = "http://www.w3.org/XML/1998/namespace"
local OWL = "http://www.w3.org/2002/07/owl#"
local VOID = "http://rdfs.org/ns/void#"
local DC = "http://purl.org/dc/elements/1.1/"
local DCTERMS = "http://purl.org/dc/terms/"
local DCAT = "http://www.w3.org/ns/dcat#"
local SCHEMA = "https://schema.org/"
local BIBO = "http://purl.org/ontology/bibo/"
local RDF_FIRST = RDF .. "first"
local RDF_REST = RDF .. "rest"
local RDF_NIL = RDF .. "nil"

local function set(values)
  local result = {}
  for _, value in ipairs(values) do result[value] = true end
  return result
end

local BIBO_ENTRY_TYPES = {
  AcademicArticle="article", Article="article", Book="book",
  BookSection="incollection", Chapter="incollection", Collection="book",
  Conference="inproceedings", Document="misc", Dissertation="phdthesis",
  Issue="article", Journal="article", LegalDocument="misc",
  Manuscript="unpublished", Note="misc", Patent="patent", Periodical="misc",
  Proceedings="book", ReferenceSource="misc", Report="techreport",
  Series="book", Standard="manual", Thesis="phdthesis", Webpage="misc",
  Website="misc",
}
local BIBO_AUTHOR_PREDICATES = set({
  BIBO.."author", BIBO.."authorList", DC.."creator", DCTERMS.."creator",
})
local BIBO_FIELD_PREDICATES = {
  {"title",{BIBO.."title", BIBO.."shortTitle", DC.."title", DCTERMS.."title"}},
  {"publisher",{BIBO.."publisher", DC.."publisher", DCTERMS.."publisher"}},
  {"journal",{BIBO.."content", DCTERMS.."isPartOf", DC.."source"}},
  {"volume",{BIBO.."volume"}}, {"number",{BIBO.."issue"}},
  {"pages",{BIBO.."pages"}}, {"pageStart",{BIBO.."pageStart"}},
  {"pageEnd",{BIBO.."pageEnd"}}, {"doi",{BIBO.."doi"}},
  {"isbn",{BIBO.."isbn", BIBO.."isbn10", BIBO.."isbn13"}},
  {"issn",{BIBO.."issn", BIBO.."eissn"}}, {"url",{BIBO.."uri"}},
  {"abstract",{BIBO.."abstract", DCTERMS.."abstract"}},
  {"note",{BIBO.."note", DCTERMS.."description", DC.."description"}},
  {"edition",{BIBO.."edition"}}, {"series",{BIBO.."series"}},
  {"chapter",{BIBO.."chapter"}}, {"organization",{BIBO.."organizer"}},
}
local BIBO_DATE_PREDICATES = {
  BIBO.."issued", BIBO.."created", BIBO.."publicationDate",
  DC.."date", DCTERMS.."issued", DCTERMS.."created",
}
local BIBO_IDENTIFIER_PREDICATES = {BIBO.."identifier", DC.."identifier", DCTERMS.."identifier"}
local NAME_PREDICATES = {
  [SKOS.."prefLabel"]=1, [FOAF.."name"]=2, [RDFS.."label"]=3,
  [SCHEMA.."name"]=4, ["http://schema.org/name"]=4,
}
local DEFINITION_PREDICATES = {[SKOS.."definition"]=1, [RDFS.."comment"]=2}
local TITLE_PREDICATES = set({DC.."title", DCTERMS.."title"})
local VERSION_PREDICATES = {
  [OWL.."versionInfo"]=1, [SCHEMA.."version"]=2,
  ["http://schema.org/version"]=2, [DCAT.."version"]=3,
  [DC.."version"]=4, [DCTERMS.."hasVersion"]=5,
}
local RESOURCE_TYPES = {
  [OWL.."Ontology"]=1, [SKOS.."Collection"]=2, [VOID.."Dataset"]=3,
  [DCAT.."Dataset"]=4, [SCHEMA.."Dataset"]=5,
  ["http://schema.org/Dataset"]=5,
}

local function list_to_set(values)
  local result = {}
  for _, value in ipairs(values) do result[value] = true end
  return result
end

local function reject_html_source(source,text)
  local trimmed=text:gsub("^\239\187\191",""):match("^%s*(.*)") or ""
  local lower=trimmed:sub(1,2048):lower()
  if not (lower:match("^<!doctype%s+html[%s>]") or lower:match("^<html[%s>]")) then
    return
  end
  local document_url=source:match("^(https?://[^?#]+)") or ""
  document_url=document_url:gsub("/+$",""):lower()
  local guidance="Use a machine-readable Turtle, RDF/XML, N-Quads, or JSON-LD source URL instead."
  if document_url=="https://schema.org" or document_url=="http://schema.org" then
    guidance="The Schema.org homepage is HTML. For the current vocabulary, use https://schema.org/version/latest/schemaorg-current-https.ttl or https://schema.org/version/latest/schemaorg-current-https.jsonld."
  end
  fail("source "..string.format("%q",source).." returned an HTML page, not RDF. "..guidance)
end

local function read_source(source, source_cache)
  if source:match("^https?://") then
    local metadata = source_cache and (source_cache .. ".meta") or nil
    local type_cache = source_cache and (source_cache .. ".type") or nil
    if source_cache and metadata and file_exists(source_cache) and file_exists(metadata)
      and read_file(metadata) == source then
      local cached=read_file(source_cache)
      reject_html_source(source,cached)
      return cached, type_cache and file_exists(type_cache)
        and trim(read_file(type_cache)):lower() or nil
    end
    local body,content_type
    if source:match("^https://") then
      -- TeX Live ships LuaSocket's HTTP client, but TLS support is not uniform.
      body,content_type=curl_fetch(source)
    else
      local http_ok, http = pcall(require, "socket.http")
      if not http_ok then fail("HTTP source requires LuaSocket in the TeX Live texlua runtime") end
      local ltn12_ok,ltn12=pcall(require,"ltn12")
      if not ltn12_ok then fail("HTTP source requires LuaSocket's ltn12 module") end
      http.TIMEOUT = 30
      local current_source=source
      for redirect_count=0,10 do
        local chunks={}
        local request_ok,code,headers,status=http.request({
          url=current_source,method="GET",
          headers={
            ["user-agent"]="RDFTools/1.0 TeX Lua helper",
            ["accept"]="text/turtle, application/rdf+xml;q=0.9, application/ld+json;q=0.8, application/json;q=0.7",
          },
          sink=ltn12.sink.table(chunks),
        })
        local response=table.concat(chunks)
        local status_code=tonumber(code)
        local response_type
        for name,value in pairs(headers or {}) do
          if tostring(name):lower()=="content-type" then
            response_type=trim(tostring(value)):lower()
            break
          end
        end
        local is_redirect=status_code==301 or status_code==302 or status_code==303
          or status_code==307 or status_code==308
        if is_redirect and headers and headers.location then
          if redirect_count==10 then fail("HTTP source exceeded the redirect limit") end
          local url_ok,url_module=pcall(require,"socket.url")
          if not url_ok then fail("HTTP redirects require LuaSocket's URL module") end
          current_source=url_module.absolute(current_source,headers.location)
          if current_source:match("^https://") then
            body,content_type=curl_fetch(current_source)
            break
          end
        elseif not request_ok or not status_code or status_code<200 or status_code>=300 then
          fail("could not retrieve HTTP source: " .. tostring(status or code))
        else
          body=response
          content_type=response_type
          break
        end
      end
    end
    reject_html_source(source,body)
    if source_cache then
      write_file(source_cache, body)
      if metadata then write_file(metadata, source) end
      if type_cache then write_file(type_cache, content_type or "") end
    end
    return body,content_type
  end
  return read_file(source),nil
end

local function detect_format(source, text, content_type)
  local media_type=content_type and content_type:match("^%s*([^;]+)") or ""
  media_type=trim(media_type):lower()
  local prefix=text:sub(1,2048):gsub("^\239\187\191",""):lower()
  local looks_like_html=prefix:match("^%s*<!doctype%s+html[%s>]")
    or prefix:match("^%s*<html[%s>]")
    or prefix:match("^%s*<head[%s>]")
    or prefix:match("^%s*<body[%s>]")
  if media_type=="text/html" or media_type=="application/xhtml+xml" or looks_like_html then
    fail("source "..string.format("%q",source).." returned an HTML page, not RDF"
      ..(media_type~="" and " (Content-Type: "..media_type..")" or "")
      ..". Use a machine-readable Turtle, RDF/XML, N-Quads, or JSON-LD source URL instead.")
  end
  if media_type=="application/ld+json" or media_type=="application/json" then return "jsonld" end
  if media_type=="text/turtle" then return "turtle" end
  if media_type=="application/rdf+xml" or media_type=="application/xml"
      or media_type=="text/xml" then return "rdfxml" end

  local path = source:match("^[^?]*") or source
  local suffix = path:match("%.([^./]+)$")
  suffix = suffix and suffix:lower() or ""
  if suffix=="jsonld" or suffix=="json" then return "jsonld" end
  if suffix == "rdf" or suffix == "xml" or suffix == "owl" then return "rdfxml" end
  if suffix == "nq" or suffix == "nquads" then return "nquads" end
  if suffix == "n3" then return "n3" end
  if suffix == "ttl" then return "turtle" end
  local head = text:sub(1, 12000)
  local first=trim(head):sub(1,1)
  if first=="{" or first=="[" then return "jsonld" end
  if head:find("<rdf:RDF", 1, true) or head:find("xmlns:rdf", 1, true)
      or head:find("<owl:Ontology", 1, true) then return "rdfxml" end
  for line in (head.."\n"):gmatch("(.-)\n") do
    local candidate=trim(line)
    if candidate:match("^GRAPH%s+") or candidate:match("^<[^>]+>%s+%S+%s+%S+%s+<") then
      return "nquads"
    end
  end
  if head:find("@forAll",1,true) or head:find("@forSome",1,true) or head:find("=>",1,true) then return "n3" end
  return "turtle"
end

local function local_name(uri)
  local value = uri:gsub("/+$", "")
  return value:match("([^/#]+)$") or value:match("([^:]+)$") or value
end

local function expand_term(term, prefixes, base)
  term = trim(term)
  if term:sub(1,1) == "<" and term:sub(-1) == ">" then
    local value = term:sub(2,-2)
    if base and base ~= "" and not value:match("^[%a][%w+%.%-]*:") then return base .. value end
    return value
  end
  if term:sub(1,2) == "_:" then return term end
  if term == "a" then return RDF .. "type" end
  local prefix, suffix = term:match("^([^:]*):(.*)$")
  if prefix then return (prefixes[prefix] or "") .. suffix end
  return term
end

local function codepoint_escape(hex)
  local number = tonumber(hex, 16)
  if not number or number > 0x10ffff or (number >= 0xd800 and number <= 0xdfff) then
    fail("invalid Unicode escape in RDF literal")
  end
  return utf8.char(number)
end

local function unescape_literal(value)
  value=value:gsub("\\u(%x%x%x%x)",codepoint_escape)
  value=value:gsub("\\U(%x%x%x%x%x%x%x%x)",codepoint_escape)
  local replacements={n="\n",r="\r",t="\t",['"']='"',["\\"]="\\",["'"]="'"}
  return (value:gsub("\\(.)",function(escape) return replacements[escape] or escape end))
end

local function split_literal(token)
  token = trim(token)
  if token:sub(1,1) ~= '"' then return token, "", "" end
  local escaped, ending = false, nil
  for index=2,#token do
    local char = token:sub(index,index)
    if char == '"' and not escaped then ending=index; break end
    if char == "\\" and not escaped then escaped=true else escaped=false end
  end
  if not ending then fail("Turtle source contains an unterminated literal") end
  local value = unescape_literal(token:sub(2,ending-1))
  local suffix = trim(token:sub(ending+1))
  local language = suffix:match("^@([^%^]+)") or ""
  local datatype = suffix:match("^%^^(.+)$") or ""
  return value, language, datatype
end

local function tokenize(statement)
  local tokens, current, index = {}, {}, 1
  local function flush()
    if #current > 0 then tokens[#tokens+1]=table.concat(current); current={} end
  end
  while index <= #statement do
    local char = statement:sub(index,index)
    if statement:sub(index,index+2) == '"""' then
      fail("Turtle source uses unsupported triple-quoted literals")
    end
    if char == "'" then fail("Turtle source uses unsupported single-quoted literals") end
    if char == '"' then
      flush()
      local ending, escaped = nil, false
      for cursor=index+1,#statement do
        local part = statement:sub(cursor,cursor)
        if part == '"' and not escaped then ending=cursor; break end
        if part == "\\" and not escaped then escaped=true else escaped=false end
      end
      if not ending then fail("Turtle source contains an unterminated literal") end
      local token_end = ending
      local in_angle = false
      while token_end < #statement do
        local next_char = statement:sub(token_end+1,token_end+1)
        if next_char == "<" then in_angle=true elseif next_char == ">" and in_angle then in_angle=false end
        if next_char:match("[%s;,]") or (next_char == "." and not in_angle) then break end
        token_end=token_end+1
      end
      tokens[#tokens+1]=statement:sub(index,token_end)
      index=token_end+1
    elseif char == "<" then
      flush()
      local ending=statement:find(">",index+1,true)
      if not ending then fail("Turtle source contains an unterminated IRI") end
      tokens[#tokens+1]=statement:sub(index,ending)
      index=ending+1
    elseif char:match("[;%[,]") or char == "]" or char == "{" or char == "}" or char == "(" or char == ")" or char == "," then
      flush(); tokens[#tokens+1]=char; index=index+1
    elseif char:match("%s") then
      flush(); index=index+1
    else
      current[#current+1]=char; index=index+1
    end
  end
  flush()
  return tokens
end

local function strip_comments(text)
  local result={}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local output, in_string, in_iri, escaped = {}, false, false, false
    for index=1,#line do
      local char=line:sub(index,index)
      if char == '"' and not escaped then in_string=not in_string end
      if char == "<" and not in_string then in_iri=true
      elseif char == ">" and in_iri and not in_string then in_iri=false end
      if char == "#" and not in_string and not in_iri then break end
      output[#output+1]=char
      if char == "\\" and not escaped then escaped=true else escaped=false end
    end
    result[#result+1]=table.concat(output)
  end
  return table.concat(result,"\n")
end

local function collect_turtle_statements(text)
  local statements,current={},{}
  local in_string,escaped,in_angle=false,false,false
  for index=1,#text do
    local char=text:sub(index,index)
    if char == '"' and not escaped and not in_angle then in_string=not in_string end
    if char == "<" and not in_string then in_angle=true
    elseif char == ">" and in_angle and not in_string then in_angle=false end
    if char == "." and not in_string and not in_angle then
      local statement=trim(table.concat(current))
      if statement ~= "" then statements[#statements+1]=statement end
      current={}
    else current[#current+1]=char end
    if char == "\\" and not escaped then escaped=true else escaped=false end
  end
  if trim(table.concat(current)) ~= "" then
    fail("Turtle source contains an unterminated statement")
  end
  return statements
end

local function validate_term(term,prefixes,role)
  if term:sub(1,1) == "<" and term:sub(-1) == ">" or term:sub(1,2) == "_:" then return end
  local prefix = term:match("^([^:]+):")
  if prefix and not prefixes[prefix] and not term:match("^[%a][%w+%.%-]*:") then
    fail("Turtle source uses an undefined prefix in " .. role .. " `" .. term .. "`")
  end
end

local function validate_turtle_statement(tokens,prefixes)
  local unsupported={["("]=true,[")"]=true,["["]=true,["]"]=true,["{"]=true,["}"]=true,
    ["=>"]=true,["<="]=true,["="]=true,["!"]=true,["^"]=true}
  for _,token in ipairs(tokens) do
    if unsupported[token] then fail("Turtle source uses unsupported construct `" .. token .. "`") end
  end
  if #tokens == 0 then return end
  if tokens[1]:sub(1,1) == '"' then fail("Turtle source uses a literal where a subject is required") end
  validate_term(tokens[1],prefixes,"subject")
  local index=2
  while index <= #tokens do
    if tokens[index] == ";" then index=index+1
    elseif tokens[index] == "," then fail("Turtle source uses a comma without a predicate")
    else
      local predicate=tokens[index]
      if predicate:sub(1,1) == '"' then fail("Turtle source uses a literal where a predicate is required") end
      validate_term(predicate,prefixes,"predicate")
      index=index+1
      if index>#tokens or tokens[index]==";" or tokens[index]=="," then
        fail("Turtle source predicate has no object")
      end
      while index<=#tokens do
        local object=tokens[index]
        if object==";" or object=="," then fail("Turtle source predicate has no object") end
        if object:sub(1,1) ~= '"' then validate_term(object,prefixes,"object") end
        index=index+1
        if tokens[index]=="," then
          index=index+1
          if index>#tokens or tokens[index]==";" or tokens[index]=="," then
            fail("Turtle source has a comma without another object")
          end
        else break end
      end
    end
  end
end

-- Normalize Turtle's four string forms before the line-oriented directive,
-- comment and statement readers run. In particular, a multiline literal may
-- contain apparent comments, directives, periods and graph keywords as text.
-- Keep escape sequences encoded until split_literal performs the decoding.
local function normalize_turtle_literals(text)
  local output,index={},1
  while index<=#text do
    local char=text:sub(index,index)
    if char=="#" then
      local ending=text:find("\n",index,true) or #text
      output[#output+1]=text:sub(index,ending)
      index=ending+1
    elseif char=="<" and text:sub(index+1,index+1)~="=" then
      local ending=text:find(">",index+1,true)
      if not ending then fail("Turtle source contains an unterminated IRI") end
      output[#output+1]=text:sub(index,ending)
      index=ending+1
    elseif char=='"' or char=="'" then
      local delimiter=char
      if text:sub(index,index+2)==char:rep(3) then delimiter=char:rep(3) end
      local long=#delimiter==3
      local parts,closed={},false
      index=index+#delimiter
      while index<=#text do
        char=text:sub(index,index)
        if text:sub(index,index+#delimiter-1)==delimiter then
          index=index+#delimiter
          closed=true
          break
        elseif char=="\\" then
          if index==#text then break end
          parts[#parts+1]=text:sub(index,index+1)
          index=index+2
        elseif char=="\n" or char=="\r" then
          if not long then fail("Turtle source contains a newline in a short literal") end
          parts[#parts+1]=char=="\n" and "\\n" or "\\r"
          index=index+1
        else
          parts[#parts+1]=char=='"' and '\\"' or char
          index=index+1
        end
      end
      if not closed then fail("Turtle source contains an unterminated literal") end
      output[#output+1]='"'..table.concat(parts)..'"'
    else
      output[#output+1]=char
      index=index+1
    end
  end
  return table.concat(output)
end

local function parse_turtle(text)
  text=normalize_turtle_literals(text)
  local prefixes,prefix_order,base={}, {}, ""
  local cleaned={}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local prefix,namespace=line:match("^%s*@?[Pp][Rr][Ee][Ff][Ii][Xx]%s+([%w_.%-]*):%s*<([^>]+)>")
    if prefix then
      local remainder=trim(line:match("^.-<[^>]+>(.*)$") or "")
      if remainder~="" and remainder~="." then fail("Turtle source has trailing text after a prefix declaration") end
      if prefixes[prefix]==nil then prefix_order[#prefix_order+1]=prefix end
      prefixes[prefix]=namespace
    elseif line:match("^%s*@prefix%f[%W]") then
      fail("Turtle source has a malformed prefix declaration")
    else
      local base_value=line:match("^%s*@?[Bb][Aa][Ss][Ee]%s+<([^>]+)>")
      if base_value then
        local remainder=trim(line:match("^.-<[^>]+>(.*)$") or "")
        if remainder~="" and remainder~="." then fail("Turtle source has trailing text after a base declaration") end
        base=base_value
      elseif line:match("^%s*@base%f[%W]") then
        fail("Turtle source has a malformed base declaration")
      else cleaned[#cleaned+1]=line end
    end
  end
  local triples={}
  for _,statement in ipairs(collect_turtle_statements(strip_comments(table.concat(cleaned,"\n")))) do
    local tokens=tokenize(statement)
    if #tokens>0 then
      for _,token in ipairs(tokens) do
        if token=="@forAll" or token=="@forSome" or token=="GRAPH" then
          fail("Turtle source uses unsupported N3 quantification or graph syntax")
        end
      end
      validate_turtle_statement(tokens,prefixes)
      local subject=expand_term(table.remove(tokens,1),prefixes,base)
      local index=1
      while index<=#tokens do
        if tokens[index]==";" then index=index+1
        else
          local predicate=expand_term(tokens[index],prefixes,base)
          index=index+1
          while index<=#tokens and tokens[index]~=";" do
            local object=tokens[index]
            local value,language,datatype=split_literal(object)
            if object:sub(1,1)~='"' then value=expand_term(object,prefixes,base); language=""; datatype="" end
            triples[#triples+1]={subject,predicate,value,language,datatype}
            index=index+1
            if tokens[index]~="," then break end
            index=index+1
          end
          if index<=#tokens and tokens[index]==";" then index=index+1 end
        end
      end
    end
  end
  return triples,prefixes,prefix_order
end

local function parse_nquads(text)
  local triples={}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line=trim(strip_comments(line))
    if line~="" then
      if line:sub(-1)~="." then fail("N-Quads source statement is missing its terminating period") end
      local tokens=tokenize(trim(line:sub(1,-2)))
      if #tokens~=4 then fail("N-Quads source requires subject, predicate, object, and graph") end
      if tokens[1]:sub(1,1)=='"' or tokens[2]:sub(1,1)=='"' then
        fail("N-Quads source uses a literal subject or predicate")
      end
      validate_term(tokens[1],{},"subject"); validate_term(tokens[2],{},"predicate"); validate_term(tokens[4],{},"graph")
      local subject=expand_term(tokens[1],{})
      local predicate=expand_term(tokens[2],{})
      local value,language,datatype=split_literal(tokens[3])
      if tokens[3]:sub(1,1)~='"' then value=expand_term(tokens[3],{}); language=""; datatype="" end
      triples[#triples+1]={subject,predicate,value,language,datatype}
    end
  end
  return triples,{},{}
end

local JSON_ARRAY = {}
local JSON_NUMBER = {}
local JSON_NULL = {}

local function is_json_array(value)
  local metadata=type(value)=="table" and getmetatable(value) or nil
  return metadata~=nil and metadata.__index==JSON_ARRAY
end

local function parse_json(text)
  if #text>8*1024*1024 then fail("JSON-LD source exceeds the 8 MiB size limit") end
  local index,length=1,#text
  local function whitespace()
    while index<=length and text:sub(index,index):match("%s") do index=index+1 end
  end
  local function parse_string()
    if text:sub(index,index)~='"' then fail("expected a JSON string") end
    index=index+1
    local output={}
    while index<=length do
      local char=text:sub(index,index)
      if char=='"' then index=index+1; return table.concat(output) end
      if char:byte()<32 then fail("unescaped control character in JSON string") end
      if char~="\\" then output[#output+1]=char; index=index+1
      else
        index=index+1
        local escape=text:sub(index,index)
        local simple={['"']='"',['\\']="\\",["/"]="/",b="\b",f="\f",n="\n",r="\r",t="\t"}
        if simple[escape] then
          output[#output+1]=simple[escape]
          index=index+1
        elseif escape=="u" then
          local hex=text:sub(index+1,index+4)
          if #hex~=4 or not hex:match("^%x%x%x%x$") then fail("invalid Unicode escape in JSON string") end
          local point=tonumber(hex,16)
          index=index+5
          if point>=0xd800 and point<=0xdbff then
            if text:sub(index,index+1)~="\\u" then fail("unpaired high surrogate in JSON string") end
            local low_hex=text:sub(index+2,index+5)
            if not low_hex:match("^%x%x%x%x$") then fail("invalid low surrogate in JSON string") end
            local low=tonumber(low_hex,16)
            if low<0xdc00 or low>0xdfff then fail("invalid low surrogate in JSON string") end
            point=0x10000+(point-0xd800)*0x400+(low-0xdc00)
            index=index+6
          elseif point>=0xdc00 and point<=0xdfff then
            fail("unpaired low surrogate in JSON string")
          end
          output[#output+1]=utf8.char(point)
        else
          fail("invalid escape in JSON string")
        end
      end
    end
    fail("unterminated JSON string")
  end
  local parse_value
  local function parse_array(depth)
    index=index+1
    whitespace()
    local values=setmetatable({}, {__index=JSON_ARRAY})
    if text:sub(index,index)=="]" then index=index+1; return values end
    while true do
      values[#values+1]=parse_value(depth+1)
      whitespace()
      local delimiter=text:sub(index,index)
      if delimiter=="]" then index=index+1; return values end
      if delimiter~="," then fail("expected ',' or ']' in JSON array") end
      index=index+1
      whitespace()
    end
  end
  local function parse_object(depth)
    index=index+1
    whitespace()
    local values={}
    if text:sub(index,index)=="}" then index=index+1; return values end
    while true do
      if text:sub(index,index)~='"' then fail("expected a JSON object key") end
      local key=parse_string()
      if values[key]~=nil then fail("duplicate JSON object key "..string.format("%q",key)) end
      whitespace()
      if text:sub(index,index)~=":" then fail("expected ':' after JSON object key") end
      index=index+1
      whitespace()
      values[key]=parse_value(depth+1)
      whitespace()
      local delimiter=text:sub(index,index)
      if delimiter=="}" then index=index+1; return values end
      if delimiter~="," then fail("expected ',' or '}' in JSON object") end
      index=index+1
      whitespace()
    end
  end
  local function parse_number()
    local start=index
    while index<=length and text:sub(index,index):match("[%d%.eE%+%-]") do index=index+1 end
    local value=text:sub(start,index-1)
    local mantissa=value:gsub("^-",""):match("^(%d+)")
    if not (value:match("^%-?%d+$") or value:match("^%-?%d+%.%d+$")
        or value:match("^%-?%d+[eE][%+%-]?%d+$")
        or value:match("^%-?%d+%.%d+[eE][%+%-]?%d+$"))
        or (mantissa and #mantissa>1 and mantissa:sub(1,1)=="0") then
      fail("invalid JSON number")
    end
    return setmetatable({value=value},{__index=JSON_NUMBER})
  end
  parse_value=function(depth)
    if depth>128 then fail("JSON-LD nesting exceeds the 128-level limit") end
    whitespace()
    local char=text:sub(index,index)
    if char=='"' then return parse_string() end
    if char=="{" then return parse_object(depth) end
    if char=="[" then return parse_array(depth) end
    if char=="-" or char:match("%d") then return parse_number() end
    if text:sub(index,index+3)=="true" then index=index+4; return true end
    if text:sub(index,index+4)=="false" then index=index+5; return false end
    if text:sub(index,index+3)=="null" then index=index+4; return JSON_NULL end
    fail("invalid JSON value")
  end
  local value=parse_value(0)
  whitespace()
  if index<=length then fail("trailing content after JSON value") end
  return value
end

local function parse_jsonld(text,source)
  local ok,document=pcall(parse_json,text)
  if not ok then fail("JSON-LD source is malformed: "..tostring(document)) end
  local url_ok,url_module=pcall(require,"socket.url")
  if not url_ok then fail("JSON-LD parsing requires LuaSocket's URL module") end
  local jsonld_prefixes,jsonld_prefix_order,prefix_conflicts={},{},{}
  local function register_prefix(prefix,namespace)
    if prefix_conflicts[prefix] then return end
    local current=jsonld_prefixes[prefix]
    if current==nil then
      jsonld_prefixes[prefix]=namespace
      jsonld_prefix_order[#jsonld_prefix_order+1]=prefix
    elseif current~=namespace then
      jsonld_prefixes[prefix]=nil
      prefix_conflicts[prefix]=true
    end
  end
  local function copy_context(context)
    local result={}
    for key,value in pairs(context) do result[key]=value end
    result.terms={}
    for key,value in pairs(context.terms or {}) do
      local definition={}
      for field,entry in pairs(value) do definition[field]=entry end
      result.terms[key]=definition
    end
    return result
  end
  local function absolute(value,base)
    if value:match("^[%a][%w+.-]*:") or value:sub(1,2)=="_:" then return value end
    if base and base~="" and base:match("^[%a][%w+.-]*:") then
      return url_module.absolute(base,value)
    end
    return value
  end
  local function expand_iri(value,context,use_vocab,active)
    if type(value)~="string" then fail("JSON-LD IRI values must be strings") end
    if value:sub(1,1)=="@" then return value end
    local definition=context.terms[value]
    if definition then
      if active[value] then fail("JSON-LD context contains a cyclic term definition") end
      active[value]=true
      local iri=expand_iri(definition.id,context,true,active)
      active[value]=nil
      return iri
    end
    local prefix,suffix=value:match("^([^:]+):(.*)$")
    if prefix and context.terms[prefix] then
      local mapping=context.terms[prefix]
      if active[prefix] then fail("JSON-LD context contains a cyclic prefix definition") end
      active[prefix]=true
      local namespace=expand_iri(mapping.id,context,true,active)
      active[prefix]=nil
      return namespace..suffix
    end
    if value:match("^[%a][%w+.-]*:") then return value end
    if use_vocab and context.vocab then return context.vocab..value end
    return absolute(value,context.base)
  end
  local apply_context
  apply_context=function(parent,value,depth)
    if depth>32 then fail("JSON-LD inline context exceeds the 32-level limit") end
    local result=copy_context(parent)
    if value==nil or value==JSON_NULL then return result end
    if type(value)=="string" then
      fail("JSON-LD remote contexts are unsupported; use an inline @context")
    end
    if is_json_array(value) then
      for _,entry in ipairs(value) do result=apply_context(result,entry,depth+1) end
      return result
    end
    if type(value)~="table" or getmetatable(value)~=nil then
      fail("JSON-LD @context must be an inline object or array of inline objects")
    end
    if value["@import"]~=nil then
      fail("JSON-LD @import is unsupported because it can load a remote context")
    end
    if value["@version"]~=nil and not (type(value["@version"])=="table"
        and getmetatable(value["@version"])
        and getmetatable(value["@version"]).__index==JSON_NUMBER
        and value["@version"].value=="1.1") then
      fail("only JSON-LD 1.1 contexts are supported")
    end
    if value["@base"]~=nil then
      if value["@base"]==JSON_NULL then result.base=nil
      elseif type(value["@base"])=="string" then
        result.base=absolute(value["@base"],parent.base)
      else fail("JSON-LD @base must be a string or null") end
    end
    if value["@vocab"]~=nil then
      if value["@vocab"]==JSON_NULL then result.vocab=nil
      elseif type(value["@vocab"])=="string" then
        result.vocab=absolute(value["@vocab"],result.base)
      else fail("JSON-LD @vocab must be a string or null") end
    end
    if value["@language"]~=nil then
      if value["@language"]~=JSON_NULL and type(value["@language"])~="string" then
        fail("JSON-LD @language must be a string or null")
      end
      if value["@language"]==JSON_NULL then result.language=nil
      else result.language=value["@language"] end
    end
    for term,definition in pairs(value) do
      if term:sub(1,1)~="@" then
        if type(definition)=="string" then
          result.terms[term]={id=definition}
        elseif type(definition)=="table" and getmetatable(definition)==nil then
          if definition["@reverse"] or definition["@context"] or definition["@nest"] then
            fail("JSON-LD reverse, scoped, and nested term definitions are unsupported")
          end
          local id=definition["@id"] or term
          if id==JSON_NULL then result.terms[term]=nil
          elseif type(id)~="string" then fail("JSON-LD term @id must be a string")
          else
            local term_definition={id=id}
            if definition["@prefix"]~=nil then
              if type(definition["@prefix"])~="boolean" then
                fail("JSON-LD term @prefix must be boolean")
              end
              term_definition.prefix=definition["@prefix"]
            end
            if definition["@type"] then
              if type(definition["@type"])~="string" then fail("JSON-LD term @type must be a string") end
              term_definition.type=definition["@type"]
            end
            if definition["@language"]~=nil then
              if definition["@language"]~=JSON_NULL and type(definition["@language"])~="string" then
                fail("JSON-LD term @language must be a string or null")
              end
              term_definition.language=definition["@language"]==JSON_NULL
                and "" or definition["@language"]
            end
            result.terms[term]=term_definition
          end
        else
          fail("JSON-LD term definitions must be strings or inline objects")
        end
      elseif term~="@base" and term~="@vocab" and term~="@language" and term~="@version" then
        fail("unsupported JSON-LD context keyword "..term)
      end
    end
    for term in pairs(value) do
      if term:sub(1,1)~="@" then
        local mapping=result.terms[term]
        if mapping and mapping.prefix~=false then
          local namespace=expand_iri(mapping.id,result,true,{})
          local inferred_prefix=namespace:match("[/#?]$")~=nil
          if mapping.prefix==true or inferred_prefix then
            register_prefix(term,namespace)
          end
        end
      end
    end
    return result
  end
  local initial={terms={},base=source and source:match("^[%a][%w+.-]*:") and source or nil}
  local triples,blank_counter={},0
  local function blank()
    blank_counter=blank_counter+1
    return "_:jsonld"..blank_counter
  end
  local emit_node,emit_value
  local is_array=is_json_array
  local function add_triple(subject,predicate,value,language,datatype)
    triples[#triples+1]={subject,predicate,value,language or "",datatype or ""}
  end
  local function property_definition(key,context)
    local iri=expand_iri(key,context,true,{})
    if iri:sub(1,1)~="@" and not iri:match("^[%a][%w+.-]*:") then
      fail("JSON-LD property "..string.format("%q",key).." does not expand to an absolute IRI")
    end
    return iri,context.terms[key]
  end
  local function iri_values(value,context)
    if is_array(value) then
      local result={}
      for _,item in ipairs(value) do result[#result+1]=expand_iri(item,context,true,{}) end
      return result
    end
    return {expand_iri(value,context,true,{})}
  end
  local function emit_list(subject,predicate,items,context,depth,term_definition)
    if not is_array(items) then fail("JSON-LD @list must contain an array") end
    local head=RDF_NIL
    if #items>0 then head=blank() end
    add_triple(subject,predicate,head)
    local cell=head
    for index,item in ipairs(items) do
      local value,language,datatype=emit_value(item,context,depth+1,term_definition)
      add_triple(cell,RDF_FIRST,value,language,datatype)
      local next_cell=index==#items and RDF_NIL or blank()
      add_triple(cell,RDF_REST,next_cell)
      cell=next_cell
    end
  end
  emit_value=function(value,context,depth,term_definition)
    if depth>128 then fail("JSON-LD nesting exceeds the 128-level limit") end
    if is_array(value) then
      fail("internal JSON-LD array expansion error")
    end
    if type(value)=="table" and getmetatable(value)
        and getmetatable(value).__index==JSON_NUMBER then
      local datatype=value.value:find("[%.eE]") and "http://www.w3.org/2001/XMLSchema#double"
        or "http://www.w3.org/2001/XMLSchema#integer"
      return value.value,"",datatype
    end
    if value==JSON_NULL then fail("JSON-LD null values do not generate RDF triples") end
    if type(value)=="boolean" then
      return value and "true" or "false","",
        "http://www.w3.org/2001/XMLSchema#boolean"
    end
    if type(value)=="string" then
      local language=term_definition and term_definition.language
      if language==nil then language=context.language or "" end
      local datatype=term_definition and term_definition.type
      if datatype then datatype=expand_iri(datatype,context,false,{}) end
      if datatype=="@id" or datatype=="@vocab" then
        return expand_iri(value,context,datatype=="@vocab",{}),"",""
      end
      return value,language or "",datatype or ""
    end
    if type(value)~="table" then fail("unsupported JSON-LD value") end
    local local_context=apply_context(context,value["@context"],0)
    if value["@list"]~=nil then
      return nil,nil,nil,local_context,value["@list"]
    end
    if value["@value"]~=nil then
      local literal=value["@value"]
      if type(literal)=="table" and getmetatable(literal)
          and getmetatable(literal).__index==JSON_NUMBER then
        return literal.value,"",
          literal.value:find("[%.eE]")
            and "http://www.w3.org/2001/XMLSchema#double"
            or "http://www.w3.org/2001/XMLSchema#integer"
      end
      if type(literal)=="boolean" then
        return literal and "true" or "false","",
          "http://www.w3.org/2001/XMLSchema#boolean"
      end
      if type(literal)~="string" then fail("JSON-LD @value must be a string, number, or boolean") end
      local language=value["@language"] or local_context.language or ""
      local datatype=value["@type"] and expand_iri(value["@type"],local_context,false,{}) or ""
      if value["@language"]==JSON_NULL then language="" end
      return literal,language,datatype
    end
    local node=emit_node(value,local_context,depth+1)
    return node,"",""
  end
  emit_node=function(node,parent_context,depth)
    if depth>128 then fail("JSON-LD nesting exceeds the 128-level limit") end
    if type(node)~="table" then fail("JSON-LD graph entries must be objects") end
    if is_array(node) then
      for _,entry in ipairs(node) do emit_node(entry,parent_context,depth+1) end
      return nil
    end
    local context=apply_context(parent_context,node["@context"],0)
    local identifier
    for key,value in pairs(node) do
      if expand_iri(key,context,true,{})=="@id" then
        if type(value)~="string" then fail("JSON-LD @id must be a string") end
        identifier=expand_iri(value,context,false,{})
      end
    end
    local subject=identifier or blank()
    local graph_values={}
    for key,value in pairs(node) do
      local predicate,definition=property_definition(key,context)
      if predicate=="@type" then
        for _,type_uri in ipairs(iri_values(value,context)) do
          add_triple(subject,RDF.."type",type_uri)
        end
      elseif predicate=="@graph" or predicate=="@included" then
        graph_values[#graph_values+1]=value
      elseif predicate=="@id" or predicate=="@context" or predicate=="@index"
          or predicate=="@value" or predicate=="@language" then
        -- These are node/value metadata, not RDF predicates.
      elseif predicate:sub(1,1)=="@" then
        fail("unsupported JSON-LD keyword "..predicate)
      else
        local values=is_array(value) and value or {value}
        for _,item in ipairs(values) do
          if type(item)=="table" and item["@list"]~=nil then
            local item_context=apply_context(context,item["@context"],0)
            emit_list(subject,predicate,item["@list"],item_context,depth+1,definition)
          else
            local object,language,datatype,_,list=emit_value(item,context,depth+1,definition)
            if list then emit_list(subject,predicate,list,_,depth+1,definition)
            else add_triple(subject,predicate,object,language,datatype) end
          end
        end
      end
    end
    for _,value in ipairs(graph_values) do emit_node(value,context,depth+1) end
    return subject
  end
  emit_node(document,initial,0)
  local prefix_order={}
  for _,term in ipairs(jsonld_prefix_order) do
    if jsonld_prefixes[term] then prefix_order[#prefix_order+1]=term end
  end
  return triples,jsonld_prefixes,prefix_order
end

-- LuaXML's DTD reader rejects qualified root names and does not expand
-- declared entities. Accept a deliberately small, non-networked DTD subset.
local function prepare_rdfxml(text)
  local entities,resolved,active={},{},{}
  local start,scan=nil,1
  -- Only a real prolog declaration is a DTD, never text in a comment/CDATA.
  while true do
    local position=text:find("<",scan,true)
    if not position then break end
    local ending
    if text:sub(position,position+3)=="<!--" then ending="-->"
    elseif text:sub(position,position+1)=="<?" then ending="?>"
    elseif text:sub(position,position+8)=="<!DOCTYPE" then start=position; break
    else break end
    local finish=text:find(ending,position+2,true)
    if not finish then fail("RDF/XML unterminated prolog declaration") end
    scan=finish+#ending
  end
  if start then
    local quote,depth,finish=nil,0,nil
    for i=start+9,#text do
      local c=text:sub(i,i)
      if quote then
        if c==quote then quote=nil end
      elseif c=='"' or c=="'" then quote=c
      elseif c=="[" then depth=depth+1
      elseif c=="]" then depth=depth-1
      elseif c==">" and depth==0 then finish=i; break end
    end
    if not finish then fail("RDF/XML source has an unterminated DOCTYPE") end
    local declaration=text:sub(start,finish)
    local header,subset=declaration:match("^<!DOCTYPE%s+([^%[]+)%[(.*)%]%s*>$")
    header=header or declaration:match("^<!DOCTYPE%s+(.-)>$")
    if not header or not trim(header):match("^[%w_:%.%-]+$") then
      fail("RDF/XML external DTDs are unsupported")
    end
    subset=(subset or ""):gsub("<!%-%-.-%-%->","")
    while trim(subset)~="" do
      local name,q,value,position=subset:match('^%s*<!ENTITY%s+([%w_:%.%-]+)%s+(["\'])(.-)%2%s*>()')
      if not name then fail("RDF/XML DTD supports only internal literal entities; external and parameter entities are unsupported") end
      if entities[name] then fail("RDF/XML duplicate entity declaration: "..name) end
      if value:find("<",1,true) or value:find("%%[%w_:%.%-]+;") then
        fail("RDF/XML entity markup and parameter references are unsupported")
      end
      entities[name]=value
      subset=subset:sub(position)
    end
    text=text:sub(1,start-1)..text:sub(finish+1)
  end
  local predefined={amp=true,lt=true,gt=true,quot=true,apos=true}
  local expand
  local function entity(name,depth)
    if predefined[name] then return "&"..name..";" end
    if resolved[name] then return resolved[name] end
    if not entities[name] then fail("RDF/XML undeclared entity: "..name) end
    if active[name] or depth>16 then fail("RDF/XML recursive or excessively nested entity: "..name) end
    active[name]=true
    local value=expand(entities[name],depth+1)
    active[name]=nil
    -- Keep replacement text safe in either kind of quoted XML attribute.
    value=value:gsub('"',"&quot;"):gsub("'","&apos;")
    resolved[name]=value
    return value
  end
  expand=function(value,depth)
    local size=0
    return (value:gsub("&([%w_:%.%-]+);",function(name)
      local replacement=entity(name,depth)
      size=size+#replacement
      if size>1024*1024 then fail("RDF/XML entity expansion limit exceeded") end
      return replacement
    end))
  end
  -- Comments, CDATA and processing instructions must retain literal entities.
  local pieces,position,total={},1,0
  while position<=#text do
    local s,e=text:find("<[!?]",position)
    local normal=text:sub(position,s and s-1 or #text)
    normal=expand(normal,0)
    total=total+#normal
    if total>8*1024*1024 then fail("RDF/XML expanded document limit exceeded") end
    pieces[#pieces+1]=normal
    if not s then break end
    local ending
    if text:sub(s,s+3)=="<!--" then ending="-->"
    elseif text:sub(s,s+8)=="<![CDATA[" then ending="]]>"
    elseif text:sub(s,s+1)=="<?" then ending="?>"
    else fail("RDF/XML unsupported declaration") end
    local last=text:find(ending,e+1,true)
    if not last then fail("RDF/XML unterminated declaration") end
    pieces[#pieces+1]=text:sub(s,last+#ending-1)
    position=last+#ending
  end
  return table.concat(pieces)
end

local function parse_rdfxml(text,source)
  kpse.set_program_name("luatex")
  local dom_ok, dom = pcall(require,"luaxml-domobject")
  if not dom_ok then fail("RDF/XML parsing requires TeX Live's LuaXML module: " .. tostring(dom)) end
  local ok, document = pcall(dom.parse,text)
  if not ok then fail("RDF/XML source is malformed: " .. tostring(document)) end
  local root=document:root_node()
  local triples,counter={},0
  local function expanded_tag(tag,namespaces)
    local prefix,local_part=tag:match("^([^:]+):(.+)$")
    if prefix then return (namespaces[prefix] or "") .. local_part end
    return (namespaces[""] or "") .. tag
  end
  local function attribute(node,name,namespaces)
    local wanted=expanded_tag(name,{rdf=RDF,xml=XML}):lower()
    for key,value in pairs(node._attr or {}) do
      if expanded_tag(key,namespaces or {rdf=RDF,xml=XML}):lower()==wanted then return value end
    end
    return nil
  end
  local url=require("socket.url")
  local function resolve(value,base)
    if value:match("^[%a][%w+.-]*:") then return value end
    return url.absolute(base or source or "",value)
  end
  local function context(node,namespaces,base,language)
    local ns={xml=XML}
    for key,value in pairs(namespaces or {}) do ns[key]=value end
    for key,value in pairs(node._attr or {}) do
      local prefix=key:match("^xmlns:(.+)$")
      if prefix then ns[prefix]=value elseif key=="xmlns" then ns[""]=value end
    end
    local own_base=attribute(node,"xml:base",ns)
    if own_base then base=resolve(own_base,base) end
    return ns,base,attribute(node,"xml:lang",ns) or language or ""
  end
  local function text_content(node)
    local pieces={}
    local function gather(current)
      if current._type=="TEXT" or current._type=="CDATA" then
        pieces[#pieces+1]=current._text or ""
      else
        for _,child in ipairs(current._children or {}) do gather(child) end
      end
    end
    gather(node)
    return trim(table.concat(pieces))
  end
  local visit,properties
  local function blank()
    counter=counter+1
    return "_:rdftools" .. counter
  end
  properties=function(resource,subject,namespaces,base,language)
    for _,child in ipairs(resource._children or {}) do
      if child._type=="ELEMENT" then
        local child_ns,child_base,child_language=context(child,namespaces,base,language)
        local parse_type=attribute(child,"rdf:parsetype",child_ns) or ""
        if parse_type~="" and parse_type~="Resource" and parse_type~="Collection" then
          fail("RDF/XML source uses unsupported rdf:parseType=" .. string.format("%q",parse_type))
        end
        local predicate=expanded_tag(child._name or "",child_ns)
        local resource_value=attribute(child,"rdf:resource",child_ns)
        local node_id=attribute(child,"rdf:nodeid",child_ns)
        if resource_value and node_id then
          fail("RDF/XML source gives a property both rdf:resource and rdf:nodeID")
        end
        local elements={}
        for _,nested in ipairs(child._children or {}) do
          if nested._type=="ELEMENT" then elements[#elements+1]=nested end
        end
        local value,literal_language,datatype
        if (resource_value or node_id) and (#elements>0 or parse_type~="") then
          fail("RDF/XML resource property has conflicting content")
        end
        if resource_value then value=resolve(resource_value,child_base)
        elseif node_id then value="_:"..node_id
        elseif parse_type=="Collection" then
          if attribute(child,"rdf:datatype",child_ns) then
            fail("RDF/XML Collection cannot have rdf:datatype")
          end
          for _,nested in ipairs(child._children or {}) do
            if (nested._type=="TEXT" or nested._type=="CDATA")
                and trim(nested._text or "")~="" then
              fail("RDF/XML Collection must contain resource nodes, not literal text")
            end
          end
          -- A collection is an ordered RDF list, not extra properties on
          -- the containing resource. An empty collection is rdf:nil.
          value=RDF_NIL
          local tail
          for _,member in ipairs(elements) do
            local cell=blank()
            if tail then triples[#triples+1]={tail,RDF_REST,cell,"",""}
            else value=cell end
            local member_subject=visit(member,child_language,child_ns,child_base)
            triples[#triples+1]={cell,RDF_FIRST,member_subject,"",""}
            tail=cell
          end
          if tail then triples[#triples+1]={tail,RDF_REST,RDF_NIL,"",""} end
        elseif parse_type=="Resource" then
          value=blank()
          properties(child,value,child_ns,child_base,child_language)
        elseif #elements>0 then
          if #elements~=1 then fail("RDF/XML property must contain exactly one resource node") end
          value=visit(elements[1],child_language,child_ns,child_base)
        else
          value=text_content(child)
          datatype=attribute(child,"rdf:datatype",child_ns)
          if datatype then datatype=resolve(datatype,child_base) end
          literal_language=datatype and "" or child_language
        end
        triples[#triples+1]={subject,predicate,value,literal_language or "",datatype or ""}
      end
    end
  end
  visit=function(resource,language,namespaces,base)
    namespaces,base,language=context(resource,namespaces,base,language)
    local about=attribute(resource,"rdf:about",namespaces)
    local identifier=attribute(resource,"rdf:id",namespaces)
    local node_id=attribute(resource,"rdf:nodeid",namespaces)
    local subject
    if about~=nil then subject=resolve(about,base)
    elseif identifier then subject=resolve("#"..identifier,base)
    elseif node_id then subject="_:"..node_id
    else subject=blank() end
    local resource_type=expanded_tag(resource._name or "",namespaces)
    if resource_type~=RDF.."Description" then
      triples[#triples+1]={subject,RDF.."type",resource_type,"",""}
    end
    properties(resource,subject,namespaces,base,language)
    return subject
  end
  local root_element
  for _,child in ipairs(root._children or {}) do if child._type=="ELEMENT" then root_element=child; break end end
  if not root_element then fail("RDF/XML source is malformed: no document element") end
  local namespaces,base,language=context(root_element,{},source,"")
  if expanded_tag(root_element._name or "",namespaces)==RDF.."RDF" then
    for _,resource in ipairs(root_element._children or {}) do
      if resource._type=="ELEMENT" then visit(resource,language,namespaces,base) end
    end
  else
    visit(root_element,"",{},source)
  end
  return triples,{},{}
end

local function tex_escape(value)
  local replacements={
    ["\\"]= "\\textbackslash{}", ["{"]="\\{", ["}"]="\\}", ["#"]="\\#",
    ["$"]="\\$", ["%"]="\\%", ["&"]="\\&", ["_"]="\\_",
    ["^"]="\\textasciicircum{}", ["~"]="\\textasciitilde{}",
  }
  local result={}
  for index=1,#value do
    local char=value:sub(index,index)
    result[#result+1]=replacements[char] or char
  end
  return table.concat(result)
end

local function bib_escape(value,url)
  value=trim(value:gsub("%s+"," "))
  local replacements
  if url then replacements={["\\"]="\\textbackslash{}",["{"]="\\{",["}"]="\\}"}
  else replacements={
    ["\\"]="\\textbackslash{}",["{"]="\\{",["}"]="\\}",["#"]="\\#",
    ["$"]="\\$",["%"]="\\%",["&"]="\\&",["_"]="\\_",
    ["^"]="\\textasciicircum{}",["~"]="\\textasciitilde{}",
  } end
  local result={}
  for index=1,#value do
    local char=value:sub(index,index)
    result[#result+1]=replacements[char] or char
  end
  return table.concat(result)
end

local function sha1(message)
  local bit=bit32
  local bytes={message:byte(1,#message)}
  local bit_length=#bytes*8
  bytes[#bytes+1]=0x80
  while (#bytes%64)~=56 do bytes[#bytes+1]=0 end
  local high=math.floor(bit_length/4294967296)
  local low=bit_length%4294967296
  for shift=24,0,-8 do bytes[#bytes+1]=bit.band(bit.rshift(high,shift),255) end
  for shift=24,0,-8 do bytes[#bytes+1]=bit.band(bit.rshift(low,shift),255) end
  local h0,h1,h2,h3,h4=0x67452301,0xEFCDAB89,0x98BADCFE,0x10325476,0xC3D2E1F0
  for offset=1,#bytes,64 do
    local w={}
    for index=0,15 do
      local p=offset+index*4
      w[index]=bit.bor(bit.lshift(bytes[p],24),bit.lshift(bytes[p+1],16),bit.lshift(bytes[p+2],8),bytes[p+3])
    end
    for index=16,79 do w[index]=bit.lrotate(bit.bxor(w[index-3],w[index-8],w[index-14],w[index-16]),1) end
    local a,b,c,d,e=h0,h1,h2,h3,h4
    for index=0,79 do
      local f,k
      if index<20 then f=bit.bor(bit.band(b,c),bit.band(bit.bnot(b),d)); k=0x5A827999
      elseif index<40 then f=bit.bxor(b,c,d); k=0x6ED9EBA1
      elseif index<60 then f=bit.bor(bit.band(b,c),bit.band(b,d),bit.band(c,d)); k=0x8F1BBCDC
      else f=bit.bxor(b,c,d); k=0xCA62C1D6 end
      local temp=(bit.lrotate(a,5)+f+e+k+w[index])%4294967296
      e,d,c,b,a=d,c,bit.lrotate(b,30),a,temp
    end
    h0=(h0+a)%4294967296; h1=(h1+b)%4294967296; h2=(h2+c)%4294967296
    h3=(h3+d)%4294967296; h4=(h4+e)%4294967296
  end
  return string.format("%08x%08x%08x%08x%08x",h0,h1,h2,h3,h4)
end

local function citation_key(prefix,subject)
  return "rdfref-" .. sha1(prefix .. "\0" .. subject):sub(1,16)
end

local function compact_uri(uri,prefixes,prefix_order)
  local result,best=uri,-1
  for _,prefix in ipairs(prefix_order or {}) do
    local namespace=prefixes[prefix]
    if namespace and #namespace>best and uri:sub(1,#namespace)==namespace then
      local term=uri:sub(#namespace+1)
      if term~="" and not term:find("[/#%s]") then
        result=prefix..":"..term
        best=#namespace
      end
    end
  end
  return result
end

local function aliases(subject,prefixes,prefix_order,include_local_name)
  local values,seen={},{}
  local function add(value) if not seen[value] then seen[value]=true; values[#values+1]=value end end
  add(subject)
  for _,prefix in ipairs(prefix_order or {}) do
    local namespace=prefixes[prefix]
    if prefix~="" and subject:sub(1,#namespace)==namespace then add(prefix .. ":" .. subject:sub(#namespace+1)) end
  end
  if include_local_name~=false then add(local_name(subject)) end
  return values
end

local function triples_by_subject(triples)
  local grouped={}
  for _,triple in ipairs(triples) do
    grouped[triple[1]]=grouped[triple[1]] or {}
    grouped[triple[1]][#grouped[triple[1]]+1]={triple[2],triple[3],triple[4],triple[5]}
  end
  return grouped
end

local function list_values(value,language,datatype,grouped)
  if value==RDF_NIL then return {} end
  local first_present,rest_present=false,false
  for _,item in ipairs(grouped[value] or {}) do
    if item[1]==RDF_FIRST then first_present=true
    elseif item[1]==RDF_REST then rest_present=true end
  end
  if not first_present or not rest_present then return {{value,language,datatype}} end
  local values,current,seen={},value,{}
  while current~=RDF_NIL and not seen[current] do
    seen[current]=true
    local first,rest
    for _,item in ipairs(grouped[current] or {}) do
      if item[1]==RDF_FIRST and not first then
        first={item[2],item[3],item[4]}
      elseif item[1]==RDF_REST and not rest then
        rest=item[2]
      end
    end
    if not first then break end
    values[#values+1]=first
    current=rest or RDF_NIL
  end
  return #values>0 and values or {{value,language,datatype}}
end

local function objects_for(subject,predicates,grouped,expand_lists)
  local predicate_set=list_to_set(predicates)
  local values={}
  for _,item in ipairs(grouped[subject] or {}) do
    if predicate_set[item[1]] then
      if expand_lists then
        for _,value in ipairs(list_values(item[2],item[3],item[4],grouped)) do
          values[#values+1]=value
        end
      else
        values[#values+1]={item[2],item[3],item[4]}
      end
    end
  end
  return values
end

local function first_object(subject,predicates,grouped)
  return objects_for(subject,predicates,grouped)[1]
end

local function resource_text(value,grouped,preferred)
  if not grouped[value] then return value end
  local predicates={}
  for _,v in ipairs(preferred or {}) do predicates[#predicates+1]=v end
  for _,v in ipairs({FOAF.."name",SCHEMA.."name","http://schema.org/name",RDFS.."label",DC.."title",DCTERMS.."title"}) do predicates[#predicates+1]=v end
  local label=first_object(value,predicates,grouped)
  return label and label[1] or local_name(value)
end

local function person_text(value,grouped)
  local family=first_object(value,{FOAF.."familyName",SCHEMA.."familyName","http://schema.org/familyName"},grouped)
  local given=first_object(value,{FOAF.."givenName",SCHEMA.."givenName","http://schema.org/givenName"},grouped)
  if family and given then return family[1] .. ", " .. given[1] end
  if family then return family[1] end
  return resource_text(value,grouped)
end

local function bib_value(subject,predicates,grouped)
  local value=first_object(subject,predicates,grouped)
  return value and resource_text(value[1],grouped) or ""
end

local function bibo_entries(prefix,triples,prefixes,prefix_order)
  local grouped=triples_by_subject(triples)
  local subject_types,ordered_subjects={},{}
  for _,triple in ipairs(triples) do
    if triple[2]==RDF.."type" and triple[3]:sub(1,#BIBO)==BIBO then
      if not subject_types[triple[1]] then subject_types[triple[1]]={} ; ordered_subjects[#ordered_subjects+1]=triple[1] end
      subject_types[triple[1]][#subject_types[triple[1]]+1]=triple[3]
    end
  end
  local entries,bib_aliases,warnings={},{},{}
  for _,subject in ipairs(ordered_subjects) do
    local type_name=local_name(subject_types[subject][1])
    local entry_type=BIBO_ENTRY_TYPES[type_name] or "misc"
    local key=citation_key(prefix,subject)
    local fields,field_order={},{}
    local function put(name,value)
      if value and value~="" then
        if fields[name]==nil then field_order[#field_order+1]=name end
        fields[name]=value
      end
    end
    local author_predicates={{BIBO.."authorList"},{BIBO.."author"},{DC.."creator",DCTERMS.."creator"}}
    local authors={}
    for _,group in ipairs(author_predicates) do authors=objects_for(subject,group,grouped,true); if #authors>0 then break end end
    if #authors>0 then
      local names={}
      for _,item in ipairs(authors) do names[#names+1]=person_text(item[1],grouped) end
      put("author",table.concat(names," and "))
    end
    local editor_groups={{BIBO.."editorList"},{BIBO.."editor"},{DC.."contributor",DCTERMS.."contributor"}}
    local editors={}
    for _,group in ipairs(editor_groups) do editors=objects_for(subject,group,grouped,true); if #editors>0 then break end end
    if #editors>0 then
      local names={}
      for _,item in ipairs(editors) do names[#names+1]=person_text(item[1],grouped) end
      put("editor",table.concat(names," and "))
    end
    for _,field in ipairs(BIBO_FIELD_PREDICATES) do put(field[1],bib_value(subject,field[2],grouped)) end
    local date_value=bib_value(subject,BIBO_DATE_PREDICATES,grouped)
    put("date",date_value)
    if date_value~="" then put("year",date_value:match("%f[%d]([12]%d%d%d)%f[%D]")) end
    if fields.pages==nil then
      local start=fields.pageStart or ""; local finish=fields.pageEnd or ""
      fields.pageStart=nil; fields.pageEnd=nil
      if start~="" and finish~="" then put("pages",start.."--"..finish)
      elseif start~="" then put("pages",start) elseif finish~="" then put("pages",finish) end
    else fields.pageStart=nil; fields.pageEnd=nil end
    for _,predicate in ipairs(BIBO_IDENTIFIER_PREDICATES) do
      if not fields.doi and not fields.isbn and not fields.issn then
        local identifier=bib_value(subject,{predicate},grouped)
        if identifier~="" then put("note","Identifier: "..identifier); break end
      end
    end
    local explicit_title=first_object(subject,BIBO_FIELD_PREDICATES[1][2],grouped)
    if fields.title==nil then put("title",local_name(subject)) end
    if not explicit_title then warnings[#warnings+1]=key end
    entries[#entries+1]={key,entry_type,fields,field_order}
    for _,alias in ipairs(aliases(subject,prefixes,prefix_order)) do bib_aliases[#bib_aliases+1]={alias,key} end
  end
  return entries,bib_aliases,warnings
end

local function write_bib(path,entries)
  local lines={"% RDFTools generated BibTeX cache; do not edit."}
  for _,entry in ipairs(entries) do
    local key,entry_type,fields,field_order=entry[1],entry[2],entry[3],entry[4]
    lines[#lines+1]="@"..entry_type.."{"..key..","
    for index,field in ipairs(field_order) do
      local value=bib_escape(fields[field],field=="url" or field=="doi")
      local suffix=index<#field_order and "," or ""
      lines[#lines+1]="  "..field.." = {"..value.."}"..suffix
    end
    lines[#lines+1]="}"
    lines[#lines+1]=""
  end
  write_file(path,table.concat(lines,"\n"))
end

local function xml_prefixes(text)
  local prefixes,order={},{}
  for name,quote,value in text:gmatch("([%w_:%.%-]+)%s*=%s*([\"'])(.-)%2") do
    if name=="xmlns" or name:match("^xmlns:") then
      local prefix=name:match("^xmlns:(.+)$") or ""
      if prefixes[prefix]==nil then order[#order+1]=prefix end
      value=value:gsub("&#[xX](%x+);",codepoint_escape)
      value=value:gsub("&#(%d+);",function(decimal)
        local number=tonumber(decimal,10)
        if not number or number>0x10ffff or (number>=0xd800 and number<=0xdfff) then
          fail("invalid XML character reference in namespace declaration")
        end
        return utf8.char(number)
      end)
      local entities={amp="&",lt="<",gt=">",quot='"',apos="'"}
      value=value:gsub("&([%a]+);",function(entity)
        return entities[entity] or ("&"..entity..";")
      end)
      prefixes[prefix]=value
    end
  end
  return prefixes,order
end

local function cache_records(prefix,source,triples,prefixes,prefix_order,kind,bib_output)
  local entries,bib_aliases,bib_warnings=bibo_entries(prefix,triples,prefixes,prefix_order)
  local lines={"% RDFTools generated cache; do not edit.","%% source: "..tex_escape(source),"%% format: "..kind}
  for _,item in ipairs(bib_aliases) do
    lines[#lines+1]="\\RDFReferenceBibRecord{"..tex_escape(prefix).."}{"..tex_escape(item[1]).."}{"..item[2].."}"
  end
  for _,key in ipairs(bib_warnings) do
    lines[#lines+1]="\\RDFReferenceBibWarning{"..tex_escape(prefix).."}{"..key.."}"
  end
  local subject_types,subjects,subject_seen={},{},{}
  local local_name_subjects,local_name_owner={},{}
  local super_terms={}
  local super_parents,super_parent_seen={},{}
  local hierarchy_parents={class={},property={}}
  local hierarchy_seen={class={},property={}}
  for _,triple in ipairs(triples) do
    local subject,predicate,parent=triple[1],triple[2],triple[3]
    -- Anonymous OWL restrictions are graph nodes, not named list entries.
    if (predicate==RDFS.."subClassOf" or predicate==RDFS.."subPropertyOf")
        and parent~="" and parent:sub(1,2)~="_:" then
      super_parents[subject]=super_parents[subject] or {}
      super_parent_seen[subject]=super_parent_seen[subject] or {}
      local seen=super_parent_seen[subject]
      if not seen[parent] then
        seen[parent]=true
        super_parents[subject][#super_parents[subject]+1]=parent
      end
      local kind=predicate==RDFS.."subClassOf" and "class" or "property"
      local graph,graph_seen=hierarchy_parents[kind],hierarchy_seen[kind]
      graph[subject]=graph[subject] or {}
      graph_seen[subject]=graph_seen[subject] or {}
      if not graph_seen[subject][parent] then
        graph_seen[subject][parent]=true
        graph[subject][#graph[subject]+1]=parent
      end
    end
  end
  local function ancestors(graph,subject)
    local ordered,queue,seen={}, {subject}, {[subject]=true}
    local position=1
    while position<=#queue do
      local current=queue[position]
      position=position+1
      for _,parent in ipairs(graph[current] or {}) do
        if not seen[parent] then
          seen[parent]=true
          ordered[#ordered+1]=parent
          queue[#queue+1]=parent
        end
      end
    end
    return ordered
  end
  for subject in pairs(super_parents) do
    super_terms[subject]=ancestors(super_parents,subject)
  end
  for _,triple in ipairs(triples) do
    if not subject_seen[triple[1]] then
      subject_seen[triple[1]]=true
      subjects[#subjects+1]=triple[1]
      if triple[1]:sub(1,2)~="_:" then
        local name=local_name(triple[1])
        local_name_subjects[name]=local_name_subjects[name] or {}
        local_name_subjects[name][#local_name_subjects[name]+1]=triple[1]
      end
    end
    if triple[2]==RDF.."type" and RESOURCE_TYPES[triple[3]] then
      subject_types[triple[1]]=math.min(subject_types[triple[1]] or 99,RESOURCE_TYPES[triple[3]])
    end
  end
  local preferred_namespace=prefixes[prefix]
  for name,candidates in pairs(local_name_subjects) do
    if #candidates==1 then
      local_name_owner[name]=candidates[1]
    elseif preferred_namespace then
      local preferred
      for _,subject in ipairs(candidates) do
        if subject:sub(1,#preferred_namespace)==preferred_namespace then
          if preferred then preferred=nil; break end
          preferred=subject
        end
      end
      if preferred then local_name_owner[name]=preferred end
    end
  end
  local function subject_aliases(subject)
    return aliases(
      subject,prefixes,prefix_order,
      local_name_owner[local_name(subject)]==subject
    )
  end
  for _,subject in ipairs(subjects) do
    if subject:sub(1,2)~="_:" and subject_types[subject]~=1 then
      lines[#lines+1]="\\RDFReferenceTermRecord{"..tex_escape(prefix).."}{"..
        tex_escape(subject).."}{rdftools-"..sha1(subject).."}{"..
        tex_escape(local_name(subject)).."}"
      for _,kind in ipairs({"class","property"}) do
        for _,parent in ipairs(ancestors(hierarchy_parents[kind],subject)) do
          lines[#lines+1]="\\RDFReferenceHierarchyRecord{"..tex_escape(prefix).."}{"..
            tex_escape(subject).."}{"..kind.."}{"..tex_escape(parent).."}{"..
            tex_escape(compact_uri(parent,prefixes,prefix_order)).."}"
        end
      end
    end
    for _,alias in ipairs(subject_aliases(subject)) do
      lines[#lines+1]="\\RDFReferenceURIRecord{"..tex_escape(prefix).."}{"..tex_escape(alias).."}{"..tex_escape(subject).."}"
      for _,parent in ipairs(super_terms[subject] or {}) do
        lines[#lines+1]="\\RDFReferenceSuperRecord{"..tex_escape(prefix).."}{"..tex_escape(alias).."}{"..tex_escape(parent).."}"
      end
      for _,parent in ipairs(super_parents[subject] or {}) do
        lines[#lines+1]="\\RDFReferenceDirectSuperRecord{"..tex_escape(prefix).."}{"..tex_escape(alias).."}{"..tex_escape(parent).."}"
      end
    end
  end
  for _,triple in ipairs(triples) do
    local subject,predicate,value,language=triple[1],triple[2],triple[3],triple[4]
    local name_rank=NAME_PREDICATES[predicate]
    local definition_rank=DEFINITION_PREDICATES[predicate]
    local item_kind,rank
    if name_rank then item_kind="name"; rank=name_rank
    elseif definition_rank then item_kind="definition"; rank=definition_rank end
    local language_value,region=language or "",""
    if language_value:find("-",1,true) then
      local hyphen=language_value:find("-",1,true)
      region=language_value:sub(hyphen+1); language_value=language_value:sub(1,hyphen-1)
    end
    if item_kind then
      for _,alias in ipairs(subject_aliases(subject)) do
        lines[#lines+1]="\\RDFReferenceRecord{"..tex_escape(prefix).."}{"..tex_escape(alias).."}{"..item_kind.."}{"..tex_escape(language_value).."}{"..tex_escape(region).."}{"..rank.."}{"..tex_escape(value).."}"
      end
    end
    local metadata_rank=subject_types[subject]
    if metadata_rank then
      if TITLE_PREDICATES[predicate] then
        lines[#lines+1]="\\RDFReferenceMetadataRecord{"..tex_escape(prefix).."}{title}{"..metadata_rank.."}{"..tex_escape(language_value).."}{"..tex_escape(region).."}{1}{"..tex_escape(value).."}"
      end
      local version_rank=VERSION_PREDICATES[predicate]
      if version_rank and (metadata_rank~=1 or predicate==OWL.."versionInfo") then
        lines[#lines+1]="\\RDFReferenceMetadataRecord{"..tex_escape(prefix).."}{version}{"..metadata_rank.."}{}{}{ "..version_rank.."}{"..tex_escape(value).."}"
        lines[#lines]=lines[#lines]:gsub("{ (%d+)}","{%1}")
      end
      if name_rank then
        lines[#lines+1]="\\RDFReferenceMetadataRecord{"..tex_escape(prefix).."}{source-name}{"..metadata_rank.."}{"..tex_escape(language_value).."}{"..tex_escape(region).."}{"..name_rank.."}{"..tex_escape(value).."}"
      end
    end
  end
  return table.concat(lines,"\n").."\n",entries,bib_warnings
end

local function write_cache(prefix,source,output,bib_output)
  local text,content_type=read_source(source,output..".source")
  local kind=detect_format(source,text,content_type)
  local triples,prefixes,prefix_order
  if kind=="rdfxml" then
    text=prepare_rdfxml(text)
    triples,prefixes,prefix_order=parse_rdfxml(text,source)
    prefixes,prefix_order=xml_prefixes(text)
  elseif kind=="jsonld" then
    triples,prefixes,prefix_order=parse_jsonld(text,source)
  elseif kind=="nquads" then triples,prefixes,prefix_order=parse_nquads(text)
  else triples,prefixes,prefix_order=parse_turtle(text) end
  local cache,entries,bib_warnings=cache_records(prefix,source,triples,prefixes,prefix_order,kind,bib_output)
  if bib_output then write_bib(bib_output,entries) end
  write_file(output,cache)
  return bib_warnings
end

local function decode_codepoints(value)
  if not value:match("^[%x,]*$") then fail("invalid source manifest field") end
  local pieces={}
  for point in value:gmatch("[^,]+") do
    local number=tonumber(point,16)
    if not number or number>0x10ffff or (number>=0xd800 and number<=0xdfff) then
      fail("invalid source manifest character")
    end
    pieces[#pieces+1]=utf8.char(number)
  end
  return table.concat(pieces)
end

local function prepare_sources(sources_hex,cache_prefix,warnings_path)
  local warnings={}
  local warnings_output=cache_path(warnings_path)
  os.remove(warnings_output)
  for line in (sources_hex..";"):gmatch("(.-);") do
    if line~="" then
      local prefix_hex,source_hex=line:match("^([^|]*)|(.*)$")
      if not prefix_hex then fail("malformed source manifest") end
      local prefix,source=decode_codepoints(prefix_hex),decode_codepoints(source_hex)
      if prefix=="" or source=="" then fail("source manifest has an empty prefix or source") end
      local output=cache_prefix..prefix..".tex"
      local bib_output=cache_prefix..prefix..".bib"
      output=cache_path(output)
      bib_output=cache_path(bib_output)
      -- Do not allow an earlier compilation's cache to hide a failed parse.
      os.remove(output)
      os.remove(bib_output)
      local bib_warnings=write_cache(prefix,source,output,bib_output)
      for _,key in ipairs(bib_warnings) do
        warnings[#warnings+1]="\\RDFReferenceBibWarning{"..tex_escape(prefix).."}{"..key.."}"
      end
    end
  end
  write_file(warnings_output,table.concat(warnings,"\n")..(#warnings>0 and "\n" or ""))
end

local function sort_index(input_path,output_path)
  if not file_exists(input_path) then write_file(output_path,""); return end
  local entries,keys={},{}
  for line in (read_file(input_path).."\n"):gmatch("(.-)\n") do
    local term,prefix,page,anchor=line:match("\\RDFReferenceIndexEntry{(.-)}{(.-)}{(.-)}%[?(.-)%]?%s*$")
    if term then
      local key=prefix.."\0"..term
      if not entries[key] then keys[#keys+1]=key end
      entries[key]={term,prefix,page,anchor or "",entries[key] and entries[key][5] or #keys}
    end
  end
  local ordered={}
  for _,key in ipairs(keys) do ordered[#ordered+1]=entries[key] end
  table.sort(ordered,function(a,b)
    local al,bl=a[1]:lower(),b[1]:lower()
    if al==bl then
      if a[2]~=b[2] then return a[2]<b[2] end
      return a[5]<b[5]
    end
    return al<bl
  end)
  local lines={}
  for _,entry in ipairs(ordered) do
    local line="\\RDFReferenceIndexEntry{"..entry[1].."}{"..entry[2].."}{"..entry[3].."}"
    if entry[4]~="" then line=line.."["..entry[4].."]" end
    lines[#lines+1]=line
  end
  write_file(output_path,table.concat(lines,"\n")..(#lines>0 and "\n" or ""))
end

local function finalize_used(input_path,output_path)
  if not file_exists(input_path) then fail("missing used glossary list: "..input_path) end
  local lines,seen={},{}
  for line in (read_file(input_path).."\n"):gmatch("(.-)\n") do
    if line~="" then
      local id=line:match("^\\RDFToolsUsedTerm{(rdftools%-%x+)}$")
      if not id or #id~=49 then fail("invalid used glossary term record") end
      if not seen[id] then
        seen[id]=true
        lines[#lines+1]=line
      end
    end
  end
  write_file(output_path,table.concat(lines,"\n")..(#lines>0 and "\n" or ""))
end

local function parse_args(args)
  local command=args[1]
  if command~="parse" and command~="sort-index"
      and command~="init-index" and command~="append-index"
      and command~="prepare-sources" and command~="finalize-used" then
    fail("usage: texlua RDFTools.lua parse --prefix PREFIX --source FILE --output FILE [--bib-output FILE]\n       texlua RDFTools.lua prepare-sources --sources-hex DATA --cache-prefix PATH --warnings FILE\n       texlua RDFTools.lua sort-index --input FILE --output FILE\n       texlua RDFTools.lua finalize-used --input FILE --output FILE\n       texlua RDFTools.lua init-index --output FILE\n       texlua RDFTools.lua append-index --output FILE --data-hex CODEPOINTS")
  end
  local options={}
  local index=2
  while index<=#args do
    local key=args[index]
    local value=args[index+1]
    if not key or key:sub(1,2)~="--" or not value or value:sub(1,2)=="--" then fail("missing value for option " .. tostring(key)) end
    options[key:sub(3)]=value
    index=index+2
  end
  local required=command=="parse" and {"prefix","source","output"}
    or command=="prepare-sources" and {"sources-hex","cache-prefix","warnings"}
    or (command=="sort-index" or command=="finalize-used") and {"input","output"}
    or command=="append-index" and {"output","data-hex"} or {"output"}
  for _,key in ipairs(required) do if not options[key] then fail("missing required option --"..key) end end
  return command,options
end

local ok, message = xpcall(function()
  local command,options=parse_args(arg)
  if command=="parse" then
    local output=cache_path(options.output)
    local bib_output=options["bib-output"] and cache_path(options["bib-output"])
    write_cache(options.prefix,options.source,output,bib_output)
  elseif command=="prepare-sources" then
    prepare_sources(
      options["sources-hex"],
      options["cache-prefix"],
      options.warnings
    )
  elseif command=="sort-index" then sort_index(options.input,cache_path(options.output))
  elseif command=="finalize-used" then finalize_used(options.input,cache_path(options.output))
  elseif command=="init-index" then write_file(cache_path(options.output),"")
  else
    local data=options["data-hex"]
    if not data:match("^[%x,]*$") then fail("invalid hexadecimal index data") end
    local pieces={}
    for point in data:gmatch("[^,]+") do
      local number=tonumber(point,16)
      if not number or number>0x10ffff or (number>=0xd800 and number<=0xdfff) then
        fail("invalid index character")
      end
      pieces[#pieces+1]=utf8.char(number)
    end
    write_file(cache_path(options.output),table.concat(pieces).."\n","ab")
  end
end,function(err) return tostring(err) end)

if not ok then
  io.stderr:write("RDFTools: ",message,"\n")
  os.exit(1)
end
