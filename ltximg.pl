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
use Text::ParseWords;
use Data::Dumper;
#--------------------------- Constantes -------------------------------#
my $tempDir   = tempdir( CLEANUP => 1);	# temporary directory
my $tempSys   = dirname($tempDir);
my $workdir   = cwd;
my $null      = devnull(); # "null" device fro windows/linux

#------------------------------ CHANGES -------------------------------#
# v1.4.9b 2016-06-20 - Rewrite some part of code , norun, nocrop
#		  - Suport minted and tcolorbox packpage for verbatim
#		  - Use tmp dir for work
#		  - Escape some characters in regex according to v5.20
# v1.2 2015-04-22 - Remove unused modules
# v1.1 2015-04-21 - Change mogrify to gs for image formats
#		  - Create output file
#                 - Rewrite source code and fix regex
#                 - Add more image format 
#	 	  - Change date to iso format
# v1.0 2013-12-01 - First public release 

#-------------------------- Getopt::Long ------------------------------#
my $prefix    = 'fig';
my $skiptag   = 'noltximg';
my $extrtag   = 'ltximg';
my $other     = "other";	# other environment for search
my $imageDir  = "images";       # dir for images (images default)
my $ignore    = "ignore";      	# ignore verbatim environment
my $myverb    = "myverb";      	# \myverb verbatim inline
my $margins   = "0";            # margins for pdf crop
my $DPI       = "150";          # value for ppm, png, jpg 
my $source    = 0;		# 1->extrac code for environments
my $nopreview = 0;              # 1->dont use preview packpage
my $subfile   = 0;              # 1->create sub image files
my $latex     = 0;             	# 1->create all images using latex
my $xetex     = 0;              # 1->create all images using xelatex
my $luatex    = 0;              # 1->create all images using lualatex
my $pdf       = 1;		# 1->create a PDF image file
my $run       = 1;		# 1->create a image file
my $crop      = 1;		# 1->create a image file
my $gray      = 0;		# 1->create a gray scale images
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

# uniq and minus funtion
sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

sub array_minus(\@\@) {
	my %e = map{ $_ => undef } @{$_[1]};
	return grep( ! exists( $e{$_} ), @{$_[0]} ); 
}

### option and bolean value
my @bool = ("false", "true");
$::opt_debug      = 0;
$::opt_verbose    = 0;

### Call GS 
find_ghostscript();

if ($Win and $::opt_gscmd =~ /\s/) {
    $::opt_gscmd = "\"$::opt_gscmd\"";
}

#----------------- Program identification, options and help -----------#

my $program   = "LTXimg";
my $nv='1.4.59';
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
  -o,--output <filename> - create a outfile.tex whitout PGF|TiKZ|PST code
  -m,--margins <int> 	 - margins in bp for pdfcrop (default 0)
  -g,--gray            	 - create a gray scale images (default off)
  -n,--noprew    	 - create images files whitout preview package
  --source     	     	 - create separate files whit only environment
  --subfile 	     	 - create separate files whit preamble and environment
  --xetex            	 - using (Xe)LaTeX compiler for create images
  --latex            	 - using LaTeX compiler for create images
  --luatex           	 - using (Lua)LaTeX compiler for create images
  --norun            	 - run script, but no create images (default off)
  --nocrop            	 - run sdfsdfdsfs (default off)
  --nopdf            	 - don't create a PDF image files (default off)
  --other  <string>   	 - search other environment to extract (default other)
  --myverb <string>	 - search verbatim in line \myverb by default
  --ignore <string>  	 - skip verbatim environment (default ignore)
  --imgdir <string>  	 - the folder for images (default images)
  --verbose       	 - verbose printing  (default [$bool[$::opt_verbose]])                       
  --debug         	 - debug information (default [$bool[$::opt_debug]])
  
  
Example:
* ltximg -e -p -j -o test-out --imgdir=pics test-in.ltx 
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
    'ignore=s' 		=> \$ignore, # ignore
    'prefix=s' 		=> \$prefix, # prefix
    'other=s' 		=> \$other, # other, other*
    'd|dpi=i'    	=> \$DPI,# numeric
    'm|margins=i'       => \$margins,# numeric
    'pdf!'		=> \$pdf,# pdf image format
    'run!'		=> \$run,# run compiler
    'crop!'		=> \$crop,# run pdfcrop
    'e|eps'      	=> \$eps, # pdftops
    'j|jpg'      	=> \$jpg, # gs
    'p|png'      	=> \$png, # gs
    'P|ppm'      	=> \$ppm, # pdftoppm
    's|svg'      	=> \$svg, # pdf2svg
    'a|all'      	=> \$all, # all
    'g|gray'      	=> \$gray,# gray scale
    'h|help'       	=> \$::opt_help, # help
    'subfile'	   	=> \$subfile, # subfile
    'source'	   	=> \$source, # source files
    'n|noprew'      	=> \$nopreview, # no preview
    'myverb'		=> \$myverb, # \myverb inline
    'xetex'	    	=> \$xetex, # xelatex compiler
    'latex'      	=> \$latex, # latex compiler
    'luatex'     	=> \$luatex,# lualatex compiler
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
my $tmp = "tmp-\L$program\E-$$"; # tmp for name-fig-tmp 
$::opt_verbose = 1 if $::opt_debug;

### source and subfile option
if ($source && $subfile) {
  die errorUsage "srcfile and subfile options are mutually exclusive";
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

### Read all file in memory 
open my $INPUTfile, '<', "$name$ext";
my $archivo;
{
    local $/;
    $archivo = <$INPUTfile>;
}
close $INPUTfile;

########################################################################
#--------- Arrangements required in the input file to extract ---------#
########################################################################

# Reserved word for script 
my @word_tmp  = qw (
	    preview  
	    nopreview 	     	
    );

# Add TMP to @word_tmp 
my $word_tmp_out = join "\n", map { qq/<TMP$_/ } @word_tmp;
my @word_tmp_out = split /\n/, $word_tmp_out;

# %Hash para cambiar \begin{ and \end{ in verbatim inline
my %word_in = (
# \begin{ and \end{    
    '\begin{'           => 	'\BEGIN{',
    '\end{'             => 	'\END{',
    );

my %word_out = (
# \begin{ and \end{    
    '\BEGIN{'           => 	'\begin{',
    '\END{'             => 	'\end{',
    );

# %Hash para cambiar tags and reserver words in verbatim inline
my %changes_in = (
# ltximg tags
    '%<*ltximg>'        => 	'%<*LTXIMG>',
    '%</ltximg>'	=> 	'%</LTXIMG>',
    '%<*noltximg>'    	=> 	'%<*NOLTXIMG>',
    '%</noltximg>'      => 	'%</NOLTXIMG>',
# pst/tikz set    
    '\psset'            => 	'\PSSET',
    '\tikzset'		=> 	'\TIKZSET',
# pspicture    
    '\pspicture'        => 	'\TRICKS',
    '\endpspicture'     => 	'\ENDTRICKS',
# psgraph    
    '\psgraph'        	=> 	'\PSGRAPHTRICKS',
    '\endpsgraph'     	=> 	'\ENDPSGRAPHTRICKS',
    );

my %changes_out = (
# ltximg tags
    '\begin{nopreview}'	=> 	'%<*noltximg>',
    '\end{nopreview}'   => 	'%</noltximg>',
# pst/tikz set    
    '\PSSET'            => 	'\psset',
    '\TIKZSET'		=> 	'\tikzset',
# pspicture    
    '\TRICKS'           => 	'\pspicture',
    '\ENDTRICKS'        => 	'\endpspicture',
# psgraph    
    '\PSGRAPHTRICKS'    => 	'\psgraph',
    '\ENDPSGRAPHTRICKS' => 	'\endpsgraph',
    );

my %reverse_tag = (
# ltximg tags
    '%<*LTXIMG>'      	=> 	'%<*ltximg>',
    '%</LTXIMG>'        => 	'%</ltximg>',
    '%<*NOLTXIMG>'      => 	'%<*noltximg>',
    '%</NOLTXIMG>'      => 	'%</noltximg>',
    );

# En %change_while estan las palabras para cambiar en verbatim inline
my %change_while = (%changes_in,%word_in);

my %change_tmp_in;
@change_tmp_in{@word_tmp} = @word_tmp_out;

my %change_tmp_out;
@change_tmp_out{@word_tmp_out} = @word_tmp;

#Join %hash to back words in preview environment (while)
my %cambios_back = (%change_tmp_out,%changes_out,%word_out);

my @extr_tmp  = qw (
    postscript tikzpicture pgfpicture ganttchart circuitikz 
    forest tikzcd dependency pspicture
    );

my @skip_tmp  = qw ();

my @verb_tmp  = qw (
    Example CenterExample SideBySideExample PCenterExample 
    PSideBySideExample verbatim Verbatim BVerbatim LVerbatim SaveVerbatim 
    VerbatimOut PSTexample PSTcode LTXexample tcblisting tcboutputlisting 
    tcbexternal extcolorbox extikzpicture spverbatim minted listing lstlisting 
    alltt comment chklisting verbatimtab listingcont verbatimwrite boxedverbatim 
    demo filecontents sourcecode xcomment pygmented pyglist program programl 
    programL programs programf programsc programt
	);

## Reglas 
my $braces      = qr/ (?:\{)(.+?)(?:\})  	/msx;
my $braquet     = qr/ (?:\[)(.+?)(?:\])  	/msx;
my $no_corchete = qr/ (?:\[ .+? \])?		/msx;

### New verbatim environments defined in input file
my @new_verb = qw (
    newtcblisting DeclareTCBListing ProvideTCBListing NewTCBListing 
    newtcbexternalizeenvironment newtcbexternalizetcolorbox
    lstnewenvironment NewListingEnvironment NewProgram specialcomment 
    includecomment DefineVerbatimEnvironment newverbatim newtabverbatim
    );
    
my $newverbenv = join "|", map quotemeta, sort { length $a <=> length $b } @new_verb; 
$newverbenv = qr/\b(?:$newverbenv) $no_corchete $braces/msx; # (for)

### MINTED 
my $mintdenv   = qr/\\ newminted $braces (?:\{.+?\})		/x;
my $mintcenv   = qr/\\ newminted $braquet (?:\{.+?\}) 		/x;
my $mintdshrt  = qr/\\ newmint $braces (?:\{.+?\}) 		/x; 
my $mintcshrt  = qr/\\ newmint $braquet (?:\{.+?\}) 		/x; 
my $mintdline  = qr/\\ newmintinline $braces (?:\{.+?\}) 	/x;
my $mintcline  = qr/\\ newmintinline $braquet (?:\{.+?\}) 	/x;   

### Pasamos a un array el archivo de entrada y quitamos las líneas molestas
my @verbinput = $archivo;
s/%.*\n//mg foreach @verbinput; # quitar comentarios
s/^\s*|\s*//mg foreach @verbinput; # quitar espacios en blanco 
my $verbinput = join '', @verbinput; 

### Expresión regular pasada a un array
my @mint_denv  = $verbinput =~ m/$mintdenv/xg;  # \newminted{$mintdenv}{options} (for)
my @mint_cenv  = $verbinput =~ m/$mintcenv/xg;  # \newminted[$mintcenv]{lang} (for)
my @mint_dshrt = $verbinput =~ m/$mintdshrt/xg; # \newmint{$mintdshrt}{options} (while)
my @mint_cshrt = $verbinput =~ m/$mintcshrt/xg; # \newmint[$mintcshrt]{lang}{options} (while)
my @mint_dline = $verbinput =~ m/$mintdline/xg; # \newmintinline{$mintdline}{options} (while)
my @mint_cline = $verbinput =~ m/$mintcline/xg; # \newmintinline[$mintcline]{lang}{options} (while)
@verbinput     = $verbinput =~ m/$newverbenv/xg;# \newverbatim environments in input file (for)

### Append "code" and "inline" 
if (!@mint_denv == 0){
$mintdenv   = join "\n", map { qq/$_\Qcode\E/ } @mint_denv;
@mint_denv  = split /\n/, $mintdenv; # (for)
}
if (!@mint_dline == 0){
$mintdline  = join "\n", map { qq/$_\Qinline\E/ } @mint_dline;
@mint_dline = split /\n/, $mintdline; # (while)
}

### Verbatim environment defined in script (standart) (for loop)
my @ignore =  $ignore;
push(@verb_tmp,@mint_denv,@mint_cenv,@verbinput,@ignore);
@verb_tmp  = uniq(@verb_tmp); 

### Pasamos @array con quotemeta 
my @mint_tmp  = qw ( mint  mintinline );

my @mintline; 
push(@mintline,@mint_dline,@mint_cline,@mint_dshrt,@mint_cshrt,@mint_tmp);
@mintline = uniq(@mintline);

my $mintline = join "|", map quotemeta, sort { length $a <=> length $b } @mintline; 
$mintline   = qr/\b(?:$mintline)/x; 

# array para los a saltar
my ($skip_in) = $archivo =~ m/^\%ltximgs$braces/gms;
my @skip_in   = parse_line('\s+|,', 0, $skip_in);
push(@skip_tmp,@skip_in);
@skip_tmp  = uniq(@skip_tmp);

# array para los entornos a extraer
my ($extr_in) = $archivo =~ m/^\%ltximge$braces/gms;
my @extr_in   = parse_line('\s+|,', 0, $extr_in);
push(@extr_tmp,@extr_in); # ahora esta todo en @extr_tmp

# array para los nuevos entornos verbatim
my ($verb_in) = $archivo =~ m/^\%ltximgv$braces/gms;
my @verb_in = parse_line('\s+|,', 0, $verb_in);
push(@verb_tmp,@verb_in); # ahora esta todo en @verb_tmp

# esto es lo que vamos ha extraer
my @environ = array_minus(@extr_tmp, @skip_tmp);
@environ  = uniq(@environ); # esto ira a un %hash (while) y (for)

# esto será verbatim
my @verbatim = array_minus(@verb_tmp, @environ);
@verbatim  = uniq(@verbatim); # esto ira a un %hash (while)

# Definimos @env_all para crear un hash y hacer los reemplazo en while
# este array contiene verbatim, skip, y los entornos a extraer

my @env_all;
push(@env_all,@environ,@skip_tmp,@verbatim); 
@env_all  = uniq(@env_all); 

# Join %hash and map to qr (while)
my $busco = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %change_while;

my @no_verb = array_minus(@env_all, @verbatim);
@no_verb  = uniq(@no_verb);

# Add <TMP to all elements in @no_verb and save in no_verb_out
my $no_verb_out = join "\n", map { qq/<TMP$_/ } @no_verb;
my @no_verb_out  = split /\n/, $no_verb_out;

# Create a %hash_for_in (whit out verbatim)
my %hash_for_in; 
@hash_for_in{@no_verb} = @no_verb_out;

my %hash_for_out; 
@hash_for_out{@no_verb_out} = @no_verb;

# Join %hash and map to qr (ciclo for)
my %change_for_in = (%change_tmp_in,%hash_for_in,%changes_in);

# %hash_for_in and map to qr (for loop)
my $busco_verb = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %change_for_in;
## Cambios a realizar
my %cambios = (
        '\begin{'          => '\BEGIN{',
        '\end{'            => '\END{',
);
 
## Variables y constantes
my $no_del = "\0";
my $del    = $no_del;
 
## Reglas
my $llaves      = qr/\{ .+? \}                                                                  /x;
my $no_llaves   = qr/(?: $llaves )?                                                             /x;
my $corchetes   = qr/\[ .+? \]                                                                  /x;
my $no_corchete = qr/(?: $corchetes )?                                                          /x;
my $anidado     = qr/(\{(?:[^\{\}]++|(?1))*\})							/x;
my $delimitador = qr/\{ (?<del>.+?) \}                                                          /x;
my $verb        = qr/(?:((spv|(?:q|f)?v|V)erb)[*]?)                          /ix;
my $lst         = qr/(?:(lst|pyg)inline)(?!\*) $no_corchete                   /ix;
my $mint        = qr/(?: $mintline |SaveVerb) (?!\*) $no_corchete $no_llaves $llaves       /ix;
my $no_mint     = qr/(?: $mintline) (?!\*) $no_corchete /ix;
my $marca       = qr/\\ (?:$verb | $lst | $mint |$no_mint) (?:\s*)? (\S) .+? \g{-1}                       /x;
my $comentario  = qr/^ \s* \%+ .+? $                                                            /mx;
my $definedel   = qr/\\ (?: DefineShortVerb | 
			  lstMakeShortInline| 
		  MakeSpecialShortVerb  |
			) [*]? $no_corchete $delimitador 
			/ix;
my $indefinedel = qr/\\ (?: (Undefine|Delete)ShortVerb | lstDeleteShortInline) $llaves  /ix;
 
## Cambiar
while ($archivo =~
        /   $marca
        |   $comentario
        |   $definedel
        |   $indefinedel
        |   $del .+? $del                                                       # delimitado
        /pgmx) {
 
    my($pos_inicial, $pos_final) = ($-[0], $+[0]);                              # posiciones
    my $encontrado = ${^MATCH};                                                 # lo encontrado
 
    if ($encontrado =~ /$definedel/) {                                          # definimos delimitador
        $del = $+{del};
        $del = "\Q$+{del}" if substr($del,0,1) ne '\\';                         # es necesario "escapar" el delimitador
    }
    elsif ($encontrado =~ /$indefinedel/) {                                     # indefinimos delimitador
        $del = $no_del;                                
    }
    else {                                                                      # aquí se hacen los cambios
        while (my($busco, $cambio) = each %cambios) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;                              # es necesario escapar $busco
        }
 
        substr $archivo, $pos_inicial, $pos_final-$pos_inicial, $encontrado;    # insertamos los nuevos cambios
 
        pos($archivo) = $pos_inicial + length $encontrado;                      # re posicionamos la siguiente búsqueda
    }
}

### Nested {...} 
my $mintd_ani   = qr/\\ (?:$mintline|pygment) (?!\*) $no_corchete $no_llaves      /x;
my $tcbxverb    = qr/\\ (?: tcboxverb [*]?|$myverb [*]?)  $no_corchete /x;
my $tcbxmint    = qr/(?:$tcbxverb|$mintd_ani) (?:\s*)? $anidado	       			/x; 

### Cambiar
while ($archivo =~ /$tcbxmint/pgmx) {
 
        my($pos_inicial, $pos_final) = ($-[0], $+[0]);                          # posiciones
        my $encontrado = ${^MATCH};                                             # lo encontrado
	while (my($busco, $cambio) = each %cambios) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;                              # es necesario escapar $busco
        }
         substr $archivo, $pos_inicial, $pos_final-$pos_inicial, $encontrado;    # insertamos los nuevos cambios
    pos($archivo)= $pos_inicial + length $encontrado;                       # re posicionamos la siguiente búsqueda
}

# Ahora volvemos los <tags> a la normalidad dentro del archivo
my $ltxtags = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %reverse_tag;
$archivo =~ s/^($ltxtags)/$reverse_tag{$1}/gmsx;

# Definimos Verbatim 
my $verbatim   = join "|", map quotemeta, sort { length $a <=> length $b } @verbatim; 
$verbatim   = qr/$verbatim/x; # (for)

## Dividimos por líneas el archivo de entrada
my @lineas = split /\n/, $archivo;

## Change in \begin{$verbatim} ... \end{$verbatim}
my $DEL;
for (@lineas) {
    if (/\\begin\{($verbatim\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
        s/($busco_verb)/$change_for_in{$1}/g;
	}
} # close for

### Volvemos a unir 
$archivo = join("\n", @lineas); 

### Ahora dividimos el archivo de entrada
my($cabeza,$cuerpo,$final) = $archivo =~ m/\A (.+?) (\\begin\{document\} .+?)(\\end\{document\}.*)\z/msx;

# Definimos Skip
my $skipenv   = join "|", map quotemeta, sort { length $a <=> length $b } @skip_tmp; 
$skipenv   = qr/$skipenv/x; # (for)

# Regex recursiva para skip, skip debe estar en el tope de los entornos
my $skip_env = qr /
		(
		    (?:
		        \\begin\{$skipenv\*?\} 
		      (?:
		        (?>[^\\]+)|
		        \\
		        (?!begin\{$skipenv\*?\})
		        (?!end\{$skipenv\*?\})|
		        (?-1)
		      )*
		      \\end\{$skipenv\*?\}
		    )
		)
		/x;

# Pass %<*noltximg> .+? %</noltximg> to \begin{nopreview} .+? \end{nopreview}
$cuerpo =~ s/^\%<\*$skiptag>(.+?)\%<\/$skiptag>/\\begin\{nopreview\}$1\\end\{nopreview\}/gmsx;

# Pass $skip_env to \begin{nopreview} .+? \end{nopreview}
$cuerpo =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
	($skip_env)/\\begin\{nopreview\}\n$1\n\\end\{nopreview\}\n/gmsx;

# Definimos los entornos a extraer
my $environ   = join "|", map quotemeta, sort { length $a <=> length $b } @environ; 
$environ   = qr/$environ/x; # (for)

### convert \pspicture to latex environment syntax
$cuerpo =~ s/\\pspicture(\*)?(.+?)\\endpspicture/\\begin{pspicture$1}$2\\end{pspicture$1}/gmsx;

### convert \psgraph to latex environment syntax
$cuerpo =~ s/\\psgraph(\*)?(.+?)\\endpsgraph/\\begin{psgraph$1}$2\\end{psgraph$1}/gmsx;

# Regex recursiva para extrear
my $extr_env = qr /
		(?:\\(psset|tikzset)(\{(?:\{.*?\}|[^\{])*\}).*?)?  # si está lo guardo
		(
		    (?:
		        \\begin\{$environ\*?\} 
		      (?:
		        (?>[^\\]+)|
		        \\
		        (?!begin\{$environ\*?\})
		        (?!end\{$environ\*?\})|
		        (?-1)
		      )*
		      \\end\{$environ\*?\}
		    )
		)
		/x;

# Pass %<*ltximg> (.+?) %</ltximg> to \begin{preview} (.+?) \end{preview}
$cuerpo =~ s/^\%<\*$extrtag>(.+?)\%<\/$extrtag>/\\begin\{preview\}$1\\end\{preview\}/gmsx;

# Pass $extr_env to \begin{preview} .+? \end{preview}
$cuerpo =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\} # si esta dentro de nopreview
					    (*SKIP)(*F)|
		\\begin\{preview\}.+?\\end\{preview\}   # si esta dentro de preview
					    (*SKIP)(*F)|
  ($extr_env)/\\begin\{preview\}\n$1\n\\end\{preview\}\n/gmsx;

#### The extract environments need back word to original 
my %nuevo_back = (%cambios_back,%changes_out,%reverse_tag,%hash_for_out);
my $busco_back = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %nuevo_back;

# split $boody by lines
@lineas = split /\n/, $cuerpo;

### Change in \begin{preview} ... \end{preview}
my $DEL;
for (@lineas) {
    if (/\\begin\{(preview)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) { # rage operator
        s/($busco_back)/$nuevo_back{$1}/g;
        }
} # close for

### Volvemos a unir 
$cuerpo = join("\n", @lineas); 

my $BP 	      = '\\\\begin\{preview\}';
my $EP 	      = '\\\\end\{preview\}';

my @env_extract  = $cuerpo =~ m/(?<=$BP)(.+?)(?=$EP)/gms;

my $envNo = 0+ @env_extract;

### If environment extract found, the run script
if ($envNo == 0){
die errorUsage "ltximg not found any environment to extract file $name$ext";
}
else{ 
print "$program $nv, $copyright" ;
}

### Create the directory for images 
-e $imageDir or mkdir($imageDir,0744) or die "Can't create $imageDir: $!\n";

### Extract source $outsrc
if ($outsrc) {
my $src_name = "$name-$prefix-";
my $srcNo    = 1;

### Source file whitout preamble
if ($source) {
print "Creating a $envNo separate files in $imageDir dir whit source code for all environments found in $name$ext\n";
while ($cuerpo =~ m/$BP\s*(?<env_src>.+?)\s*$EP/gms) {
open my $OUTsrc, '>', "$imageDir/$src_name$srcNo$ext";
    print $OUTsrc $+{env_src};
close $OUTsrc;
	  } # close while
continue {
    $srcNo++; 
    }
} # close source 

### Subfile whit preamble
if ($subfile) {
print "Creating a $envNo separate files in $imageDir dir whit source code for all environments found in $name$ext\n";
while ($cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms) { # search $cuerpo
open my $OUTsrc, '>', "$imageDir/$src_name$srcNo$ext";
print $OUTsrc <<"EOC";
$cabeza\\pagestyle\{empty\}\n\\begin\{document\}$+{'env_src'}\\end\{document\}
EOC
close $OUTsrc;
	    } # close while 
continue {
    $srcNo++; 
	}
    } # close subfile
} # close $outsrc

########################################################################
# Creation a one file whit all environments extracted from input file  #
# the extraction works in two ways, first try using the preview package#
# (default) otherwise creates a one file whit only environment         #
########################################################################

### $nopreview 
if ($nopreview) {
my @env_extract;

while ( $cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms ) { # search $cuerpo
    push @env_extract, $+{env_src}."\n\\newpage\n";
}
open my $OUTfig, '>', "$name-$prefix-$tmp$ext";
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
\\renewcommand\\PreviewBbAdjust\{-60pt -60pt 60pt 60pt\}\}%
EXTRA

### write
open my $OUTfig, '>', "$name-$prefix-$tmp$ext";
print   $OUTfig $preview.$cabeza.$cuerpo."\n\\end{document}";
close   $OUTfig;
} # close preview

### Copy all source environment in one file 
if ($source or $subfile) {
copy("$workdir/$name-$prefix-$tmp$ext", "$imageDir/$name-$prefix-all$ext");
} 

#------------------ Compiling file whit all environments --------------#
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

### Option for pdfcrop if $opt::debug
my $opt_crop = $xetex ?  "--xetex --margins $margins"
             : $luatex ? "--luatex --margins $margins"
	     : $latex ?  "--margins $margins"
             :           "--pdftex --margins $margins"
             ;

### Option for images if $opt::debug 
my $opt_img  =  $png ? "-q -dSAFER -sDEVICE=pngalpha -r$DPI"
              : $jpg ? "-q -dSAFER -sDEVICE=jpeg -r$DPI -dJPEGQ=100 -dGraphicsAlphaBits=4 -dTextAlphaBits=4"
	      : $ppm ? "-q -eps -f $+{num} -l $+{num}"
	      : $eps ? "-q -eps -f $+{num} -l $+{num}"
	      : $pdf ? '-q -dSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress'
	      : 	'' 
	      ;

### Message on the terminal
if($run){
    if($nopreview){
    print "Creating a temporary file $name-$prefix-all.pdf whit all environments using $compiler\n";
	}
else{
    print "Creating a temporary file $name-$prefix-all.pdf whit all environments using $compiler and preview package\n";
	}


### Compiling file whit all environments $name-$prefix
if($opt::verbose){
    system("$compiler $write18 $opt_compiler -output-directory=$tempDir $name-$prefix-$tmp$ext");
    }
else{
    system("$compiler $write18 $opt_compiler -output-directory=$tempDir $name-$prefix-$tmp$ext > $null");    
    }

### Remove tmp image file 
unlink "$name-$prefix-$tmp$ext";

### Changue to tmp dir and work
chdir $tempDir;

### Compiling file using latex>dvips>ps2pdf
if($latex){
    system("dvips -q -Ppdf -o $name-$prefix-$tmp.ps $name-$prefix-$tmp.dvi");
    system("ps2pdf  -dPDFSETTINGS=/prepress $name-$prefix-$tmp.ps  $name-$prefix-$tmp.pdf");
} # close latex

### Count environments found in pdf file using gs

print "The file $name-fig.pdf contain $envNo environment extracted, need a crop whit using pdfcrop whit margins $margins bp\n";

### Crop file
if($::opt_verbose){
    system("pdfcrop $opt_crop $name-$prefix-$tmp.pdf $name-$prefix-$tmp.pdf");
    }
else{
    system("pdfcrop $opt_crop $name-$prefix-$tmp.pdf $name-$prefix-$tmp.pdf > $null");    
}

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
print "Create $imageDir/$name-$prefix-$pdfNo.pdf from $name--$prefix-all.pdf\r"; 
system("$::opt_gscmd $opt_gspdf -o $workdir/$imageDir/$name-$prefix-%1d.pdf $name-$prefix-$tmp.pdf");
    } # close for
print "Done, PDF images files are in $imageDir\r";
}
### PNG format
if ($png) {
for (my $pngNo = 1; $pngNo <= $envNo; $pngNo++) { # open for
print "Create $imageDir/$name-$prefix-$pngNo.png from $name-$prefix-all.pdf\r"; 
system("$::opt_gscmd $opt_gspng -o $workdir/$imageDir/$name-$prefix-%1d.png $name-$prefix-$tmp.pdf");
    } # close for
print "Done, PNG images files are in $imageDir\r";  
}
### JPEG format
if ($jpg) {
for (my $jpgNo = 1; $jpgNo <= $envNo; $jpgNo++) { # open for
print "Create $imageDir/$name-$prefix-$jpgNo.jpg from $name-$prefix-all.pdf\r"; 
system("$::opt_gscmd $opt_gsjpg -o $workdir/$imageDir/$name-$prefix-%1d.jpg $name-$prefix-$tmp.pdf");
    } # close for
print "Done, JPG images files are in $imageDir\r";  
}
### SVG format pdf2svg
if ($svg) {
for (my $svgNo = 1; $svgNo <= $envNo; $svgNo++) { # open for
print "Create $imageDir/$name-$prefix-$svgNo.svg from $name-$prefix-all.pdf\r"; 
system("pdf2svg $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-%1d.svg all");
    } # close for
print "Done, SVG images files are in $imageDir\r";  
}
### EPS format
if ($eps) {
for (my $epsNo = 1; $epsNo <= $envNo; $epsNo++) { # abrimos for
print "Create $imageDir/$name-$prefix-$epsNo.eps from $name-$prefix-all.pdf\r";   
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){ # windows
system("pdftops -cfg xpd -q -eps -f $epsNo -l $epsNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-$epsNo.eps");
}
else{ # linux
system("pdftops -q -eps -f $epsNo -l $epsNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-$epsNo.eps");
	}
    } # close for
print "Done, EPS images files are in $imageDir\r";  
} # close EPS

### PPM format
if ($ppm) {
for (my $ppmNo = 1; $ppmNo <= $envNo; $ppmNo++) { # abrimos for
print "Create $imageDir/$name-fig-$ppmNo.ppm from $name-$prefix-all.pdf\r";   
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){ # windows
system("pdftoppm  -cfg xpd  -q -r $DPI -f $ppmNo -l $ppmNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-$ppmNo");
}
else{ # linux
system("pdftoppm -q -r $DPI -f $ppmNo -l $ppmNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-fig-$ppmNo");
			    }
		    } # close for
print "Done, PPM images files are in $imageDir\r";  
} # close PPM 

### Clean ghostcript windows tmp files, not need in linux :)
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
if (opendir(DIR,$workdir/$imageDir)) {                         # open dir
    while (my $oldname = readdir DIR) {               # read and sustitute
        my $newname = $oldname =~ s/^($name-$prefix-\d+)(-\d+).ppm$/$1 . ".ppm"/re;
        if ($oldname ne $newname) {                   # validate
            rename("$imageDir/$oldname", "$imageDir/$newname"); # rename
		    }
		}
    closedir DIR;
	} # close rename ppm
} 

# back to $working dir
chdir $workdir;
print "Done, all images files are in $workdir/$imageDir/\n";
} # close run 

########################################################################
# Output file creation, environments replacing by images and remove    #
# unused package in preamble 					       #
########################################################################

if ($outfile) {
### Convert Postscript environments to includegraphics 
my $grap="\\includegraphics[scale=1]{$name-$prefix-";
my $close = '}';
my $imgNo = 1; # counter for images

$cuerpo =~ s/$BP.+?$EP/$grap@{[$imgNo++]}$close/msg; # changes

### Constantes
my $USEPACK  	= quotemeta('\usepackage');
my $GRAPHICX 	= quotemeta('{graphicx}');
my $GRAPHICPATH = quotemeta('\graphicspath{');
 
### Regex
my $CORCHETES = qr/\[ [^]]*? \]/x;
my $PALABRAS  = qr/\b (?: pst-\w+ | pstricks (?: -add )? | psfrag |psgo |vaucanson-g| auto-pst-pdf | graphicx )/x;
my $FAMILIA   = qr/\{ \s* $PALABRAS (?: \s* [,] \s* $PALABRAS )* \s* \}/x;

### Coment
$cabeza =~ s/ ^ ($USEPACK $CORCHETES $GRAPHICX) /%$1/msxg;

### Coment \graphicspath for order and future use
$cabeza =~ s/ ^ ($GRAPHICPATH) /%$1/msxg;
 
### Delete lines
$cabeza =~ s/ ^ $USEPACK (?: $CORCHETES )? $FAMILIA \n//msxg;
 
### Delete words
$cabeza =~ s/ (?: ^ $USEPACK \{ | \G) [^}]*? \K (,?) \s* $PALABRAS (\s*) (,?) /$1 and $3 ? ',' : $1 ? $2 : ''/gemsx;

### Search graphics pacth
my $graphicspath= qr/\\ graphicspath \{	((?: $llaves )+) \}/ix;

## Cambiar
if($cabeza =~ m/($graphicspath)/m){
while ($cabeza =~ /$graphicspath /pgmx) {
    my($pos_inicial, $pos_final) = ($-[0], $+[0]);	# posiciones
    my $encontrado = ${^MATCH};				# lo encontrado

    if ($encontrado =~ /$graphicspath/) {
    	my $argumento = $1;
	if ($argumento !~ /\{$imageDir\\\}/) {
	    $argumento .= "\{$imageDir/\}";

	    my $cambio = "\\graphicspath{$argumento}";

	    substr $cabeza, $pos_inicial, $pos_final-$pos_inicial, $cambio;
	    
	    pos($cabeza) = $pos_inicial + length $cambio;
	    }
	}
    } #close while
    
my ($GraphicsPath) = $cabeza =~ m/($graphicspath)/msx;
	
### Append to premble
$cabeza .= <<"EXTRA";
\\usepackage{graphicx}
$GraphicsPath
\\usepackage{grfext}
\\PrependGraphicsExtensions*{.pdf}
EXTRA
} # close if ($cabeza)
else{ 
my $GraphicsPath = "\\graphicspath\{\{$imageDir/\}\}";
### Append to premble
$cabeza .= <<"EXTRA";
\\usepackage{graphicx}
$GraphicsPath
\\usepackage{grfext}
\\PrependGraphicsExtensions*{.pdf}
EXTRA
} # close
 
### Clean PST content in preamble
    $cabeza =~ s/\\usepackage\{\}/% delete/gmsx;
    $cabeza =~ s/\\psset\{.+?\}/% \\psset delete/gmsx;
    $cabeza =~ s/\\SpecialCoor/% \\SpecialCoor/gmsx;
 
#### Replace in body
#while (my($busco, $cambio) = each %cambios) {
    #$cabeza =~ s/\Q$busco\E/$cambio/g;
    #$cuerpo =~ s/\Q$busco\E/$cambio/g;
    #$final  =~ s/\Q$busco\E/$cambio/g;
            #}

### Write output file 
open my $OUTfile, '>', "$output$ext";
print   $OUTfile "$cabeza$cuerpo\n$final";
close $OUTfile;

if($run){
### Define pdflates if latex for output 
$compiler = 'pdflatex' if $latex;

print "Creating the file $output$ext whitout environments using $compiler\n";

if($::opt_verbose){
	system("$compiler $write18 $opt_compiler -output-directory=$tempDir $workdir/$output$ext");
	}
else{
	system("$compiler $write18 $opt_compiler -output-directory=$tempDir $workdir/$output$ext > $null");
	}
### Copy generated pdf file to work dir
copy("$tempDir/$output.pdf", "$workdir/$output.pdf");	
    } # close outfile file
} # close run
if ($outfile) {
print "Finish, the file $output.pdf are in $workdir and put all figures in $imageDir dir\n";
}else{
print "Finish, all figures are in $workdir/$imageDir dir\n";
}

__END__


### Escritura un resultado temporal
open my $SALIDA, '>', "$output$ext";
print   $SALIDA "$cabeza$cuerpo\n$final";
close   $SALIDA;

### Change postcript envirnomnet to includegraphics

my $grap="\\includegraphics[scale=1]{EXTRAIDO-$prefix-";
my $close = '}';
my $imgNo = 1; # counter
$cuerpo =~ s/$BP.+?$EP/$grap@{[$imgNo++]}$close/msg;  
$cuerpo =~ s/($busco_back)/$nuevo_back{$1}/msg;
# Pass %<*noltximg> .+? %</noltximg> to \begin{nopreview} .+? \end{nopreview}
$cuerpo =~ s/^\\begin\{nopreview\}(.+?)\\end\{nopreview\}/\%<\*$skiptag>$1\%<\/$skiptag>/gmsx;



 
__END__
#delete @cambios{'\begin{postscript}','\end{postscript}'};
#print Dumper(\%cambios);



__END__
