#!/usr/bin/env perl
use v5.22;
use File::Basename;
use Getopt::Long qw(:config bundling_values require_order no_ignore_case);
use autodie;
use File::Temp qw(tempdir);
use File::Copy;
use Config;
use File::Spec::Functions qw(catfile devnull);
use File::Find;
use Cwd;
use Data::Dumper;

#--------------------------- Constantes -------------------------------#
my $tempDir   = tempdir( CLEANUP => 1);	# temporary directory
my $tempSys   = dirname($tempDir);
my $workdir   = cwd;
my $null      = devnull(); # "null" device fro windows/linux

#---------------------- Program identification ------------------------#
my $program   = "LTXimg";
my $nv='1.4.9y';
my $copyright = <<END_COPYRIGHT ;
2015-08-21 - Copyright (c) 2013-2016 by Pablo Gonzalez L, pablgonz<at>yahoo.com
END_COPYRIGHT

#------------------------------ CHANGES -------------------------------#
# v1.4.9y 2016-09-11 - All options its read from cmd line and input file
# v1.4.9u 2016-08-14 - Rewrite some part of code , norun, nocrop, clean
#		     - Suport minted and tcolorbox packpage for verbatim
#		     - Use tmp dir for work
#		     - Escape some characters in regex according to v5.2xx
# v1.2	  2015-04-22 - Remove unused modules
# v1.1	  2015-04-21 - Change mogrify to gs for image formats
#		     - Create output file
#                    - Rewrite source code and fix regex
#                    - Add more image format
#	 	     - Change date to iso format
# v1.0 	  2013-12-01 - First public release

#------------------------------ Values --------------------------------#
my $prefix    = 'fig';
my $skiptag   = 'noltximg';
my $extrtag   = 'ltximg';
my $imageDir  = "images";       # dir for images (images default)
my $myverb    = "myverb";      	# \myverb verbatim inline
my $margins   = "0";            # margins for pdfcrop
my $DPI       = "150";          # value for ppm, png, jpg
my $force     = 0;      	# force mode for pstriks/tikz settings
my $latex     = 0;             	# 1->create all images using latex
my $xetex     = 0;              # 1->create all images using xelatex
my $luatex    = 0;              # 1->create all images using lualatex
my $noprew    = 0;              # 1->dont use preview packpage
my $srcenv    = 0;		# 1->create src code for environments
my $subenv    = 0;              # 1->create sub document for environments
my @extr_env_tmp;              	# 1->extract environments
my @skip_env_tmp;              	# 1->skip some environment
my @verb_env_tmp;              	# 1->verbatim environment
my @verw_env_tmp;               # 1->verbatim write environment
my @delt_env_tmp;              	# 1->delete some environment
my $clean     = 1;              # 1->clean pst and <tags> in output file
my $pdf       = 1;		# 1->create a PDF image file
my $run       = 1;		# 1->create a image file
my $png       = 0;              # 1->create .png using Ghoscript
my $jpg       = 0;              # 1->create .jpg using Ghoscript
my $eps       = 0;              # 1->create .eps using pdftops
my $svg       = 0;		# 1->create .svg using pdf2svg
my $ppm       = 0;             	# 1->create .ppm using pdftoppm
my $all       = 0;	       	# 1->create all images type
my $crop      = 1;		# 1->create a image file
my $gray      = 0;		# 1->create a gray scale images
my $output;		        # set output name for outfile
my $outfile   = 0;	       	# 1->write output file
my $outsrc    = 0;	       	# 1->enable write src env files

#----------------------------- Search GS ------------------------------#
# The next code it's part of pdfcrop adapted from TexLive 2014
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

### call GS
find_ghostscript();

if ($Win and $::opt_gscmd =~ /\s/) {
    $::opt_gscmd = "\"$::opt_gscmd\"";
}

### option and bolean value
my @bool = ("false", "true");
$::opt_debug      = 0;
$::opt_verbose    = 0;

#----------------- Program identification, options and help -----------#

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
Usage: 	ltximg [options] <file>.<ext>
	ltximg --latex  [options] <file>.<ext>
	ltximg --xetex  [options] <file>.<ext>
	ltximg --luatex [options] <file>.<ext>
LTXimg extract and convert all related environments from (La)TeX file
  into single images files (pdf/png/eps/jpg/svg) using Ghostscript.
  By default search and extract environments using (pdf)LaTeX.

Environments default suports by LTXimg:

	pspicture tikzpicture pgfpicture psgraph postscript

Options:

  -h,--help          	- display this help and exit
  -l,--license       	- display license and exit
  -v,--version 	     	- display version (current $nv) and exit
  -d,--dpi = <int>     	- the dots per inch for images (default $DPI)
  -j,--jpg           	- create .jpg files (need Ghostscript) [$::opt_gscmd]
  -p,--png           	- create .png files (need Ghostscript) [$::opt_gscmd]
  -e,--eps	     	- create .eps files (need pdftops)
  -s,--svg	     	- create .svg files (need pdf2svg)
  -P,--ppm	     	- create .ppm files (need pdftoppm)
  -a,--all	     	- create .(pdf,eps,jpg,png) images
  -g,--gray            	- create a gray scale images (default off)
  -f,--force            - try to capture psset/tikz to extract (default off)
  -n,--noprew    	- create images files whitout preview package (default off)
  -o,--output = <name>  - create a outfile.tex whitout PGF|TiKZ|PST code
  -m,--margin = <int> 	- margins in bp for pdfcrop (default 0)
  --srcenv   	     	- create separate files whit only code environment
  --subenv 	     	- create sub files whit preamble and code environment
  --xetex            	- using (Xe)LaTeX compiler for create images
  --latex            	- using LaTeX compiler for create images
  --luatex           	- using (Lua)LaTeX compiler for create images
  --norun            	- run script, but no create images (default off)
  --nopdf            	- don't create a PDF image files (default off)
  --nocrop            	- run sdfsdfdsfs (default off)
  --noclean            	- don't remove clean tag and pst packpages(default: off)
  --extrenv = <string>  - search other environment to extract (default: empty)
  --skipenv = <string>  - skip default environment to extract (default: empty)
  --verbenv = <string>  - add new verbatim environment (default: empty)
  --writenv = <string>  - add new verbatim write environment (default: empty)
  --deltenv = <string>  - delete environment in output file (default: empty)
  --myverb  = <string>	- search verbatim in line (default: \myverb)
  --skipenv = <string>  - skip verbatim environment (default:  empty)
  --imgdir  = <string>  - the folder for images (default: images)
  --verbose       	- verbose printing  (default [$bool[$::opt_verbose]])
  --debug         	- debug information (default [$bool[$::opt_debug]])

Example:
* ltximg -e -p -j --imgdir pics -o test-out test-in.ltx
* produce test-out.tex whitout PGF|TiKZ|PST environments and create "pics"
* dir whit all images (pdf,eps,png,jpg) and source (.ltx) for all related
* parts using (pdf)LaTeX whit preview package and cleaning all tmp files.
* Suport bundling for short options: ltximg -epjco --imgdir=pics test.ltx
* Use texdoc ltximg for full documentation.
END_OF_USAGE

### error
sub errorUsage { die "@_ (try ltximg --help for more information)\n"; }

### Getopt::Long
my $result=GetOptions (
# short and long options
    'h|help'       	=> \$::opt_help, # $::opt_help
    'v|version'       	=> \$::opt_version, # $::opt_version
    'l|license'       	=> \$::opt_license, # $::opt_license
    'd|dpi=i'    	=> \$DPI,# numeric
    'm|margin=i'        => \$margins,# numeric
    'e|eps'      	=> \$eps, # pdftops
    'j|jpg'      	=> \$jpg, # gs
    'p|png'      	=> \$png, # gs
    'P|ppm'      	=> \$ppm, # pdftoppm
    's|svg'      	=> \$svg, # pdf2svg
    'a|all'      	=> \$all, # all
    'g|gray'      	=> \$gray,# gray (bolean)
    'f|force'      	=> \$force,# force (bolean value)
    'n|noprew'      	=> \$noprew, # no preview (bolean)
    'o|output=s{1}'     => \$output, # output file name (string)
# bolean options
    'subenv'	   	=> \$subenv, # subfile environments (bolean)
    'srcenv'	   	=> \$srcenv, # source files (bolean)
    'xetex'	    	=> \$xetex,  # xelatex compiler
    'latex'      	=> \$latex,  # latex compiler
    'luatex'     	=> \$luatex, # lualatex compiler
# string options from command line
    'extrenv=s{1,9}'	=> \@extr_env_tmp, # extract environments
    'skipenv=s{1,9}'	=> \@skip_env_tmp, # skip environment
    'verbenv=s{1,9}'	=> \@verb_env_tmp, # verbatim environment
    'writenv=s{1,9}'	=> \@verw_env_tmp, # verbatim write environment
    'deltenv=s{1,9}'	=> \@delt_env_tmp, # delete environment
# string options
    'imgdir=s{1}'	=> \$imageDir, # images dir
    'myverb=s{1}'	=> \$myverb, # \myverb inline (string)
    'prefix=s{1}' 	=> \$prefix, # prefix
# negated options
    'crop!'		=> \$crop,# run pdfcrop
    'pdf!'		=> \$pdf, # pdf image format
    'clean!'		=> \$clean,# clean  output file
    'run!'		=> \$run,# run compiler
    "debug!",
    "verbose!",
    ) or die $usage;

#-------------------- Options for command line ------------------------#

### Help
if ($::opt_help) {
    print $usage;
    exit(0);
}

### Version
if ($::opt_version) {
    print $title;
    exit(0);
}

### Licence
if ($::opt_license) {
    print $licensetxt;
    exit(0);
}

### Set values for verbose, debug, source options and tmp
my $tmp = "tmp-\L$program\E-$$"; # tmp for name-fig-tmp
$::opt_verbose = 1 if $::opt_debug;

### source and subfile option
if ($srcenv && $subenv) {
  die errorUsage "srcenv and subenv options are mutually exclusive";
}

#---------------------- Check the input arguments ---------------------#
@ARGV > 0 or errorUsage "Input filename missing";
@ARGV < 2 or errorUsage "Unknown option or too many input files";

#-------------------- Check inputfile extention -----------------------#
my @SuffixList = ('.tex', '', '.ltx');    # posibles
my ($name, $path, $ext) = fileparse($ARGV[0], @SuffixList);
$ext = '.tex' if not $ext;


#------------------- Read input file in memory (slurp) ----------------#
open my $INPUTfile, '<', "$name$ext";
my $archivo;
{
    local $/;
    $archivo = <$INPUTfile>;
}
close $INPUTfile;

#--------- Arrangements required in the input file to extract ---------#
### uniq funtion
sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

### minus funtion
sub array_minus(\@\@) {
	my %e = map{ $_ => undef } @{$_[1]};
	return grep( ! exists( $e{$_} ), @{$_[0]} );
}

### Default environment to extract
my @extr_tmp  = qw (
    postscript tikzpicture pgfpicture pspicture psgraph
    );

push(@extr_env_tmp,@extr_tmp);

### Default verbatim environment

my @verb_tmp  = qw (
    Example CenterExample SideBySideExample PCenterExample PSideBySideExample 
    verbatim Verbatim BVerbatim LVerbatim SaveVerbatim PSTexample PSTcode 
    LTXexample tcblisting spverbatim minted listing lstlisting
    alltt comment chklisting verbatimtab listingcont boxedverbatim
    demo sourcecode xcomment pygmented pyglist program programl
    programL programs programf programsc programt
    );

push(@verb_env_tmp,@verb_tmp);

### Default verbatim write skip environment
my @verbw_tmp = qw (
    filecontents tcboutputlisting tcbexternal extcolorbox
    extikzpicture VerbatimOut verbatimwrite
    );
    
push(@verw_env_tmp,@verbw_tmp);

### Rules to capture in regex
my $braces      = qr/ (?:\{)(.+?)(?:\})  	/msx;
my $braquet     = qr/ (?:\[)(.+?)(?:\])  	/msx;
my $no_corchete = qr/ (?:\[ .+? \])?		/msx;

### New verbatim environments defined in input file
my @new_verb = qw (
    newtcblisting DeclareTCBListing ProvideTCBListing NewTCBListing
    lstnewenvironment NewListingEnvironment NewProgram specialcomment
    includecomment DefineVerbatimEnvironment newverbatim newtabverbatim
    );

### Regex to capture names for new verbatim environments in input file
my $newverbenv = join "|", map quotemeta, sort { length $a <=> length $b } @new_verb;
$newverbenv = qr/\b(?:$newverbenv) $no_corchete $braces/msx;

### New verbatim write environments defined in input file
my @new_verb_write = qw (
    renewtcbexternalizetcolorbox
    renewtcbexternalizeenvironment
    newtcbexternalizeenvironment
    newtcbexternalizetcolorbox
       );

### Regex to capture names for new verbatim write environments in input file
my $newverbwrt = join "|", map quotemeta, sort { length $a <=> length $b } @new_verb_write;
$newverbwrt = qr/\b(?:$newverbwrt) $no_corchete $braces/msx;

### Regex to capture MINTED related environments
my $mintdenv   = qr/\\ newminted $braces (?:\{.+?\})		/x;
my $mintcenv   = qr/\\ newminted $braquet (?:\{.+?\}) 		/x;
my $mintdshrt  = qr/\\ newmint $braces (?:\{.+?\}) 		/x;
my $mintcshrt  = qr/\\ newmint $braquet (?:\{.+?\}) 		/x;
my $mintdline  = qr/\\ newmintinline $braces (?:\{.+?\}) 	/x;
my $mintcline  = qr/\\ newmintinline $braquet (?:\{.+?\}) 	/x;

### Pass input file to @array and remove % and coments
my @verbinput = $archivo;
s/%.*\n//mg foreach @verbinput; # del comments
s/^\s*|\s*//mg foreach @verbinput; # del white space
my $verbinput = join '', @verbinput;

### Capture names in input file using regex and save in @array
my @newv_write = $verbinput =~ m/$newverbwrt/xg;# \newverbatim write environments in input file (for)

### Add @newv_write defined in input file to @verw_env_tmp
push(@verw_env_tmp,@newv_write);

my @mint_denv  = $verbinput =~ m/$mintdenv/xg;  # \newminted{$mintdenv}{options} (for)
my @mint_cenv  = $verbinput =~ m/$mintcenv/xg;  # \newminted[$mintcenv]{lang} (for)
my @mint_dshrt = $verbinput =~ m/$mintdshrt/xg; # \newmint{$mintdshrt}{options} (while)
my @mint_cshrt = $verbinput =~ m/$mintcshrt/xg; # \newmint[$mintcshrt]{lang}{options} (while)
my @mint_dline = $verbinput =~ m/$mintdline/xg; # \newmintinline{$mintdline}{options} (while)
my @mint_cline = $verbinput =~ m/$mintcline/xg; # \newmintinline[$mintcline]{lang}{options} (while)
my @verb_input = $verbinput =~ m/$newverbenv/xg;# \newverbatim environments in input file (for)

### Add new verbatim environment defined in input file to @vrbenv
push(@verb_env_tmp,@mint_denv,@mint_cenv,@verb_input);

### Append "code" (minted)
if (!@mint_denv == 0){
$mintdenv   = join "\n", map { qq/$_\Qcode\E/ } @mint_denv;
@mint_denv  = split /\n/, $mintdenv;
}

### Append "inline" (minted)
if (!@mint_dline == 0){
$mintdline  = join "\n", map { qq/$_\Qinline\E/ } @mint_dline;
@mint_dline = split /\n/, $mintdline;
}

### Join all minted inline/short in @array
my @mintline;
my @mint_tmp  = qw ( mint  mintinline );
push(@mintline,@mint_dline,@mint_cline,@mint_dshrt,@mint_cshrt,@mint_tmp);
@mintline = uniq(@mintline);

### Create a regex using @mintline
my $mintline = join "|", map quotemeta, sort { length $a <=> length $b } @mintline;
$mintline   = qr/\b(?:$mintline)/x;

#----------------- Options from input file ----------------------------#
# % ltximg : extrenv : {extrenv1, extrenv2, ... , extrenvn}
# % ltximg : skipenv : {skipenv1, skipenv2, ... , skipenvn}
# % ltximg : verbenv : {verbwrt1, verbwrt2, ... , verbwrtn}
# % ltximg : writenv : {verbwrt1, verbwrt2, ... , verbwrtn}
# % ltximg : deltenv : {deltenv1, deltenv2, ... , deltenvn} 
# % ltximg : options : {opt1=arg, opt2=arg, ... , bolean..} 

# gramática
my $rx_myscrypt = qr/
    ^ %+ \s* ltximg (?&SEPARADOR) (?<clave>(?&CLAVE)) (?&SEPARADOR) \{ (?<argumentos>(?&ARGUMENTOS)) \}
    (?(DEFINE)
	(?<CLAVE>      \w+       )
	(?<ARGUMENTOS> .+?       )
	(?<SEPARADOR>  \s* : \s* )
    )
/mx;

# Dividir
my($optin, $documento) = $archivo =~ m/\A \s* (.+?) \s* (\\documentclass.*)\z/msx;

# Procesar
my %resultado;

while ($optin =~ /$rx_myscrypt/g) {
    my($clave, $argumentos) = @+{qw(clave argumentos)};
    my @argumentos = split /\s*,\s*?/, $argumentos;
    for (@argumentos) {
    	s/^ \s* | \s* $//gx;
    }
    if ($clave eq 'options') {
    	for my $argumento (@argumentos) {
    	    if ($argumento =~ /(?<key>\S+) \s* = \s* (?<valor>\S+)/x) {
    	    	$resultado{$clave}{$+{'key'}} = $+{'valor'};
	    }
	    else {
	    	$resultado{$clave}{$argumento} = 1; 
			}
		}
    }
    else {
	push @{ $resultado{ $clave } }, @argumentos;
    }
} # close while

# Delete <*remove> ... </remove> from input file
$optin  =~s/^\%<\*remove>\s*(.+?)\s*\%<\/remove>(?:[\t ]*(?:\r?\n|\r))+//gmsx;

### Set some options from input file
if (exists $resultado{extract} ) { # extract
    push @extr_env_tmp, @{ $resultado{extract} };
}
if (exists $resultado{skipenv} ) { # skipenv
    push @skip_env_tmp, @{ $resultado{skipenv} };
}
if (exists $resultado{verbenv} ) { # verbenv
    push @verb_env_tmp, @{ $resultado{verbenv} };
}
if (exists $resultado{writenv} ) { # writenv
    push @verw_env_tmp, @{ $resultado{writenv} };
}
if (exists $resultado{deltenv} ) { # deltenv
    push @delt_env_tmp, @{ $resultado{deltenv} };
}
if (exists $resultado{options}{myverb}){ # myverb | code |
    $myverb = $resultado{options}{myverb};
    }
#--------------- Create @array to all type of environments-------------#

### @env_all_tmp contain all environments
my @env_all_tmp;
push(@env_all_tmp,@extr_env_tmp,@skip_env_tmp,@verb_env_tmp,@verw_env_tmp,@delt_env_tmp);
@env_all_tmp  = uniq(@env_all_tmp);

### @no_env_all_tmp contain all No extracted environments
my @no_env_all_tmp;
push(@no_env_all_tmp,@skip_env_tmp,@verb_env_tmp,@verw_env_tmp,@delt_env_tmp);
@no_env_all_tmp = uniq(@no_env_all_tmp);

#### The operation return @extract environment 
my @extract = array_minus(@env_all_tmp,@no_env_all_tmp);
@extract = uniq(@extract);

#### The operation return @no_extract
my @no_extract = array_minus(@env_all_tmp,@extract);
my @no_skip;
push(@no_skip,@verb_env_tmp,@verw_env_tmp,@delt_env_tmp);
my @skipped = array_minus(@no_extract,@no_skip);
@skipped = uniq(@skipped);

#### The operation return @delte_env environment
my @no_ext_skip = array_minus(@no_extract,@skipped);
my @no_del;
push(@no_del,@verb_env_tmp,@verw_env_tmp);
my @delete_env = array_minus(@no_ext_skip,@no_del);
@delete_env    = uniq(@delete_env);

#### The operation return @verbatim environment
my @no_ext_skip_del = array_minus(@no_ext_skip,@delete_env);
my @verbatim = array_minus(@no_ext_skip_del,@verw_env_tmp);

#### The operation return @verbatim write environment
my @verbatim_w = array_minus(@no_ext_skip_del,@verbatim);

#### Definimos @env_all para crear un hash y hacer los reemplazo en while
my @no_verb_env;
push(@no_verb_env,@extract,@skipped,@delete_env,@verbatim_w);
my @no_verw_env;
push(@no_verw_env,@extract,@skipped,@delete_env,@verbatim);

#-------------------- Changues in input/output file -------------------#

### Reserved words in verbatim inline (while)
my %changes_in = (
# ltximg tags
    '%<*ltximg>'        => 	'%<*LTXIMG>',
    '%</ltximg>'	=> 	'%</LTXIMG>',
    '%<*noltximg>'    	=> 	'%<*NOLTXIMG>',
    '%</noltximg>'      => 	'%</NOLTXIMG>',
    '%<*clean>'    	=> 	'%<*CLEAN>',
    '%</clean>'      	=> 	'%</CLEAN>',
    '%<*remove>'    	=> 	'%<*REMOVE>',
    '%</remove>'	=> 	'%</REMOVE>',
    '%<*ltximgverw>'    => 	'%<*LTXIMGVERW>',
    '%</ltximgverw>'	=> 	'%</LTXIMGVERW>',
# pst/tikz set
    '\psset'            => 	'\PSSET',
    '\tikzset'		=> 	'\TIKZSET',
# pspicture
    '\pspicture'        => 	'\TRICKS',
    '\endpspicture'     => 	'\ENDTRICKS',
# pgfpicture
    '\pgfpicture'       => 	'\PGFTRICKS',
    '\endpgfpicture'    => 	'\ENDPGFTRICKS',
# tikzpicture
    '\tikzpicture'      => 	'\TKZTRICKS',
    '\endtikzpicture'   => 	'\ENDTKZTRICKS',
# psgraph
    '\psgraph'        	=> 	'\PSGRAPHTRICKS',
    '\endpsgraph'     	=> 	'\ENDPSGRAPHTRICKS',
# some reserved 
    '\usepackage'	=>	'\USEPACKAGE',
    '{graphicx}'	=>	'{GRAPHICX}',
    '\graphicspath{'	=>	'\GRAPHICSPATH{',
    );

### Changues for \begin... \end inline verbatim
my %init_end = (
# begin{ and end{
    '\begin{'           => 	'\BEGIN{',
    '\end{'             => 	'\END{',
    );

### Changues for \begin{document} ... \end{document}
my %document = (
# begin/end document for split
    '\begin{document}'	=> 	'\BEGIN{document}',
    '\end{document}'    => 	'\END{document}',
    );

### Reverse for extract and output file
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
# pgfpicture
    '\PGFTRICKS'        => 	'\pgfpicture',
    '\ENDPGFTRICKS'     => 	'\endpgfpicture',
# tikzpicture
    '\TKZTRICKS'        => 	'\tikzpicture',
    '\ENDTKZTRICKS'     => 	'\endtikzpicture',
# psgraph
    '\PSGRAPHTRICKS'    => 	'\psgraph',
    '\ENDPSGRAPHTRICKS' => 	'\endpsgraph',
# some reserved 
    '\USEPACKAGE'	=>	'\usepackage',
    '{GRAPHICX}'	=>	'{graphicx}',
    '\GRAPHICSPATH{'	=>	'\graphicspath{',
# begin{ and end{
    '\BEGIN{'           => 	'\begin{',
    '\END{'             => 	'\end{',
    );

### Reverse tags, need back in all file to extract
my %reverse_tag = (
# ltximg tags
    '%<*LTXIMG>'      	=> 	'%<*ltximg>',
    '%</LTXIMG>'        => 	'%</ltximg>',
    '%<*NOLTXIMG>'      => 	'%<*noltximg>',
    '%</NOLTXIMG>'      => 	'%</noltximg>',
    '%<*CLEAN>'      	=> 	'%<*clean>',
    '%</CLEAN>'      	=> 	'%</clean>',
    '%<*REMOVE>'    	=> 	'%<*remove>',
    '%</REMOVE>'    	=> 	'%</remove>',
    '%<*LTXIMGVERW>'    => 	'%<*ltximgverw>',
    '%</LTXIMGVERW>'    => 	'%</ltximgverw>',
    );

#---------------- Create a hash \begin{env} ... \end{env} --------------------#

# subrun to create hash
sub crearhash{
    my %cambios;

    for my $aentra(@_){
	for my $initend (qw(begin end)) {
		$cambios{"\\$initend\{$aentra"} = "\\\U$initend\E\{$aentra";
			}
		}
    return %cambios;
}

my %extract_env = crearhash(@extract);
my %skiped_env = crearhash(@skipped);
my %verb_env = crearhash(@verbatim);
my %verbw_env = crearhash(@verbatim_w);
my %delete_env = crearhash(@delete_env);
my %change_verbw_env = crearhash(@no_verw_env);
my %change_verb_env  = crearhash(@no_verb_env);

### Cambios a realizar
my %cambios = (%changes_in,%init_end);

### Variables y constantes
my $no_del = "\0";
my $del    = $no_del;

### Rules
my $llaves      = qr/\{ .+? \}                                                          /x;
my $no_llaves   = qr/(?: $llaves )?                                                     /x;
my $corchetes   = qr/\[ .+? \]                                                          /x;
my $no_corchete = qr/(?: $corchetes )?                                                  /x;
my $anidado     = qr/(\{(?:[^\{\}]++|(?1))*\})						/x;
my $delimitador = qr/\{ (?<del>.+?) \}                                                  /x;
my $verb        = qr/(?:((spv|(?:q|f)?v|V)erb)[*]?)                          		/ix;
my $lst         = qr/(?:(lst|pyg)inline)(?!\*) $no_corchete                   		/ix;
my $mint        = qr/(?: $mintline |SaveVerb) (?!\*) $no_corchete $no_llaves $llaves    /ix;
my $no_mint     = qr/(?: $mintline) (?!\*) $no_corchete 				/ix;
my $marca       = qr/\\ (?:$verb | $lst | $mint |$no_mint) (?:\s*)? (\S) .+? \g{-1}     /x;
my $comentario  = qr/^ \s* \%+ .+? $                                                    /mx;
my $definedel   = qr/\\ (?: DefineShortVerb | lstMakeShortInline| MakeSpecialShortVerb ) [*]? $no_corchete $delimitador	/ix;
my $indefinedel = qr/\\ (?: (Undefine|Delete)ShortVerb | lstDeleteShortInline) $llaves  /ix;

### Cambiar
while ($documento =~
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

        substr $documento, $pos_inicial, $pos_final-$pos_inicial, $encontrado;    # insertamos los nuevos cambios

        pos($documento) = $pos_inicial + length $encontrado;                      # re posicionamos la siguiente búsqueda
    }
}

### Nested {...}
my $mintd_ani   = qr/\\ (?:$mintline|pygment) (?!\*) $no_corchete $no_llaves  /x;
my $tcbxverb    = qr/\\ (?: tcboxverb [*]?|$myverb [*]?)  $no_corchete        /x;
my $tcbxmint    = qr/(?:$tcbxverb|$mintd_ani) (?:\s*)? $anidado	       	      /x;

### Changue {...} verbatim
while ($documento =~ /$tcbxmint/pgmx) {

        my($pos_inicial, $pos_final) = ($-[0], $+[0]);                          # posiciones
        my $encontrado = ${^MATCH};                                             # lo encontrado
	while (my($busco, $cambio) = each %cambios) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;                              # es necesario escapar $busco
        }
         substr $documento, $pos_inicial, $pos_final-$pos_inicial, $encontrado;    # insertamos los nuevos cambios
    pos($documento)= $pos_inicial + length $encontrado;                       # re posicionamos la siguiente búsqueda
}

#---------------------- Back changues in input file -------------------#

### Ahora volvemos los <*tags> a la normalidad dentro del archivo
my $ltxtags = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %reverse_tag;
$documento =~ s/^($ltxtags)/$reverse_tag{$1}/gmsx;

### Definimos Verbatim
my $verbatim = join "|", map quotemeta, sort { length $a <=> length $b } @verbatim;
$verbatim = qr/$verbatim/x;

### Definimos Verbatim write
my $verbatim_w = join "|", map quotemeta, sort { length $a <=> length $b } @verbatim_w;
$verbatim_w = qr/$verbatim_w/x;

### Defined Skip (sorted)
my $skipenv = join "|", map quotemeta, sort { length $a <=> length $b } @skipped;
$skipenv   = qr/$skipenv/x;

### Defined environments to extract
my $environ = join "|", map quotemeta, sort { length $a <=> length $b } @extract;
$environ = qr/$environ/x;

### Defined environments to delete
my $delenv = join "|", map quotemeta, sort { length $a <=> length $b } @delt_env_tmp;
$delenv = qr/$delenv/x;

### Split by lines input file
my @lineas = split /\n/, $documento;

#------------------ Change betwen $verbatim and $verbatim_w -----------#

### hash and Regex
my %replace = (%change_verb_env,%changes_in,%document);
my $find = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %replace;

my $DEL;
for (@lineas) {
    if (/\\begin\{($verbatim\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
	s/($find)/$replace{$1}/g;
	}
    if (/\\begin\{($verbatim_w\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
    my %replace = (%change_verbw_env,%changes_in,%document);
    my $find = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %replace;
	s/($find)/$replace{$1}/g;
	}
} # close for

### Join lines
$documento = join("\n", @lineas);

### Split input file
my($cabeza,$cuerpo,$final) = $documento =~ m/\A (.+?) (\\begin\{document\} .+?)(\\end\{document\}.*)\z/msx;

#-------------------- Necesari Regex for input file -------------------#
### Regex recursiva for delete environment
my $delt_env = qr /
		(
		    (?:
		        \\begin\{$delenv\*?\}
		      (?:
		        (?>[^\\]+)|
		        \\
		        (?!begin\{$delenv\*?\})
		        (?!end\{$delenv\*?\})|
		        (?-1)
		      )*
		      \\end\{$delenv\*?\}
		    )
		)
		/x;
		
### Regex recursiva for verbatim write
my $verb_wrt = qr /
		(
		    (?:
		        \\begin\{$verbatim_w\*?\}
		      (?:
		        (?>[^\\]+)|
		        \\
		        (?!begin\{$verbatim_w\*?\})
		        (?!end\{$verbatim_w\*?\})|
		        (?-1)
		      )*
		      \\end\{$verbatim_w\*?\}
		    )
		)
		/x;

### Pass $verb_wrt to %<*ltximgverw> ... %</ltximgverw>
$cuerpo =~ s/($verb_wrt)/\%<\*ltximgverw>\n$1\n\%<\/ltximgverw>/gmsx;

### Regex recursiva para skip, skip debe estar en el tope de los entornos
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

### Pass %<*noltximg> ... %</noltximg> to \begin{nopreview} ... \end{nopreview}
$cuerpo =~ s/^\%<\*$skiptag>(.+?)\%<\/$skiptag>/\\begin\{nopreview\}$1\\end\{nopreview\}/gmsx;

### Pass $skip_env to \begin{nopreview} .+? \end{nopreview}
$cuerpo =~ s/
	    \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
	    \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
	($skip_env)/\\begin\{nopreview\}\n$1\n\\end\{nopreview\}\n/gmsx;

### Regex to extract environments
my $extr_env = qr /
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

#-------------- Convert plain TeX to LaTeX environment syntax ---------#
### hash anónimo
my %special =  map { $_ => 1 } @extract;

### pspicture
if(exists($special{pspicture})){
    $cuerpo =~ s/
    \\pspicture(\*)?(.+?)\\endpspicture/\\begin{pspicture$1}$2\\end{pspicture$1}/gmsx;
    }
    
### psgraph

if(exists($special{psgraph})){
    $cuerpo =~ s/
    \\psgraph(\*)?(.+?)\\endpsgraph/\\begin{psgraph$1}$2\\end{psgraph$1}/gmsx;
    }
    
### tikzpicture
if(exists($special{tikzpicture})){
    $cuerpo =~ s/
    \\tikzpicture(.+?)\\endtikzpicture/\\begin{tikzpicture}$1\\end{tikzpicture}/gmsx;
    }
    
### pgfpicture
if(exists($special{pgfpicture})){
    $cuerpo =~ s/
    \\pgfpicture(.+?)\\endpgfpicture/\\begin{pgfpicture}$1\\end{pgfpicture}/gmsx;
    }

### Pass %<*ltximg> (.+?) %</ltximg> to \begin{preview} (.+?) \end{preview}
$cuerpo =~ s/^\%<\*$extrtag>(.+?)\%<\/$extrtag>/\\begin\{preview\}$1\\end\{preview\}/gmsx;

#----------------- FORCE mode for pstriks/psgraph/tikzpiture ----------#
$force  = 1 if exists $resultado{options}{force}; # from input file
if ($force) {
# pspicture or psgraph found
if(exists($special{pspicture}) or exists($special{psgraph}))
{
$cuerpo =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
	    \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
	    \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
	    \\begin\{postcript\}.+?\\end\{postcript\}(*SKIP)(*F)|
        (?<code>
        (?:\\psset\{(?:\{.*?\}|[^\{])*\}.+?)?  # si está lo guardo
        \\begin\{(?<env> pspicture\*?| psgraph)\} .+? \\end\{\k<env>\}
	)
    /\\begin\{preview\}\n$+{code}\n\\end\{preview\}/gmsx;
}
# tikzpicture found
if(exists($special{tikzpicture})){
$cuerpo =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
	    \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
	    \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
	    \\begin\{postcript\}.+?\\end\{postcript\}(*SKIP)(*F)|
        (?<code>
        (?:\\tikzset\{(?:\{.*?\}|[^\{])*\}.+?)?  # si está lo guardo
        \\begin\{(?<env> tikzpicture)\} .+? \\end\{\k<env>\}
	)
    /\\begin\{preview\}\n$+{code}\n\\end\{preview\}/gmsx; 
}

} # close force mode

### Pass $extr_env to \begin{preview} .+? \end{preview}
$cuerpo =~ s/	\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
		\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
		\\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
  ($extr_env)/\\begin\{preview\}\n$1\n\\end\{preview\}/gmsx;

### The extract environments need back word to original
my %replace = (%changes_out,%reverse_tag);
my $find = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %replace;

# ---------------- Change betwen \begin{...} ...\end{...} -------------#

# Split $cabeza by lines
@lineas = split /\n/, $cabeza;

### Changues in verbatim write
my $DEL;
for (@lineas) {
    if (/\\begin\{($verbatim_w\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
    	s/($find)/$replace{$1}/g;
	}
} # close for

### Join lines in $cuerpo
$cabeza = join("\n", @lineas);

# -------- Change back betwen \begin{preview} ... \end{preview} -------#
# Split $boody by lines
@lineas = split /\n/, $cuerpo;

my $DEL;
for (@lineas) {
    if (/\\begin\{(preview)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) { # rage operator
        s/($find)/$replace{$1}/g;
        }
	
    if (/\\begin\{($verbatim_w\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
    	s/($find)/$replace{$1}/g;
	}
    
} # close for

### Join lines in $cuerpo
$cuerpo = join("\n", @lineas);

my $BP 	= '\\\\begin\{preview\}';
my $EP 	= '\\\\end\{preview\}';

my @env_extract  = $cuerpo =~ m/(?<=$BP)(.+?)(?=$EP)/gms;
my $envNo = 0+ @env_extract;

### If environment extract found, the run script
print "$program $nv, $copyright" ;
if ($envNo == 0){
    die errorUsage "ltximg not found any environment to extract file $name$ext"; 
    }
else{
    say "The file $name$ext contain $envNo environment to extracted";
    }

### Set name of output file from input file 
if (exists $resultado{options}{output}){
    $output = $resultado{options}{output};
    }
### The output file name not contain - at begin
if (defined $output) {
if ($output =~ /(^\-|^\.).*?/){ 
    die errorUsage "$output it is not a valid name for the output file";
    }
### The output file name its not equal to input file name
if ($output eq "$name") { # $output = $input
    $output = "$name-out$ext";
    }
if ($output eq "$name$ext") { # $output = $input
    $output = "$name-out$ext";
    }
### Remove .ltx o .tex extension
if ($output =~ /.*?$ext/){ 
    $output =~ s/(.+?)$ext/$1/gms;
    }
} # close output string check

### If output name ok, then $outfile
$outfile = 1 and $pdf = 1 if defined($output);

#----------------Set option from input file ---------------------------#
$run    = 0 if exists $resultado{options}{norun};
$pdf    = 0 if exists $resultado{options}{nopdf};
$clean  = 0 if exists $resultado{options}{noclean};
$crop   = 0 if exists $resultado{options}{nocrop};
$noprew = 1 if exists $resultado{options}{noprew};
$force  = 1 if exists $resultado{options}{force};
$xetex  = 1 if exists $resultado{options}{xetex};
$latex  = 1 if exists $resultado{options}{latex};
$luatex = 1 if exists $resultado{options}{luatex};
$srcenv = 1 if exists $resultado{options}{srcenv};
$subenv = 1 if exists $resultado{options}{subenv};

### if srcenv or subenv option are OK then execute 
$outsrc = 1 and $subenv= 0 if $srcenv ;
$outsrc = 1 and $srcenv= 0 if $subenv ;

### Set imgdir name from input file
if (exists $resultado{options}{imgdir}){
    $imageDir = $resultado{options}{imgdir};
    }

### Set prefix name from input file
if (exists $resultado{options}{prefix}){
    $prefix = $resultado{options}{prefix};
    }

### Set pdfcrop margins from input file
if (exists $resultado{options}{margins}){
    $margins = $resultado{options}{margins};
    }

### Set DPI resolution for images defined in input file
if (exists $resultado{options}{dpi}){
    $DPI = $resultado{options}{dpi};
    }

### Create the directory for images
-e $imageDir or mkdir($imageDir,0744) or die "Can't create $imageDir: $!\n";

### options for page numering for $crop
my $opt_page = $crop ? "\\pagestyle\{empty\}\n\\begin\{document\}"
              :        "\\begin\{document\}"
              ;

### preamble options for subfiles
my $sub_prea = $clean? "$cabeza$opt_page"
              :        "$optin\n$cabeza$opt_page"
              ;

### Extract source $outsrc
if ($outsrc) {
my $src_name = "$name-$prefix-";
my $srcNo    = 1;

### Source file whitout preamble
if ($srcenv) {
print "Creating a $envNo separate files whit source code for all environments\n";
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
if ($subenv) {
print "Creating a $envNo separate files whit source code and preamble for all environments\n";
while ($cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms) { # search $cuerpo
open my $OUTsub, '>', "$imageDir/$src_name$srcNo$ext";
print $OUTsub <<"EOC";
$sub_prea$+{'env_src'}\\end\{document\}
EOC
close $OUTsub;
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
if ($noprew) {

my @env_extract;

while ( $cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms ) { # search $cuerpo
    push @env_extract, $+{env_src}."\n\\newpage\n";
}
open my $OUTfig, '>', "$name-$prefix-$tmp$ext";
print $OUTfig "$cabeza"."$opt_page"."@env_extract\n"."\\end{document}";
close $OUTfig;
} # close $noprew

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
print   $OUTfig $preview.$cabeza."\n".$cuerpo."\n\\end{document}";
close   $OUTfig;
} # close preview

#----------- Define compilers and options for other software -----------#

### Compilers
my $compiler = $xetex ? 'xelatex'
             : $luatex ? 'lualatex'
	     : $latex ?  'latex'
             :           'pdflatex'
             ;

### Define --shell-escape for TeXLive and MikTeX
my $write18 = '-shell-escape'; # TeXLive
$write18 = '-enable-write18' if defined($ENV{"TEXSYSTEM"}) and
                          $ENV{"TEXSYSTEM"} =~ /miktex/i;

### Define --interaction=mode for compilers
my $opt_compiler = '-interaction=batchmode' ; # default
$opt_compiler = '-interaction=nonstopmode' if defined($::opt_verbose);

### Option for pdfcrop if $opt::debug
my $opt_crop = $xetex ?  "--xetex --margins $margins"
             : $luatex ? "--luatex --margins $margins"
	     : $latex ?  "--margins $margins"
             :           "--pdftex --margins $margins"
             ;

### Option for GS
my $opt_gspdf='-q -dNOSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress';
my $opt_gspng="-q -dNOSAFER -sDEVICE=pngalpha -r$DPI";
my $opt_gsjpg="-q -dNOSAFER -sDEVICE=jpeg -r$DPI -dJPEGQ=100 -dGraphicsAlphaBits=4 -dTextAlphaBits=4";
my $opt_gsgray='-q -dNOSAFER -sColorConversionStrategy=Gray -dProcessColorModel=/DeviceGray -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress';

### Message on the terminal
if($run){
    if($noprew){
    print "Creating a temporary file $name-$prefix-all.pdf whit all environments using $compiler\n";
	}
    else{
    print "Creating a temporary file $name-$prefix-all.pdf whit all environments using $compiler and preview package\n";
    }

#------------------ Compiling file whit all environments --------------#

### Compiling file $name-$prefix using pdftex/luatex/xetex in
if($opt::verbose){
    system("$compiler $write18 $opt_compiler -recorder $name-$prefix-$tmp$ext");
    }
else{
    system("$compiler $write18 $opt_compiler -recorder $name-$prefix-$tmp$ext > $null");
    }

### Compiling file using latex>dvips>ps2pdf
if($latex){
    system("dvips -q -Ppdf -o $name-$prefix-$tmp.ps $name-$prefix-$tmp.dvi");
    system("ps2pdf  -dPDFSETTINGS=/prepress $name-$prefix-$tmp.ps  $name-$prefix-$tmp.pdf");
    } # close latex

### Create a gray file
if($gray or exists $resultado{options}{gray}){
print "Convert to gray scale the file $name-$prefix-all.pdf\n";
move("$name-$prefix-$tmp.pdf", "$name-gray.pdf");
system("$::opt_gscmd $opt_gsgray -o $name-$prefix-$tmp.pdf $name-gray.pdf");
move("$name-gray.pdf", "$tempDir/$name-gray.pdf");
 } # close gray

### Crop file
if($crop or exists $resultado{options}{crop}){
print "The file $name-$prefix-all.pdf contain $envNo environment extracted, using pdfcrop whit margins $margins bp\n";
    if($::opt_verbose){
	system("pdfcrop $opt_crop $name-$prefix-$tmp.pdf $name-$prefix-$tmp.pdf");}
    else{
	system("pdfcrop $opt_crop $name-$prefix-$tmp.pdf $name-$prefix-$tmp.pdf > $null"); }
} # close $crop
else{
    print "The file $name-$prefix-all.pdf contain $envNo environment extracted\n";
}

### Fix pdftops error message in windows
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){
open my $ppmconf, '>', 'xpd';
print $ppmconf <<'EOH';
errQuiet yes
EOH
close $ppmconf;
}

#---------------------- Create image formats --------------------------#

### PDF format
if ($pdf or exists $resultado{options}{pdf}) {
for (my $pdfNo = 1; $pdfNo <= $envNo; $pdfNo++) { 
print "Create $imageDir/$name-$prefix-$pdfNo.pdf from $name-$prefix-all.pdf\r";
system("$::opt_gscmd $opt_gspdf -o $workdir/$imageDir/$name-$prefix-%1d.pdf $name-$prefix-$tmp.pdf");
    }
print "Done, PDF images files are in $imageDir\r";
}

### PNG format
if ($png or exists $resultado{options}{png}) {
for (my $pngNo = 1; $pngNo <= $envNo; $pngNo++) {
print "Create $imageDir/$name-$prefix-$pngNo.png from $name-$prefix-all.pdf\r";
system("$::opt_gscmd $opt_gspng -o $workdir/$imageDir/$name-$prefix-%1d.png $name-$prefix-$tmp.pdf");
    }
print "Done, PNG images files are in $imageDir\r";
}

### JPEG format
if ($jpg or exists $resultado{options}{jpg}) {
for (my $jpgNo = 1; $jpgNo <= $envNo; $jpgNo++) {
print "Create $imageDir/$name-$prefix-$jpgNo.jpg from $name-$prefix-all.pdf\r";
system("$::opt_gscmd $opt_gsjpg -o $workdir/$imageDir/$name-$prefix-%1d.jpg $name-$prefix-$tmp.pdf");
    }
print "Done, JPG images files are in $imageDir\r";
}

### SVG format pdf2svg
if ($svg or exists $resultado{options}{svg}) {
for (my $svgNo = 1; $svgNo <= $envNo; $svgNo++) {
print "Create $imageDir/$name-$prefix-$svgNo.svg from $name-$prefix-all.pdf\r";
system("pdf2svg $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-%1d.svg all");
    }
print "Done, SVG images files are in $imageDir\r";
}

### EPS format pdftops
if ($eps or exists $resultado{options}{eps}) {
for (my $epsNo = 1; $epsNo <= $envNo; $epsNo++) { 
print "Create $imageDir/$name-$prefix-$epsNo.eps from $name-$prefix-all.pdf\r";
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){ # windows
system("pdftops -cfg xpd -q -eps -f $epsNo -l $epsNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-$epsNo.eps");
	}
else{ # linux
system("pdftops -q -eps -f $epsNo -l $epsNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-$epsNo.eps");
	}
    } 
print "Done, EPS images files are in $imageDir\r";
} 

### PPM format pdftoppm
if ($ppm or exists $resultado{options}{ppm}) {
for (my $ppmNo = 1; $ppmNo <= $envNo; $ppmNo++) { 
print "Create $imageDir/$name-$prefix-$ppmNo.ppm from $name-$prefix-all.pdf\r";
if ($^O eq 'MSWin32' or $^O eq 'MSWin64'){ # windows
system("pdftoppm  -cfg xpd  -q -r $DPI -f $ppmNo -l $ppmNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-$ppmNo");
	}
else{ # linux
system("pdftoppm -q -r $DPI -f $ppmNo -l $ppmNo $name-$prefix-$tmp.pdf $workdir/$imageDir/$name-$prefix-$ppmNo");
	}
    } # close for
print "Done, PPM images files are in $imageDir\r";
} 

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
if ($ppm or exists $resultado{options}{ppm}) {
if (opendir(DIR,$imageDir)) {                         # open dir
    while (my $oldname = readdir DIR) {               # read and sustitute
        my $newname = $oldname =~ s/^($name-$prefix-\d+)(-\d+).ppm$/$1 . ".ppm"/re;
        if ($oldname ne $newname) {                   # validate
            rename("$imageDir/$oldname", "$imageDir/$newname"); # rename
		    }
		}
    closedir DIR;
	} # close rename ppm
}

print "Done, all images files are in $workdir/$imageDir/\n";
} # close run

#------------------------- Create a output file -----------------------#

### Outfile
if ($outfile) {

### Convert Postscript environments to includegraphics
my $grap="\\includegraphics[scale=1]{$name-$prefix-";
my $close = '}';
my $imgNo = 1; # counter for images

### Regex
$cuerpo =~ s/$BP.+?$EP/$grap@{[$imgNo++]}$close/msg; # changes

### Constantes
my $USEPACK  	= quotemeta('\usepackage');
my $GRAPHICX 	= quotemeta('{graphicx}');
my $GRAPHICPATH = quotemeta('\graphicspath{');

### Precompiled regex
my $CORCHETES = qr/\[ [^]]*? \]/x;
my $PALABRAS  = qr/\b (?: pst-\w+ | pstricks (?: -add )? | psfrag |psgo |vaucanson-g| auto-pst-pdf | graphicx )/x;
my $FAMILIA   = qr/\{ \s* $PALABRAS (?: \s* [,] \s* $PALABRAS )* \s* \}/x;

### Regex for Coment
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
		^ ($USEPACK $CORCHETES $GRAPHICX) /%$1/msxg;

### Coment \graphicspath for order and future use
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
		^ ($GRAPHICPATH) /%$1/msxg;
if($clean){
### Remove lines
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
		^ $USEPACK (?: $CORCHETES )? $FAMILIA \n//msxg;

### Delete words
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)| 
(?: ^ $USEPACK \{ | \G) [^}]*? \K (,?) \s* $PALABRAS (\s*) (,?) /$1 and $3 ? ',' : $1 ? $2 : ''/gemsx;

$cabeza =~ s/^\\usepackage\{\}(?:[\t ]*(?:\r?\n|\r))+//gmsx;
#$cabeza =~ s/^(?:[\t ]*(?:\r?\n|\r))+//gmsx;
}
### Regex to search graphics path
my $graphicspath= qr/\\ graphicspath \{	((?: $llaves )+) \}/ix;

### Cambiar
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

### Append to premble
my ($GraphicsPath) = $cabeza =~ m/($graphicspath)/msx;

$cabeza .= <<"EXTRA";

\\usepackage{graphicx}
$GraphicsPath
\\usepackage{grfext}
\\PrependGraphicsExtensions*{.pdf}
EXTRA
} # close if ($cabeza)
else{

### Append to premble
my $GraphicsPath = "\\graphicspath\{\{$imageDir/\}\}";
$cabeza .= <<"EXTRA";

\\usepackage{graphicx}
$GraphicsPath
\\usepackage{grfext}
\\PrependGraphicsExtensions*{.pdf}
EXTRA
} # close

### Clean PST content in preamble
if($clean){
    $cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
		   \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))+//gmsx;
    $cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
		\\SpecialCoor(?:[\t ]*(?:\r?\n|\r))+//gmsx;
    $cabeza =~ s/^\%<\*clean>.+?\%<\/clean>//gmsx;
    #$cabeza =~ s/^(?:[\t ]*(?:\r?\n|\r))+//gmsx;
}

### Options for out_file (add $end to outfile)
my $out_file = $clean ? "$cabeza$cuerpo\n\\end\{document\}"
              :         "$optin\n$cabeza$cuerpo\n$final"
              ;

### Clean tags in output file
if($clean){
    $out_file =~ s/^\%<\*clean>.+?\%<\/clean>(?:[\t ]*(?:\r?\n|\r))+//gmsx;
    }

### Back changues in all words in outfile
    $out_file  =~s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
		    \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
		    \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))?//gmsx;			
    $out_file  =~s/\%<\*ltximgverw>\s*(.+?)\s*\%<\/ltximgverw>/$1/gmsx;
    $out_file  =~s/^\%<\*remove>\s*(.+?)\s*\%<\/remove>(?:[\t ]*(?:\r?\n|\r))+//gmsx;
    $out_file =~ s/($delt_env)(?:[\t ]*(?:\r?\n|\r))?//gmsx;
    $out_file  =~s/($find)/$replace{$1}/g;

### Write output file
open my $OUTfile, '>', "$output$ext";
print   $OUTfile "$out_file";
close $OUTfile;

if($run){
### Define pdflatex if latex for output
$compiler = 'pdflatex' if $latex;

print "Creating the file $output$ext whitout environments using $compiler\n";

if($::opt_verbose){
	system("$compiler $write18 $opt_compiler -recorder $workdir/$output$ext");
	}
else{
	system("$compiler $write18 $opt_compiler -recorder $workdir/$output$ext > $null");
	}

    } # close outfile file
} # close run

### End of script work
if ($outfile) {
if($run){
    say "Finish, the file $output.pdf are in $workdir and put all figures in $imageDir dir";
	    }
    else{
    say "Creating the file $output$ext in $workdir/ whitout environments"; }
}  # close $outfile
else{
    say "Finish, all figures are in $workdir/$imageDir dir";
    }

### Copy the file whit all source to image dir
if ($srcenv or $subenv) {
copy("$workdir/$name-$prefix-$tmp$ext", "$imageDir/$name-$prefix-all$ext");
}

#---------------------- Clean temporary files -------------------------#
if($run){

my @protected = qw();
push (@protected,"$output$ext","$output.pdf") if defined $output;

my $flsline = "OUTPUT";
my @flsfile = "$name-$prefix-$tmp.fls";
push(@flsfile,"$output.fls") if defined $output;

my @tmpfiles;
for my $filename(@flsfile){
    open my $RECtmp, '<', "$filename";
    push @tmpfiles, grep /\Q$flsline/,<$RECtmp>;
    close $RECtmp;
}

@tmpfiles = grep { s/$flsline\s+//mg } @tmpfiles;
@tmpfiles = grep { s/^\s*|\s*//mg } @tmpfiles;


if($latex){
push (@tmpfiles,"$name-$prefix-$tmp.ps");
}
push (@tmpfiles,@flsfile,"$name-$prefix-$tmp$ext","$name-$prefix-$tmp.pdf");

my @delfiles = array_minus(@tmpfiles, @protected);

foreach my $tmpfile (@delfiles)
{
   move("$tmpfile", "$tempDir");
}
}
__END__
