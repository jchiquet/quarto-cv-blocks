-- YAML file loader for cv-blocks.
--
-- Pandoc's Lua sandbox has no YAML decoder. An earlier version of this
-- module piggybacked on Pandoc's own YAML-metadata-block parser (wrap the
-- file in `---\n...\n---\n`, read it as Markdown, take `.meta`) — but that
-- routes every string scalar through Pandoc's Markdown *inline* parser,
-- which mangles the raw LaTeX macros our fields must stay opaque to
-- (`\href{...}{...}`, `\em`, `\phd`, backslash-escapes, ...). Confirmed
-- empirically: `\href{...}{Some \em text}` decoded to `` and `` — the
-- LaTeX was silently eaten.
--
-- Instead we shell out to Python + PyYAML to convert YAML -> JSON, and
-- decode the JSON with `pandoc.json.decode`, which does a literal,
-- non-reinterpreting decode straight into plain Lua
-- tables/strings/booleans.

local M = {}

-- pandoc.json.decode represents JSON `null` as a distinct userdata
-- sentinel (`pandoc.json.null`), not Lua `nil` — so `heading: null` in a
-- data file would otherwise decode to a truthy, unusable value instead of
-- simply being absent. Strip it recursively so callers can use plain
-- `if value then ... end` checks.
local function strip_json_null(value)
  if value == pandoc.json.null then
    return nil
  elseif type(value) == "table" then
    local out = {}
    for k, v in pairs(value) do
      out[k] = strip_json_null(v)
    end
    return out
  else
    return value
  end
end

local YAML_TO_JSON = [[
import sys, json, yaml
with open(sys.argv[1], encoding="utf-8") as f:
    data = yaml.safe_load(f)
json.dump(data, sys.stdout, ensure_ascii=False)
]]

--- Reads a YAML file and returns it as plain Lua tables.
-- @param path string path to a .yml file
-- @return table|nil decoded content, or nil + error message on failure
function M.read_yaml_file(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil, ("cv-blocks: cannot find YAML file " .. path)
  end
  fh:close()

  local ok, json_text = pcall(pandoc.pipe, "python3", { "-c", YAML_TO_JSON, path }, "")
  if not ok then
    return nil, ("cv-blocks: failed to run python3/pyyaml on " .. path .. ": " .. tostring(json_text))
  end

  local ok2, data = pcall(pandoc.json.decode, json_text)
  if not ok2 then
    return nil, ("cv-blocks: failed to decode JSON produced from " .. path .. ": " .. tostring(data))
  end

  return strip_json_null(data)
end

local BIB_KEYS = [[
import sys, re, json
text = open(sys.argv[1], encoding="utf-8").read()
print(json.dumps(re.findall(r"@\w+\s*\{\s*([^,\s]+)\s*,", text)))
]]

--- Extracts BibTeX/biblatex entry keys from a .bib file (a plain regex
-- over `@type{key,`, not a real parser — `\nocite` silently ignores any
-- spurious key this over-matches, so it doesn't need to be exact). Used
-- to build `\nocite{key1,key2,...}` for each bibliography section, since
-- biblatex has no built-in way to filter `\printbibliography` by
-- originating .bib file (confirmed empirically:
-- `\addbibresource[label=]`/`\printbibliography[label=]` do NOT filter,
-- despite looking like they should) -- see cv-patterns.lua.
-- @param path string path to a .bib file
-- @return table|nil array of citation keys, or nil + error message
function M.read_bib_keys(path)
  local fh = io.open(path, "r")
  if not fh then
    return nil, ("cv-blocks: cannot find bib file " .. path)
  end
  fh:close()

  local ok, json_text = pcall(pandoc.pipe, "python3", { "-c", BIB_KEYS, path }, "")
  if not ok then
    return nil, ("cv-blocks: failed to extract keys from " .. path .. ": " .. tostring(json_text))
  end

  local ok2, keys = pcall(pandoc.json.decode, json_text)
  if not ok2 then
    return nil, ("cv-blocks: failed to decode key list from " .. path .. ": " .. tostring(keys))
  end

  return keys
end

local BIB_FIELD = [[
import sys, re, json

path, key, field = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()

entry_re = re.compile(r"@\w+\s*\{\s*" + re.escape(key) + r"\s*,")
m = entry_re.search(text)
if not m:
    print(json.dumps(None))
    sys.exit(0)

start = m.end()
next_at = text.find("\n@", start)
entry_text = text[start:next_at if next_at != -1 else len(text)]

field_re = re.compile(r"\b" + re.escape(field) + r"\s*=\s*\{", re.IGNORECASE)
fm = field_re.search(entry_text)
if not fm:
    print(json.dumps(None))
    sys.exit(0)

i = fm.end()
depth = 1
start_val = i
n = len(entry_text)
while i < n and depth > 0:
    c = entry_text[i]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
    i += 1
print(json.dumps(entry_text[start_val:i - 1]))
]]

--- Extracts a single field's raw value from one entry of a .bib file
-- (e.g. `abstract`), via balanced-brace scanning -- handles nested
-- braces (LaTeX capitalization guards like `{Gaussian}`) that a plain
-- regex over `field\s*=\s*\{([^}]*)\}` would cut short at the first
-- inner `}`. Not a real BibTeX parser, same "good enough" spirit as
-- read_bib_keys above, but this one has to preserve a field's actual
-- content instead of just spotting a key.
-- @param path string path to a .bib file
-- @param key string citation key of the entry to look up
-- @param field string field name (case-insensitive), e.g. "abstract"
-- @return string|nil the field's raw value, or nil if the entry/field
--   isn't found, or (nil, error message) on I/O/decode failure
function M.read_bib_field(path, key, field)
  local fh = io.open(path, "r")
  if not fh then
    return nil, ("cv-blocks: cannot find bib file " .. path)
  end
  fh:close()

  local ok, json_text = pcall(pandoc.pipe, "python3", { "-c", BIB_FIELD, path, key, field }, "")
  if not ok then
    return nil, ("cv-blocks: failed to extract field from " .. path .. ": " .. tostring(json_text))
  end

  local ok2, value = pcall(pandoc.json.decode, json_text)
  if not ok2 then
    return nil, ("cv-blocks: failed to decode field value from " .. path .. ": " .. tostring(value))
  end

  -- pandoc.json.decode represents JSON `null` (field/entry not found) as
  -- a distinct userdata sentinel, not Lua `nil` -- same gotcha strip_json_null
  -- works around in read_yaml_file above; callers need a plain falsy nil.
  return strip_json_null(value)
end

return M
