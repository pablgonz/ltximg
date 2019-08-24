## LTXimg &ndash; LaTeX environments to image format

## Description

**ltximg** is a perl *script* that automates the process of extracting and converting
environments provided by **tikz**, **pstricks** and other packages from input file
to image formats in individual files using `ghostscript` and `poppler-utils`. Generates a file
with only extracted environments and other with environments converted to `\includegraphics`.

## Syntax
```bash
$ ltximg [<compiler>] [<options>] [--] <input file>.<tex|ltx>
```
## Usage
```bash
$ ltximg --latex  [<options>] <file.tex>
$ ltximg --arara  [<options>] <file.tex>
$ ltximg [<options>] <file.tex>
$ ltximg <file.tex>
```
If used without `[<compiler>]` and `[<options>]` the extracted environments are converted to `pdf` image format
and saved in the `/images` directory using `pdflatex` and `preview` package. Relative or absolute `paths` for files
and directories is not supported. If the last `[<options>]` take a *list separated by commas*, you need `--` at the end.

## Default environments extract
```bash
    pspicture    tikzpicture    pgfpicture    psgraph    postscript    PSTexample
```
## Options

```bash
                                                                    [default]
-h, --help            Display command line help and exit            [off]
-l, --license         Display GPL license and exit                  [off]
-v, --version         Display current version (1.7) and exit        [off]
-t, --tif             Create .tif files using ghostscript           [gs]
-b, --bmp             Create .bmp files using ghostscript           [gs]
-j, --jpg             Create .jpg files using ghostscript           [gs]
-p, --png             Create .png files using ghostscript           [gs]
-e, --eps             Create .eps files using poppler-utils         [pdftops]
-s, --svg             Create .svg files using poppler-utils         [pdftocairo]
-P, --ppm             Create .ppm files using poppler-utils         [pdftoppm]
-g, --gray            Gray scale for images using ghostscript       [off]
-f, --force           Capture "\psset" and "\tikzset" to extract    [off]
-n, --noprew          Create images files whitout "preview" package [off]
-d <integer>, --dpi <integer>
                      Dots per inch resolution for images           [150]
-m <integer>, --margin <integer>
                      Set margins for pdfcrop                       [0]
--imgdir <dirname>    Set name of directory to save images          [images]
--zip                 Compress files generated in .zip format       [off]
--tar                 Compress files generated in .tar.gz format    [off]
-o <filename>, --output <filename>
                      Create output file                            [off]
--verbose             Verbose printing                              [off]
--srcenv              Create files whit only code environment       [off]
--subenv              Create files whit preamble and code           [off]
--latex               Using latex>dvips>ps2pdf for compiler input
                      and pdflatex for compiler output              [off]
--dvips               Using latex>dvips>ps2pdf for compiler input
                      and latex>dvips>ps2pdf for compiler output    [off]
--arara               Use arara for compiler input and output       [off]
--xetex               Using xelatex for compiler input and output   [off]
--dvipdf              Using dvipdfmx for compiler input and output  [off]
--luatex              Using lualatex for compiler input and output  [off]
--prefix <string>     Set prefix append to each image file          [off]
--norun               Run script, but no create images files        [off]
--nopdf               Don't create a ".pdf" image files             [off]
--nocrop              Don't run pdfcrop                             [off]
--verbcmd <cmdname>   Set "\cmdname" verbatim command               [myverb]
--clean (doc|pst|tkz|all|off)
                      Removes specific text in output file          [doc]
--extrenv <env1,...>  Add new environments to extract               [empty]
--skipenv <env1,...>  Skip environments to extract                  [empty]
--verbenv <env1,...>  Add verbatim environments                     [empty]
--writenv <env1,...>  Add verbatim write environments               [empty]
--deltenv <env1,...>  Delete environments in output file            [empty]
```
## Example
```bash
$ ltximg --latex -e -p --srcenv --imgdir=mypics -o test-out test-in.ltx
```
```bash
$ ltximg --latex -ep --srcenv --imgdir mypics -o test-out  test-in.ltx
```
   Create a `/mypics` directory whit all extracted environments converted to
   image formats (`.pdf`, `.eps`, `.png`), individual files whit source code (`.tex`)
   for all extracted environments, a file `test-out.ltx` whit all environments converted to `\includegraphics`
   and file `test-in-fig-all.tex` with only the extracted environments using
   `latex>dvips>ps2pdf` and `preview` package for `<input file>` and `pdflatex`
   for `<output file>`.

## Documentation
   For full documentation use:
```bash
$ texdoc ltximg
```
   For recreation all documentation use:
```bash
$ arara ltximg-doc.dtx
```

## Licence
This program is free software; you can redistribute it and/or modify it under the terms of the GNU
General Public License as published by the Free Software Foundation; either version 3 of the License,
or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
License for more details.

## Author

Written by Pablo González L <pablgonz@yahoo.com>, last update 2019-08-24.

## Copyright

Copyright 2013 - 2019 by Pablo González L
