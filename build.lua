--[[
  ** Build config for ltximg using l3build **
--]]

-- Identification
module     = "ltximg"
pkgversion = "1.8"
pkgdate    = "2020-02-25"

ctanpkg    = module
ctanzip    = ctanpkg.."-"..pkgversion

-- Configuration of files for build and installation
maindir       = "."
docfiledir    = "./doc"
docfiles      = {"ltximg-doc.tex"}
sourcefiledir = "./script"
sourcefiles   = {"ltximg-doc.tex","ltximg-doc.pdf","ltximg.pl"}
installfiles  = {"*.*"}
scriptfiles   = {"*.pl"}

tdslocations  = {
  "doc/latex/ltximg/ltximg-doc.pdf",
  "doc/latex/ltximg/ltximg-doc.tex",
  "doc/latex/ltximg/README.md",
  "scripts/ltximg/ltximg.pl",
}

flatten = false
packtdszip = false

-- Generating documentation
typesetfiles  = {"ltximg-doc.tex"}
typesetexe    = "lualatex"
typesetopts   = "--interaction=batchmode"
typesetruns   = 2
makeindexopts = "-q"

-- Create make_temp_dir() function
local function make_temp_dir()
  local tmpname = os.tmpname()
  tempdir = basename(tmpname)
  print("** Creating the temporary directory ./"..tempdir)
  errorlevel = mkdir(tempdir)
  if errorlevel ~= 0 then
    error("** Error!!: The ./"..tempdir.." directory could not be created")
    return errorlevel
  end
end

-- Add "testpkg" target to l3build CLI
if options["target"] == "testpkg" then
  make_temp_dir()
  -- Copy script
  print("** Copying ltximg.pl from "..sourcefiledir.." to ./"..tempdir)
  errorlevel = cp("ltximg.pl", sourcefiledir, tempdir)
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy ltximg.pl from "..sourcefiledir.." to /"..tempdir)
    return errorlevel
  end
  -- Check syntax of script
  local script = jobname(tempdir.."/ltximg.pl")
  script = script..".pl"
  print("** Running: perl -cw "..script)
  errorlevel = run(tempdir, "perl -cw "..script)
  if errorlevel ~= 0 then
    error("** Error!!: perl -cw "..script)
    return errorlevel
  end
  -- Copy test files
  print("** Copying files from ./test to ./"..tempdir)
  errorlevel = cp("*.tex", "./test", tempdir)
  if errorlevel ~= 0 then
    error("** Error!!: Can't copy files from ./test to /"..tempdir)
  end
  -- First test
  local file = jobname(tempdir.."/test-pst-exa-swpl.tex")
  print("** Running: perl "..script..".pl --latex "..file..".tex")
  errorlevel = run(tempdir, "perl "..script.." --latex "..file..".tex")
  if errorlevel ~= 0 then
    error("** Error!!: perl "..script..".pl --latex "..file..".tex")
    return errorlevel
  end
  -- Clean
  print("** Remove temporary directory ./"..tempdir)
  cleandir(tempdir.."/images")
  cleandir(tempdir)
  lfs.rmdir(tempdir.."/images")
  lfs.rmdir(tempdir)
  os.exit()
end
