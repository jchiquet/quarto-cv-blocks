# quarto-cv-blocks

[![Build](https://github.com/jchiquet/quarto-cv-blocks/actions/workflows/build.yml/badge.svg)](https://github.com/jchiquet/quarto-cv-blocks/actions/workflows/build.yml)

A Quarto extension for writing an academic CV/resume as data (YAML files)
rather than hand-formatted LaTeX. It provides a PDF format
(`cv-blocks-pdf`) and three content blocks (`.cv-block`,
`.cv-personalinfo`, `.cv-bibliography`) that render structured entries —
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
  just to use `.cv-block`/`.cv-personalinfo`/`.cv-bibliography`. On a
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
format:
  cv-blocks-pdf: default
classoption: [10pt, english]   # omit "english" for French
author: Jane Doe
title: My CV
cv-blocks:
  lang: en      # or fr — selects the language-specific parts of the data
  long: true    # or false — selects the long/short variant of the data
---
```

`author`/`title` are Quarto's own native metadata keys, not specific to
this extension — set once per document, or project-wide in `_quarto.yml`
if every document shares the same author (as the four example CVs at the
root of this repo do — see there). The extension uses them to define
`\nom`/`\title`, the two macros the fancyhdr footer relies on, and that a
document can freely reuse in its own raw LaTeX (e.g. a hand-built title
page). No `header-includes` needed just for that.

Then use the content blocks in the document body.

### Content blocks

A `.cv-block` Div's `file` attribute points at a YAML file with a
top-level `groups:` list. Each group has an optional `heading` and a list
of `entries`, each with a `date`, a `title`, and optional `items`:

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

`heading` and `label` are short vocabulary words, resolved against the
document's `cv-blocks.lang`/`cv-blocks.long` metadata — each can be a
plain string, an `{en:, fr:}` pair, a `{long:, short:}` pair, or both
nested (`{en: {long:, short:}, fr: {long:, short:}}`) when a heading
needs to vary along both axes. `date`/`title`/`item.text` are opaque raw
LaTeX content and aren't translated by the extension — write the
localized text directly, or use the `en`/`fr` entry variants below.

Entries can also be tagged `long_only`/`short_only`, or replaced by an
`en`/`fr` or `long`/`short` variant — see the data files under `data/` in
this repo for worked examples of every pattern.

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

### Personal info

A `.cv-personalinfo` Div's `file` attribute points at a YAML file with
just a short bio (email/web/github come from document metadata instead,
see below):

```yaml
# personal.yml
en:
  bio: ["Born January 1, 1990"]
  position: "Researcher"
  address: ["Example Institute", "1 Example Street"]
fr:
  bio: ["Née le 1 janvier 1990"]
  position: "Chercheuse"
  address: ["Institut Exemple", "1 rue de l'exemple"]
```

```markdown
::: {.cv-personalinfo file="personal.yml"}
:::
```

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

A `.cv-bibliography` Div's `file` attribute points at a YAML file listing
one or more bibliography **sections**, each with its own `.bib` file,
citation-key prefix, and independent numbering:

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

Bibliography groups can also be tagged `long_only`/`short_only`, same as
entries.

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
`_body.qmd`, `data/`) is at the root of this repo and doubles as a
reference for the schema above:

```sh
quarto render                                   # all four
quarto render cv-en-long.qmd --to cv-blocks-pdf  # just one
```
