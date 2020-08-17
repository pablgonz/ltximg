--[[
  ** Build config for ltximg using l3build **
--]]

-- Identification
module  = "ltximg"
scriptv = "1.8"
scriptd = "2020-08-16"
ctanpkg = module
ctanzip = ctanpkg.."-"..scriptv

-- Configuration of files for build and installation
maindir       = "."
docfiledir    = "./doc"
docfiles      = {"ltximg-doc.tex"}
textfiledir   = "."
textfiles     = {"README.md"}
sourcefiledir = "./script"
sourcefiles   = {"ltximg-doc.tex","ltximg-doc.pdf","ltximg.pl"}
installfiles  = {"*.*"}
scriptfiles   = {"*.pl"}

tdslocations  = {
  "doc/support/ltximg/ltximg-doc.pdf",
  "doc/support/ltximg/ltximg-doc.tex",
  "doc/support/ltximg/README.md",
  "scripts/ltximg/ltximg.pl",
}

-- Clean files
cleanfiles = {
  ctanzip..".curlopt",
  ctanzip..".zip",
}

flatten = false
packtdszip = false

-- Update date and version
tagfiles = {"ltximg-doc.tex", "README.md","ltximg.pl"}

function update_tag(file, content, tagname, tagdate)
  if string.match(file, "%.tex$") then
    content = string.gsub(content,
                          "\\def\\fileversion{.-}",
                          "\\def\\fileversion{"..scriptv.."}")
    content = string.gsub(content,
                          "\\def\\filedate{.-}",
                          "\\def\\filedate{"..scriptd.."}")
  end
  if string.match(file, "README.md$") then
    local scriptd = string.gsub(scriptd, "-", "/")
    content = string.gsub(content,
                          "Release v%d+.%d+%a* \\%[%d%d%d%d%/%d%d%/%d%d\\%]",
                          "Release v"..scriptv.." \\["..scriptd.."\\]")
  end
  if string.match(file, "ltximg.pl$") then
    local scriptv = "v"..scriptv
    content = string.gsub(content,
                          "(my %$date %s* = ')(.-)';",
                          "%1"..scriptd.."';")
    content = string.gsub(content,
                          "(my %$nv %s* = ')(.-)';",
                          "%1"..scriptv.."';")
  end
  return content
end

-- Create check_marked_tags() function
local function check_marked_tags()
  local f = assert(io.open("doc/ltximg-doc.tex", "r"))
  marked_tags = f:read("*all")
  f:close()
  local m_docv = string.match(marked_tags, "\\def\\fileversion{(.-)}")
  local m_docd = string.match(marked_tags, "\\def\\filedate{(.-)}")

  if scriptv == m_docv and scriptd == m_docd then
    print("** Checking version and date in ltximg-doc.tex: OK")
  else
    print("** Warning: ltximg-doc.tex is marked with version "..m_docv.." and date "..m_docd)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
    print("** Check version and date in build.lua then run l3build tag")
  end
end

-- Create check_script_tags() function
local function check_script_tags()
  local scriptv = "v"..scriptv
  --local scriptd = string.gsub(scriptd, "/", "-")

  local f = assert(io.open("script/ltximg.pl", "r"))
  script_tags = f:read("*all")
  f:close()
  local m_scriptd = string.match(script_tags, "my %$date %s* = '(.-)';")
  local m_scriptv = string.match(script_tags, "my %$nv %s* = '(.-)';")

  if scriptv == m_scriptv and scriptd == m_scriptd then
    print("** Checking version and date in ltximg.pl: OK")
  else
    print("** Warning: ltximg.pl is marked with version "..m_scriptv.." and date "..m_scriptd)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
    print("** Check version and date in build.lua then run l3build tag")
  end
end

-- Config tag_hook
function tag_hook(tagname)
  check_marked_tags()
  check_script_tags()
end

-- Add "tagged" target to l3build CLI
if options["target"] == "tagged" then
  check_marked_tags()
  check_script_tags()
  os.exit()
end

-- Generating documentation
typesetfiles  = {"ltximg-doc.tex"}
typesetexe    = "lualatex"
typesetopts   = "--interaction=batchmode"
typesetruns   = 2
makeindexopts = "-q"

-- Create make_tmp_dir() function
local function make_tmp_dir()
  -- Fix basename(path) in windows
  local function basename(path)
    return path:match("^.*[\\/]([^/\\]*)$")
  end
  local tmpname = os.tmpname()
  tmpdir = basename(tmpname)
  print("** Creating the temporary directory ./"..tmpdir)
  errorlevel = mkdir(tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: The ./"..tmpdir.." directory could not be created")
    return errorlevel
  end
  return 0
end

-- Add "testpkg" target to l3build CLI
if options["target"] == "testpkg" then
  make_tmp_dir()
  -- Copy script
  print("** Copying ltximg.pl from "..sourcefiledir.." to ./"..tmpdir)
  errorlevel = cp("ltximg.pl", sourcefiledir, tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy ltximg.pl from "..sourcefiledir.." to /"..tmpdir)
    return errorlevel
  end
  -- Check syntax of script
  local script = jobname(tmpdir.."/ltximg.pl")
  script = script..".pl"
  print("** Running: perl -cw "..script)
  errorlevel = run(tmpdir, "perl -cw "..script)
  if errorlevel ~= 0 then
    error("** Error!!: perl -cw "..script)
    return errorlevel
  end
  -- Copy test files
  print("** Copying files from ./test to ./"..tmpdir)
  errorlevel = cp("*.tex", "./test", tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy files from ./test to /"..tmpdir)
  end
  -- First test
  local file = jobname(tmpdir.."/test-pst-exa-swpl.tex")
  print("** Running: perl "..script..".pl --latex "..file..".tex")
  errorlevel = run(tmpdir, "perl "..script.." --latex "..file..".tex")
  if errorlevel ~= 0 then
    error("** Error!!: perl "..script..".pl --latex "..file..".tex")
    return errorlevel
  end
  -- Clean
  print("** Remove temporary directory ./"..tmpdir)
  cleandir(tmpdir.."/images")
  cleandir(tmpdir)
  lfs.rmdir(tmpdir.."/images")
  lfs.rmdir(tmpdir)
  os.exit()
end
