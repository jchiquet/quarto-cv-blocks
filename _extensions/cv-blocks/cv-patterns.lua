-- Rendering of the `groups: [...]` (and Pattern F) YAML schema into the
-- \multblock/\block LaTeX primitives (partials/pdf/before-body.tex). We
-- deliberately don't reimplement their table layout in Lua/Pandoc AST: we
-- emit calls to the macros themselves as raw LaTeX and let LaTeX do the
-- formatting, so entry content stays genuinely opaque (raw `\href`, `\em`,
-- ... pass through untouched).
--
-- opts passed to every function: { lang = "en"|"fr", long = boolean }

local cv_yaml = require("cv-yaml")

local M = {}

-- ---------------------------------------------------------------------
-- Shared i18n resolver: any short label (group heading, item label) can
-- be a plain string, an {en:, fr:} pair, a {long:, short:} pair, or an
-- {en: {long:, short:}, fr: {long:, short:}} nesting of both (in either
-- order) -- resolved recursively so all combinations fall out for free.
-- ---------------------------------------------------------------------

local function resolve_i18n(value, opts)
  if value == nil then
    return nil
  end
  if type(value) ~= "table" then
    return value
  end
  if value.en ~= nil or value.fr ~= nil then
    return resolve_i18n(opts.lang == "fr" and value.fr or value.en, opts)
  end
  if value.long ~= nil or value.short ~= nil then
    return resolve_i18n(opts.long and value.long or value.short, opts)
  end
  return value
end

-- ---------------------------------------------------------------------
-- Base primitive: one resolved {date, title, items?} entry.
-- ---------------------------------------------------------------------

--- Renders one {date, title, items?} entry as a \multblock (items
-- present) or \block (no items) call. `title`/`item.text` are opaque raw
-- LaTeX and are never escaped or reinterpreted (spec: "le contenu ...
-- reste opaque"). `item.label` is a short vocabulary word, not opaque
-- content, so it goes through the same i18n resolver as group headings.
local function render_simple_entry(entry, opts)
  local date = entry.date or ""
  local title = entry.title or ""

  if entry.items and #entry.items > 0 then
    local pairs_latex = {}
    for _, item in ipairs(entry.items) do
      local label = resolve_i18n(item.label, opts) or ""
      table.insert(pairs_latex, string.format("{%s}{%s}", label, item.text or ""))
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
    return opts.lang == "fr" and entry.fr or entry.en
  end
  return opts.long and entry.long or entry.short
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
  if entry.long_only and not opts.long then
    return false
  end
  if entry.short_only and opts.long then
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

  if group.long_only and not opts.long then
    if group.short_fallback then
      local text = opts.lang == "fr" and group.short_fallback.fr or group.short_fallback.en
      blocks:insert(pandoc.RawBlock("latex", text or ""))
    end
    return
  end
  if group.short_only and opts.long then
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
  local side = opts.lang == "fr" and data.fr or data.en
  if not side then
    error("cv-patterns: pattern F data has no '" .. tostring(opts.lang) .. "' key")
  end

  local blocks = pandoc.List({})

  if side.intro then
    blocks:insert(pandoc.RawBlock("latex", side.intro))
  end
  if not opts.long and side.short_note then
    blocks:insert(pandoc.RawBlock("latex", side.short_note))
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
  if opts.long then
    for _, latex in ipairs(render_entry_list(side.long_entries, opts)) do
      blocks:insert(pandoc.RawBlock("latex", latex))
    end
  end

  return blocks
end

-- ---------------------------------------------------------------------
-- Personal info block: name/contact block under the CV header. The
-- layout (two-column tabular, icon-prefixed contact lines) lives here as
-- generic code; the content (bio lines, position, address) comes from
-- data/personal.yml. Column widths differ EN/FR since French text needs
-- a wider left column.
-- ---------------------------------------------------------------------

local PERSONAL_INFO_WIDTH = {
  en = { left = "0.6", right = "0.4" },
  fr = { left = "0.5", right = "0.5" },
}

--- Renders the personal-info block (name/contact block under the CV
-- header) from data/personal.yml content. `email`/`web`/`github` come
-- from the document's own metadata (see cv-blocks.lua's read_author),
-- not from this file, to avoid a second place to keep them in sync.
-- @param data table { en = {bio, position, address}, fr = {...} }
-- @param opts table { lang = "en"|"fr", email, web, github }
-- @return pandoc.List of pandoc Block elements
function M.render_personal_info(data, opts)
  local side = opts.lang == "fr" and data.fr or data.en
  local width = PERSONAL_INFO_WIDTH[opts.lang] or PERSONAL_INFO_WIDTH.en

  local bio = table.concat(side.bio, "\\\\\n    ")
  local address = table.concat(side.address, "\\\\\n    ")

  local tex = string.format(
    [[
\noindent\begin{tabular}{@{}l@{}r@{}}
  \begin{minipage}[t]{%s\textwidth}
    %s\\[1ex]
    {\scriptsize\faEnvelope}~\href{mailto:%s}{\texttt{%s}}\\
    {\scriptsize\faFirefox}~\href{%s}{\texttt{%s}}\\
    {\small\faGithub}~\href{%s}{\texttt{%s}}
  \end{minipage}
  &
  \begin{minipage}[t]{%s\textwidth}
    %s\\[1ex]
    %s
  \end{minipage}
\end{tabular}]],
    width.left, bio, opts.email, opts.email, opts.web, opts.web, opts.github, opts.github,
    width.right, side.position, address
  )

  return pandoc.List({ pandoc.RawBlock("latex", tex) })
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
-- @param opts table { long = boolean, ["bib-dir"] = string }
-- @return pandoc.List of pandoc Block elements
function M.render_bibliography(data, opts)
  local blocks = pandoc.List({})
  for _, group in ipairs(data.groups or {}) do
    if not (group.long_only and not opts.long) then
      local heading = resolve_i18n(group.heading, opts)
      if heading then
        blocks:insert(pandoc.RawBlock("latex", "\\subsubsection{" .. heading .. "}"))
      end

      local bib_dir = opts["bib-dir"]
      local bib_path = bib_dir and (bib_dir .. "/" .. group.bib .. ".bib") or (group.bib .. ".bib")
      local keys, err = cv_yaml.read_bib_keys(bib_path)
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
-- lang/long visibility and pattern D/E variants -- used by the
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
        if not (group.long_only and not opts.long) then
          local bib_dir = opts["bib-dir"]
          local bib_path = bib_dir and (bib_dir .. "/" .. group.bib .. ".bib") or (group.bib .. ".bib")
          local keys, err = cv_yaml.read_bib_keys(bib_path)
          if not keys then
            error(err)
          end
          n = n + #keys
        end
      elseif not (group.long_only and not opts.long) and not (group.short_only and opts.long) then
        n = n + count_entry_list(group.entries, opts)
      end
    end
  end
  return n
end

--- Counts the entries a full data/<section>.yml document would render
-- (see M.render), optionally restricted to a single group.
-- @param data table plain Lua table decoded from a data/<section>.yml file
-- @param opts table { lang = "en"|"fr", long = boolean, ["bib-dir"] = string }
-- @param group_index integer|nil 1-based index into `data.groups`, if set
-- @return integer
function M.count(data, opts, group_index)
  if data.groups then
    return count_groups(data.groups, opts, group_index)
  elseif data.entries then
    return count_entry_list(data.entries, opts)
  elseif data.en or data.fr then
    local side = opts.lang == "fr" and data.fr or data.en
    local n = count_entry_list(side and side.entries, opts)
    if opts.long then
      n = n + count_entry_list(side and side.long_entries, opts)
    end
    return n
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
-- @param opts table { lang = "en"|"fr", long = boolean }
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
