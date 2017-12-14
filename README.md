## ltximg &ndash; LaTeX environments to image format 

## Description

**ltximg** is a perl *script* that automates the process of extracting and converting
environments provided by **tikz**, **pstricks** and other packages from input file
to image formats in individual files using `ghostscript` and `poppler-utils`. Generates a file 
with only extracted environments and another with environments converted to `includegraphics`.

## Syntax
```
$ ltximg <compiler> [<options>] [--] <file>.<tex|ltx>
```
## Usage
```
$ ltximg --latex  [<options>] <file.tex>
$ ltximg --arara  [<options>] <file.tex>
$ ltximg [<options>] <file.tex>
$ ltximg <file.tex>
```
If used without `<compiler>` and `[<options>]` the extracted environments are converted to `pdf` image format 
and saved in the `/images` directory using `pdflatex` and `preview` package. Relative or absolute `paths` for files 
and directories is not supported and if the last `[<options>]` take a list separated by commas you need `--` at the end.

## Default environments extract
```
    pspicture    tikzpicture    pgfpicture    psgraph    postscript    PSTexample
```
## Options in command line

```
Options:                                                          (default)

 -h,--help               - display this help and exit              (off)
 -l,--license            - display license and exit                (off)
 -v,--version            - display version (current v1.5) and exit (off) 
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
 --dvipdf                - using latex>dvipdfmx for input and output
 --luatex                - using lualatex for compiler input and output
 --prefix=<string>       - prefix append to each image file        (fig)
 --norun                 - run script, but no create images files  (off)
 --nopdf                 - don't create a PDF image files          (off)
 --nocrop                - don't run pdfcrop                       (off)
 --myverb=<verbcmd>      - set custom verbatim \verbcmd|<code>|    (myverb)
 --clean=<doc|pst|tkz|all|off>
                         - removes specific text in output file    (doc)
 --extrenv=<env1,...>    - add new environments to extract         (empty)
 --skipenv=<env1,...>    - skip environments to extract            (empty)
 --verbenv=<env1,...>    - add verbatim environments               (empty)
 --writenv=<env1,...>    - add verbatim write environments         (empty)
 --deltenv=<env1,...>    - delete environments in output file      (empty)
```
## Example
```
$ ltximg --latex -e -p --srcenv --imgdir=pics -o test-out test-in.ltx
```
```
$ ltximg --latex -ep --srcenv --imgdir pics -o test-out  test-in.ltx
```
Create a `/pics` directory whit all extracted environments (whit source code) converted to image 
formats (`pdf`, `eps`, `png`) in individual files, an output file `test-out.ltx` whit all environments 
converted to `\includegraphics` and a single file `test-in-fig-all.tex` with only the extracted environments 
using `latex>dvips>ps2pdf` and `preview` package for input file and `pdflatex` for output file. 
Use `texdoc ltximg` for full documentation.

## Licence
This program is free software; you can redistribute it and/or modify it under the terms of the GNU 
General Public License as published by the Free Software Foundation; either version 3 of the License, 
or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even 
the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public 
License for more details.

## Author

Written by Pablo González L <pablgonz@yahoo.com>

## Copyright

Copyright © 2013 - 2017 Pablo González L [2017-12-22]
