# **ltximg** - latex to image

## Description
**ltximg** is a perl *script* that automates the process of extracting and converting
environments provided by **pgf**, **tikz**, **pstricks** and other packages from input file
to image formats in individual files using `ghostscript` and `poppler-utils`. It is possible 
to create an output file with all extracted environments converted to `\includegraphics`.

## Usage
```
$ ltximg <compiler> [<options>] <file.ext>
$ ltximg --latex  [<options>] <file.ext>
$ ltximg --xetex  [<options>] <file.ext>
$ ltximg --arara  [<options>] <file.ext>
```
If called whitout `<compiler>` and `[<options>]`, the extracted environments are converted to `pdf` 
format and saved in `/images` dir using `pdflatex` and `preview` package.

## Default environments extract
```
    pspicture    tikzpicture    pgfpicture    psgraph    postscript    PSTexample
```
## Options in command line

```
Options:                                                          (default)

 -h,--help               - display this help and exit
 -l,--license            - display license and exit
 -v,--version            - display version (current 1.5rc) and exit
 -d,--dpi=<int>          - dots per inch for images                (150)
 -t,--tif                - create .tif files using ghostscript     (gs)
 -b,--bmp                - create .bmp files using ghostscript     (gs)
 -j,--jpg                - create .jpg files using ghostscript     (gs)
 -p,--png                - create .png files using ghostscript     (gs)
 -e,--eps                - create .eps files using poppler-utils   (pdftops)
 -s,--svg                - create .svg files using poppler-utils   (pdftocairo)
 -P,--ppm                - create .ppm files using poppler-utils   (pdftoppm)
 -g,--gray               - gray scale for images using ghostscript (off)
 -f,--force              - capture \psset and \tikzset to extract  (off)
 -n,--noprew             - create images files whitout preview     (off)
 -m,--margin=<int>       - margins in bp for pdfcrop               (0)
 -o,--output=<outname>   - create output file whit all extracted
                           converted to \includegraphics
 --imgdir=<string>       - set name of folder to save images       (images)
 --verbose               - verbose printing, set -interaction=mode (off)
 --srcenv                - create files whit only code environment
                           [mutually exclusive whit --subenv]
 --subenv                - create files whit preamble and code 
                           [mutually exclusive whit --srcenv]
 --arara                 - use arara for compiler input and output, 
                           need {options: "-recorder"} in arara rule
 --xetex                 - using xelatex for compiler input and output
 --latex                 - using latex>dvips>ps2pdf for compiler input 
                           and pdflatex for compiler output
 --dvips                 - using latex>dvips>ps2pdf for compiler input 
                           and latex>dvips>ps2pdf for compiler output
 --dvipdf                - using latex>dvipdfmx for input and output file
 --luatex                - using lualatex for compiler input and output
 --prefix=<string>       - prefix append to each image file        (fig)
 --norun                 - run script, but no create images files  (off)
 --nopdf                 - don't create a PDF image files          (off)
 --nocrop                - don't run pdfcrop                       (off)
 --myverb=<verbcmd>      - set custom verbatim \verbcmd|<code>|    (myverb)
 --clean=<doc|pst|tkz|all|off>
                         - removes specific text in output file    (doc)
 --extrenv=<env1,...>--  - add new environments to extract         (empty)
 --skipenv=<env1,...>--  - skip environments to extract            (empty)
 --verbenv=<env1,...>--  - add verbatim environments               (empty)
 --writenv=<env1,...>--  - add verbatim write environments         (empty)
 --deltenv=<env1,...>--  - delete environments in output file      (empty)
```
## Examples
```
$ ltximg -e -p -j --srcenv --imgdir=pics -o test-out test-in.ltx
```
Create a `/pics` dir whit all extracted environments (whit source code) converted to image 
formats (`pdf`, `eps`, `png`, `jpg`) in individual files and output file `test-out.ltx` whit 
all environments converted to `\includegraphics` using `pdflatex` whit `preview` package.

Suport bundling for short options:
```
$ ltximg -epj --srcenv --imgdir pics -o test-out  test-in.ltx
```
Use `texdoc ltximg` for full documentation.

Readme for version 1.5.rc [2017-12-13], (c) 2013 - 2017 by Pablo González L <pablgonz@yahoo.com>
