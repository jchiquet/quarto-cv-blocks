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
-- `cv-blocks.data-dir` if set in document/project metadata. Bibliography
-- `.bib` file paths (referenced by name inside the YAML, not `file`) are
-- resolved the same way against `cv-blocks.bib-dir`.
--
-- Language (en/fr) and length (long/short) are driven by document
-- metadata:
--
--   cv-blocks:
--     lang: en      # or fr; default "en"
--     long: true    # or false; default true

local cv_yaml = require("cv-yaml")
local cv_patterns = require("cv-patterns")

local opts = { lang = "en", long = true }

local function read_opts(meta)
  local m = meta["cv-blocks"]
  if not m then
    return
  end
  if m.lang then
    opts.lang = pandoc.utils.stringify(m.lang)
  end
  if m.long ~= nil then
    -- MetaBool values stringify to "true"/"false".
    opts.long = pandoc.utils.stringify(m.long) == "true"
  end
  if m["bib-dir"] then
    opts["bib-dir"] = pandoc.utils.stringify(m["bib-dir"])
  end
end

local function data_dir(meta)
  local m = meta["cv-blocks"]
  if m and m["data-dir"] then
    return pandoc.utils.stringify(m["data-dir"])
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
