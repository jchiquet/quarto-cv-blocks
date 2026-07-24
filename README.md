# quarto-cv-blocks

[![Build](https://github.com/jchiquet/quarto-cv-blocks/actions/workflows/build.yml/badge.svg)](https://github.com/jchiquet/quarto-cv-blocks/actions/workflows/build.yml)

A Quarto extension for writing an academic CV/resume as data (YAML files)
rather than hand-formatted LaTeX. It provides a PDF format
(`cv-blocks-pdf`) and three content blocks (`.cv-block`,
`.cv-header`, `.cv-bibliography`) that render structured entries —
positions, degrees, grants, teaching, publications — as clean two-column
LaTeX blocks. Content can be tagged English/French and long/short so the
same data files produce a full CV or a one-page summary in either
language.

## Requirements

- [Quarto](https://quarto.org) >= 1.4
- **LuaLaTeX** (the default PDF engine of this extension; a
  [TinyTeX](https://quarto.org/docs/output-formats/pdf-engine.html)
  install via `quarto install tinytex` is enough). TinyTeX installs
  missing LaTeX packages itself, on demand, the first time a document
  actually needs them (`titlesec`, `fancyhdr`, `float`, `eurosym`,
  `fontawesome`, `psnfss`, `biblatex`/`biber`, ...) — nothing to install
  by hand, as long as the machine rendering has network access.
- **Python 3 with [PyYAML](https://pyyaml.org/)** (`pip install pyyaml`)
  — used by the extension's Lua filter to parse the YAML data files
- Optionally, **R or Python with a plotting/table library** (e.g.
  `ggplot2`/`knitr`, or `matplotlib`/`pandas`) if a document uses
  executable code chunks — see "Executable code" below. Not required
  just to use `.cv-block`/`.cv-header`/`.cv-bibliography`. On a
  fresh Ubuntu machine (as in CI, see `.github/workflows/build.yml`),
  installing `ggplot2` from source needs a few system libraries first:
  `libcurl4-openssl-dev`, `libfontconfig1-dev`, `libharfbuzz-dev`,
  `libfribidi-dev`.

## Installation

```sh
quarto add jchiquet/quarto-cv-blocks
```

This installs the extension under `_extensions/cv-blocks/` in the current
project.

## Usage

Set the format and a few metadata keys in a document's YAML header:

```yaml
---
lang: en          # or fr -- this extension only supports these two
fontsize: 10pt
format:
  cv-blocks-pdf:
    details: true     # or false — selects the long/short variant of the data
    compact: true     # optional — one-page document, no running header/footer
    frontpage: true   # optional — cover page (name, title, date, TOC) before the body
author: Jane Doe
title: My CV
---
```

`lang`/`fontsize` are Quarto's own native, top-level keys — not specific
to this extension — and drive both the extension's own EN/FR content
selection *and* Quarto's usual LaTeX machinery (babel, hyphenation, the
document class's font-size option) from that single setting, so there's
no separate `classoption: [10pt, english]` to keep in sync by hand. Only
`en`/`fr` are supported; anything else falls back to English content
(same as leaving `lang` unset). Both languages' babel shorthands stay
available regardless of which is `lang:` (`_extension.yml` sets
`variables: {babel-otherlangs: [french, english]}`), so raw LaTeX content
can freely use e.g. French's `\ieme`/`\iere` ordinal-suffix macros even
in an English document without an "Undefined control sequence" error.

`details`/`compact` (and `cv-data-dir`/`bib-dir`, see "Content blocks" and
"Bibliography" below) live under `format.cv-blocks-pdf` — Quarto merges
format-scoped metadata into the same top-level table the extension reads,
same mechanism as any other pandoc PDF option (`classoption`, `geometry`,
...), so this isn't a special case. `cv-data-dir` is deliberately not
`data-dir`, dodging a confirmed Quarto reserved-key collision:
`data-dir` is silently swallowed before it even reaches a filter's
metadata table (confirmed empirically; `bib-dir` has no such problem and
keeps its plain name).

`details` and `compact` are independent: `details` only controls which
`long_only`/`short_only` content shows, not page count — a document can
show the short content set and still span several pages (e.g. a detailed
"dossier scientifique" that happens to omit the long-only entries). Set
`compact: true` only for a document that actually fits on one page, to
drop fancyhdr's running header/footer (`\pagestyle{empty}` instead of the
default `fancy`).

`author`/`title` are Quarto's own native metadata keys, not specific to
this extension — set once per document, or project-wide in `_quarto.yml`
if every document shares the same author (as the four example CVs at the
root of this repo do — see there). The extension uses them to define
`\nom`/`\title`, the two macros the fancyhdr footer relies on, and that a
document can freely reuse in its own raw LaTeX. No `header-includes`
needed just for that.

`frontpage: true` adds a cover page before the body — centered name/title,
a "Last update: <today>" line, and a `\tableofcontents` — built from
`\nom`/`\title`, so no raw LaTeX needed for it either. Meant for a longer,
multi-part document (e.g. a "dossier scientifique"); most documents here
put the name/personal info directly as the first heading instead (see the
four example CVs) and leave this off (the default).

Then use the content blocks in the document body.

### Content blocks

A `.cv-block` Div's `file` attribute points at a YAML file with a
top-level `groups:` list, resolved relative to the input document by
default, or to `cv-data-dir` if set (see "Usage" above). Each group has an
optional `heading` and a list of `entries`, each with a `date`, a `title`,
and optional `items`:

```yaml
# experience.yml
groups:
  - heading: {en: "Experience", fr: "Expérience"}
    entries:
      - date: "2020--"
        title: "Researcher, Example Institute"
        items:
          - label: {en: "Focus", fr: "Thème"}
            text: "Statistics and Machine Learning"
```

```markdown
::: {.cv-block file="experience.yml"}
:::
```

`heading`, `label`, `date`, `title`, `item.text` and `funding` are all
resolved against the document's `lang`/`details` metadata the same way:
each can be a plain string, an `{en:, fr:}` pair, a `{long:, short:}`
pair, or both nested (`{en: {long:, short:}, fr: {long:, short:}}`) when
a field needs to vary along both axes. `date`/`title`/`item.text`/
`funding` are otherwise opaque raw LaTeX content and never reinterpreted
beyond that — write the localized text directly on the field that
differs, or replace the whole entry with an `en`/`fr` variant (below) if
more than a couple of fields differ.

Entries can also be tagged `long_only`/`short_only`, or replaced by an
`en`/`fr` or `long`/`short` variant — see the data files under `data/` in
this repo for worked examples of every pattern.

A `funding` field is shorthand for a trailing item with a fixed EN/FR
"Support"/"Financement" label — for a grant's funder or type (ANR,
Horizon Europe, ...), instead of writing that item out by hand on every
entry:

```yaml
entries:
  - date: "2023--2027"
    title: "A funded project"
    funding: "Horizon Europe"
```

An `item`'s `text` isn't limited to a short value: it's typeset in a wide
table column, so a longer sentence just wraps like a paragraph. Combined
with a `long`/`short` entry variant, this is enough to add a free-text
description to a grant or a supervised thesis in the long CV only,
without touching the short one:

```yaml
entries:
  - long:
      date: "2023--2027"
      title: "A funded project"
      items:
        - label: {en: "Support", fr: "Financement"}
          text: "Horizon Europe"
        - label: {en: "Description", fr: "Description"}
          text: "A longer paragraph describing the project's goals,
            methodology, and impact -- shown only in the long CV."
    short:
      date: "2023--2027"
      title: "A funded project"
      items:
        - label: {en: "Support", fr: "Financement"}
          text: "Horizon Europe"
```

See `data/grants.yml` (the "DISCERN" grant) and `data/students.yml` for
worked examples.

### Header

A `.cv-header` Div's `file` attribute points at a YAML file with just a
short bio (email/web/github come from document metadata instead, see
below):

```yaml
# personal.yml
photo: photo.jpg   # optional -- resolved against cv-data-dir, like `file`
en:
  bio: ["Born January 1, 1990"]
  address: ["Example Institute", "1 Example Street"]
fr:
  bio: ["Née le 1 janvier 1990"]
  address: ["Institut Exemple", "1 rue de l'exemple"]
```

```markdown
## {{< meta author >}} {.unnumbered}

### Researcher in Statistics {.unnumbered}

::: {.cv-header file="personal.yml"}
:::
```

renders as a research-domain/theme tagline (from `categories:`/
`keywords:` metadata, if set — skipped entirely if neither is) followed
by the name/contact block, itself preceded by a `photo` column if set (a
JPG/PNG, scaled to a fixed height so it occupies about the same vertical
space as the bio/address columns beside it, regardless of its own aspect
ratio — column widths adjust automatically to make room for it). A job
title/position isn't part of this data file — it's just a heading in the
document body, styled the same way as any other section, placed between
the name and this Div (see the four example CVs at the root of this
repo).

The email/web/github contact line comes from document metadata instead
of `personal.yml` — `email`/`url` from Quarto's native `author:` schema,
`github` from a plain top-level key (not part of that schema):

```yaml
author:
  name: Jane Doe
  email: jane.doe@example.org
  url: https://example.org
github: https://github.com/example
```

### Bibliography

A `.cv-bibliography` Div's `file` attribute points at a YAML file (resolved
against `cv-data-dir`, same as `.cv-block`) listing one or more
bibliography **sections**, each with its own `.bib` file (resolved
against `bib-dir` if set), citation-key prefix, and independent
numbering:

```yaml
# publications.yml
groups:
  - heading: "Selected Publications"
    prefix: JP
    bib: papers   # resolves to papers.bib
  - heading: "Selected Talks"
    prefix: CT
    bib: talks    # resolves to talks.bib
```

```markdown
::: {.cv-bibliography file="publications.yml"}
:::
```

renders as two separately-numbered lists, `[JP1]`, `[JP2]`, ... and
`[CT1]`, `[CT2]`, ..., each restarting from 1.

List every `.bib` file under Quarto's native `bibliography:` key (no
`\addbibresource`/`header-includes` needed — Quarto's own PDF template
emits one per entry when `cite-method: biblatex` is active, which this
extension always sets) and it will run biber automatically — no external
compile script needed, even for a document with a bibliography:

```yaml
bibliography:
  - papers.bib
  - talks.bib
```

Each entry is resolved against `bib-dir` too, same as a `bib:` field in a
`.cv-bibliography` data file — an entry that already looks like an
absolute path is left alone, so `bib-dir` can be set once (e.g. to an
external repo the real `.bib` files live in) instead of repeating it on
every `bibliography:` line.

Bibliography groups can also be tagged `long_only`/`short_only`, same as
entries.

### Counting entries

The `cv_count` shortcode counts the entries a `.cv-block`/
`.cv-bibliography` Div pointed at the same file would render — handy for
a hand-written summary sentence ("N students supervised", "N papers")
that stays in sync with the data instead of a number updated by hand:

```markdown
{{< cv_count file="students.yml" >}}
{{< cv_count file="students.yml" group=1 >}}
```

`file` resolves the same way as a Div's `file` attribute (against
`cv-data-dir`); `group` restricts the count to one 1-based group index, e.g.
to separate current students from alumni, or PhD students from Master's
students, when both live in the same file as separate groups. The count
always includes `long_only` content — a total like "47 journal papers"
belongs in a short CV's summary too — so it isn't affected by the
document's own `details` setting.

Quote `file`/`group` values normally; inside a raw LaTeX
(`` ```{=latex} ``) block specifically, put a space between a `{...}`
argument delimiter and the shortcode's own `{{<` (e.g. `{Production}{
{{< cv_count file="papers.yml" >}} papers}`, not `{Production}{{{<`) —
three consecutive `{` otherwise confuses the shortcode parser.

The `cv_sum` shortcode is the same idea for a numeric field instead of
entries — e.g. a per-entry `hours:` field on `data/teachings.yml`, for a
"~N hours of teaching" sentence that stays in sync instead of a
hand-maintained estimate:

```yaml
# teachings.yml
entries:
  - date: "2020--24"
    title: "Statistics in Action with R"
    hours: 60
```

```markdown
{{< cv_sum file="teachings.yml" field="hours" >}}
```

Same `file`/`group` resolution and quoting rules as `cv_count`; `field`
is required (no sensible default).

The `cv_keywords` shortcode joins a list-valued metadata field into a
single separated string — handy for a "Themes"/"Research" line in the
same summary, since Quarto's own `{{< meta >}}` shortcode refuses
list-valued fields. Defaults to Quarto's native `keywords:`, `$\cdot$`
separator; `field`/`sep` override either, e.g. to read Quarto's native
`categories:` for a comma-separated list of research domains instead:

```yaml
keywords: [Sparse models, Multi-omics integration, Reproducible research]
categories: [Statistical methods, Machine learning]
```

```markdown
{{< cv_keywords >}}
{{< cv_keywords sep=", " >}}
{{< cv_keywords field="categories" sep=", " >}}
```

### Executable code (figures, tables)

A `cv-blocks-pdf` document is a regular Quarto document outside of its
`.cv-*` Divs, so ordinary Markdown, math (`$...$`/`$$...$$`), and
executable R/Python code chunks work as usual — e.g. for a "Research
Project" section with a figure or a table generated from code. Set an
engine (`engine: knitr` or `jupyter: python3`) in the document's YAML
header, same as any other Quarto document.

Captioned tables (`tbl-cap:`) just work: pandoc emits them as a
`longtable`, which isn't a floating environment, so it stays exactly
where it's placed. A captioned **figure** (`fig-cap:`) is a real LaTeX
float and can drift away from where it's placed on the page — add
`fig-pos: "H"` to pin it in place instead (the extension loads the
`float` package needed for `[H]`):

````markdown
```{r}
#| fig-cap: "A caption"
#| fig-pos: "H"
plot(1:10)
```
````

Figure captions are placed below the figure (`fig-cap-location: bottom`,
set in `_extension.yml`).

See `cv-en-long.qmd`/`cv-fr-long.qmd`'s "Research Project" section for a
worked example (a captioned R/ggplot2 figure + a captioned `kable`
table).

## Examples

Four example CVs (en/fr × long/short, one fictitious data set) are
rendered on every push to `main` and published from the `gh-pages`
branch:

- [cv-en-long.pdf](https://jchiquet.github.io/quarto-cv-blocks/cv-en-long.pdf)
- [cv-en-short.pdf](https://jchiquet.github.io/quarto-cv-blocks/cv-en-short.pdf)
- [cv-fr-long.pdf](https://jchiquet.github.io/quarto-cv-blocks/cv-fr-long.pdf)
- [cv-fr-short.pdf](https://jchiquet.github.io/quarto-cv-blocks/cv-fr-short.pdf)

The long versions include two bibliography sections ("Selected
Publications" and "Selected Talks", `[JP...]` and `[CT...]` prefixes),
rendered from `data/papers.yml` + `data/papers.bib`/`data/talks.bib`, to
demonstrate `.cv-bibliography` with multiple independently-numbered
sections, and a "Students" section (`data/students.yml`) with a
long-only description paragraph on a supervised thesis — see
"Content blocks" above.

The source for these four documents (`cv-{en,fr}-{long,short}.qmd`,
`data/`) is at the root of this repo and doubles as a reference for the
schema above:

```sh
quarto render                                   # all four
quarto render cv-en-long.qmd --to cv-blocks-pdf  # just one
```
