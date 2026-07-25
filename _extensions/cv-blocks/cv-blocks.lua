-- cv-blocks: filter entry point. Dispatches .cv-block/.cv-header/
-- .cv-bibliography Divs to cv-patterns.lua's renderers -- see the README
-- for the full data-file schema.
--
-- Usage in a .qmd:
--
--   ::: {.cv-block file="students.yml"}
--   :::
--
--   ::: {.cv-header file="personal.yml"}
--   :::
--
--   ::: {.cv-bibliography file="papers.yml"}
--   :::
--
-- `file` is resolved relative to the input document by default, or to
-- `cv-data-dir` if set under `format.cv-blocks-pdf` in document/project
-- metadata. Bibliography `.bib` file paths (referenced by name inside the
-- YAML, not `file`) are resolved the same way against `bib-dir` -- and so
-- is Quarto's own native `bibliography:` metadata list (each bare entry
-- gets `bib-dir` prefixed, so it doesn't need repeating on every line;
-- entries that already look absolute are left alone).
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
-- A single `.cv-block` can override that document-wide default with its
-- own `details` Div attribute, for a document that mixes long and short
-- sections (e.g. a full CV with a long Students section but a short
-- Teaching one even though `details: true` overall):
--
--   ::: {.cv-block file="students.yml"}
--   :::
--
--   ::: {.cv-block file="teachings.yml" details="false"}
--   :::
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
-- filter runs. `.cv-header` uses the first author's email/url instead of
-- requiring them again in the data file -- see the README, "Usage".
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

-- Joins a list-valued metadata field (Quarto's native `categories:`/
-- `keywords:`) with a separator, for `.cv-header`'s research-domain/theme
-- tagline -- nil if the field is unset, so the tagline line it belongs to
-- is skipped entirely rather than rendered empty.
local function join_meta_list(list, sep)
  if not list then
    return nil
  end
  local items = {}
  for _, item in ipairs(list) do
    table.insert(items, pandoc.utils.stringify(item))
  end
  return table.concat(items, sep)
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
  if meta["cv-data-dir"] then
    opts["cv-data-dir"] = pandoc.utils.stringify(meta["cv-data-dir"])
  end
  opts.categories = join_meta_list(meta.categories, ", ")
  opts.keywords = join_meta_list(meta.keywords, " $\\cdot$ ")
end

-- Prefixes every native `bibliography:` entry with `bib-dir`, so it can
-- list bare filenames (`chiquet_journal.bib`) instead of repeating the
-- full path on every line -- entries that already look absolute are left
-- alone. Rewriting `meta.bibliography` here (in the Meta filter) reaches
-- Quarto's own template, which resolves it into `\addbibresource{...}`
-- calls after all filters have run (confirmed empirically).
local function rewrite_bibliography(meta)
  if not meta.bibliography or not opts["bib-dir"] then
    return
  end
  local rewritten = pandoc.List({})
  for _, entry in ipairs(meta.bibliography) do
    local path = pandoc.utils.stringify(entry)
    if not path:match("^/") then
      path = opts["bib-dir"] .. "/" .. path
    end
    rewritten:insert(pandoc.MetaString(path))
  end
  meta.bibliography = rewritten
end

-- `cv-data-dir` is already resolved into opts by read_opts (the Meta pass
-- always runs before any Div is visited), so a Div's `file` attribute can
-- just reuse it directly instead of re-reading the Meta table.
local function resolve_path(file)
  if opts["cv-data-dir"] then
    return opts["cv-data-dir"] .. "/" .. file
  end
  return file
end

-- Loads the YAML file a Div's `file` attribute points at; returns
-- (data, nil) on success or (nil, RawBlock-with-error) on failure, so
-- callers can just `if not data then return err end`.
local function load_div_data(div)
  local file = div.attributes["file"]
  if not file then
    return nil, pandoc.RawBlock("latex", "% cv-blocks: Div missing required 'file' attribute")
  end

  local path = resolve_path(file)
  local data, err = cv_yaml.read_yaml_file(path)
  if not data then
    return nil, pandoc.RawBlock("latex", "% cv-blocks: " .. tostring(err))
  end

  return data
end

-- A `.cv-block` Div can override the document-wide `details:` setting
-- for just that block (e.g. `::: {.cv-block file="students.yml"
-- details="true"}` inside a document rendered with `details: false`) --
-- handy for picking long/short per-section instead of only per-document.
-- Returns the shared `opts` unchanged when the Div has no `details`
-- attribute (the common case), or a shallow copy with `details`
-- overridden otherwise -- `opts` is only ever read downstream, never
-- mutated, so callers besides this one are unaffected either way.
local function resolve_div_opts(div)
  local override = div.attributes["details"]
  if override == nil then
    return opts
  end
  local scoped = {}
  for k, v in pairs(opts) do
    scoped[k] = v
  end
  scoped.details = (override == "true")
  return scoped
end

local function render_with(render_fn, div)
  local data, err = load_div_data(div)
  if not data then
    return err
  end

  local ok, result = pcall(render_fn, data, resolve_div_opts(div))
  if not ok then
    return pandoc.RawBlock("latex", "% cv-blocks: " .. tostring(result))
  end
  return result
end

-- A plain Pandoc definition list (`Term\n:   Definition`) renders as the
-- same {label}|{content} tabular \multblock/\block use (see
-- before-body.tex), instead of LaTeX's default `description` environment
-- -- so a document can build a multblock-style aligned, ruled summary
-- from plain markdown instead of a raw \multblock call. Every row uses
-- \multblock's \readBlock look (\em label, no special first-row
-- treatment) since a definition list has no title/date concept of its
-- own.
--
-- Builds the tabular body as a single Inlines stream (RawInline markup
-- spliced around the term's/definitions' own Inlines) instead of
-- stringifying each side through pandoc.write -- a `{{< cv_count ... >}}`
-- shortcode is still an unresolved placeholder Span at filter time
-- (Quarto substitutes its real value in a later pass over the final
-- AST), so serializing it early via pandoc.write bakes in an empty
-- string instead of the eventual number. Keeping the original Inlines
-- objects in the returned AST (rather than a RawBlock string) lets that
-- later substitution still find and resolve them normally.
local function render_definition_list(el)
  local body = pandoc.Inlines({})
  for _, item in ipairs(el.content) do
    local term, definitions = item[1], item[2]
    body:insert(pandoc.RawInline("latex", "\\hfill{\\em "))
    body:extend(term)
    body:insert(pandoc.RawInline("latex", "} & "))
    for i, blocks in ipairs(definitions) do
      for _, blk in ipairs(blocks) do
        if blk.content then
          body:extend(blk.content)
        end
      end
      if i < #definitions then
        body:insert(pandoc.LineBreak())
      end
    end
    body:insert(pandoc.RawInline("latex", " \\\\"))
    body:insert(pandoc.SoftBreak())
  end

  return pandoc.Blocks({
    pandoc.RawBlock("latex", "\\par\\noindent\\begin{tabular}[t]{@{}R{.15\\linewidth}|p{.8\\linewidth}}"),
    pandoc.Plain(body),
    pandoc.RawBlock("latex", "\\end{tabular}\\medskip"),
  })
end

return {
  {
    Meta = function(meta)
      read_opts(meta)
      rewrite_bibliography(meta)
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
      if div.classes:includes("cv-header") then
        return render_with(cv_patterns.render_header, div)
      end
      if div.classes:includes("cv-bibliography") then
        return render_with(cv_patterns.render_bibliography, div)
      end
      return nil
    end,
    DefinitionList = render_definition_list,
  },
}
