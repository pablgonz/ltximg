# demopkg --- model dtx file

## Description
`demopkg.dtx` is based on [Joseph Wright's model `dtx`
file](http://www.texdev.net/2009/10/06/a-model-dtx-file/) with some
modifications made to suit my tastes. In particular, I find it helpful to
include detailed installation instructions by default, to use the `gitinfo2`
package, and to generally package things with GitHub distribution in mind.

Package usage details should be covered by `demopkg.pdf`.

## Installation
Run

```
$ pdflatex demopkg.dtx
```
to generate the `.ins`, `.sty`, and `.pdf` files. In order to properly generate
the change history and index, run
```
$ makeindex -s gind.ist demopkg
$ makeindex -s gglo.ist -o demopkg.gls demopkg.glo
$ pdflatex demopkg.dtx
$ pdflatex demopkg.dtx
```
(You TeX environment may take care of this for you. I have vague recollections
of TeXShop not requiring me to manually run `makeindex`, but using Emacs AUCTeX
seems to require manual `makeindex`ing whether I run `C-c C-c latexmk` or `C-c
C-c LaTeX`.)
Finally, to use the generated `.sty` file, move it to the appropriate location
for your TeX distribution. Perhaps the easiest way to do this is by running
```
$ mv demopkg.sty $(kpsewhich -var-value=TEXMFHOME)/tex/latex
```
although if you're looking to make the file available to all users on a Unix
device, you're probably better off setting
`/usr/local/texlive/texmf-local/tex/latex` as the target directory (and then
running
```
# texhash
```
To ensure that installation has succeeded, run
```
$ kpsewhich demopkg.sty
```

and if the output is a path to the file, you're golden.
