#!/usr/bin/env perl
use v5.20;
use File::Basename;
use Getopt::Long qw(:config bundling_values require_order no_ignore_case);
use File::Temp qw(tempdir);
use File::Copy;
use Config;
use File::Spec::Functions qw(catfile devnull);
use File::Find;
use Cwd;
use autodie;
use Data::Dumper; # comment after test

### Directory for work and tmp files
my $tempDir   = tempdir( CLEANUP => 1);
my $tempSys   = dirname($tempDir);
my $workdir   = cwd;
my $null      = devnull();

### Program identification
my $program   = "LTXimg";
my $nv='1.5';
my $copyright = <<END_COPYRIGHT ;
2017-11-27 (c) 2013-2017 by Pablo Gonzalez, pablgonz<at>yahoo.com
END_COPYRIGHT

### Default values
my $prefix    = 'fig';
my $skiptag   = 'noltximg';
my $extrtag   = 'ltximg';
my $imageDir  = "images";       # dir for images 
my $myverb    = "myverb";       # \myverb verbatim inline
my $margins   = "0";            # margins for pdfcrop
my $DPI       = "150";          # value for ppm, png, jpg
my $arara     = 0;              # use arara to compiler files
my $force     = 0;              # force mode for pstriks/tikz settings
my $latex     = 0;              # create all images using latex
my $dvips     = 0;              # create output using dvips>ps2pdf
my $dvipdf    = 0;              # create all images using dvipdfmx
my $xetex     = 0;              # create all images using xelatex
my $luatex    = 0;              # create all images using lualatex
my $noprew    = 0;              # don't use preview packpage
my $srcenv    = 0;              # create src code for environments
my $subenv    = 0;              # create sub document for environments
my @extr_env_tmp;               # extract environments
my @skip_env_tmp;               # skip some environment
my @verb_env_tmp;               # verbatim environment
my @verw_env_tmp;               # verbatim write environment
my @delt_env_tmp;               # delete some environment
my @clean;                      # clean options
my $pdf       = 1;              # create a PDF image file
my $run       = 1;              # run mode compiler
my $crop      = 1;              # croped pdf image files
my $gray      = 0;              # create a gray scale images
my $output;                     # set output name for outfile
my $outfile   = 0;              # write output file
my $outsrc    = 0;              # enable write src env files
my $debug     = 0;              # debug
my $PSTexa    = 0;              # extract PSTexample environments
my $STDenv    = 0;              # extract standart environments
my $verbose   = 0;              # verbose

### Search Ghostscript
# The next code it's part of pdfcrop adapted from TexLive 2014
# Windows detection
my $Win = 0;
$Win = 1 if $^O =~ /mswin32/i;
$Win = 1 if $^O =~ /cygwin/i;

my $archname = $Config{'archname'};
$archname = 'unknown' unless defined $Config{'archname'};

# get Ghostscript command name
my $gscmd = '';
sub find_ghostscript () {
    return if $gscmd;
    if ($debug) {
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
    print "* OS name: $^O\n" if $debug;
    print "* Arch name: $archname\n" if $debug;
    print "* System: $system\n" if $debug;
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
                $gscmd = $candidate;
                $found = 1;
                print "* Found ($candidate): $file\n" if $debug;
                last;
            }
            print "* Not found ($candidate): $file\n" if $debug;
        }
        last if $found;
    }
    if (not $found and $Win) {
        $found = SearchRegistry();
    }
    if ($found) {
        print "* Autodetected ghostscript command: $gscmd\n" if $debug;
    }
    else {
        $gscmd = $$candidates_ref[0];
        print "* Default ghostscript command: $gscmd\n" if $debug;
    }
}

sub SearchRegistry () {
    my $found = 0;
    eval 'use Win32::TieRegistry qw|KEY_READ REG_SZ|;';
    if ($@) {
        if ($debug) {
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
                if $debug;
        return $found;
    }
    print "* Search registry at `$current_key'.\n" if $debug;
    my %list;
    foreach my $key_name_gs (grep /Ghostscript/i, $software->SubKeyNames()) {
        $current_key = "$key_name_software$key_name_gs/";
        print "* Registry entry found: $current_key\n" if $debug;
        my $key_gs = $software->Open($key_name_gs, $open_params);
        if (not $key_gs) {
            print "* Cannot open registry key `$current_key'!\n" if $debug;
            next;
        }
        foreach my $key_name_version ($key_gs->SubKeyNames()) {
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            print "* Registry entry found: $current_key\n" if $debug;
            if (not $key_name_version =~ /^(\d+)\.(\d+)$/) {
                print "  The sub key is not a version number!\n" if $debug;
                next;
            }
            my $version_main = $1;
            my $version_sub = $2;
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            my $key_version = $key_gs->Open($key_name_version, $open_params);
            if (not $key_version) {
                print "* Cannot open registry key `$current_key'!\n" if $debug;
                next;
            }
            $key_version->FixSzNulls(1);
            my ($value, $type) = $key_version->GetValue('GS_DLL');
            if ($value and $type == REG_SZ()) {
                print "  GS_DLL = $value\n" if $debug;
                $value =~ s|([\\/])([^\\/]+\.dll)$|$1gswin32c.exe|i;
                my $value64 = $value;
                $value64 =~ s/gswin32c\.exe$/gswin64c.exe/;
                if ($archname =~ /mswin32-x64/i and -f $value64) {
                    $value = $value64;
                }
                if (-f $value) {
                    print "EXE found: $value\n" if $debug;
                }
                else {
                    print "EXE not found!\n" if $debug;
                    next;
                }
                my $sortkey = sprintf '%02d.%03d %s',
                        $version_main, $version_sub, $key_name_gs;
                $list{$sortkey} = $value;
            }
            else {
                print "Missing key `GS_DLL' with type `REG_SZ'!\n" if $debug;
            }
        }
    }
    foreach my $entry (reverse sort keys %list) {
        $gscmd = $list{$entry};
        print "* Found (via registry): $gscmd\n" if $debug;
        $found = 1;
        last;
    }
    return $found;
} # end GS search

### If windows
if ($Win and $gscmd =~ /\s/) {
    $gscmd = "\"$gscmd\"";
}

### Call GS
find_ghostscript();

### Program identification, options and help for command line

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
Usage: ltximg [<compiler>] [<options>] <file>.<ext>
* ltximg --latex  [<options>] <file>.<ext>
* ltximg --xetex  [<options>] <file>.<ext>
* ltximg --luatex [<options>] <file>.<ext>
* ltximg --arara  [<options>] <file>.<ext>

LTXimg extract and convert all related environments from (La)TeX file
  into single images files using Ghostscript and other software.If called
  whitout compiler, extract and convert environments using pdflatex  and
  Ghostscript. The images and files created are saved in /images dir by
  default.

Default environments suports:

  pspicture tikzpicture pgfpicture psgraph postscript PSTexample

Options:

 -h,--help             - display this help and exit
 -l,--license          - display license and exit
 -v,--version          - display version (current $nv) and exit
 -d,--dpi = <int>      - dots per inch for images (default: $DPI)
 -t,--tif              - create .tif files using ghostscript [$gscmd]
 -b,--bmp              - create .bmp files using ghostscript [$gscmd]
 -j,--jpg              - create .jpg files using ghostscript [$gscmd]
 -p,--png              - create .png files using ghostscript [$gscmd]
 -e,--eps              - create .eps files using pdftops
 -s,--svg              - create .svg files using pdftocairo
 -P,--ppm              - create .ppm files using pdftoppm
 -g,--gray             - gray scale for images using ghostscript (default: off)
 -f,--force            - capture \\psset and \\tikzset to extract (default: off)
 -n,--noprew           - create images files whitout preview (default: off)
 -m,--margin <int>     - margins in bp for pdfcrop (default: 0)
 -o,--output <outname> - create output file whit environmets converted in image.
                         <outname> must not contain extension.
 --imgdir  <string>    - the folder for images (default: images)
 --verbose             - verbose printing (default: off)
 --srcenv              - create separate files whit only code environment
 --subenv              - create sub files whit preamble and code environment
 --arara               - use arara for compiler files, need to pass "-recorder"
                         % arara : <compiler> : {options: "-recorder"}
 --xetex               - using (Xe)LaTeX compiler for create images
 --latex               - using latex>dvips>ps2pdf compiler for create images
 --dvips               - using latex>dvips>ps2pdf for compiler output file
 --dvipdf              - using latex>dvipdfmx  for create images
 --luatex              - using (Lua)LaTeX compiler for create images
 --prefix              - prefix append to each file created (default: fig)
 --norun               - run script, but no create images (default off)
 --nopdf               - don't create a PDF image files (default: off)
 --nocrop              - don't run pdfcrop (default: off)
 --myverb  <string>    - set verbatim inline command \\string (default: myverb)
 --clean <value>       - removes specific text in the output file (default: doc)
                         values are: <doc|pst|tkz|all|off>
 --extrenv <env1,...>  - search other environment to extract (need -- at end)
 --skipenv <env1,...>  - skip default environment, no extract (need -- at end)
 --verbenv <env1,...>  - add new verbatim environment (need -- at end)
 --writenv <env1,...>  - add new verbatim write environment (need -- at end)
 --deltenv <env1,...>  - delete environment in output file (need -- at end)

Example:
* ltximg -e -p -j --srcenv --imgdir pics -o test-out test-in.ltx
* produce a file test-out.ltx whitout all environments suported and create /pics
* dir whit all images (pdf,eps,png,jpg) and source code (.ltx) in separate files 
* for all environment extracted using (pdf)LaTeX whit preview package.
* Suport bundling for short options:
* ltximg -epj --srcenv --imgdir pics -o test-out  test-in.ltx
* Use texdoc ltximg for full documentation.
END_OF_USAGE

### Error in command line
sub errorUsage { die "@_ (try ltximg --help for more information)\n"; }

### Getopt::Long configuration
my %opts_cmd;
my %opts_cmd_other;
my $result=GetOptions (
# short and long options
    'h|help'         => \$opts_cmd{help}, # help
    'v|version'      => \$opts_cmd{version}, # version
    'l|license'      => \$opts_cmd{license}, # license
    'd|dpi=i'        => \$DPI, # numeric
    'm|margin=i'     => \$margins, # numeric
    'b|bmp'          => \$opts_cmd{bmp}, # gs
    't|tif'          => \$opts_cmd{tif}, # gs
    'j|jpg'          => \$opts_cmd{jpg}, # gs
    'p|png'          => \$opts_cmd{png}, # gs
    's|svg'          => \$opts_cmd_other{svg}, # pdftocairo
    'e|eps'          => \$opts_cmd_other{eps}, # pdftops
    'P|ppm'          => \$opts_cmd_other{ppm}, # pdftoppm
    'g|gray'         => \$gray,   # gray (bolean)
    'f|force'        => \$force,  # force (bolean)
    'n|noprew'       => \$noprew, # no preview (bolean)
    'o|output=s{1}'  => \$output, # output file name (string)
# bolean options
    'subenv'         => \$subenv, # subfile environments (bolean)
    'srcenv'         => \$srcenv, # source files (bolean)
    'arara'          => \$arara,  # arara compiler
    'xetex'          => \$xetex,  # xelatex compiler
    'latex'          => \$latex,  # latex compiler
    'luatex'         => \$luatex, # lualatex compiler
    'dvips'          => \$dvips,  # dvips compiler
    'dvipdf'         => \$dvipdf, # dvipdfmx compiler
# string options from command line
    'extrenv=s{1,9}' => \@extr_env_tmp, # extract environments
    'skipenv=s{1,9}' => \@skip_env_tmp, # skip environment
    'verbenv=s{1,9}' => \@verb_env_tmp, # verbatim environment
    'writenv=s{1,9}' => \@verw_env_tmp, # verbatim write environment
    'deltenv=s{1,9}' => \@delt_env_tmp, # delete environment
# string options
    'imgdir=s{1}'    => \$imageDir, # images dir
    'myverb=s{1}'    => \$myverb,   # \myverb inline (string)
    'prefix=s{1}'    => \$prefix,   # prefix
# negated options
    'crop!'          => \$crop,    # run pdfcrop
    'pdf!'           => \$pdf,     # pdf image format
    'clean=s{1}'     => \@clean,   # clean output file
    'run!'           => \$run,     # run compiler
    'debug!'         => \$debug,   # debug mode
    'verbose!'       => \$verbose, # debug mode,
    ) or die $usage;
    
### Split comma separte list options from command line
s/^\s*(\=):?|\s*//mg foreach @extr_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @skip_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @verb_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @verw_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @delt_env_tmp;
@extr_env_tmp = split(/,/,join('',@extr_env_tmp));
@skip_env_tmp = split(/,/,join('',@skip_env_tmp));
@verb_env_tmp = split(/,/,join('',@verb_env_tmp));
@verw_env_tmp = split(/,/,join('',@verw_env_tmp));
@delt_env_tmp = split(/,/,join('',@delt_env_tmp));

### Validate input string options
if ( grep( /(^\-|^\.).*?/, @extr_env_tmp ) ) {
  die errorUsage "Invalid option for --extrenv, invalid environment name";
}
if ( grep( /(^\-|^\.).*?/, @skip_env_tmp ) ) {
  die errorUsage "Invalid option for --skipenv, invalid environment name";
}
if ( grep( /(^\-|^\.).*?/, @verb_env_tmp ) ) {
  die errorUsage "Invalid option for --verbenv, invalid environment name";
}
if ( grep( /(^\-|^\.).*?/, @verw_env_tmp ) ) {
  die errorUsage "Invalid option for --verwenv, invalid environment name";
}
if ( grep( /(^\-|^\.).*?/, @delt_env_tmp ) ) {
  die errorUsage "Invalid option for --deltenv, invalid environment name";
}

### Help
if (defined $opts_cmd{help}){
    find_ghostscript();
    print $usage;
    exit(0);
}

### Version
if (defined $opts_cmd{version}){
    print $title;
    exit(0);
}

### Licence
if (defined $opts_cmd{license}){
    print $licensetxt;
    exit(0);
}

### Set tmp random name for name-fig-tmp (temp files)
my $tmp = "$$";

### Check --srcenv and --subenv option
if ($srcenv && $subenv) {
  die errorUsage "--srcenv and --subenv options are mutually exclusive";
}

### Check the input file from command line
@ARGV > 0 or errorUsage "Input filename missing";
@ARGV < 2 or errorUsage "Unknown option or too many input files";

### Check input file extention
my @SuffixList = ('.tex', '', '.ltx');    # posibles
my ($name, $path, $ext) = fileparse($ARGV[0], @SuffixList);
$ext = '.tex' if not $ext;

### Read input file in memory (slurp), need :crlf for windows/linux
open my $INPUTfile, '<:crlf', "$name$ext";
my $archivo;
{
    local $/;
    $archivo = <$INPUTfile>;
}
close $INPUTfile;

### Funtion uniq
sub uniq {
    my %seen;
    grep !$seen{$_}++, @_;
}

### Funtion array_minus
sub array_minus(\@\@) {
    my %e = map{ $_ => undef } @{$_[1]};
    return grep( ! exists( $e{$_} ), @{$_[0]} );
}

### Funtion to create hash
sub crearhash{
    my %cambios;

    for my $aentra(@_){
    for my $initend (qw(begin end)) {
        $cambios{"\\$initend\{$aentra"} = "\\\U$initend\E\{$aentra";
            }
        }
    return %cambios;
}

### Default environment to extract
my @extr_tmp  = qw (
    postscript tikzpicture pgfpicture pspicture psgraph
    );

push(@extr_env_tmp,@extr_tmp);

### Default verbatim environment
my @verb_tmp  = qw (
    Example CenterExample SideBySideExample PCenterExample PSideBySideExample
    verbatim Verbatim BVerbatim LVerbatim SaveVerbatim PSTcode
    LTXexample tcblisting spverbatim minted listing lstlisting
    alltt comment chklisting verbatimtab listingcont boxedverbatim
    demo sourcecode xcomment pygmented pyglist program programl
    programL programs programf programsc programt
    );

push(@verb_env_tmp,@verb_tmp);

### Default verbatim write skip environment
my @verbw_tmp = qw (
    filecontents tcboutputlisting tcbexternal extcolorbox extikzpicture
    VerbatimOut verbatimwrite file­con­tents­def file­con­tentshere
    PSTexample
    );

push(@verw_env_tmp,@verbw_tmp);

### Rules to capture in regex
my $braces      = qr/ (?:\{)(.+?)(?:\})     /msx;
my $braquet     = qr/ (?:\[)(.+?)(?:\])     /msx;
my $no_corchete = qr/ (?:\[ .+? \])?        /msx;

### Capture new verbatim environments defined in input file
my @new_verb = qw (
    newtcblisting DeclareTCBListing ProvideTCBListing NewTCBListing
    lstnewenvironment NewListingEnvironment NewProgram specialcomment
    includecomment DefineVerbatimEnvironment newverbatim newtabverbatim
    );

### Regex to capture names for new verbatim environments from input file
my $newverbenv = join "|", map quotemeta, sort { length $a <=> length $b } @new_verb;
$newverbenv = qr/\b(?:$newverbenv) $no_corchete $braces/msx;

### Capture new verbatim write environments defined in input file
my @new_verb_write = qw (
    renewtcbexternalizetcolorbox renewtcbexternalizeenvironment
    newtcbexternalizeenvironment newtcbexternalizetcolorbox
    );

### Regex to capture names for new verbatim write environments from input file
my $newverbwrt = join "|", map quotemeta, sort { length $a <=> length $b } @new_verb_write;
$newverbwrt = qr/\b(?:$newverbwrt) $no_corchete $braces/msx;

### Regex to capture MINTED related environments
my $mintdenv   = qr/\\ newminted $braces (?:\{.+?\})            /x;
my $mintcenv   = qr/\\ newminted $braquet (?:\{.+?\})           /x;
my $mintdshrt  = qr/\\ newmint $braces (?:\{.+?\})              /x;
my $mintcshrt  = qr/\\ newmint $braquet (?:\{.+?\})             /x;
my $mintdline  = qr/\\ newmintinline $braces (?:\{.+?\})        /x;
my $mintcline  = qr/\\ newmintinline $braquet (?:\{.+?\})       /x;

### Pass input file to @array and remove % and comments
my @verbinput = $archivo;
s/%.*\n//mg foreach @verbinput; # del comments
s/^\s*|\s*//mg foreach @verbinput; # del white space
my $verbinput = join '', @verbinput;

### Capture \newverbatim write names in input file
my @newv_write = $verbinput =~ m/$newverbwrt/xg;

### Add @newv_write defined in input file to @verw_env_tmp
push(@verw_env_tmp,@newv_write);

### Capture \newminted{$mintdenv}{options} (for)
my @mint_denv  = $verbinput =~ m/$mintdenv/xg;

### Capture \newminted[$mintcenv]{lang} (for)
my @mint_cenv  = $verbinput =~ m/$mintcenv/xg;

### Capture \newmint{$mintdshrt}{options} (while)
my @mint_dshrt = $verbinput =~ m/$mintdshrt/xg;

### Capture \newmint[$mintcshrt]{lang}{options} (while)
my @mint_cshrt = $verbinput =~ m/$mintcshrt/xg;

### Capture \newmintinline{$mintdline}{options} (while)
my @mint_dline = $verbinput =~ m/$mintdline/xg;

### Capture \newmintinline[$mintcline]{lang}{options} (while)
my @mint_cline = $verbinput =~ m/$mintcline/xg;

### Capture \newverbatim environments in input file (for)
my @verb_input = $verbinput =~ m/$newverbenv/xg;

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
my @mint_tmp  = qw ( mint  mintinline lstinline);
push(@mintline,@mint_dline,@mint_cline,@mint_dshrt,@mint_cshrt,@mint_tmp);
@mintline = uniq(@mintline);

### Create a regex using @mintline
my $mintline = join "|", map quotemeta, sort { length $a <=> length $b } @mintline;
$mintline   = qr/\b(?:$mintline)/x;

### Options from input file
# % ltximg : extrenv : {extrenv1, extrenv2, ... , extrenvn}
# % ltximg : skipenv : {skipenv1, skipenv2, ... , skipenvn}
# % ltximg : verbenv : {verbwrt1, verbwrt2, ... , verbwrtn}
# % ltximg : writenv : {verbwrt1, verbwrt2, ... , verbwrtn}
# % ltximg : deltenv : {deltenv1, deltenv2, ... , deltenvn}
# % ltximg : options : {opt1=arg, opt2=arg, ... , bolean}

### Regex to capture before preamble
my $rx_myscrypt = qr/
    ^ %+ \s* ltximg (?&SEPARADOR) (?<clave>(?&CLAVE)) (?&SEPARADOR) \{ (?<argumentos>(?&ARGUMENTOS)) \}
    (?(DEFINE)
    (?<CLAVE>      \w+       )
    (?<ARGUMENTOS> .+?       )
    (?<SEPARADOR>  \s* : \s* )
    )
/mx;

### Split input file, $optin contain % ltximg : <argument>
my($optin, $documento) = $archivo =~ m/\A (\s* .*? \s*) (\\documentclass.*)\z/msx;

### Process options from input file
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
                } # close for
            else {
                $resultado{$clave}{$argumento} = 1;
                }
            } # close for
    } # close if
    else {
        push @{ $resultado{ $clave } }, @argumentos;
    }
} # close while

### Validate clean
my %clean =  map { $_ => 1 } @clean;

### By default clean = doc
$clean{doc} = 1 ;

### Set clean options from input file
$clean{doc} = 1 if ($resultado{options}{clean} eq 'doc');
$clean{off} = 1 if ($resultado{options}{clean} eq 'off');
$clean{pst} = 1 if ($resultado{options}{clean} eq 'pst');
$clean{tkz} = 1 if ($resultado{options}{clean} eq 'tkz');
$clean{all} = 1 if ($resultado{options}{clean} eq 'all');

### Set clean options for script
if ($clean{pst} or $clean{tikz}) {
    $clean{doc} = 1;
}
if ($clean{all}) {
    @clean{qw(pst doc tkz)} = (1) x 3;
}
if ($clean{off}) {
    undef %clean;
}

### Set extract options from input file
if (exists $resultado{extract} ) {
    push @extr_env_tmp, @{ $resultado{extract} };
}

### Set skipenv options from input file
if (exists $resultado{skipenv} ) {
    push @skip_env_tmp, @{ $resultado{skipenv} };
}

### Set verbenv options from input file
if (exists $resultado{verbenv} ) {
    push @verb_env_tmp, @{ $resultado{verbenv} };
}

### Set writenv options from input file
if (exists $resultado{writenv} ) {
    push @verw_env_tmp, @{ $resultado{writenv} };
}

### Set deltenv options from input file
if (exists $resultado{deltenv} ) {
    push @delt_env_tmp, @{ $resultado{deltenv} };
}

### Set \myverb|<code>| options from input file
if (exists $resultado{options}{myverb}){
    $myverb = $resultado{options}{myverb};
    }

### Create  @env_all_tmp contain all environments
my @env_all_tmp;
push(@env_all_tmp,@extr_env_tmp,@skip_env_tmp,@verb_env_tmp,@verw_env_tmp,@delt_env_tmp);
@env_all_tmp  = uniq(@env_all_tmp);

### Create @no_env_all_tmp contain all No extracted environments
my @no_env_all_tmp;
push(@no_env_all_tmp,@skip_env_tmp,@verb_env_tmp,@verw_env_tmp,@delt_env_tmp);
@no_env_all_tmp = uniq(@no_env_all_tmp);

### The operation return @extract environment
my @extract = array_minus(@env_all_tmp,@no_env_all_tmp);
@extract = uniq(@extract);

### The operation return @no_extract
my @no_extract = array_minus(@env_all_tmp,@extract);
my @no_skip;
push(@no_skip,@verb_env_tmp,@verw_env_tmp,@delt_env_tmp);
my @skipped = array_minus(@no_extract,@no_skip);
@skipped = uniq(@skipped);

### The operation return @delte_env environment
my @no_ext_skip = array_minus(@no_extract,@skipped);
my @no_del;
push(@no_del,@verb_env_tmp,@verw_env_tmp);
my @delete_env = array_minus(@no_ext_skip,@no_del);
@delete_env    = uniq(@delete_env);

### The operation return @verbatim environment
my @no_ext_skip_del = array_minus(@no_ext_skip,@delete_env);
my @verbatim = array_minus(@no_ext_skip_del,@verw_env_tmp);

### The operation return @verbatim write environment
my @verbatim_w = array_minus(@no_ext_skip_del,@verbatim);

### Create @env_all for hash and replace in while
my @no_verb_env;
push(@no_verb_env,@extract,@skipped,@delete_env,@verbatim_w);
my @no_verw_env;
push(@no_verw_env,@extract,@skipped,@delete_env,@verbatim);

### Reserved words in verbatim inline (while)
my %changes_in = (
# ltximg tags
    '%<*ltximg>'        =>  '%<*LTXIMG>',
    '%</ltximg>'        =>  '%</LTXIMG>',
    '%<*noltximg>'      =>  '%<*NOLTXIMG>',
    '%</noltximg>'      =>  '%</NOLTXIMG>',
    '%<*remove>'        =>  '%<*REMOVE>',
    '%</remove>'        =>  '%</REMOVE>',
    '%<*ltximgverw>'    =>  '%<*LTXIMGVERW>',
    '%</ltximgverw>'    =>  '%</LTXIMGVERW>',
# pst/tikz set
    '\psset'            =>  '\PSSET',
    '\tikzset'          =>  '\TIKZSET',
# pspicture
    '\pspicture'        =>  '\TRICKS',
    '\endpspicture'     =>  '\ENDTRICKS',
# pgfpicture
    '\pgfpicture'       =>  '\PGFTRICKS',
    '\endpgfpicture'    =>  '\ENDPGFTRICKS',
# tikzpicture
    '\tikzpicture'      =>  '\TKZTRICKS',
    '\endtikzpicture'   =>  '\ENDTKZTRICKS',
# psgraph
    '\psgraph'          =>  '\PSGRAPHTRICKS',
    '\endpsgraph'       =>  '\ENDPSGRAPHTRICKS',
# some reserved
    '\usepackage'       =>  '\USEPACKAGE',
    '{graphicx}'        =>  '{GRAPHICX}',
    '\graphicspath{'    =>  '\GRAPHICSPATH{',
    );

### Changues for \begin... \end inline verbatim
my %init_end = (
# begin{ and end{
    '\begin{'           =>  '\BEGIN{',
    '\end{'             =>  '\END{',
    );

### Changues for \begin{document} ... \end{document}
my %document = (
# begin/end document for split
    '\begin{document}'  =>  '\BEGIN{document}',
    '\end{document}'    =>  '\END{document}',
    );

### Reverse for extract and output file
my %changes_out = (
# ltximg tags
    '\begin{nopreview}' =>  '%<*noltximg>',
    '\end{nopreview}'   =>  '%</noltximg>',
# pst/tikz set
    '\PSSET'            =>  '\psset',
    '\TIKZSET'          =>  '\tikzset',
# pspicture
    '\TRICKS'           =>  '\pspicture',
    '\ENDTRICKS'        =>  '\endpspicture',
# pgfpicture
    '\PGFTRICKS'        =>  '\pgfpicture',
    '\ENDPGFTRICKS'     =>  '\endpgfpicture',
# tikzpicture
    '\TKZTRICKS'        =>  '\tikzpicture',
    '\ENDTKZTRICKS'     =>  '\endtikzpicture',
# psgraph
    '\PSGRAPHTRICKS'    =>  '\psgraph',
    '\ENDPSGRAPHTRICKS' =>  '\endpsgraph',
# some reserved
    '\USEPACKAGE'       =>  '\usepackage',
    '{GRAPHICX}'        =>  '{graphicx}',
    '\GRAPHICSPATH{'    =>  '\graphicspath{',
# begin{ and end{
    '\BEGIN{'           =>  '\begin{',
    '\END{'             =>  '\end{',
    );

### Reverse tags, need back in all file to extract
my %reverse_tag = (
# ltximg tags
    '%<*LTXIMG>'        =>  '%<*ltximg>',
    '%</LTXIMG>'        =>  '%</ltximg>',
    '%<*NOLTXIMG>'      =>  '%<*noltximg>',
    '%</NOLTXIMG>'      =>  '%</noltximg>',
    '%<*REMOVE>'        =>  '%<*remove>',
    '%</REMOVE>'        =>  '%</remove>',
    '%<*LTXIMGVERW>'    =>  '%<*ltximgverw>',
    '%</LTXIMGVERW>'    =>  '%</ltximgverw>',
    );

### Creatate a hash for changues
my %extract_env = crearhash(@extract);
my %skiped_env = crearhash(@skipped);
my %verb_env = crearhash(@verbatim);
my %verbw_env = crearhash(@verbatim_w);
my %delete_env = crearhash(@delete_env);
my %change_verbw_env = crearhash(@no_verw_env);
my %change_verb_env  = crearhash(@no_verb_env);

### Join changues in new hash
my %cambios = (%changes_in,%init_end);

### Variables y constantes
my $no_del = "\0";
my $del    = $no_del;

### Rules
my $llaves      = qr/\{ .+? \}                                                          /x;
my $no_llaves   = qr/(?: $llaves )?                                                     /x;
my $corchetes   = qr/\[ .+? \]                                                          /x;
my $anidado     = qr/(\{(?:[^\{\}]++|(?1))*\})                                          /x;
my $delimitador = qr/\{ (?<del>.+?) \}                                                  /x;
my $verb        = qr/(?:((spv|(?:q|f)?v|V)erb)[*]?)                                     /ix;
my $lst         = qr/(?:(lst|pyg)inline)(?!\*) $no_corchete                             /ix;
my $mint        = qr/(?: $mintline |SaveVerb) (?!\*) $no_corchete $no_llaves $llaves    /ix;
my $no_mint     = qr/(?: $mintline) (?!\*) $no_corchete                                 /ix;
my $marca       = qr/\\ (?:$verb | $lst | $mint |$no_mint) (?:\s*)? (\S) .+? \g{-1}     /x;
my $comentario  = qr/^ \s* \%+ .+? $                                                    /mx;
my $definedel   = qr/\\ (?: DefineShortVerb | lstMakeShortInline| MakeSpecialShortVerb ) [*]? $no_corchete $delimitador /ix;
my $indefinedel = qr/\\ (?: (Undefine|Delete)ShortVerb | lstDeleteShortInline) $llaves  /ix;

### Changues in input file for create a tmp file for extract
while ($documento =~
        /   $marca
        |   $comentario
        |   $definedel
        |   $indefinedel
        |   $del .+? $del
        /pgmx) {
    my($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my $encontrado = ${^MATCH};
    if ($encontrado =~ /$definedel/) {
        $del = $+{del};
        $del = "\Q$+{del}" if substr($del,0,1) ne '\\';
    }
    elsif ($encontrado =~ /$indefinedel/) {
        $del = $no_del;
    }
    else {
        while (my($busco, $cambio) = each %cambios) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;
        }
        substr $documento, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos($documento) = $pos_inicial + length $encontrado;
    }
}

### Regex for verbatim inline {...}
my $mintd_ani = qr/\\ (?:$mintline|pygment) (?!\*) $no_corchete $no_llaves     /x;
my $tcbxverb  = qr/\\ (?: tcboxverb [*]?|$myverb [*]?|lstinline)  $no_corchete /x;
my $tcbxmint  = qr/(?:$tcbxverb|$mintd_ani) (?:\s*)? $anidado	       	       /x;

### Changue \verb{...} inline 
while ($documento =~ /$tcbxmint/pgmx) {
        my($pos_inicial, $pos_final) = ($-[0], $+[0]);
        my $encontrado = ${^MATCH};
        while (my($busco, $cambio) = each %cambios) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;
            } # close while
        substr $documento, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos($documento)= $pos_inicial + length $encontrado;
} # close while

### Changue <*TAGS> to <*tags> in file
my $ltxtags = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %reverse_tag;
$documento =~ s/^($ltxtags)/$reverse_tag{$1}/gmsx;

### Defined Verbatim
my $verbatim = join "|", map quotemeta, sort { length $a <=> length $b } @verbatim;
$verbatim = qr/$verbatim/x;

### Defined Verbatim write
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

### Split file by lines
my @lineas = split /\n/, $documento;

### Hash and Regex
my %replace = (%change_verb_env,%changes_in,%document);
my $find = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %replace;

### Change in $verbatim and $verbatim_w
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

### Regex for delete environment
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

### Regex for verbatim write
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

### Regex for skip environment
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

### Convert plain TeX syntax to LaTeX syntax
my %special =  map { $_ => 1 } @extract; # anon hash

### Convert \pspicture
if(exists($special{pspicture})){
    $cuerpo =~ s/
    \\pspicture(\*)?(.+?)\\endpspicture/\\begin{pspicture$1}$2\\end{pspicture$1}/gmsx;
    }

### Convert \psgraph
if(exists($special{psgraph})){
    $cuerpo =~ s/
    \\psgraph(\*)?(.+?)\\endpsgraph/\\begin{psgraph$1}$2\\end{psgraph$1}/gmsx;
    }

### Convert \tikzpicture
if(exists($special{tikzpicture})){
    $cuerpo =~ s/
    \\tikzpicture(.+?)\\endtikzpicture/\\begin{tikzpicture}$1\\end{tikzpicture}/gmsx;
    }

### Convert \pgfpicture
if(exists($special{pgfpicture})){
    $cuerpo =~ s/
    \\pgfpicture(.+?)\\endpgfpicture/\\begin{pgfpicture}$1\\end{pgfpicture}/gmsx;
    }

### Pass %<*ltximg> (.+?) %</ltximg> to \begin{preview} (.+?) \end{preview}
$cuerpo =~ s/^\%<\*$extrtag>(.+?)\%<\/$extrtag>/\\begin\{preview\}$1\\end\{preview\}/gmsx;

### Pass $extr_env to \begin{preview} .+? \end{preview}
$cuerpo =~ s/	\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
        \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
        \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
  ($extr_env)/\\begin\{preview\}\n$1\n\\end\{preview\}/gmsx;

### Set bolean options from input file
$force  = 1 if exists $resultado{options}{force};
$run    = 0 if exists $resultado{options}{norun};
$pdf    = 0 if exists $resultado{options}{nopdf};
$crop   = 0 if exists $resultado{options}{nocrop};
$noprew = 1 if exists $resultado{options}{noprew};
$force  = 1 if exists $resultado{options}{force};
$arara  = 1 if exists $resultado{options}{arara};
$xetex  = 1 if exists $resultado{options}{xetex};
$latex  = 1 if exists $resultado{options}{latex};
$dvips  = 1 if exists $resultado{options}{dvips};
$dvipdf = 1 if exists $resultado{options}{dvipdf};
$luatex = 1 if exists $resultado{options}{luatex};
$srcenv = 1 if exists $resultado{options}{srcenv};
$subenv = 1 if exists $resultado{options}{subenv};

### FORCE mode for pstricks/psgraph/tikzpiture
if ($force) {
# pspicture or psgraph found
if(exists($special{pspicture}) or exists($special{psgraph})){
$cuerpo =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
        \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
        \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
        \\begin\{postscript\}.+?\\end\{postscript\}(*SKIP)(*F)|
        (?<code>
        (?:\\psset\{(?:\{.*?\}|[^\{])*\}.+?)?  # if exist ...save
        \\begin\{(?<env> pspicture\*?| psgraph)\} .+? \\end\{\k<env>\}
    )
    /\\begin\{preview\}\n$+{code}\n\\end\{preview\}/gmsx;
} # close pspicture

# tikzpicture found
if(exists($special{tikzpicture})){
$cuerpo =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
        \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
        \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
        \\begin\{postscript\}.+?\\end\{postscript\}(*SKIP)(*F)|
        (?<code>
        (?:\\tikzset\{(?:\{.*?\}|[^\{])*\}.+?)?  # if exist ...save
        \\begin\{(?<env> tikzpicture)\} .+? \\end\{\k<env>\}
    )
    /\\begin\{preview\}\n$+{code}\n\\end\{preview\}/gmsx;
    } # close tikzpicture
} # close force mode

### The extract environments need back word to original
%replace = (%changes_out,%reverse_tag);
$find = join "|", map {quotemeta} sort { length($a)<=>length($b) } keys %replace;

### Split $cabeza by lines
@lineas = split /\n/, $cabeza;

### Changues in verbatim write
for (@lineas) {
    if (/\\begin\{($verbatim_w\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
        s/($find)/$replace{$1}/g;
    }
} # close for

### Join lines in $cabeza
$cabeza = join("\n", @lineas);

### Change back betwen \begin{preview} ... \end{preview} -------#
@lineas = split /\n/, $cuerpo;

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

### If environment extract found, the run script
my $BP  = '\\\\begin\{preview\}';
my $EP  = '\\\\end\{preview\}';

my @env_extract  = $cuerpo =~ m/(?<=$BP)(.+?)(?=$EP)/gms;
my $envNo = scalar @env_extract;

### PSTexample suport (new)
my $BE  = '\\\\begin\{PSTexample\}';
my $EE  = '\\\\end\{PSTexample\}';

my @exa_extract  = $cuerpo =~ m/(?<=$BE)(.+?)(?=$EE)/gms;
my $exaNo = scalar @exa_extract;

### Check if PSTexample environment found
if($exaNo!= 0){
    $PSTexa=1;
}

### Check if standart environment found
if($envNo!= 0){
    $STDenv=1;
}

if($PSTexa){
my $exaNo = 1;
### Append graphic= to \begin{PSTexample}[...]
while ($cuerpo =~ /\\begin\{PSTexample\}(\[.+?\])?/gsm) {
    my $swpl_grap = "graphic=\{\[scale=1\]$imageDir/$name-$prefix-exa";

    my $corchetes = $1;
    my($pos_inicial, $pos_final) = ($-[1], $+[1]);

    if (not $corchetes) {
        $pos_inicial = $pos_final = $+[0];
    }
    if (not $corchetes  or  $corchetes =~ /\[\s*\]/) {
        $corchetes = "[$swpl_grap-$exaNo}]";
    }
    else {
        $corchetes =~ s/\]/,$swpl_grap-$exaNo}]/;
    }
    substr($cuerpo, $pos_inicial, $pos_final - $pos_inicial) = $corchetes;
    pos($cuerpo) = $pos_inicial + length $corchetes;
} # close while
continue {
    $exaNo++;
    }

### Pass PSTexample to nopreview envirnment
$cuerpo =~ s/\%<\*ltximgverw>\n
    (?<code>
         \\begin\{PSTexample\} .+? \\end\{PSTexample\}
    )
    \n\%<\/ltximgverw>
    /\\begin\{nopreview\}\n$+{code}\n\\end\{nopreview\}/gmsx;
} # close PSTexa

### Standart command line script identification
print "$program $nv, $copyright" ;

### Check if enviromento found
if ($envNo == 0 and $exaNo == 0){
    die errorUsage "ltximg not found any environment to extract in file $name$ext";
    }
elsif ($envNo!= 0 and $exaNo!= 0){
    say "The file $name$ext contain $envNo environment to extract and $exaNo PSTexample environment to extract";
    }
elsif ($envNo == 0 and $exaNo!= 0){
    say "The file $name$ext contain $exaNo PSTexample environment to extract";
    }
else {
say "The file $name$ext contain $envNo environment to extract";
    }

### Set name of output file from input file
if (exists $resultado{options}{output}){
    $output = $resultado{options}{output};
    }

### The output file name not contain - at begin
if (defined $output) {
if ($output =~ /(^\-|^\.).*?/){
    die errorUsage "$output it is not a valid name for output file";
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
if(defined($output)){
    $outfile = 1;
}

### If --srcenv or --subenv option are OK then execute script
if($srcenv){
    $outsrc = 1;
    $subenv = 0;
}
if ($subenv){
    $outsrc = 1;
    $srcenv = 0;
}

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

### Options for page numering for $crop
my $opt_page = $crop ? "\n\\pagestyle\{empty\}\n\\begin\{document\}"
              :        "\n\\begin\{document\}"
              ;

### Preamble options for subfiles
my $sub_prea = "$optin$cabeza$opt_page";

### Delete <*remove> ... </remove> in $sub_prea
$sub_prea =~s/^\%<\*remove>\s*(.+?)\s*\%<\/remove>(?:[\t ]*(?:\r?\n|\r))?+//gmsx;

my $opt_prew = $xetex ? 'xetex,'
             : $latex ? ''
             :          'pdftex,'
             ;

### Lines put at begin document
my $preview = <<"EXTRA";
\\AtBeginDocument\{%
\\RequirePackage\[${opt_prew}active,tightpage\]\{preview\}%
\\renewcommand\\PreviewBbAdjust\{-60pt -60pt 60pt 60pt\}\}%
EXTRA

### Extract source $outsrc
if ($outsrc) {
my $src_name = "$name-$prefix-";
my $srcNo    = 1;

### Source file whitout preamble for standart environment
if ($srcenv) {

### Extract standart environment in single files
if($STDenv){
say "Creating $envNo files with the source code for all environments";
while ($cuerpo =~ m/$BP\s*(?<env_src>.+?)\s*$EP/gms) {
open my $OUTsrc, '>', "$imageDir/$src_name$srcNo$ext";
    print $OUTsrc $+{env_src};
close $OUTsrc;
        } # close while
continue {
    $srcNo++;
    }
} # close STDenv

### Extract PSTexample in single files
if($PSTexa){
say "Creating $exaNo files with the source code for all PSTexample environments";
while ($cuerpo =~ m/$BE\[.+?(?<pst_exa_name>$imageDir\/.+?-\d+)\}\]\s*(?<exa_src>.+?)\s*$EE/gms) {
open my $OUTexa, '>', "$+{'pst_exa_name'}$ext";
    print $OUTexa $+{'exa_src'};
close $OUTexa;
        }
    } # close PSTexa
} # close srcenv

### Subfile whit preamble
if ($subenv) {

### Extract standart environmets in subfile files
if($STDenv){
say "Creating a $envNo files whit source code and preamble for all environments";
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
} # close STDenv

### Extract PSTexample environmets in subfiles
if($PSTexa){
say "Creating a $exaNo files whit source code and preamble for all PSTexample environments";
while ($cuerpo =~ m/$BE\[.+?(?<pst_exa_name>$imageDir\/.+?-\d+)\}\]\s*(?<exa_src>.+?)\s*$EE/gms) {
open my $OUTsub, '>', "$+{'pst_exa_name'}$ext";
print $OUTsub "$sub_prea\n$+{'exa_src'}\n\\end\{document\}";
close $OUTsub;
             } # close while
        } # close $PSTexa
    } # close subenv
} # close $outsrc

### Create a one file whit all PSTexample environments
if($PSTexa){
say "Creating the temporary file $name-$prefix-exa-$tmp$ext whit $exaNo PSTexample environments extracted";
@exa_extract = undef;
while ( $cuerpo =~ m/$BE\[.+? $imageDir\/.+?-\d+\}\](?<exa_src>.+?)$EE/gmsx ) { # search $cuerpo
push @exa_extract, $+{exa_src}."\n\\newpage\n";
open my $OUTfig, '>', "$name-$prefix-exa-$tmp$ext";
    print $OUTfig "$optin"."$cabeza"."$opt_page"."@exa_extract\n"."\\end\{document\}";
close $OUTfig;
    }# close while

### Move file to /image dir
if(!$run){
say "Moving the file $name-$prefix-exa-$tmp$ext to $imageDir/$name-$prefix-exa-all$ext";
move("$workdir/$name-$prefix-exa-$tmp$ext", "$imageDir/$name-$prefix-exa-all$ext");
    }
}# close $PSTexa

### Creating one file whit all environments extracted (nopreview option)
if($STDenv){
open my $OUTfig, '>', "$name-$prefix-$tmp$ext";
if ($noprew) {
say "Creating the temporary file $name-$prefix-$tmp$ext whit $envNo environments extracted";
my @env_extract;
while ( $cuerpo =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms ) { # search $cuerpo
    push @env_extract, $+{env_src}."\n\\newpage\n";
        } # close while
print $OUTfig "$optin"."$cabeza"."$opt_page"."@env_extract\n"."\\end{document}";
    } # close noprew
else {
say "Creating the temporary file $name-$prefix-$tmp$ext whit $envNo environment extracted using preview package";
print $OUTfig $optin.$preview.$cabeza."\n".$cuerpo."\n\\end{document}";
    }
close $OUTfig;

### Move file to image dir
if(!$run){
say "Moving the file $name-$prefix-$tmp$ext to $imageDir/$name-$prefix-all$ext";
    move("$workdir/$name-$prefix-$tmp$ext", "$imageDir/$name-$prefix-all$ext");
        }
} # close $STDenv

### Define --shell-escape for TeXLive and MikTeX
my $write18 = '-shell-escape'; # TeXLive
   $write18 = '-enable-write18' if defined($ENV{"TEXSYSTEM"}) and
                          $ENV{"TEXSYSTEM"} =~ /miktex/i;

### Define --interaction=mode for compilers
my $opt_compiler = $verbose ? "$write18 -interaction=nonstopmode -recorder"
                  :           "$write18 -interaction=batchmode -recorder"
                  ;

### Define $silence
my $silence = $verbose ? ''
            :            ">$null"
            ;

### Append -q to cmd line
my $quiet = $verbose ?  ''
            :           '-q'
            ;

### Compilers
my $compiler = $xetex ?  "xelatex $opt_compiler"
             : $luatex ? "lualatex $opt_compiler"
             : $latex ?  "latex $opt_compiler"
             : $dvips ?  "latex $opt_compiler"
             : $dvipdf ? "latex $opt_compiler"
             : $arara ?  'arara'
             :           "pdflatex $opt_compiler"
             ;

### Message for compilers in cmd line
my $show_compiler = $xetex ?  'xelatex'
                  : $luatex ? 'lualatex'
                  : $latex ?  'latex>dvips>ps2pdf'
                  : $dvips ?  'latex>dvips>ps2pdf'
                  : $dvipdf ? 'latex>dvipdfmx'
                  : $arara ?  'arara'
                  :           'pdflatex'
                  ;

### Message for mode operation in cmd line
my $opt_mode = $noprew ? "$show_compiler"
             :           "$show_compiler and preview package"
             ;

### Options -sDEVICE=<device> using by GS
my %opt_gs_dev = (
    pdf  => "$gscmd $quiet -dNOSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress",
    gray => "$gscmd $quiet -dNOSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -sColorConversionStrategy=Gray -dProcessColorModel=/DeviceGray",
    png  => "$gscmd $quiet -dNOSAFER -sDEVICE=pngalpha -r$DPI",
    bmp  => "$gscmd $quiet -dNOSAFER -sDEVICE=bmp32b -r$DPI",
    jpg  => "$gscmd $quiet -dNOSAFER -sDEVICE=jpeg -r$DPI -dJPEGQ=100 -dGraphicsAlphaBits=4 -dTextAlphaBits=4",
    tif  => "$gscmd $quiet -dNOSAFER -sDEVICE=tiff32nc -r$DPI",
);

### Other options to pdftops/pdftoppm/pdf2svg...this line poppler-utils
my %opt_other_dev = (
    eps  => "pdftops $quiet -eps",
    ppm  => "pdftoppm $quiet -r $DPI",
    svg  => "pdftocairo $quiet -svg",
);

### Option for pdfcrop
my $opt_crop = $xetex ?  "--xetex --margins $margins"
             : $luatex ? "--luatex --margins $margins"
             : $latex ?  "--margins $margins"
             :           "--pdftex --margins $margins"
             ;

### Run creation a one file whit all environment
if($run){
opendir(my $DIR, $workdir);
while (readdir $DIR) {
### Compiler generate file
if (/(?<nombre>$name-$prefix(-exa)?)(?<type>-$tmp$ext)/) {
    system("$compiler $+{nombre}$+{type} $silence");
say "Compiling the file $+{nombre}$+{type} using $show_compiler";

### Compiling file using latex>dvips>ps2pdf
if($dvips or $latex){
    system("dvips -q -Ppdf -o $+{nombre}-$tmp.ps $+{nombre}-$tmp.dvi");
    system("ps2pdf  -dPDFSETTINGS=/prepress -dAutoRotatePages=/None $+{nombre}-$tmp.ps  $+{nombre}-$tmp.pdf");
    } # close latex

### Compiling file using latex>dvipdfmx
if($dvipdf){
    system("dvipdfmx -q $+{nombre}-$tmp.dvi");
    } # close dvipdf

### If option gray
if($gray){
say "Moving the file $+{nombre}-$tmp.pdf to $tempDir/$+{nombre}-all.pdf in gray scale";
system("$opt_gs_dev{gray} -o $tempDir/$+{nombre}-all.pdf $workdir/$+{nombre}-$tmp.pdf");
move("$workdir/$+{nombre}-$tmp.pdf","$tempDir/$+{nombre}-$tmp.pdf");
    }
else{
say "Moving the file $+{nombre}-$tmp.pdf to $tempDir/$+{nombre}-all.pdf";
move("$workdir/$+{nombre}-$tmp.pdf", "$tempDir/$+{nombre}-all.pdf");
}

### Crop file
if($crop){
say "The file $+{nombre}-all.pdf need a crop, using pdfcrop $opt_crop";
system("pdfcrop $opt_crop $tempDir/$+{nombre}-all.pdf $tempDir/$+{nombre}-all.pdf $silence");
}

### Move tmp file whit all source to /images dir
move("$workdir/$+{nombre}$+{type}", "$imageDir/$+{nombre}-all$ext");
        } # close if m/.../
    } # close while
closedir $DIR;
} # close run

### Append image type options
$opts_cmd{pdf} = 'pdf' if $pdf;
$opts_cmd_other{eps} = 1 if exists $resultado{options}{eps};
$opts_cmd_other{ppm} = 1 if exists $resultado{options}{ppm};
$opts_cmd_other{svg} = 1 if exists $resultado{options}{svg};
$opts_cmd{png} = 1 if exists $resultado{options}{png};
$opts_cmd{jpg} = 1 if exists $resultado{options}{jpg};
$opts_cmd{bmp} = 1 if exists $resultado{options}{bmp};

### Suported format
my %format = (%opts_cmd,%opts_cmd_other);
my $format = join " ",grep { defined $format{$_} } keys %format;

### Generate separate image files
if($run){
opendir(my $DIR, $tempDir);
while (readdir $DIR) {
### pdf png jpg bmp tif format suported in ghostscript 
if (/(?<nombre>$name-$prefix(-exa)?)(?<type>-all\.pdf)/) {
for my $var (qw(pdf png jpg bmp tif)) {
    if (defined $opts_cmd{$var}) {
    my $ghostcmd = "$opt_gs_dev{$var} -o $workdir/$imageDir/$+{nombre}-%1d.$var $tempDir/$+{nombre}$+{type}";
    system("$ghostcmd");
    print "Create a $var image format: runing command $opt_gs_dev{$var} in $+{nombre}$+{type}\r\n";
    } # close defined for ghostscript
    }# close for
} # close if m/.../

### EPS/PPM/SVG for standart images files
if (/(?<nombre>$name-$prefix)(?<type>-all\.pdf)/) {
for my $var (qw(eps ppm svg)) {
    if (defined $opts_cmd_other{$var}) {
    for (my $epsNo = 1; $epsNo <= $envNo; $epsNo++) {
my $no_ghostcmd = "$opt_other_dev{$var} -f $epsNo -l $epsNo $tempDir/$+{nombre}$+{type} $workdir/$imageDir/$+{nombre}-$epsNo.$var";
system("$no_ghostcmd");
            } # close for C style
print "Create a $var image format: runing command $opt_other_dev{$var} in $+{nombre}$+{type}\r\n";
        } #  close defined
    } # close for my $var
} # close if m/.../

### EPS/PPM/SVG for pst-exa pack
if (/(?<nombre>$name-$prefix-exa)(?<type>-all\.pdf)/) {
for my $var (qw(eps ppm svg)) {
    if (defined $opts_cmd_other{$var}) {
    for (my $epsNo = 1; $epsNo <= $exaNo; $epsNo++) {
my $no_ghostcmd = "$opt_other_dev{$var} -f $epsNo -l $epsNo $tempDir/$+{nombre}$+{type} $workdir/$imageDir/$+{nombre}-$epsNo.$var";
system("$no_ghostcmd");
                } # close for C style
print "Create a $var image format: runing command $opt_other_dev{$var} in $+{nombre}$+{type}\r\n";
            } #  close defined
        } # close for my $var
    } # close if m/.../
} # close while
closedir $DIR; #close dir

### Renaming and copy PPM format
if(defined $opts_cmd_other{ppm}){
opendir(my $DIR, $imageDir);
while (readdir $DIR) {
    if (/(?<nombre>$name-fig(-exa)?-\d+\.ppm)(?<sep>-\d+)(?<ppm>\.ppm)/) {
    move("$imageDir/$+{nombre}$+{sep}$+{ppm}", "$imageDir/$+{nombre}");
            } # close if
        } # close while
closedir $DIR;
    } # close renaming PPM
} # close run

### Create a output file
if ($outfile) {
say "Creating the file $output$ext with all extracted environments converted to images";

### Convert Postscript environments to includegraphics
my $grap="\\includegraphics[scale=1]{$name-$prefix-";
my $close = '}';
my $imgNo = 1; # counter for images

### Regex for convert environment to \includegraphics
$cuerpo =~ s/$BP.+?$EP/$grap@{[$imgNo++]}$close/msg; # changes

### Constant
my $USEPACK  	= quotemeta('\usepackage');
my $GRAPHICPATH = quotemeta('\graphicspath{');

### Precompiled regex
my $CORCHETES = qr/\[ [^]]*? \]/x;
my $PALABRAS  = qr/\b (?: graphicx )/x;
my $FAMILIA   = qr/\{ \s* $PALABRAS (?: \s* [,] \s* $PALABRAS )* \s* \}(\%*)?/x;

### Regex to capture graphicspath
my $graphix = qr/(\\ usepackage \s*\[\s* .+? \s*\] \s*\{\s* graphicx \s*\} )/ix;

### Capture graphix for future use
my (@graphix) = $cabeza =~ m/$graphix/x;

### Remove graphix
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
        ^ $USEPACK (?: $CORCHETES )? $FAMILIA \s*//msxg;

### Comment \graphicspath for order and future use
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
        ^ ($GRAPHICPATH) /%$1/msxg;

### Regex to capture options for pst-exa pack
my $pstexa     = qr/(?:\\ usepackage) \[\s*(.+?)\s*\] (?:\{\s*(pst-exa)\s*\} )   /x;

### Capture option for pst-exa
my (@pst_exa) = $cabeza =~ m/$pstexa/xg;

### Search name option in pst-exa
my %pst_exa =  map { $_ => 1 } @pst_exa;

### Clean file (pst/tags)
if($clean{pst}){
$PALABRAS  = qr/\b (?: pst-\w+ | pstricks (?: -add )? | psfrag |psgo |vaucanson-g| auto-pst-pdf )/x;
$FAMILIA   = qr/\{ \s* $PALABRAS (?: \s* [,] \s* $PALABRAS )* \s* \}(\%*)?/x;

### Remove packpage lines
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
        ^ $USEPACK (?: $CORCHETES )? $FAMILIA \s*//msxg;

### Delete packpage words
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
(?: ^ $USEPACK \{ | \G) [^}]*? \K (,?) \s* $PALABRAS (\s*) (,?) /$1 and $3 ? ',' : $1 ? $2 : ''/gemsx;

### Delete \psset
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
           \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))+//gmsx;

### Delete \SpecialCoor
$cabeza =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
        \\SpecialCoor(?:[\t ]*(?:\r?\n|\r))+//gmsx;
} # close clean{pst}

### Delete empty package line
$cabeza =~ s/^\\usepackage\{\}(?:[\t ]*(?:\r?\n|\r))+//gmsx;

### Append graphix to end of preamble
if(!@graphix == 0){
$cabeza .= <<"EXTRA";
@graphix
EXTRA
}else{
$cabeza .= <<"EXTRA";

\\usepackage{graphicx}
EXTRA
}

### Regex to capture graphicspath
my $graphicspath= qr/\\ graphicspath \{	((?: $llaves )+) \}/ix;

### If preamble contain graphicspath
if($cabeza =~ m/($graphicspath)/m){
while ($cabeza =~ /$graphicspath /pgmx) {
    my($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my $encontrado = ${^MATCH};
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

### Regex to capture
my ($GraphicsPath) = $cabeza =~ m/($graphicspath)/msx;

### Append graphicspath to end of preamble
$cabeza .= <<"EXTRA";
$GraphicsPath
\\usepackage{grfext}
\\PrependGraphicsExtensions*{.pdf}
EXTRA
} # close if ($cabeza)
else{
### If preamble not contain graphicspath, append to premble
my $GraphicsPath = "\\graphicspath\{\{$imageDir/\}\}";

### Append graphicspath to end of preamble
$cabeza .= <<"EXTRA";
$GraphicsPath
\\usepackage{grfext}
\\PrependGraphicsExtensions*{.pdf}
EXTRA
} # close graphicspath

### Suport for \usepackage[swpl]{pst-exa}
if(exists($pst_exa{swpl})){
$cabeza .= <<'EXTRA';
\usepackage[swpl,pdf]{pst-exa}
EXTRA
}

### Suport for \usepackage[tcb]{pst-exa}
if(exists($pst_exa{tcb})){
$cabeza .= <<'EXTRA';
\usepackage[tcb,pdf]{pst-exa}
EXTRA
$cuerpo =~ s/(graphic=\{)\[(scale=\d*)\]($imageDir\/$name-$prefix-exa-\d*)\}/$1$2\}\{$3\}/gsmx;
}

### Options for out_file (add $end to outfile)
my $out_file = $clean{doc} ? "$optin$cabeza$cuerpo\n\\end\{document\}"
              :              "$optin$cabeza$cuerpo\n$final"
              ;

### Clean \psset content in output file
if($clean{pst}){
$out_file  =~s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
        \%<\*ltximgverw> .+? \%<\/ltximgverw>(*SKIP)(*F)|
           \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
}

### Clean \tikzset content in output file
if($clean{tkz}){
$out_file  =~s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
        \%<\*ltximgverw> .+? \%<\/ltximgverw>(*SKIP)(*F)|
           \\tikzset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
}

### Back changues in all words in outfile
$out_file =~s/\\begin\{nopreview\}\s*(.+?)\s*\\end\{nopreview\}/$1/gmsx;
$out_file =~s/\%<\*ltximgverw>\s*(.+?)\s*\%<\/ltximgverw>/$1/gmsx;
$out_file =~s/\%<\*noltximg>\n(.+?)\n\%<\/noltximg>/$1/gmsx;
$out_file =~s/^\%<\*remove>\s*(.+?)\s*\%<\/remove>(?:[\t ]*(?:\r?\n|\r))+//gmsx;
$out_file =~ s/($delt_env)(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
$out_file =~s/($find)/$replace{$1}/g;

### Write output file
open my $OUTfile, '>', "$output$ext";
print   $OUTfile "$out_file";
close $OUTfile;

### Compile output file
if($run){
### If input file using latex otputfile using pdflatex
$compiler = "pdflatex $opt_compiler" if $latex;
$show_compiler = "pdflatex" if $latex;

### Message for mode operation in cmd line
say "Compiling the file $output$ext using $show_compiler";

### Compiling output file
system("$compiler $output$ext $silence");

### Compiling file using latex>dvips>ps2pdf
if($dvips){
    system("dvips -q -Ppdf $output.dvi");
    system("ps2pdf  -dPDFSETTINGS=/prepress -dAutoRotatePages=/None $output.ps  $output.pdf");
} # close dvips

### Compiling file using latex>dvipdfmx
if($dvipdf){
    system("dvipdfmx -q $output.dvi");
           } # close dvipdf
      } # close run
} # close outfile file

### Clean tmp files
if($run){
say "Removing temporary files creating";
my @protected = qw();
push (@protected,"$output$ext","$output.pdf") if defined $output;

my $flsline = "OUTPUT";
my @flsfile;

if ($PSTexa) {
push @flsfile,"$name-$prefix-exa-$tmp.fls";
}

if ($STDenv) {
push @flsfile,"$name-$prefix-$tmp.fls";
}

push(@flsfile,"$output.fls") if defined $output;

my @tmpfiles;
for my $filename(@flsfile){
    open my $RECtmp, '<', "$filename";
    push @tmpfiles, grep /^$flsline/,<$RECtmp>;
    close $RECtmp;
}

foreach (@tmpfiles) {
    s/^$flsline\s+|\s+$//g;
    }

if($latex or $dvips){
push @tmpfiles,"$name-$prefix-$tmp.ps";
    }

if ($PSTexa) {
push @tmpfiles,"$name-$prefix-exa-$tmp.ps";
}

if($dvips){
push @tmpfiles,"$output.ps";
    }

push @tmpfiles,@flsfile,"$name-$prefix-$tmp$ext","$name-$prefix-$tmp.pdf";

my @delfiles = array_minus(@tmpfiles, @protected);

foreach my $tmpfile (@delfiles){
   move("$tmpfile", "$tempDir");
    }
} # close clean tmp files

### End of script work
if($run){
say "Finish, image formats: $format are in $workdir/$imageDir/";
    }
else{
say "Done";
    }

__END__

## CHANGES
 v1.5. (d)  2017-11-27 - Validate string list options
                       - Changue pdf2svg for pdftocairo
                       - Changue tab for space in code
                       - Move Changues to end of code
                       - Add some comments to --help
 v1.5. (d)  2017-09-11 - Remove qw(:all) from autodie (dev>null problem)
 v1.5. (d)  2017-05-18 - Complete suport for pst-exa pack
                       - Clean take and optional
                       - use autodie qw(:all)
 v1.5. (d)  2017-02-08 - Append suport partial for pst-exa pack
 v1.5. (d)  2017-02-02 - Append arara compiler, clean and comment code
 v1.5. (d)  2017-02-01 - Clean un code, new regex and optimitation
 v1.5. (d)  2017-01-31 - Rewrite clean tmp, add options to tiff, bmp
                       - Append dvips and dvipdfm for creation images
 v1.4.1(d)  2016-11-29 - Remove and rewrite code for regex and system call
 v1.4  (d)  2016-11-29 - Append bmp, tif format
 v1.3.1(d)  2016-10-16 - All options its read from cmd line and input file
 v1.3  (d)  2016-08-14 - Rewrite some part of code , norun, nocrop, clean
                       - Suport minted and tcolorbox packpage for verbatim
                       - Use tmp dir for work
                       - Escape some characters in regex according to v5.2xx
 v1.2  (p)  2015-04-22 - Remove unused modules
 v1.1  (p)  2015-04-21 - Change mogrify to gs for image formats
                       - Create output file
                       - Rewrite source code and fix regex
                       - Add more image format
                       - Change date to iso format
 v1.0  (p)  2013-12-01 - First public release
