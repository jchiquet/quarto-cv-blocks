-- cv-blocks: filter entry point. Dispatches .cv-block/.cv-personalinfo/
-- .cv-bibliography Divs to cv-patterns.lua's renderers -- see the README
-- for the full data-file schema.
--
-- Usage in a .qmd:
--
--   ::: {.cv-block file="students.yml"}
--   :::
--
--   ::: {.cv-personalinfo file="personal.yml"}
--   :::
--
--   ::: {.cv-bibliography file="papers.yml"}
--   :::
--
-- `file` is resolved relative to the input document by default, or to
-- `cv-data-dir` if set under `format.cv-blocks-pdf` in document/project
-- metadata. Bibliography `.bib` file paths (referenced by name inside the
-- YAML, not `file`) are resolved the same way against `bib-dir`.
--
-- Language is Quarto's own native, top-level `lang:` key -- this
-- extension only supports "en"/"fr" (any other value falls back to
-- English content, same as unset). Reusing it (instead of a separate
-- `cv-lang`) means a document's language is set once and drives both
-- this extension's EN/FR content selection *and* Quarto's own babel
-- setup, document class option, hyphenation, etc. -- no manual
-- `classoption: [english]` needed, and no risk of the two disagreeing.
--
-- Length (long/short) and everything else extension-specific is
-- format-scoped document metadata (Quarto flattens `format.cv-blocks-pdf.*`
-- into the top-level meta table this filter sees, same as any other
-- format option):
--
--   lang: en                   # or "fr"; default "en" if unset
--   format:
--     cv-blocks-pdf:
--       details: true          # or false; default true
--
-- `cv-data-dir` (not `data-dir`) specifically dodges a confirmed Quarto
-- reserved-key collision: `data-dir` is silently swallowed before it
-- reaches a filter's meta table at all (empirically confirmed -- unlike
-- `bib-dir`, which is a plain, unclaimed key and flattens through fine).

local cv_yaml = require("cv-yaml")
local cv_patterns = require("cv-patterns")

local opts = { lang = "en", details = true }

-- Quarto normalizes the document's `author:` metadata into `authors`
-- (a list of structured records with `name`/`email`/`url`/... fields,
-- the same one its own PDF template uses for `\author{...}`) before our
-- filter runs. `.cv-personalinfo` uses the first author's email/url
-- instead of requiring them again in the data file -- see the README,
-- "Personal info".
local function read_author(meta)
  local authors = meta.authors
  if not authors or not authors[1] then
    return
  end
  local author = authors[1]
  if author.email then
    opts.email = pandoc.utils.stringify(author.email)
  end
  if author.url then
    opts.web = pandoc.utils.stringify(author.url)
  end
  -- `github` isn't part of Quarto's author schema -- a top-level
  -- `github:` metadata key instead (plain custom field, not a normalized
  -- author sub-field).
  if meta.github then
    opts.github = pandoc.utils.stringify(meta.github)
  end
end

local function read_opts(meta)
  read_author(meta)

  if meta.lang then
    opts.lang = pandoc.utils.stringify(meta.lang)
  end
  if meta.details ~= nil then
    -- MetaBool values stringify to "true"/"false".
    opts.details = pandoc.utils.stringify(meta.details) == "true"
  end
  if meta["bib-dir"] then
    opts["bib-dir"] = pandoc.utils.stringify(meta["bib-dir"])
  end
end

local function data_dir(meta)
  if meta["cv-data-dir"] then
    return pandoc.utils.stringify(meta["cv-data-dir"])
  end
  return nil
end

local function resolve_path(file, meta)
  local dir = data_dir(meta)
  if dir then
    return dir .. "/" .. file
  end
  return file
end

local Meta

-- Loads the YAML file a Div's `file` attribute points at; returns
-- (data, nil) on success or (nil, RawBlock-with-error) on failure, so
-- callers can just `if not data then return err end`.
local function load_div_data(div)
  local file = div.attributes["file"]
  if not file then
    return nil, pandoc.RawBlock("latex", "% cv-blocks: Div missing required 'file' attribute")
  end

  local path = resolve_path(file, Meta)
  local data, err = cv_yaml.read_yaml_file(path)
  if not data then
    return nil, pandoc.RawBlock("latex", "% cv-blocks: " .. tostring(err))
  end

  return data
end

local function render_with(render_fn, div)
  local data, err = load_div_data(div)
  if not data then
    return err
  end

  local ok, result = pcall(render_fn, data, opts)
  if not ok then
    return pandoc.RawBlock("latex", "% cv-blocks: " .. tostring(result))
  end
  return result
end

return {
  {
    Meta = function(meta)
      read_opts(meta)
      Meta = meta
      return meta
    end,
  },
  {
    Div = function(div)
      if div.t ~= "Div" then
        return nil
      end
      if div.classes:includes("cv-block") then
        return render_with(cv_patterns.render, div)
      end
      if div.classes:includes("cv-personalinfo") then
        return render_with(cv_patterns.render_personal_info, div)
      end
      if div.classes:includes("cv-bibliography") then
        return render_with(cv_patterns.render_bibliography, div)
      end
      return nil
    end,
  },
}
