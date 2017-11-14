#!/usr/bin/env perl
use v5.22;
use File::Basename; 
use Getopt::Long qw(:config bundling_override require_order no_ignore_case);
use autodie;                  
use File::Temp qw(tempdir);
use File::Copy;
use Config;
use File::Spec::Functions qw(catfile devnull);
use File::Find;
use Cwd;
#--------------------------- Constantes -------------------------------#
my $BPL       = '\begin{postscript}';
my $EPL       = '\end{postscript}';
my $sipgf     = 'pgfpicture';
my $nopgf     = 'pgfinterruptpicture';
my $BP 	      = '\\\\begin\{postscript\}';
my $EP 	      = '\\\\end\{postscript\}';
my $tempDir   = tempdir( CLEANUP => 1);	# temporary directory
my $tempSys   = dirname($tempDir);
my $workdir   = cwd;
my $null      = devnull(); # "null" device fro windows/linux

#------------------------------ CHANGES -------------------------------#
# v1.3 2016-04-02 - Rewrite some part of code 
#		  - Escape some characters in regex
# v1.2 2015-04-22 - Remove unused modules
# v1.1 2015-04-21 - Change mogrify to gs for image formats
#		  - Create output file
#                 - Rewrite source code and fix regex
#                 - Add more image format 
#	 	  - Change date to iso format
# v1.0 2013-12-01 - First public release 

#-------------------------- Getopt::Long ------------------------------#
my $other     = "other";	# other environment for search
my $imageDir  = "images";       # dir for images (images default)
my $ignore    = "ignore";      	# ignore verbatim environment
my $margins   = "0";            # margins for pdf crop
my $DPI       = "150";          # value for ppm, png, jpg 
my $source    = 0;		# 1->extrae codigo de las imágenes
my $clear     = 0;              # 0 or 1, clears all temporary files
my $nopreview = 0;              # 1->activa el modo nopreview
my $subfile   = 0;              # 1->create sub image files
my $latex     = 0;             	# 1->create all images using latex
my $xetex     = 0;              # 1->create all images using xelatex
my $luatex    = 0;              # 1->create all images using lualatex
my $pdf       = 1;		# 1->create a PDF image file
my $png       = 0;              # 1->create .png using Ghoscript
my $jpg       = 0;              # 1->create .jpg using Ghoscript
my $eps       = 0;              # 1->create .eps using pdftops
my $svg       = 0;		# 1->create .svg using pdf2svg
my $ppm       = 0;             	# 1->create .ppm using pdftoppm
my $all       = 0;	       	# 1->create all images type
my $output;		        # set output name for outfile
my $outfile   = 0;	       	# 1->write output file
my $outsrc    = 0;	       	# 1->enable write src env files

#----------------------------- Search GS ------------------------------#
# The next code its part of pdfcrop from TexLive 2014
# Windows detection 
my $Win = 0;
$Win = 1 if $^O =~ /mswin32/i;
$Win = 1 if $^O =~ /cygwin/i;

my $archname = $Config{'archname'};
$archname = 'unknown' unless defined $Config{'archname'};

# get Ghostscript command name
$::opt_gscmd = '';
sub find_ghostscript () {
    return if $::opt_gscmd;
    if ($::opt_debug) {
        print "* Perl executable: $^X\n";
        if ($] < 5.006) {
            print "* Perl version: $]\n";
        }
        else {
            printf "* Perl version: v%vd\n", $^V;
        }
        if (defined &ActivePerl::BUILD) {
            printf "* Perl product: ActivePerl, build %s\n", ActivePerl::BUILD();
        }
        printf "* Pointer size: $Config{'ptrsize'}\n";
        printf "* Pipe support: %s\n",
                (defined($Config{'d_pipe'}) ? 'yes' : 'no');
        printf "* Fork support: %s\n",
                (defined($Config{'d_fork'}) ? 'yes' : 'no');
    }
    my $system = 'unix';
    $system = "dos" if $^O =~ /dos/i;
    $system = "os2" if $^O =~ /os2/i;
    $system = "win" if $^O =~ /mswin32/i;
    $system = "cygwin" if $^O =~ /cygwin/i;
    $system = "miktex" if defined($ENV{"TEXSYSTEM"}) and
                          $ENV{"TEXSYSTEM"} =~ /miktex/i;
    print "* OS name: $^O\n" if $::opt_debug;
    print "* Arch name: $archname\n" if $::opt_debug;
    print "* System: $system\n" if $::opt_debug;
    my %candidates = (
        'unix' => [qw|gs gsc|],
        'dos' => [qw|gs386 gs|],
        'os2' => [qw|gsos2 gs|],
        'win' => [qw|gswin32c gs|],
        'cygwin' => [qw|gs gswin32c|],
        'miktex' => [qw|mgs gswin32c gs|]
    );
    if ($system eq 'win' or $system eq 'cygwin' or $system eq 'miktex') {
        if ($archname =~ /mswin32-x64/i) {
            my @a = ();
            foreach my $name (@{$candidates{$system}}) {
                push @a, 'gswin64c' if $name eq 'gswin32c';
                push @a, $name;
            }
            $candidates{$system} = \@a;
        }
    }
    my %exe = (
        'unix' => '',
        'dos' => '.exe',
        'os2' => '.exe',
        'win' => '.exe',
        'cygwin' => '.exe',
        'miktex' => '.exe'
    );
    my $candidates_ref = $candidates{$system};
    my $exe = $Config{'_exe'};
    $exe = $exe{$system} unless defined $exe;
    my @path = File::Spec->path();
    my $found = 0;
    foreach my $candidate (@$candidates_ref) {
        foreach my $dir (@path) {
            my $file = File::Spec->catfile($dir, "$candidate$exe");
            if (-x $file) {
                $::opt_gscmd = $candidate;
                $found = 1;
                print "* Found ($candidate): $file\n" if $::opt_debug;
                last;
            }
            print "* Not found ($candidate): $file\n" if $::opt_debug;
        }
        last if $found;
    }
    if (not $found and $Win) {
        $found = SearchRegistry();
    }
    if ($found) {
        print "* Autodetected ghostscript command: $::opt_gscmd\n" if $::opt_debug;
    }
    else {
        $::opt_gscmd = $$candidates_ref[0];
        print "* Default ghostscript command: $::opt_gscmd\n" if $::opt_debug;
    }
}

sub SearchRegistry () {
    my $found = 0;
    eval 'use Win32::TieRegistry qw|KEY_READ REG_SZ|;';
    if ($@) {
        if ($::opt_debug) {
            print "* Registry lookup for Ghostscript failed:\n";
            my $msg = $@;
            $msg =~ s/\s+$//;
            foreach (split /\r?\n/, $msg) {
                print " $_\n";
            }
        }
        return $found;
    }
    my $open_params = {Access => KEY_READ(), Delimiter => '/'};
    my $key_name_software = 'HKEY_LOCAL_MACHINE/SOFTWARE/';
    my $current_key = $key_name_software;
    my $software = new Win32::TieRegistry $current_key, $open_params;
    if (not $software) {
        print "* Cannot find or access registry key `$current_key'!\n"
                if $::opt_debug;
        return $found;
    }
    print "* Search registry at `$current_key'.\n" if $::opt_debug;
    my %list;
    foreach my $key_name_gs (grep /Ghostscript/i, $software->SubKeyNames()) {
        $current_key = "$key_name_software$key_name_gs/";
        print "* Registry entry found: $current_key\n" if $::opt_debug;
        my $key_gs = $software->Open($key_name_gs, $open_params);
        if (not $key_gs) {
            print "* Cannot open registry key `$current_key'!\n" if $::opt_debug;
            next;
        }
        foreach my $key_name_version ($key_gs->SubKeyNames()) {
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            print "* Registry entry found: $current_key\n" if $::opt_debug;
            if (not $key_name_version =~ /^(\d+)\.(\d+)$/) {
                print "  The sub key is not a version number!\n" if $::opt_debug;
                next;
            }
            my $version_main = $1;
            my $version_sub = $2;
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            my $key_version = $key_gs->Open($key_name_version, $open_params);
            if (not $key_version) {
                print "* Cannot open registry key `$current_key'!\n" if $::opt_debug;
                next;
            }
            $key_version->FixSzNulls(1);
            my ($value, $type) = $key_version->GetValue('GS_DLL');
            if ($value and $type == REG_SZ()) {
                print "  GS_DLL = $value\n" if $::opt_debug;
                $value =~ s|([\\/])([^\\/]+\.dll)$|$1gswin32c.exe|i;
                my $value64 = $value;
                $value64 =~ s/gswin32c\.exe$/gswin64c.exe/;
                if ($archname =~ /mswin32-x64/i and -f $value64) {
                    $value = $value64;
                }
                if (-f $value) {
                    print "EXE found: $value\n" if $::opt_debug;
                }
                else {
                    print "EXE not found!\n" if $::opt_debug;
                    next;
                }
                my $sortkey = sprintf '%02d.%03d %s',
                        $version_main, $version_sub, $key_name_gs;
                $list{$sortkey} = $value;
            }
            else {
                print "Missing key `GS_DLL' with type `REG_SZ'!\n" if $::opt_debug;
            }
        }
    }
    foreach my $entry (reverse sort keys %list) {
        $::opt_gscmd = $list{$entry};
        print "* Found (via registry): $::opt_gscmd\n" if $::opt_debug;
        $found = 1;
        last;
    }
    return $found;
} # end GS search 

########################################################################
###		Program identification, options and help 	     ###
########################################################################


### option and bolean value
my @bool = ("false", "true");
$::opt_debug      = 0;
$::opt_verbose    = 0;

### Call GS 
find_ghostscript();

if ($Win and $::opt_gscmd =~ /\s/) {
    $::opt_gscmd = "\"$::opt_gscmd\"";
}

my $program   = "LTXimg";
my $nv='1.4';
my $copyright = <<END_COPYRIGHT ;
2015-04-21 - Copyright (c) 2013-2016 by Pablo Gonzalez L.
END_COPYRIGHT
my $licensetxt = <<END_LICENSE ;
    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
 
    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    General Public License for more details.
 
    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston,
    MA  02111-1307  USA
END_LICENSE
my $title = "$program $nv, $copyright";
my $usage = <<"END_OF_USAGE";
${title}
Usage: ltximg [compiler] [options] input.ltx 

LTXimg extract and convert all PGF/TiKZ/Pstricks environments from TeX 
  source into single images files (pdf/png/eps/jpg/svg) using Ghostscript. 
  By default search and extract environments using (pdf)LaTeX.

Environments suports by LTXimg:

    pspicture	tikzpicture	pgfpicture	forest	ganttchart
    tikzcd	circuitikz	dependency	other	postscript

Options:
  
  -h,--help          	 - display this help and exit
  -l,--license       	 - display license and exit
  -v,--version 	     	 - display version (current $nv) and exit
  -d,--dpi <int>     	 - the dots per inch for images (default $DPI)
  -j,--jpg           	 - create .jpg files (need Ghostscript) [$::opt_gscmd]
  -p,--png           	 - create .png files (need Ghostscript) [$::opt_gscmd]
  -e,--eps	     	 - create .eps files (need pdftops)
  -s,--svg	     	 - create .svg files (need pdf2svg)
  -P,--ppm	     	 - create .ppm files (need pdftoppm)
  -a,--all	     	 - create .(pdf,eps,jpg,png) images
  -c,--clear             - delete all temp and aux files for output file
  -o,--output <filename> - create a outfile.tex whitout PGF|TiKZ|PST code
  -m,--margins <int> 	 - margins in bp for pdfcrop (default 0)
  -np,--nopreview    	 - create images files whitout preview package
  --source     	     	 - create separate files whit only code environment
  --subfile 	     	 - create separate files whit preamble and code environment
  --xetex            	 - using (Xe)LaTeX for create images
  --latex            	 - using LaTeX for create images
  --luatex           	 - using (Lua)LaTeX for create images
  --nopdf            	 - don't create a PDF image files (default off)
  --other <string>   	 - search other environment to extract (default other)
  --ignore <string>  	 - skip verbatim environment (default ignore)
  --imgdir <string>  	 - the folder for images (default images)
  --verbose       	 - verbose printing  (default [$bool[$::opt_verbose]])                       
  --debug         	 - debug information (default [$bool[$::opt_debug]])
  
  
Example:
* ltximg -e -p -j -c -o test-out --imgdir=pics test-in.ltx 
* produce test-out.tex whitout PGF|TiKZ|PST environments and create "pics"
* dir whit all images (pdf,eps,png,jpg) and source (.ltx) for all related 
* parts using (pdf)LaTeX whit preview package and cleaning all tmp files. 
* Suport bundling for short options: ltximg -epjco --imgdir=pics test.ltx
END_OF_USAGE

### error
sub errorUsage { die "@_ (try ltximg --help for more information)\n"; }

### Getopt::Long
my $result=GetOptions (
    'imgdir=s' 		=> \$imageDir, # images
    'ignore=s' 		=> \$ignore, # ignore, ignore*
    'other=s' 		=> \$other, # other, other*
    'd|dpi=i'    	=> \$DPI,# numeric
    'm|margins=i'       => \$margins,# numeric
    'pdf!'		=> \$pdf,# numeric,
    'e|eps'      	=> \$eps, # pdftops
    'j|jpg'      	=> \$jpg, # gs
    'p|png'      	=> \$png, # gs
    'P|ppm'      	=> \$ppm, # pdftoppm
    's|svg'      	=> \$svg, # pdf2svg
    'a|all'      	=> \$all, # all
    'h|help'       	=> \$::opt_help, # help
    'c|clear'    	=> \$clear,    # flag
    'subfile'	   	=> \$subfile, # subfile
    'source'	   	=> \$source, # src 
    'np|nopreview'      => \$nopreview, # 
    'xetex'	    	=> \$xetex, # 
    'latex'      	=> \$latex, # 
    'luatex'     	=> \$luatex,# 
    'o|output=s'        => \$output, # output file name
    "debug!",
    "verbose!",
    ) or die $usage;

### Options for command line
if ($::opt_help) {
    print $usage;
    exit(0);
}
if ($::opt_version) {
    print $title;
    exit(0);
}
if ($::opt_license) {
    print $licensetxt;
    exit(0);
} 
### Set values for verbose, debug, source options and tmp

my $tmp = "tmp-\L$program\E-$$"; 
say "$tmp";
### debug option
$::opt_verbose = 1 if $::opt_debug;
### source and subfile option
if ($source && $subfile) {
  die errorUsage "source and subfile options are mutually exclusive";
}
$outsrc = 1 and $subfile= 0 if $source ;
$outsrc = 1 and $source= 0 if $subfile ;

#---------------------- Check the input arguments ---------------------#
@ARGV > 0 or errorUsage "Input filename missing";
@ARGV < 2 or errorUsage "Unknown option or too many input files";

#--------------------- Arreglo de la extensión ------------------------#
my @SuffixList = ('.tex', '', '.ltx');    # posibles
my ($name, $path, $ext) = fileparse($ARGV[0], @SuffixList);
$ext = '.tex' if not $ext;


### Check the name of the output file 
if (defined $output) {
if ($output =~ /(^\-|^\.).*?/){ # validate otput file name 
    die errorUsage "$output it is not a valid name for the output file";
    } 
if ($output eq "$name") { # $output = $input
    $output = "$name-out$ext";  
    }
if ($output eq "$name$ext") { # $output = $input
    $output = "$name-out$ext";  
    }
if ($output =~ /.*?$ext/){ # remove .ltx o .tex extension
    $output =~ s/(.+?)$ext/$1/gms;
    }
} # close output string check

### If output name ok, then $outfile 
$outfile = 1 and $pdf = 1 if defined($output);
#$outsrc = 1 if defined($subfile) or defined($source);

### Create the directory for images 
-e $imageDir or mkdir($imageDir,0744) or die "Can't create $imageDir: $!\n";

### Standart console line ltximg run
print "$program $nv, $copyright" ;

########################################################################
### Arrangements required in the input file to extract environments ####
########################################################################

#--------------- Create a hash with changes for VERBATIM --------------#
my %cambios = (
# pst/tikz set    
    '\psset'                	=> '\PSSET',
    '\tikzset'		        => '\TIKZSET',
# pspicture    
    '\pspicture'                => '\TRICKS',
    '\endpspicture'             => '\ENDTRICKS',
# pspicture
    '\begin{pspicture'          => '\begin{TRICKS',
    '\end{pspicture'            => '\end{TRICKS',
# postscript
    '\begin{postscript}'        => '\begin{POSTRICKS}',
    '\end{postscript}'          => '\end{POSTRICKS}',
# $other    
    "\\begin\{$other"		=> '\begin{OTHER',
    "\\end\{$other"		=> '\end{OTHER',
# document
    '\begin{document}'          => '\begin{DOCTRICKS}',
    '\end{document}'            => '\end{DOCTRICKS}',
# tikzpicture
    '\begin{tikzpicture}'       => '\begin{TIKZPICTURE}',
    '\end{tikzpicture}'         => '\end{TIKZPICTURE}',
# pgfinterruptpicture
    '\begin{pgfinterruptpicture'=> '\begin{PGFINTERRUPTPICTURE',
    '\end{pgfinterruptpicture'  => '\end{PGFINTERRUPTPICTURE',
# pgfpicture
    '\begin{pgfpicture}'        => '\begin{PGFPICTURE}',
    '\end{pgfpicture}'          => '\end{PGFPICTURE}',
# ganttchart
    '\begin{ganttchart}'        => '\begin{GANTTCHART}',
    '\end{ganttchart}'          => '\end{GANTTCHART}',
# circuitikz
    '\begin{circuitikz}'        => '\begin{CIRCUITIKZ}',
    '\end{circuitikz}'          => '\end{CIRCUITIKZ}',
# forest     
    '\begin{forest}'       	=> '\begin{FOREST}',
    '\end{forest}'         	=> '\end{FOREST}',
# tikzcd 
    '\begin{tikzcd}'       	=> '\begin{TIKZCD}',
    '\end{tikzcd}'         	=> '\end{TIKZCD}',
# dependency
    '\begin{dependency}'       	=> '\begin{DEPENDENCY}',
    '\end{dependency}'         	=> '\end{DEPENDENCY}',
);

#--------------------------- Read all file in memory ------------------#
open my $INPUTfile, '<', "$name$ext";
my $archivo;
{
    local $/;
    $archivo = <$INPUTfile>;
}
close $INPUTfile;

#------------------------ Coment inline Verbatim ----------------------#

### Variables and constants
my $no_del = "\0";
my $del    = $no_del;

### Rules
my $llaves      = qr/\{ .+? \}                                                                  /x;
my $no_corchete = qr/(?:\[ .+? \])?                                                             /x;
my $delimitador = qr/\{ (?<del>.+?) \}                                                          /x;
my $verb        = qr/(spv|v|V)erb [*]?                                                          /ix;
my $lst         = qr/lstinline (?!\*) $no_corchete                                              /ix;
my $mint        = qr/mint      (?!\*) $no_corchete $llaves                                      /ix;
my $marca       = qr/\\ (?:$verb | $lst | $mint ) (\S) .+? \g{-1}              			/x;
my $comentario  = qr/^ \s* \%+ .+? $                                                            /mx;
my $definedel   = qr/\\ (?:   DefineShortVerb | lstMakeShortInline  ) $no_corchete $delimitador /ix;
my $indefinedel = qr/\\ (?: UndefineShortVerb | lstDeleteShortInline) $llaves                   /ix;

while ($archivo =~
        /   $marca
        |   $comentario
        |   $definedel
        |   $indefinedel
        |   $del .+? $del                                                       # delimited
        /pgmx) {
 
        my($pos_inicial, $pos_final) = ($-[0], $+[0]);                          # positions
        my $encontrado = ${^MATCH};                                             # found
 
    if ($encontrado =~ /$definedel/){                                           # defined delimiter
                        $del = $+{del};
                        $del = "\Q$+{del}" if substr($del,0,1) ne '\\';         # it is necessary to "escape"
                }
    elsif($encontrado =~ /$indefinedel/) {                                      # undefinde delimiter
                 $del = $no_del;                                       
        }
    else {                                                                      # we make changes
        while (my($busco, $cambio) = each %cambios) {
                       $encontrado =~ s/\Q$busco\E/$cambio/g;                   # it is necessary to escape $ busco
                        }
        substr $archivo, $pos_inicial, $pos_final-$pos_inicial, $encontrado;    # insert the new changes
 
        pos($archivo)= $pos_inicial + length $encontrado;                       # we position the next search
        }
}

#--------------------- Coment Verbatim environment --------------------#

### Split input file by lines
my @lineas = split /\n/, $archivo;

### Define Verbatim environments
my $VERBATIM  = qr/(?: (v|V)erbatim\*?   | # verbatim and fancyvrb 
(?:(?:P)?Center|(?:P)?SideBySide)?Example | # fancyvrb
			   PSTexample    | # pst-exa 
			   PSTcode       | # pst-exa 
			   LTXexample    | # showexpl 
			   $ignore\*?    | # $ignore 
			   tcblisting\*? | # tcolorbox 
			tcboutputlisting | # tcolorbox 
			    tcbexternal  | # tcolorbox 
			    extcolorbox  | # tcolorbox 
			    extikzpicture| # tcolorbox 
			   spverbatim    | # spverbatim
			   minted        | # minted
			   listing	 | # minted
			   lstlisting    | # listing
			   alltt         | # alltt 
			   comment\*?    | # comment 
			   xcomment        # xcomment
			   )/xi;

### postscript environment
my $POSTSCRIPT = qr/(?: postscript)/xi;
 
### tikzpicture environment
my $ENVIRONMENT    = qr/(?: tikzpicture | pspicture\*?)/xi;

### Del    
my $DEL;

### Coment verbatim environment in input file
for (@lineas) {
    if (/\\begin\{($VERBATIM)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
        while (my($busco, $cambio) = each %cambios) {
            s/\Q$busco\E/$cambio/g;
        }
    }
} # close 

### tcbverb verbatim from tcolorbox and mintinline
my $tcbverb = qr/\\(?:tcboxverb|myverb|mintinline)/;
my $arg_brac = qr/(?:\[.+?\])?/;
my $arg_curl = qr/\{(.+)\}/;      

### Coment tcolorbox inline verbatim in input file
for (@lineas) {
    if (m/$tcbverb$arg_brac$arg_curl/) {
        while (my($busco, $cambio) = each %cambios) {
            s/\Q$busco\E/$cambio/g;
        }
    } 
} # close 

###\newtcblisting[opcional]{nombre}
###\renewtcblisting[opcional]{nombre}
### \DeclareTCBListing[opcional]{nombre}
### \NewTCBListing[opcional]{nombre}
### \RenewTCBListing[opcional]{nombre}
#### \ProvideTCBListing[opcional]{nombre}
### \newtcbexternalizeenvironment{nombre}
### \renewtcbexternalizeenvironment{nombre}
### \newtcbexternalizetcolorbox{nombre}
### \renewtcbexternalizetcolorbox{nombre}


### Join lines
$archivo = join("\n", @lineas); 

### Split input file 
my($cabeza,$cuerpo,$final) = $archivo =~ m/\A (.+?) (\\begin\{document\} .+?)(\\end\{document\}.*)\z/msx;

########################################################################
###  Regex to convert All environment into Postscript environments   ###
########################################################################
 
### \pspicture to \begin{pspicture}
$cuerpo =~ s/\\pspicture(\*)?(.+?)\\endpspicture/\\begin{pspicture$1}$2\\end{pspicture$1}/gmsx;
 
### tikz/pst to Postscript
$cuerpo =~ s/\\begin\{$POSTSCRIPT\}.+?\\end\{$POSTSCRIPT\}(*SKIP)(*F)|
        (
        (?:\\(psset|tikzset)(\{(?:\{.*?\}|[^\{])*\}).*?)?  # si está lo guardo
        (\\begin\{($ENVIRONMENT)\} (.*?)  \\end\{\g{-2}\})
    )
    /$BPL\n$1\n$EPL/gmsx;
 
### pgfpicture to Postscript
$cuerpo =~ s/\\begin\{$POSTSCRIPT\}.+?\\end\{$POSTSCRIPT\}(*SKIP)(*F)|
    (
        \\begin\{$sipgf\}
            .*?
            (
                \\begin\{$nopgf\}
                .+?
                \\end\{$nopgf\}
                .*?
            )*?
        \\end\{$sipgf\}
    )
    /$BPL\n$1\n$EPL/gmsx;
 
### other to PostScript
my $EXPORT  = qr/(forest|ganttchart|tikzcd|circuitikz|dependency|$other\*?)/x;
 
$cuerpo =~ s/\\begin\{$POSTSCRIPT\}.+?\\end\{$POSTSCRIPT\}(*SKIP)(*F)|
        (\\begin\{($EXPORT)\} (.*?)  \\end\{\g{-2}\})
        /$BPL\n$1\n$EPL/gmsx;

########################################################################
###     Extract the PGF/TikZ/PST environments in separate files      ###
########################################################################

### Source $outsrc
if ($outsrc) {
my $src_name = "$name-fig-";   # name for output source file
my $srcNo    = 1; # source counter

### Source file whitout preamble
if ($source) {
print "Creating a separate files in $imageDir dir whit source code for all environments found in $name$ext\n";
while ($cuerpo =~ m/$BP\s*(?<env_src>.+?)\s*$EP/gms) {
open my $OUTsrc, '>', "$imageDir/$src_name$srcNo$ext";
    print $OUTsrc $+{env_src};
close $OUTsrc;
	  } # close while source 
# auto increment counter
continue {
    $srcNo++; 
    }
} # close source 

### Subfile whit preamble
if ($subfile) {
print "Creating a separate files in $imageDir dir whit source code for all environments found in $name$ext\n";
while ($cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms) { # search $cuerpo
open my $OUTsrc, '>', "$imageDir/$src_name$srcNo$ext";
print $OUTsrc <<"EOC";
$cabeza\\pagestyle\{empty\}\n\\begin\{document\}$+{'env_src'}\\end\{document\}
EOC
close $OUTsrc;
	    } # close while 
# auto increment counter
continue {
    $srcNo++; 
	}
    } # close subfile
} # close $outsrc

########################################################################
############# MINTED ###################################################
########################################################################
## Revisamos si esta cargado minted
#my ($minted) = $cabeza  =~ m/\\usepackage(\[?.+?\]?\{minted\})/msx;

#if ($cabeza =~ m/\\usepackage\[outputdir=images\]\{minted\}/)
#{
#$cabeza =~ s/\\usepackage\[outputdir=images\]\{minted\}/\\usepackage\[outputdir=$tempDir\]\{minted\}/msxg;
#}

#say "se ha encontrado $minted";

#######################################################################


########################################################################
# Creation a one ile whit all environments extracted from input file   #
# the extraction works in two ways, first try using the preview package#
# (default) otherwise creates a one file whit only environment         #
########################################################################

### $nopreview 
if ($nopreview) {
my @env_extract;

while ( $cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms ) { # search $cuerpo
    push @env_extract, $+{env_src}."\n\\newpage\n";
}
open my $OUTfig, '>', "$tempDir/$name-fig$ext";
print $OUTfig $cabeza."\\pagestyle{empty}\n\\begin{document}\n"."@env_extract\n"."\\end{document}";
close $OUTfig;
} # close $nopreview

### preview mode (default) 
else {
my $opt_prew = $xetex ? 'xetex,'
             : $latex ? ''
             :          'pdftex,'
             ;

my $preview = <<"EXTRA";
\\AtBeginDocument\{%
\\RequirePackage\[${opt_prew}active,tightpage\]\{preview\}%
\\renewcommand\\PreviewBbAdjust\{-60pt -60pt 60pt 60pt\}%
\\newenvironment\{postscript\}\{\}\{\}%
\\PreviewEnvironment\{postscript\}\}%
EXTRA

# write
open my $OUTfig, '>', "$workdir/$name-fig-$ext";
print   $OUTfig $preview.$cabeza.$cuerpo."\\end{document}";
close   $OUTfig;
} # close preview

### Copy source image file
if ($source) {
#copy("$workdir/$name-fig$ext", "$imageDir/$name-fig$ext");
    } # close $source

########################################################################
#------------------ Compiling file whit all environments --------------#
########################################################################

### Define compilers 
my $compiler = $xetex ? 'xelatex'
             : $luatex ? 'lualatex'
	     : $latex ?  'latex'
             :           'pdflatex'
             ;
	      
### Define --shell-escape for TeXLive and MikTeX
my $write18 = '-shell-escape'; # TeXLive
$write18 = '-enable-write18' if defined($ENV{"TEXSYSTEM"}) and
                          $ENV{"TEXSYSTEM"} =~ /miktex/i;

### Define --interaction mode for compilers
my $opt_compiler = '-interaction=batchmode' ; # default
$opt_compiler = '-interaction=nonstopmode' if defined($::opt_verbose);

### Option for pdfcrop
my $opt_crop = $xetex ?  "--xetex --margins $margins"
             : $luatex ? "--luatex --margins $margins"
	     : $latex ?  "--margins $margins"
             :           "--pdftex --margins $margins"
             ;

### Message on the terminal
if($nopreview){
print "Creating a temporary file $name-fig.pdf whit all PGF/TIKZ/PST environments using $compiler\n";
    }
else{
print "Creating a temporary file $name-fig.pdf whit all PGF/TIKZ/PST environments using $compiler and preview package\n";
    }

system("$compiler $write18 $opt_compiler -output-directory=$tempDir $workdir/$name-fig$ext > $null");

### move to $tempdir, ghostcript problem in input file path
chdir $tempDir;

### Compiling file using latex>dvips>ps2pdf
if($latex){
system("dvips -q -Ppdf -o $name-fig.ps $name-fig.dvi");
system("ps2pdf  -dPDFSETTINGS=/prepress $name-fig.ps  $name-fig.pdf");
    }
    
### Count environment found in file 
my $envNo= qx($::opt_gscmd -q -c "($name-fig.pdf) (r) file runpdfbegin pdfpagecount = quit");
chomp($envNo); # remove \n
print "The file $name-fig.pdf contain $envNo environment extracted, need a crop whit using pdfcrop whit margins $margins bp\n";
system("pdfcrop $opt_crop $name-fig.pdf $name-fig.pdf > $null");

### Option for gs
my $opt_gspdf='-q -dNOSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress';
my $opt_gspng="-q -dNOSAFER -sDEVICE=pngalpha -r$DPI";
my $opt_gsjpg="-q -dNOSAFER -sDEVICE=jpeg -r$DPI -dJPEGQ=100 -dGraphicsAlphaBits=4 -dTextAlphaBits=4";

### Fix pdftops error message in windows
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){
open my $ppmconf, '>', 'xpd';
print $ppmconf <<'EOH';
errQuiet yes
EOH
close $ppmconf;
}

########################################################################
###			 Create image formats	 		     ###
########################################################################

### PDF format
if ($pdf) {
for (my $pdfNo = 1; $pdfNo <= $envNo; $pdfNo++) { # open for
print "Create $imageDir/$name-fig-$pdfNo.pdf from $name-fig.pdf\r"; 
system("$::opt_gscmd $opt_gspdf -o $workdir/$imageDir/$name-fig-%1d.pdf $name-fig.pdf");
    } #close for
print "Done, PDF images files are in $imageDir\r";
}
### PNG format
if ($png) {
for (my $pngNo = 1; $pngNo <= $envNo; $pngNo++) { # open for
print "Create $imageDir/$name-fig-$pngNo.png from $name-fig.pdf\r"; 
system("$::opt_gscmd $opt_gspng -o $workdir/$imageDir/$name-fig-%1d.png $name-fig.pdf");
    } #close for
print "Done, PNG images files are in $imageDir\r";  
}
### JPEG format
if ($jpg) {
for (my $jpgNo = 1; $jpgNo <= $envNo; $jpgNo++) { # open for
print "Create $imageDir/$name-fig-$jpgNo.jpg from $name-fig.pdf\r"; 
system("$::opt_gscmd $opt_gsjpg -o $workdir/$imageDir/$name-fig-%1d.jpg $name-fig.pdf");
    } #close for
print "Done, JPG images files are in $imageDir\r";  
}
### SVG format pdf2svg
if ($svg) {
for (my $svgNo = 1; $svgNo <= $envNo; $svgNo++) { # open for
print "Create $imageDir/$name-fig-$svgNo.svg from $name-fig.pdf\r"; 
system("pdf2svg $name-fig.pdf $workdir/$imageDir/$name%1d.svg all");
    } #close for
print "Done, SVG images files are in $imageDir\r";  
}
### EPS format
if ($eps) {
for (my $epsNo = 1; $epsNo <= $envNo; $epsNo++) { # abrimos for
print "Create $imageDir/$name-fig-$epsNo.eps from $name-fig.pdf\r";   
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){ # windows
system("pdftops -cfg xpd -q -eps -f $epsNo -l $epsNo $name-fig.pdf $workdir/$imageDir/$name-fig-$epsNo.eps");
}
else{ # linux
system("pdftops -q -eps -f $epsNo -l $epsNo $name-fig.pdf $workdir/$imageDir/$name-fig-$epsNo.eps");
	}
    } # close for
print "Done, EPS images files are in $imageDir\r";  
} # close EPS

### PPM format
if ($ppm) {
for (my $ppmNo = 1; $ppmNo <= $envNo; $ppmNo++) { # abrimos for
print "Create $imageDir/$name-fig-$ppmNo.ppm from $name-fig.pdf\r";   
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){ # windows
system("pdftoppm  -cfg xpd  -q -r $DPI -f $ppmNo -l $ppmNo $name-fig.pdf $workdir/$imageDir/$name-fig-$ppmNo");
}
else{ # linux
system("pdftoppm -q -r $DPI -f $ppmNo -l $ppmNo $name-fig.pdf $workdir/$imageDir/$name-fig-$ppmNo");
			    }
		    } # close for
print "Done, PPM images files are in $imageDir\r";  
} # close PPM 

# back to $working dir
chdir $workdir;

### Clean ghostcript windows tmp files
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){
my @del_tmp;
find(\&del_tmp, $tempSys);
sub del_tmp{
my $tmp_gs = $_;
if(-f $tmp_gs && $tmp_gs =~ m/\_t.+?\.tmp$/){ # search _.+?.tmp
push @del_tmp, $File::Find::name;
	    }
	} # close del_tmp
    unlink @del_tmp; 
} # close clean tmp_gs

### Renaming PPM
if ($ppm) {
if (opendir(DIR,$imageDir)) {                         # open dir
    while (my $oldname = readdir DIR) {               # read and sustitute
        my $newname = $oldname =~ s/^($name-fig-\d+)(-\d+).ppm$/$1 . ".ppm"/re;
        if ($oldname ne $newname) {                   # validate
            rename("$imageDir/$oldname", "$imageDir/$newname"); # rename
		    }
		}
    closedir DIR;
	} # close rename ppm
} 

print "Done, all images files are in $workdir/$imageDir/\n";

########################################################################
# Output file creation, environments replacing by images and remove    #
# unused package in preamble 					       #
########################################################################

if ($outfile) {
### Convert Postscript to includegraphics 
my $grap="\\includegraphics[scale=1]{$name-fig-";
my $close = '}';
my $imgNo = 1; # counter for images

$cuerpo =~ s/$BP.+?$EP/$grap@{[$imgNo++]}$close/msg; # changes

#-------------------------- Reverse changes ---------------------------#
my %cambios = (
# pst/tikz set    
    '\PSSET'			=>	'\psset',
    '\TIKZSET' 			=> 	'\tikzset',		        
# pspicture    
    '\TRICKS'			=>	'\pspicture',
    '\ENDTRICKS'		=>	'\endpspicture',             
# pspicture
    '\begin{TRICKS'		=>	'\begin{pspicture',
    '\end{TRICKS'		=>	'\end{pspicture',
# $other    
    '\begin{OTHER'		=>	"\\begin\{$other",		
    '\end{OTHER'		=>	"\\end\{$other",
# document
    '\begin{DOCTRICKS}'		=>	'\begin{document}',
    '\end{DOCTRICKS}'		=>	'\end{document}',
# tikzpicture
    '\begin{TIKZPICTURE}'	=>	'\begin{tikzpicture}',
    '\end{TIKZPICTURE}'  	=>	'\end{tikzpicture}',
# pgfinterruptpicture
    '\begin{PGFINTERRUPTPICTURE'=>	'\begin{pgfinterruptpicture',
    '\end{PGFINTERRUPTPICTURE'  =>	'\end{pgfinterruptpicture',
# pgfpicture
    '\begin{PGFPICTURE}'	=>	'\begin{pgfpicture}',
    '\end{PGFPICTURE}'		=>	'\end{pgfpicture}',
# ganttchart
    '\begin{GANTTCHART}'	=>	'\begin{ganttchart}',
    '\end{GANTTCHART}'		=>	'\end{ganttchart}',
# circuitikz
    '\begin{CIRCUITIKZ}'	=>	'\begin{circuitikz}',
    '\end{CIRCUITIKZ}'		=>	'\end{circuitikz}',
# forest     
    '\begin{FOREST}'		=>	'\begin{forest}',
    '\end{FOREST}'		=>	'\end{forest}',
# tikzcd 
    '\begin{TIKZCD}'		=>	'\begin{tikzcd}',
    '\end{TIKZCD}'		=>	'\end{tikzcd}',
# dependency
    '\begin{DEPENDENCY}'	=>	'\begin{dependency}',
    '\end{DEPENDENCY}'		=>	'\end{dependency}',
# postscript
    '\begin{POSTRICKS}'		=> 	'\begin{postscript}',
    '\end{POSTRICKS}'		=>	'\end{postscript}',
);

#------------------------ Clean output file  --------------------------#

### Constantes
my $USEPACK  = quotemeta('\usepackage');
my $GRAPHICX = quotemeta('{graphicx}');
 
### Regex
my $CORCHETES = qr/\[ [^]]*? \]/x;
my $PALABRAS  = qr/\b (?: pst-\w+ | pstricks (?: -add )? | psfrag |psgo |vaucanson-g| auto-pst-pdf | graphicx )/x;
my $FAMILIA   = qr/\{ \s* $PALABRAS (?: \s* [,] \s* $PALABRAS )* \s* \}/x;

### Coment
$cabeza =~ s/ ^ ($USEPACK $CORCHETES $GRAPHICX) /%$1/msxg;
 
### Delete lines
$cabeza =~ s/ ^ $USEPACK (?: $CORCHETES )? $FAMILIA \n//msxg;
 
### Delete words
$cabeza =~ s/ (?: ^ $USEPACK \{ | \G) [^}]*? \K (,?) \s* $PALABRAS (\s*) (,?) /$1 and $3 ? ',' : $1 ? $2 : ''/gemsx;
     
### Append to premble
$cabeza .= <<"EXTRA";
\\usepackage{graphicx}
\\graphicspath{{$imageDir/}}
\\usepackage{grfext}
\\PrependGraphicsExtensions*{.pdf}
EXTRA
 
### Clean PST content in preamble
$cabeza =~ s/\\usepackage\{\}/% delete/gmsx;
$cabeza =~ s/\\psset\{.+?\}/% \\psset delete/gmsx;
$cabeza =~ s/\\SpecialCoor/% \\SpecialCoor/gmsx;
 
### Replace in body
while (my($busco, $cambio) = each %cambios) {
            $cabeza =~ s/\Q$busco\E/$cambio/g;
                        $cuerpo =~ s/\Q$busco\E/$cambio/g;
			$final =~ s/\Q$busco\E/$cambio/g;
            }

### Write output file 
open my $OUTfile, '>', "$workdir/$output$ext";
    print $OUTfile <<"EOC";
$cabeza$cuerpo$final
EOC
close $OUTfile;

#### Define compilers 
#my $compiler = $xetex ? 'xelatex'
             #: $luatex ? 'lualatex'
	     #: $latex ?  'pdflatex'
             #:           'pdflatex'
             #;
$compiler = 'pdflatex' if $latex;
print "Creating the file $output$ext whitout PGF/TIKZ/PST environments using $compiler\n";
system("$compiler $write18 $opt_compiler $workdir/$output$ext > $null");
} # close outfile file

if ($clear) {
my @del_tmp;
find(\&del_tmp, $workdir);
sub del_tmp{
my $auximgfile = $_;
if(-f $auximgfile && $auximgfile =~ /$output\.(aux|dvi|log|toc)/){ # search
push @del_tmp, $File::Find::name;
	    }
	}
    unlink @del_tmp;
} # close clear $outfile

if ($outfile) {
print "Finish, LTXimg create the file $output.pdf in $workdir and put all figures in $imageDir dir\n";
}else{
print "Finish, LTXimg create all figures in $imageDir dir\n";
}

__END__


### Define options for compilers
#my $opt_compile = $miktex ? '--enable-write18 --interaction=batchmode'
               #:            '--shell-escape --interaction=batchmode'
               #; 



### Option for images
my $opt_img  =  $png ? "-q -dSAFER -sDEVICE=pngalpha -r$DPI"
              : $jpg ? "-q -dSAFER -sDEVICE=jpeg -r$DPI -dJPEGQ=100 -dGraphicsAlphaBits=4 -dTextAlphaBits=4"
	      : $ppm ? "-q -eps -f $+{num} -l $+{num}"
	      : $eps ? "-q -eps -f $+{num} -l $+{num}"
	      : $pdf ? '-q -dSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress'
	      : 	'' 
	      ;



### Source
if ($source) {
my $src_file = "$name-src-";   # name for output source file
my $srcNo    = 1; # source counter

while ($cuerpo =~ m/$BP\s*(?<env_src>.+?)\s*$EP/gms) {
open my $OUTsrc, '>', "$imageDir/$src_file$srcNo$ext";
    print $OUTsrc $+{env_src};
close $OUTsrc;
	    } # close while
continue {
    $srcNo++; # auto increment counter
    }  
} # close

### Subfile
if ($subfile) {
my $sub_file = "$name-fig-";   # output sub files name
my $subNo = 1; # subfile counter

while ($cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms) { # search $cuerpo
open my $OUTsrc, '>', "$imageDir/$sub_file$subNo$ext";
print $OUTsrc <<"EOC";
$cabeza\\pagestyle\{empty\}\n\\begin\{document\}$+{'env_src'}\\end\{document\}
EOC
close $OUTsrc;
	    } # close while 
continue {
    $subNo++; # auto increment counter
    }
} # close $subfile
