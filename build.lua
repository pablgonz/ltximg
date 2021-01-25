--[[
  ** Build config for ltximg using l3build **
--]]

-- Identification
module  = "ltximg"
scriptv = "2.0"
scriptd = "2021-01-24"
ctanpkg = module
ctanzip = ctanpkg.."-"..scriptv

-- Configuration of files for build and installation
maindir        = "."
docfiledir     = "./doc"
docfiles       = {"ltximg-doc.tex"}
textfiles      = {"README.md"}
sourcefiledir  = "./script"
sourcefiles    = {"ltximg-doc.tex", "ltximg-doc.pdf", "ltximg.pl", "ltximg.1", "ltximg.man1.pdf" }
installfiles   = {"*.*"}
scriptfiles    = {"*.pl"}
scriptmanfiles = {"ltximg.1", "ltximg.man1.pdf"}

tdslocations  = {
  "doc/support/ltximg/ltximg-doc.pdf",
  "doc/support/ltximg/ltximg-doc.tex",
  "doc/support/ltximg/README.md",
  "doc/man/man1/ltximg.1",
  "doc/man/man1/ltximg.man1.pdf",
  "scripts/ltximg/ltximg.pl",
}

-- Clean files
cleanfiles = {
  ctanzip..".curlopt",
  ctanzip..".zip",
}

-- For CTAN distribution
flatten = true
packtdszip = true

-- Update date and version
tagfiles = {"ltximg-doc.tex", "README.md", "ltximg.pl"}

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
    content = string.gsub(content,
                          "Release v%d+.%d+%a* \\%[%d%d%d%d%-%d%d%-%d%d\\%]",
                          "Release v"..scriptv.." \\["..scriptd.."\\]")
   content = string.gsub(content,
                          "version %((.-)%)",
                          "version ("..scriptv..")")
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

-- Line length in 80 characters
local function os_message(text)
  local mymax = 77 - string.len(text) - string.len("done")
  local msg = text.." "..string.rep(".", mymax).." done"
  return print(msg)
end

-- Create check_marked_tags() function
local function check_marked_tags()
  local f = assert(io.open("doc/ltximg-doc.tex", "r"))
  marked_tags = f:read("*all")
  f:close()
  local m_docv = string.match(marked_tags, "\\def\\fileversion{(.-)}")
  local m_docd = string.match(marked_tags, "\\def\\filedate{(.-)}")

  if scriptv == m_docv and scriptd == m_docd then
    os_message("Checking version and date in ltximg-doc.tex")
  else
    print("** Warning: ltximg-doc.tex is marked with version "..m_docv.." and date "..m_docd)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
  end
end

-- Create check_script_tags() function
local function check_script_tags()
  local scriptv = "v"..scriptv

  local f = assert(io.open("script/ltximg.pl", "r"))
  script_tags = f:read("*all")
  f:close()
  local m_scriptd = string.match(script_tags, "my %$date %s* = '(.-)';")
  local m_scriptv = string.match(script_tags, "my %$nv %s* = '(.-)';")

  if scriptv == m_scriptv and scriptd == m_scriptd then
    os_message("Checking version and date in ltximg.pl")
  else
    print("** Warning: ltximg.pl is marked with version "..m_scriptv.." and date "..m_scriptd)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
  end
end

-- Create check_readme_tags() function
local function check_readme_tags()
  local scriptv = "v"..scriptv

  local f = assert(io.open("./README.md", "r"))
  readme_tags = f:read("*all")
  f:close()
  local m_readmev, m_readmed = string.match(readme_tags, "Release (v%d+.%d+%a*) \\%[(%d%d%d%d%-%d%d%-%d%d)\\%]")

  if scriptv == m_readmev and scriptd == m_readmed then
    os_message("Checking version and date in README.md")
  else
    print("** Warning: README.md is marked with version "..m_readmev.." and date "..m_readmed)
    print("** Warning: build.lua is marked with version "..scriptv.." and date "..scriptd)
  end
end

-- Config tag_hook
function tag_hook(tagname)
  check_readme_tags()
  check_marked_tags()
  check_script_tags()
end

-- Add "tagged" target to l3build CLI
if options["target"] == "tagged" then
  check_readme_tags()
  check_marked_tags()
  check_script_tags()
  os.exit()
end

-- Generating LaTeX documentation
typesetfiles  = {"ltximg-doc.tex"}
typesetexe    = "lualatex"
typesetopts   = "--interaction=batchmode"
typesetruns   = 2

function typeset(file)
  local file = jobname(docfiledir.."/ltximg-doc.tex")
  -- lualatex
  print("** Running: lualatex -interaction=batchmode "..file..".tex")
  errorlevel = runcmd("lualatex "..file..".tex >"..os_null, typesetdir, {"TEXINPUTS","LUAINPUTS"})
  if errorlevel ~= 0 then
    error("** Error!!: lualatex -interaction=batchmode "..file..".tex")
    return errorlevel
  end
  -- lualatex second run
  print("** Running: lualatex -interaction=batchmode "..file..".tex")
  errorlevel = runcmd("lualatex "..file..".tex >"..os_null, typesetdir, {"TEXINPUTS","LUAINPUTS"})
  if errorlevel ~= 0 then
    error("** Error!!: lualatex -interaction=batchmode "..file..".tex")
    return errorlevel
  end
  return 0
end

-- Generating man pages for script
function docinit_hook()
  -- Check OS
  local my_os = package.config:sub(1,1)
  local podcmd  = "--utf8 --center='General Commands Manual' --name=ltximg --release="..scriptv.." --date="..scriptd
  local file = jobname(typesetdir.."/ltximg.pl")
  -- If Linux
  if my_os == "/" then
    print("Typesetting ltximg.1")
    print("** Running: pod2man "..podcmd.." "..file..".pl "..file..".1")
    errorlevel = run(typesetdir, "pod2man "..podcmd.." "..file..".pl "..file..".1")
    if errorlevel ~= 0 then
      error("** Error!!: pod2man "..podcmd.." "..file..".pl "..file..".1")
      return errorlevel
    end
    -- Update man file in ./script
    errorlevel = cp(file..".1", typesetdir, sourcefiledir)
    if errorlevel ~= 0 then
      error("** Error!!: Can't copy "..file..".1 from "..typesetdir.." to "..sourcefiledir)
      return errorlevel
    end
    print("Typesetting ltximg.man1.pdf")
    print("** Running: man -Tpdf ./"..file..".1 > "..file..".man1.pdf")
    errorlevel = run(typesetdir, "man -Tpdf ./"..file..".1 > "..file..".man1.pdf")
    if errorlevel ~= 0 then
      error("** Error!!: man -Tpdf ./"..file..".1 > "..file..".man1.pdf")
      return errorlevel
    end
    -- Update man file in ./script
    errorlevel = cp(file..".man1.pdf", typesetdir, sourcefiledir)
    if errorlevel ~= 0 then
      error("** Error!!: Can't copy "..file..".man1.pdf from "..typesetdir.." to "..sourcefiledir)
      return errorlevel
    end
  else
    print("Cannot generate man pages in Windows")
  end
  return 0
end

-- Create make_tmp_dir() function
local function make_tmp_dir()
  -- Fix basename(path) in windows
  local function basename(path)
    return path:match("^.*[\\/]([^/\\]*)$")
  end
  local tmpname = os.tmpname()
  tmpdir = basename(tmpname)
  errorlevel = mkdir(tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: The ./"..tmpdir.." directory could not be created")
    return errorlevel
  else
    os_message("Creating the temporary directory ./"..tmpdir)
  end
  return 0
end

-- Add "testpkg" target to l3build CLI
if options["target"] == "testpkg" then
  -- Check tags
  check_readme_tags()
  check_marked_tags()
  check_script_tags()
  -- Create a ./tmp dir
  make_tmp_dir()
  -- Copy script
  errorlevel = cp("ltximg.pl", sourcefiledir, tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy ltximg.pl from "..sourcefiledir.." to /"..tmpdir)
    return errorlevel
  else
    os_message("Copying ltximg.pl from "..sourcefiledir.." to ./"..tmpdir)
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
  errorlevel = cp("*.tex", "./test", tmpdir)
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy files from ./test to /"..tmpdir)
    return errorlevel
  else
    os_message("Copying files from ./test to ./"..tmpdir)
  end
  -- First test
  local file = jobname(tmpdir.."/test-pst-exa-swpl.tex")
  print("** Running: perl "..script..".pl --latex "..file..".tex")
  errorlevel = run(tmpdir, "perl "..script.." --latex "..file..".tex")
  if errorlevel ~= 0 then
    error("** Error!!: perl "..script..".pl --latex "..file..".tex")
    return errorlevel
  end
  -- Second test
  local file = jobname(tmpdir.."/test-pst-exa-swpl.tex")
  print("** Running: perl "..script..".pl --xetex "..file..".tex")
  errorlevel = run(tmpdir, "perl "..script.." --xetex "..file..".tex")
  if errorlevel ~= 0 then
    error("** Error!!: perl "..script..".pl --xetex "..file..".tex")
    return errorlevel
  end
  -- Clean
  cleandir(tmpdir.."/images")
  cleandir(tmpdir)
  lfs.rmdir(tmpdir.."/images")
  lfs.rmdir(tmpdir)
  os_message("Remove temporary directory ./"..tmpdir)
  os.exit()
end

-- Load personal data
local ok, mydata = pcall(require, "mypersonaldata.lua")
if not ok then
  mydata = {email="XXX", uploader="YYY"}
end

-- CTAN upload config
uploadconfig = {
  author      = "Pablo González Luengo",
  uploader    = mydata.uploader,
  email       = mydata.email,
  pkg         = ctanpkg,
  version     = scriptv,
  license     = "lppl1.3c",
  summary     = "Extract LaTeX environments to image format and standalone files",
  description = [[ltximg is a perl script that automates the process of extracting and converting environments provided by TikZ, PStricks and other packages from input file to image formats and standalone files using ghostscript and poppler-utils. Generates a file with only extracted environments and another with all extracted environments converted to \includegraphics.]],
  topic       = { "chunks", "graphics", "subdocs" },
  ctanPath    = "/support/"..ctanpkg,
  repository  = "https://github.com/pablgonz/"..ctanpkg,
  bugtracker  = "https://github.com/pablgonz/"..ctanpkg.."/issues",
  support     = "https://github.com/pablgonz/"..ctanpkg.."/issues",
  announcement_file="ctan.ann",
  note_file   = "ctan.note",
  update      = true,
}

-- GitHub release version
local function os_capture(cmd, raw)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  if raw then return s end
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
  return s
end

-- Create a target for CLI
if options["target"] == "release" then
  -- Capture
  local gitbranch = os_capture("git symbolic-ref --short HEAD")
  local gitstatus = os_capture("git status --porcelain")
  local tagongit  = os_capture('git for-each-ref refs/tags --sort=-taggerdate --format="%(refname:short)" --count=1')
  local gitpush   = os_capture("git log --branches --not --remotes")

  -- Execute
  if gitbranch == "master" then
    os_message("Checking git branch '"..gitbranch.."'")
  else
    error("** Error!!: You must be on the 'master' branch")
  end
  if gitstatus == "" then
    os_message("Checking status of the files")
  else
    error("** Error!!: Files have been edited, please commit all changes")
  end
  if gitpush == "" then
    os_message("Checking pending commits")
  else
    error("** Error!!: There are pending commits, please run git push")
  end
  -- Check tags
  check_readme_tags()
  check_marked_tags()
  check_script_tags()

  local scriptv = "v"..scriptv
  errorlevel = os.execute("git tag -a "..scriptv.." -m 'Release "..scriptv.." "..scriptd.."'")
  if errorlevel ~= 0 then
    error("** Error!!: tag "..tagongit.." already exists, run git tag -d "..scriptv.." && git push --delete origin "..scriptv)
    return errorlevel
  else
    os_message("Checking last tag marked in GitHub '"..tagongit.."'")
    print("** Running: git tag -a "..scriptv.." -m 'Release "..scriptv.." "..scriptd.."'")
  end

  os_message("** Running: git push --tags --quiet")
  os.execute("git push --tags --quiet")
  if fileexists(ctanzip..".zip") then
    os_message("** Checking "..ctanzip..".zip file to send to CTAN: OK")
  else
    os_message("** Creating "..ctanzip..".zip file to send to CTAN")
    os.execute("l3build ctan > "..os_null)
  end
  os_message("** Running: l3build upload --debug")
  os.execute("l3build upload --debug > "..os_null)
  print("** Now check "..ctanzip..".curlopt file and add changes to ctan.ann")
  print("** If everything is OK run (manually): l3build upload")
  os.exit(0)
end
