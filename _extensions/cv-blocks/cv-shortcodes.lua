-- cv_count: inserts a live count of entries from a data/<section>.yml
-- file, so a hand-written summary sentence ("N students supervised",
-- "N papers") stays in sync with the data instead of a number that has
-- to be updated by hand every time an entry is added.
--
--   {{< cv_count file="students.yml" >}}
--   {{< cv_count file="students.yml" group=1 >}}   -- 1-based group index
--
-- Resolves `file` against `cv-data-dir` the same way cv-blocks.lua
-- resolves a Div's `file` attribute, and `bib:` paths against `bib-dir`
-- the same way `.cv-bibliography` does (both format.cv-blocks-pdf.*
-- options).
-- Always counts as if `details: true` -- a count is a lifetime total ("47
-- journal papers" belongs in the short CV's summary too), not display
-- filtering, so a `long_only` group/entry still counts even from a short
-- document. Use `group=` to split a total into its parts (e.g. current vs
-- alumni students, one group each) rather than relying on long/short for
-- that. EN/FR variants still follow the document's own native `lang:`,
-- since that's a real translation, not a visibility filter.

local cv_yaml = require("cv-yaml")
local cv_patterns = require("cv-patterns")

-- Shortcode arguments inside a raw LaTeX fenced block (`{=latex}`) don't
-- get their surrounding quotes stripped the way they do elsewhere in a
-- document (confirmed empirically) -- strip them ourselves so
-- `file="data/papers.yml"` works the same in both places.
local function unquote(s)
  return (s:gsub('^"(.*)"$', "%1"))
end

local function count_opts(meta)
  local opts = { lang = "en", details = true }
  if meta.lang then
    opts.lang = pandoc.utils.stringify(meta.lang)
  end
  if meta["bib-dir"] then
    opts["bib-dir"] = pandoc.utils.stringify(meta["bib-dir"])
  end
  return opts
end

local function resolve_path(file, meta)
  local dir = meta["cv-data-dir"] and pandoc.utils.stringify(meta["cv-data-dir"])
  if dir then
    return dir .. "/" .. file
  end
  return file
end

-- A kwarg absent from a shortcode call isn't nil in `kwargs`, it's an
-- empty Inlines (truthy but stringifies to "") -- check the stringified
-- value, not the table itself, and fall back to `default` when empty.
local function kwarg_or(kwargs, name, default)
  local v = kwargs[name] and unquote(pandoc.utils.stringify(kwargs[name])) or ""
  return v ~= "" and v or default
end

-- Shared by cv_count/cv_sum: resolves `file=`, loads its YAML, and parses
-- `group=` -- everything the two shortcodes need before they diverge on
-- what to do with the data. Returns (data, group_index, nil) on success,
-- or (nil, nil, "[<tag>: ...]") ready to hand straight back as the
-- shortcode's own error output.
local function load_data(kwargs, meta, tag)
  local file = kwarg_or(kwargs, "file", "")
  if file == "" then
    return nil, nil, "[" .. tag .. ": missing file= argument]"
  end

  local path = resolve_path(file, meta)
  local data, err = cv_yaml.read_yaml_file(path)
  if not data then
    return nil, nil, "[" .. tag .. ": " .. tostring(err) .. "]"
  end

  local group_index = kwargs["group"] and tonumber(unquote(pandoc.utils.stringify(kwargs["group"])))
  return data, group_index, nil
end

-- cv_keywords: joins a list-valued metadata field (Quarto's native
-- `keywords:` by default) with a separator, e.g. for a summary's
-- "Themes"/"Research" line. Quarto's own `{{< meta >}}` shortcode
-- explicitly rejects list-valued fields ("Unsupported type 'List' for key
-- keywords in a meta shortcode"), so this fills the gap.
--
--   keywords: [Sparse models, Multi-omics integration, Reproducible research]
--   categories: [Statistical methods, Machine learning]
--   {{< cv_keywords >}}                              -- "Sparse models $\cdot$ Multi-omics integration $\cdot$ Reproducible research"
--   {{< cv_keywords sep=", " >}}                      -- custom separator
--   {{< cv_keywords field="categories" sep=", " >}}   -- another list-valued field, e.g. Quarto's native `categories:`
function cv_keywords(args, kwargs, meta)
  local field = kwarg_or(kwargs, "field", "keywords")
  local list = meta[field]
  if not list then
    return pandoc.Str("[cv_keywords: no " .. field .. " metadata]")
  end
  local sep = kwarg_or(kwargs, "sep", " $\\cdot$ ")
  local items = {}
  for _, item in ipairs(list) do
    table.insert(items, pandoc.utils.stringify(item))
  end
  return pandoc.Str(table.concat(items, sep))
end

function cv_count(args, kwargs, meta)
  local data, group_index, err = load_data(kwargs, meta, "cv_count")
  if err then
    return pandoc.Str(err)
  end

  local ok, n = pcall(cv_patterns.count, data, count_opts(meta), group_index)
  if not ok then
    return pandoc.Str("[cv_count: " .. tostring(n) .. "]")
  end

  return pandoc.Str(tostring(n))
end

-- cv_sum: like cv_count, but totals a numeric entry field (e.g. `hours:`
-- on each data/teachings.yml entry) instead of counting entries -- for a
-- "~N hours of teaching" summary that stays in sync with the data.
--
--   {{< cv_sum file="teachings.yml" field="hours" >}}
--   {{< cv_sum file="teachings.yml" field="hours" group=1 >}}
function cv_sum(args, kwargs, meta)
  local field = kwarg_or(kwargs, "field", "")
  if field == "" then
    return pandoc.Str("[cv_sum: missing field= argument]")
  end

  local data, group_index, err = load_data(kwargs, meta, "cv_sum")
  if err then
    return pandoc.Str(err)
  end

  local ok, n = pcall(cv_patterns.sum, data, count_opts(meta), group_index, field)
  if not ok then
    return pandoc.Str("[cv_sum: " .. tostring(n) .. "]")
  end

  -- YAML values parsed via cv_yaml.lua come back as Lua floats even for
  -- whole numbers (e.g. 256.0) -- %g drops the trailing ".0" but still
  -- shows real decimals if a summed field ever has any.
  return pandoc.Str(string.format("%g", n))
end
