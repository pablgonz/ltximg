# **ltximg** - latex to image

## Description
> **ltximg** is a *perl script* that automates the process of extracting and converting
environments provided by **pgf**, **tikz**, **pstricks** and other packages from input file
to image formats in individual files using `ghostscript` and `poppler-utils`.
It is possible to create an output file with all extracted environments converted to
`\includegraphics`. By default the extracted environments are converted to `pdf` format
and saved in the `/images` using `preview` package and `pdflatex` if no `<compiler>` and options is used.

## Usage
```
$ ltximg <compiler> [options] <file.ext>
$ ltximg --latex  [options] <file.ext>
$ ltximg --xetex  [options] <file.ext>
$ ltximg --arara  [options] <file.ext>
```
If called whitout `compiler` option, extract and convert environments using `pdflatex`
and `ghostscript`. The images in individual files created are saved in a `/images` dir by
default.

## Default environments suports
```
    pspicture    tikzpicture    pgfpicture    psgraph    postscript    PSTexample
```
## Options

```
 -h,--help             - display this help and exit
 -l,--license          - display license and exit
 -v,--version          - display version (current 1.5) and exit
 -d,--dpi = <int>      - dots per inch for images (default: 150)
 -t,--tif              - create .tif files using ghostscript [gs]
 -b,--bmp              - create .bmp files using ghostscript [gs]
 -j,--jpg              - create .jpg files using ghostscript [gs]
 -p,--png              - create .png files using ghostscript [gs]
 -e,--eps              - create .eps files using pdftops
 -s,--svg              - create .svg files using pdftocairo
 -P,--ppm              - create .ppm files using pdftoppm
 -g,--gray             - gray scale for images using ghostscript (default: off)
 -f,--force            - capture \psset and \tikzset to extract (default: off)
 -n,--noprew           - create images files whitout preview (default: off)
 -m,--margin <int>     - margins in bp for pdfcrop (default: 0)
 -o,--output <outname> - create output file whit environmets converted in image.
                         <outname> must not contain extension.
 --imgdir    <string>  - the name of folder for images (default: images)
 --verbose             - set -interaction=batchmode for compiler (default: off)
 --srcenv              - create separate files whit only code environment
 --subenv              - create sub files whit preamble and code environment
 --arara               - use arara for compiler files, need to pass "-recorder"
                         % arara : <compiler> : {options: "-recorder"}
 --xetex               - using xelatex compiler for create images
 --latex               - using latex>dvips>ps2pdf compiler for create images
 --dvips               - using latex>dvips>ps2pdf for compiler output file
 --dvipdf              - using latex>dvipdfmx  for create images
 --luatex              - using lualatex compiler for create images
 --prefix              - prefix append to each file created (default: fig)
 --norun               - run script, but no create images (default off)
 --nopdf               - don't create a PDF image files (default: off)
 --nocrop              - don't run pdfcrop (default: off)
 --myverb  <string>    - set verbatim inline command \string (default: myverb)
 --clean   <value>     - removes specific text in the output file (default: doc)
                         values are: <doc|pst|tkz|all|off>
 --extrenv <env1,...>  - search other environment to extract (need -- at end)
 --skipenv <env1,...>  - skip default environment to extract (need -- at end)
 --verbenv <env1,...>  - add new verbatim environment (need -- at end)
 --writenv <env1,...>  - add new verbatim write environment (need -- at end)
 --deltenv <env1,...>  - delete environment in output file (need -- at end)
```
## Examples
```
$ ltximg -e -p -j --srcenv --imgdir=pics -o test-out test-in.ltx
```
Create a `/pics` folder and save all the extracted environments converted to
image formats (pdf, eps, png, jpg) and source code (.ltx) in individual files.
Create a file `test-out.ltx` whit all environments converted to `\includegraphics`
using pdflatex whit `preview` package.

Suport bundling for short options:
```
$ ltximg -epj --srcenv --imgdir pics -o test-out  test-in.ltx
```
Use `texdoc ltximg` for full documentation.

Readme for version 1.5.rc (2017-12-03). Copyright (C) 2013 - 2017 by Pablo González L <pablgonz@yahoo.com>
