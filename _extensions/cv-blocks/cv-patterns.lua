-- Rendering of the `groups: [...]` (and Pattern F) YAML schema into the
-- \multblock/\block LaTeX primitives (partials/pdf/before-body.tex). We
-- deliberately don't reimplement their table layout in Lua/Pandoc AST: we
-- emit calls to the macros themselves as raw LaTeX and let LaTeX do the
-- formatting, so entry content stays genuinely opaque (raw `\href`, `\em`,
-- ... pass through untouched).
--
-- opts passed to every function: { lang = "en"|"fr", details = boolean }

local cv_yaml = require("cv-yaml")

local M = {}

-- Picks `t.fr`/`t.en` by the document's own language -- the one primitive
-- every EN/FR selection in this file (resolve_i18n, Pattern D/F documents,
-- the address label) is built from.
local function lang_pick(t, opts)
  return opts.lang == "fr" and t.fr or t.en
end

-- A bibliography group's .bib path, resolved against `bib-dir` the same
-- way a `.cv-block` Div's `file` attribute is resolved against
-- `cv-data-dir` -- shared by render_bibliography and count_groups
-- (M.count doesn't render, but still needs each bib group's key count).
local function bib_path(group, opts)
  local bib_dir = opts["bib-dir"]
  return bib_dir and (bib_dir .. "/" .. group.bib .. ".bib") or (group.bib .. ".bib")
end

-- ---------------------------------------------------------------------
-- Inline counts: `{{< cv_count file="..." group=N >}}` / `{{< cv_sum
-- file="..." field="..." group=N >}}` embedded directly inside an opaque
-- text field (item text, a group's `short_fallback`, Pattern F's
-- `short_note`...), e.g. a `\phdjury` short-mode entry summarizing a
-- long list as "19 as reviewer, 11 as examiner" from a separate, atomic
-- data/juries.yml, or a `short_fallback` sentence collapsing a whole
-- long_only group ("22 MSc students") -- the same "stay in sync with the
-- data instead of a hand-updated number" job the `cv_count`/`cv_sum`
-- shortcodes do for the qmd body (see cv-shortcodes.lua and the README,
-- "Counting entries"), but reachable from *inside* a data file, where
-- content arrives via `cv_yaml.read_yaml_file` (a plain `io.open` + JSON
-- decode) rather than Pandoc's own markdown parsing -- so it never passes
-- through Quarto's shortcode-expansion pass and a literal
-- `{{< cv_count ... >}}` there would otherwise survive untouched into the
-- final LaTeX. Deliberately reuses the shortcode's own `{{< ... >}}`
-- syntax (rather than inventing a second placeholder convention) so
-- there's exactly one thing to remember regardless of where the count is
-- written; unlike the real shortcode, quoting `file=`/`group=` is not
-- required here (plain Lua pattern matching, no interaction with
-- Pandoc/Quarto's own parser).
--
-- Always counts/sums as a lifetime total (`details = true`), same
-- rationale as the shortcode: a number quoted inside running prose
-- ("19 jurys as reviewer") is a fact about the world, not something that
-- should silently change count depending on which document currently
-- happens to be rendering it.
local function parse_shortcode_attrs(attrs)
  local kv = {}
  for key, val in attrs:gmatch('([%a][%w%-_]*)%s*=%s*"([^"]*)"') do
    kv[key] = val
  end
  for key, val in attrs:gmatch('([%a][%w%-_]*)%s*=%s*([%w%.]+)') do
    if kv[key] == nil then
      kv[key] = val
    end
  end
  return kv
end

local function resolve_inline_count_path(file, opts)
  if opts["cv-data-dir"] and not file:match("^/") then
    return opts["cv-data-dir"] .. "/" .. file
  end
  return file
end

local function load_inline_count_data(kv, opts, tag)
  if not kv.file then
    return nil, "[" .. tag .. ": missing file=]"
  end
  local data, err = cv_yaml.read_yaml_file(resolve_inline_count_path(kv.file, opts))
  if not data then
    return nil, "[" .. tag .. ": " .. tostring(err) .. "]"
  end
  return data, nil
end

local function expand_inline_counts(text, opts)
  if type(text) ~= "string" or not text:find("cv_count", 1, true) and not text:find("cv_sum", 1, true) then
    return text
  end

  text = text:gsub("{{<%s*cv_count%s+(.-)%s*>}}", function(attrs)
    local kv = parse_shortcode_attrs(attrs)
    local data, err = load_inline_count_data(kv, opts, "cv_count")
    if not data then
      return err
    end
    local ok, n = pcall(M.count, data, { lang = opts.lang, details = true }, kv.group and tonumber(kv.group))
    if not ok then
      return "[cv_count: " .. tostring(n) .. "]"
    end
    return tostring(n)
  end)

  text = text:gsub("{{<%s*cv_sum%s+(.-)%s*>}}", function(attrs)
    local kv = parse_shortcode_attrs(attrs)
    if not kv.field then
      return "[cv_sum: missing field=]"
    end
    local data, err = load_inline_count_data(kv, opts, "cv_sum")
    if not data then
      return err
    end
    local ok, n = pcall(M.sum, data, { lang = opts.lang, details = true }, kv.group and tonumber(kv.group), kv.field)
    if not ok then
      return "[cv_sum: " .. tostring(n) .. "]"
    end
    return string.format("%g", n)
  end)

  return text
end

-- ---------------------------------------------------------------------
-- Shared i18n resolver: any short label (group heading, item label) can
-- be a plain string, an {en:, fr:} pair, a {long:, short:} pair, or an
-- {en: {long:, short:}, fr: {long:, short:}} nesting of both (in either
-- order) -- resolved recursively so all combinations fall out for free,
-- with any embedded `{{< cv_count ... >}}`/`{{< cv_sum ... >}}` expanded
-- at the leaf (see expand_inline_counts above).
-- ---------------------------------------------------------------------

local function resolve_i18n(value, opts)
  if value == nil then
    return nil
  end
  if type(value) ~= "table" then
    return expand_inline_counts(value, opts)
  end
  if value.en ~= nil or value.fr ~= nil then
    return resolve_i18n(lang_pick(value, opts), opts)
  end
  if value.long ~= nil or value.short ~= nil then
    return resolve_i18n(opts.details and value.long or value.short, opts)
  end
  return value
end

-- ---------------------------------------------------------------------
-- Pattern G: an entry's `items` computed from one or more atomic
-- data/<file>.yml roster files (juries.yml, phdfollowup.yml, ...) instead
-- of typed out by hand -- so a per-year breakdown shown inside e.g.
-- activities.yml's \hdrjury/\phdjury/\phdfollowup entries stays in sync
-- with the same atomic entries `{{< cv_count >}}` already totals
-- elsewhere (see expand_inline_counts above), instead of being copied
-- into activities.yml by hand every time a jury or follow-up is added.
--
--   - date: ""
--     title: "\\hdrjury"
--     roster:
--       - {file: juries.yml, group: 1, label: "\\reviewer"}
--       - {file: juries.yml, group: 2, label: "\\examiner"}
--
-- Each roster entry (`{date, title}`, same shape as any other simple
-- entry -- `title` here is a person's name) is bucketed by `date`
-- (treated as a year), one output item per distinct year, most recent
-- first. Within a year, entries from the same `roster` section are
-- joined with ", "; sections are joined with "; ", each prefixed with
-- its own `label` (e.g. "\reviewer: A, B") -- except a lone section with
-- no `label`, which joins names directly with no prefix (phdfollowup.yml
-- has only one role: the follow-up itself).
local function roster_year_key(date)
  local n = tonumber(date)
  return n and string.format("%g", n) or tostring(date)
end

local function roster_source_entries(file, group_index, opts)
  local data, err = cv_yaml.read_yaml_file(resolve_inline_count_path(file, opts))
  if not data then
    error(err)
  end
  if group_index then
    local group = (data.groups or {})[group_index]
    return (group and group.entries) or {}
  end
  return data.entries or {}
end

local function build_roster_items(roster, opts)
  local years = {}
  local year_order = {}

  for _, section in ipairs(roster) do
    for _, e in ipairs(roster_source_entries(section.file, section.group, opts)) do
      local year = roster_year_key(e.date)
      if not years[year] then
        years[year] = {}
        table.insert(year_order, year)
      end
      local by_label = years[year]
      local key = section.label or ""
      if not by_label[key] then
        by_label[key] = { label = section.label, names = {} }
        table.insert(by_label, key)
      end
      table.insert(by_label[key].names, e.title)
    end
  end

  table.sort(year_order, function(a, b) return tonumber(a) > tonumber(b) end)

  local items = {}
  for _, year in ipairs(year_order) do
    local parts = {}
    for _, key in ipairs(years[year]) do
      local section = years[year][key]
      local names = table.concat(section.names, ", ")
      table.insert(parts, section.label and (section.label .. ": " .. names) or names)
    end
    table.insert(items, { label = year, text = table.concat(parts, "; ") })
  end
  return items
end

-- ---------------------------------------------------------------------
-- Base primitive: one resolved {date, title, items?} entry.
-- ---------------------------------------------------------------------

local FUNDING_LABEL = { en = "Support", fr = "Financement" }
local SUMMARY_LABEL = { en = "Summary", fr = "Résumé" }

-- A bib field's path is resolved against `bib-dir`, same as a bibliography
-- group's `.bib` -- unlike `bib_path` above, `abstract_from.file` already
-- carries its own `.bib` extension (same convention as `roster.file`),
-- so it's just concatenated, not appended.
local function resolve_bib_path(file, opts)
  local bib_dir = opts["bib-dir"]
  return bib_dir and (bib_dir .. "/" .. file) or file
end

--- Renders one {date, title, items?, funding?, abstract_from?} entry as
-- a \multblock (items present) or \block (no items) call. `title`,
-- `date`, `item.text` and `funding` are opaque raw LaTeX content --
-- never escaped or reinterpreted -- but each may itself be an {en:, fr:}
-- pair (same resolver as `item.label`/group headings), so a single entry
-- can carry per-language text for just the fields that actually differ,
-- instead of duplicating the whole entry via the Pattern D en/fr
-- variant. `funding` (the funder/grant type -- "ANR", "Horizon
-- Europe", ...) is shorthand for a trailing item with that fixed EN/FR
-- label, instead of writing it out on every grant entry by hand.
--
-- `abstract_from: {file, key, field?}` pulls a long-form summary
-- straight out of a .bib entry (e.g. a supervised thesis's own
-- `abstract`/`abstract_fr` field in student_theses.bib) instead of
-- keeping a second copy of it in this YAML file -- one editing point,
-- shared with whatever else already reads that .bib (e.g. the website's
-- student pages). Only shown when `opts.details` (the long CV) -- a
-- thesis abstract has no place in a one-page short CV. Picks
-- `field` if given; otherwise `abstract_fr`/`abstract` by document
-- language, falling back to `abstract` if the language-specific field
-- isn't written yet (better an English summary than none while
-- translations catch up).
local function append_abstract_item(items, entry, opts)
  if not (entry.abstract_from and opts.details) then
    return
  end
  local path = resolve_bib_path(entry.abstract_from.file, opts)
  local key = entry.abstract_from.key
  local field = entry.abstract_from.field or (opts.lang == "fr" and "abstract_fr" or "abstract")

  local ok, value = pcall(cv_yaml.read_bib_field, path, key, field)
  if (not ok or not value) and not entry.abstract_from.field and field ~= "abstract" then
    ok, value = pcall(cv_yaml.read_bib_field, path, key, "abstract")
  end
  if ok and value then
    table.insert(items, { label = SUMMARY_LABEL, text = value })
  end
end

local function render_simple_entry(entry, opts)
  local date = resolve_i18n(entry.date, opts) or ""
  local title = resolve_i18n(entry.title, opts) or ""

  local items = {}
  local source_items = entry.items
  if not source_items and entry.roster then
    source_items = build_roster_items(entry.roster, opts)
  end
  for _, item in ipairs(source_items or {}) do
    table.insert(items, item)
  end
  if entry.funding then
    table.insert(items, { label = FUNDING_LABEL, text = entry.funding })
  end
  append_abstract_item(items, entry, opts)

  if #items > 0 then
    local pairs_latex = {}
    for _, item in ipairs(items) do
      local label = resolve_i18n(item.label, opts) or ""
      local text = resolve_i18n(item.text, opts) or ""
      table.insert(pairs_latex, string.format("{%s}{%s}", label, text))
    end
    return string.format("\\multblock{%s}{%s}{%s}", date, title, table.concat(pairs_latex))
  else
    return string.format("\\block{%s}{%s}", date, title)
  end
end

-- ---------------------------------------------------------------------
-- Patterns D & E: an entry replaced by a full en/fr or long/short
-- variant — either a single entry (D) or a list of entries (E).
-- ---------------------------------------------------------------------

local function is_variant_entry(entry)
  return entry.en ~= nil or entry.fr ~= nil or entry.long ~= nil or entry.short ~= nil
end

local function select_variant(entry, opts)
  if entry.en ~= nil or entry.fr ~= nil then
    return lang_pick(entry, opts)
  end
  return opts.details and entry.long or entry.short
end

-- true when `variant` is a YAML sequence (Pattern E) rather than a single
-- entry map (Pattern D): sequences decode with a truthy [1], entry maps
-- don't (they have a `date`/`title` key instead).
local function is_entry_list(variant)
  return variant[1] ~= nil
end

-- ---------------------------------------------------------------------
-- Pattern A (long_only/short_only on an entry) + dispatch over an
-- `entries:` list, folding in patterns D and E.
-- ---------------------------------------------------------------------

local function entry_visible(entry, opts)
  if entry.long_only and not opts.details then
    return false
  end
  if entry.short_only and opts.details then
    return false
  end
  return true
end

local function render_entry_list(entries, opts)
  local out = {}
  for _, entry in ipairs(entries or {}) do
    if entry_visible(entry, opts) then
      if is_variant_entry(entry) then
        local variant = select_variant(entry, opts)
        if variant then
          if is_entry_list(variant) then
            for _, sub_entry in ipairs(variant) do
              table.insert(out, render_simple_entry(sub_entry, opts))
            end
          else
            table.insert(out, render_simple_entry(variant, opts))
          end
        end
      else
        table.insert(out, render_simple_entry(entry, opts))
      end
    end
  end
  return out
end

-- ---------------------------------------------------------------------
-- Groups: heading (Pattern B) + entries, with the whole group optionally
-- collapsing to a fallback sentence in short mode (Pattern C).
-- ---------------------------------------------------------------------

local function render_group(group, opts, blocks)
  -- The heading is shown unconditionally, even when long_only collapses
  -- the group to a short_fallback sentence.
  local heading = resolve_i18n(group.heading, opts)
  if heading then
    blocks:insert(pandoc.RawBlock("latex", "\\subsubsection{" .. heading .. "}"))
  end

  if group.long_only and not opts.details then
    if group.short_fallback then
      local text = expand_inline_counts(lang_pick(group.short_fallback, opts), opts)
      blocks:insert(pandoc.RawBlock("latex", text or ""))
    end
    return
  end
  if group.short_only and opts.details then
    return
  end

  for _, latex in ipairs(render_entry_list(group.entries, opts)) do
    blocks:insert(pandoc.RawBlock("latex", latex))
  end
end

local function render_groups(groups, opts)
  local blocks = pandoc.List({})
  for _, group in ipairs(groups) do
    render_group(group, opts, blocks)
  end
  return blocks
end

-- ---------------------------------------------------------------------
-- Pattern F: free text + nested conditionals (teachings.yml). Top-level
-- document keyed directly by en/fr (no `groups:`).
-- ---------------------------------------------------------------------

local SPACER_MACRO = {
  medskip = "\\medskip",
  bigskip = "\\bigskip",
}

local function resolve_pattern_f(data, opts)
  local side = lang_pick(data, opts)
  if not side then
    error("cv-patterns: pattern F data has no '" .. tostring(opts.lang) .. "' key")
  end

  local blocks = pandoc.List({})

  if not opts.details and side.short_note then
    blocks:insert(pandoc.RawBlock("latex", expand_inline_counts(side.short_note, opts)))
  end
  if side.spacer then
    local macro = SPACER_MACRO[side.spacer]
    if not macro then
      error("cv-patterns: unknown spacer '" .. tostring(side.spacer) .. "' (expected medskip/bigskip)")
    end
    blocks:insert(pandoc.RawBlock("latex", macro))
  end

  for _, latex in ipairs(render_entry_list(side.entries, opts)) do
    blocks:insert(pandoc.RawBlock("latex", latex))
  end
  if opts.details then
    for _, latex in ipairs(render_entry_list(side.long_entries, opts)) do
      blocks:insert(pandoc.RawBlock("latex", latex))
    end
  end

  return blocks
end

-- ---------------------------------------------------------------------
-- Header block: optional research-domain/theme tagline (from `categories:`/
-- `keywords:` metadata) followed by the name/contact block, optionally
-- preceded by a photo column. The layout (tabular of minipages,
-- icon-prefixed contact lines) lives here as generic code; the content
-- (bio lines, address, photo path) comes from data/personal.yml. Column
-- widths differ EN/FR since French text needs a wider bio column. A
-- document's job title/position is its own heading in the qmd body
-- instead (see the README, "Usage"), not part of this block.
-- ---------------------------------------------------------------------

local PERSONAL_INFO_WIDTH = {
  en = { left = "0.6", right = "0.4" },
  fr = { left = "0.5", right = "0.5" },
}
local PERSONAL_INFO_WIDTH_WITH_PHOTO = {
  en = { photo = "0.16", left = "0.46", right = "0.38" },
  fr = { photo = "0.16", left = "0.35", right = "0.49" },
}

-- Heads the address column with a fixed EN/FR label -- mainly so the two
-- (or three, with a photo) columns occupy the same vertical space (bio +
-- contact icons on the left vs. just an address, otherwise visibly
-- shorter).
local ADDRESS_LABEL = { en = "Professional address", fr = "Adresse professionnelle" }

-- Photo height, not width: both a portrait photo and a square placeholder
-- avatar then scale to the same vertical space as the bio/address
-- columns beside them (roughly what a 6-line contact block takes),
-- regardless of their own aspect ratio.
local PHOTO_HEIGHT = "2.3cm"

-- Nudges the photo above the plain top-of-first-line alignment `\raisebox{-\height}`
-- gives it, and adds breathing room between the photo and the bio column.
local PHOTO_RAISE = "3mm"
local PHOTO_GAP = "2.5em"

-- Breathing room between the bio/contact column and the address column.
local ADDRESS_GAP = "1.5em"

--- Renders the header block (optional tagline + photo + name/contact
-- block under the CV header) from data/personal.yml content.
-- `email`/`web`/`github` come from the document's own metadata (see
-- cv-blocks.lua's read_author), not from this file, to avoid a second
-- place to keep them in sync -- same for `categories`/`keywords` (see
-- read_opts).
-- @param data table { photo?, en = {bio, address}, fr = {...} }
-- @param opts table { lang = "en"|"fr", email, web, github, categories?, keywords? }
-- @return pandoc.List of pandoc Block elements
function M.render_header(data, opts)
  local side = lang_pick(data, opts)
  local width_table = data.photo and PERSONAL_INFO_WIDTH_WITH_PHOTO or PERSONAL_INFO_WIDTH
  local width = width_table[opts.lang] or width_table.en

  -- `photo` is resolved against `cv-data-dir`, same as a `.cv-block`
  -- Div's `file` attribute or a bibliography `bib:` entry -- a bare
  -- filename doesn't need `cv-data-dir` repeated in it.
  local photo = data.photo
  if photo and opts["cv-data-dir"] and not photo:match("^/") then
    photo = opts["cv-data-dir"] .. "/" .. photo
  end

  local bio = table.concat(side.bio, "\\\\\n    ")
  local address = table.concat(side.address, "\\\\\n    ")
  local address_label = lang_pick(ADDRESS_LABEL, opts)

  local blocks = pandoc.List({})

  if opts.categories or opts.keywords then
    local tagline = string.format(
      [[
\large\itshape\color{mred} %s \\[0.3em]
\normalsize\upshape\color{black} %s
\vspace{1em}]],
      opts.categories or "", opts.keywords or ""
    )
    blocks:insert(pandoc.RawBlock("latex", tagline))
  end

  local photo_column = ""
  local col_spec = string.format("@{}l@{\\hspace{%s}}r@{}", ADDRESS_GAP)
  if photo then
    photo_column = string.format(
      [[
  \begin{minipage}[t]{%s\textwidth}
    \raisebox{-\height+%s}{\includegraphics[height=%s,keepaspectratio]{%s}}
  \end{minipage}
  &
]],
      width.photo, PHOTO_RAISE, PHOTO_HEIGHT, photo
    )
    col_spec = string.format("@{}l@{\\hspace{%s}}l@{\\hspace{%s}}r@{}", PHOTO_GAP, ADDRESS_GAP)
  end

  local tex = string.format(
    [[
\noindent\begin{tabular}{%s}
%s  \begin{minipage}[t]{%s\textwidth}
    %s\\[1ex]
    {\scriptsize\faEnvelope}~\href{mailto:%s}{\texttt{%s}}\\
    {\scriptsize\faFirefox}~\href{%s}{\texttt{%s}}\\
    {\small\faGithub}~\href{%s}{\texttt{%s}}
  \end{minipage}
  &
  \begin{minipage}[t]{%s\textwidth}
    \textsf{%s}\\[1ex]
    %s
  \end{minipage}
\end{tabular}]],
    col_spec, photo_column,
    width.left, bio, opts.email, opts.email, opts.web, opts.web, opts.github, opts.github,
    width.right, address_label, address
  )
  blocks:insert(pandoc.RawBlock("latex", tex))

  return blocks
end

-- ---------------------------------------------------------------------
-- Bibliography sections. Each group is one categorized bibliography
-- section: a heading, a label prefix (e.g. "[JP1]"), and a .bib file --
-- the opaque unit here is the .bib file itself (never touched), same
-- spirit as \multblock/\block leaving field content opaque.
--
-- Uses biblatex specifically so Quarto's own compile loop can run biber
-- automatically (`cite-method: biblatex` in _extension.yml) -- Quarto's
-- automation has no notion of BibTeX for raw-LaTeX bibliographies. See
-- the README ("Bibliography") for the full mechanism and its trade-offs.
--
-- Each section is wrapped in its own `refsection` environment with an
-- explicit `\nocite{key1,key2,...}` for that .bib file's own entries
-- (`cv_yaml.read_bib_keys`, a regex over `@type{key,`, not a real parser
-- -- good enough since a spurious extra "key" that doesn't exist is
-- silently ignored). `refsection` isn't just for filtering: it's what
-- makes each section's `[JP1]`, `[JP2]`, ... numbering restart cleanly.
--
-- Consuming documents must list every `.bib` referenced under Quarto's
-- native `bibliography:` metadata key (can't be emitted from here, since
-- it has to land in the preamble) -- see the README ("Bibliography").
-- ---------------------------------------------------------------------

--- Renders a data/<section>.yml file with a top-level `groups: [...]`
-- list of bibliography sections into a list of pandoc Blocks.
-- @param data table { groups: [{ heading?, prefix, bib, long_only? }, ...] }
-- @param opts table { details = boolean, ["bib-dir"] = string }
-- @return pandoc.List of pandoc Block elements
function M.render_bibliography(data, opts)
  local blocks = pandoc.List({})
  for _, group in ipairs(data.groups or {}) do
    if not (group.long_only and not opts.details) then
      local heading = resolve_i18n(group.heading, opts)
      if heading then
        blocks:insert(pandoc.RawBlock("latex", "\\subsubsection{" .. heading .. "}"))
      end

      local keys, err = cv_yaml.read_bib_keys(bib_path(group, opts))
      if not keys then
        error(err)
      end

      local tex = string.format(
        "\\begin{refsection}\n\\nocite{%s}\n\\newrefcontext[labelprefix=%s]\n\\printbibliography[heading=none]\n\\end{refsection}",
        table.concat(keys, ","), group.prefix
      )
      blocks:insert(pandoc.RawBlock("latex", tex))
    end
  end
  return blocks
end

-- ---------------------------------------------------------------------
-- Counting: how many entries a `.cv-block`/`.cv-bibliography` Div
-- pointed at this same file/group would actually render, respecting
-- lang/details visibility and pattern D/E variants -- used by the
-- `cv_count` shortcode (cv-shortcodes.lua) to keep a hand-written
-- "N students supervised"-style summary in sync with the data instead
-- of a number that silently drifts. Mirrors render_entry_list/
-- render_group/render_bibliography's visibility logic exactly, but
-- counts instead of emitting LaTeX.
-- ---------------------------------------------------------------------

local function count_entry_list(entries, opts)
  local n = 0
  for _, entry in ipairs(entries or {}) do
    if entry_visible(entry, opts) then
      if is_variant_entry(entry) then
        local variant = select_variant(entry, opts)
        if variant then
          n = n + (is_entry_list(variant) and #variant or 1)
        end
      else
        n = n + 1
      end
    end
  end
  return n
end

local function count_groups(groups, opts, group_index)
  local n = 0
  for i, group in ipairs(groups or {}) do
    if not group_index or i == group_index then
      if group.bib then
        if not (group.long_only and not opts.details) then
          local keys, err = cv_yaml.read_bib_keys(bib_path(group, opts))
          if not keys then
            error(err)
          end
          n = n + #keys
        end
      elseif not (group.long_only and not opts.details) and not (group.short_only and opts.details) then
        n = n + count_entry_list(group.entries, opts)
      end
    end
  end
  return n
end

--- Counts the entries a full data/<section>.yml document would render
-- (see M.render), optionally restricted to a single group.
-- @param data table plain Lua table decoded from a data/<section>.yml file
-- @param opts table { lang = "en"|"fr", details = boolean, ["bib-dir"] = string }
-- @param group_index integer|nil 1-based index into `data.groups`, if set
-- @return integer
function M.count(data, opts, group_index)
  if data.groups then
    return count_groups(data.groups, opts, group_index)
  elseif data.entries then
    return count_entry_list(data.entries, opts)
  elseif data.en or data.fr then
    local side = lang_pick(data, opts)
    local n = count_entry_list(side and side.entries, opts)
    if opts.details then
      n = n + count_entry_list(side and side.long_entries, opts)
    end
    return n
  else
    error("cv-blocks: unrecognized data schema (expected top-level 'groups', 'entries', or 'en'/'fr' keys)")
  end
end

-- ---------------------------------------------------------------------
-- Summing: total of a numeric field (e.g. `hours:`) across the entries a
-- `.cv-block` Div pointed at this same file/group would render -- same
-- visibility/variant logic as counting above, but adds up a field's
-- value instead of adding 1 per entry. Used by the `cv_sum` shortcode
-- for a "~N hours of teaching"-style summary that stays in sync with the
-- data instead of a hand-maintained estimate.
-- ---------------------------------------------------------------------

local function sum_entry_list(entries, opts, field)
  local total = 0
  for _, entry in ipairs(entries or {}) do
    if entry_visible(entry, opts) then
      if is_variant_entry(entry) then
        local variant = select_variant(entry, opts)
        if variant then
          if is_entry_list(variant) then
            for _, sub_entry in ipairs(variant) do
              total = total + (tonumber(sub_entry[field]) or 0)
            end
          else
            total = total + (tonumber(variant[field]) or 0)
          end
        end
      else
        total = total + (tonumber(entry[field]) or 0)
      end
    end
  end
  return total
end

local function sum_groups(groups, opts, group_index, field)
  local total = 0
  for i, group in ipairs(groups or {}) do
    if not group_index or i == group_index then
      if not (group.long_only and not opts.details) and not (group.short_only and opts.details) then
        total = total + sum_entry_list(group.entries, opts, field)
      end
    end
  end
  return total
end

--- Sums a numeric field across the entries a full data/<section>.yml
-- document would render (see M.render), optionally restricted to a
-- single group. Bibliography groups (`group.bib`) aren't supported --
-- there's no per-entry numeric field to sum in a .bib file.
-- @param data table plain Lua table decoded from a data/<section>.yml file
-- @param opts table { lang = "en"|"fr", details = boolean }
-- @param group_index integer|nil 1-based index into `data.groups`, if set
-- @param field string entry field name to sum, e.g. "hours"
-- @return number
function M.sum(data, opts, group_index, field)
  if data.groups then
    return sum_groups(data.groups, opts, group_index, field)
  elseif data.entries then
    return sum_entry_list(data.entries, opts, field)
  elseif data.en or data.fr then
    local side = lang_pick(data, opts)
    local total = sum_entry_list(side and side.entries, opts, field)
    if opts.details then
      total = total + sum_entry_list(side and side.long_entries, opts, field)
    end
    return total
  else
    error("cv-blocks: unrecognized data schema (expected top-level 'groups', 'entries', or 'en'/'fr' keys)")
  end
end

-- ---------------------------------------------------------------------
-- Entry point.
-- ---------------------------------------------------------------------

--- Renders a full data/<section>.yml document (either `{groups: [...]}`
-- or a Pattern F document keyed by `en`/`fr`) into a list of pandoc
-- Blocks.
-- @param data table plain Lua table decoded from a data/<section>.yml file
-- @param opts table { lang = "en"|"fr", details = boolean }
-- @return pandoc.List of pandoc Block elements
function M.render(data, opts)
  if data.groups then
    return render_groups(data.groups, opts)
  elseif data.entries then
    -- Bare `entries:` at the top level is shorthand for a single group
    -- with `heading: null` (e.g. experience.yml).
    local blocks = pandoc.List({})
    for _, latex in ipairs(render_entry_list(data.entries, opts)) do
      blocks:insert(pandoc.RawBlock("latex", latex))
    end
    return blocks
  elseif data.en or data.fr then
    return resolve_pattern_f(data, opts)
  else
    error("cv-blocks: unrecognized data schema (expected top-level 'groups', 'entries', or 'en'/'fr' keys)")
  end
end

return M
