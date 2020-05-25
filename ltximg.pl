#!/usr/bin/env perl
use v5.26;

############################# LICENCE ##################################
# This program is free software; you can redistribute it and/or modify #
# it under the terms of the GNU General Public License as published by #
# the Free Software Foundation; either version 3 of the License, or    #
# (at your option) any later version.                                  #
#                                                                      #
# This program is distributed in the hope that it will be useful, but  #
# WITHOUT ANY WARRANTY; without even the implied warranty of           #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU    #
# General Public License for more details.                             #
########################################################################

use Getopt::Long qw(:config bundling_values require_order no_ignore_case);
use File::Spec::Functions qw(catfile);
use File::Basename;
use Archive::Tar;
use Data::Dumper;
use FileHandle;
use IO::Compress::Zip qw(:all);
use File::Path qw(remove_tree);
use File::Temp qw(tempdir);
use POSIX qw(strftime);
use File::Copy;
use File::Find;
use autodie;
use Config;
use Cwd;

### Directory for work and temp files
my $tempDir = tempdir( CLEANUP => 1);
my $workdir = cwd;

### Real script name
my $scriptname = 'ltximg';

### Script identification
my $program   = 'LTXimg';
my $nv        = 'v1.8';
my $date      = '2020-05-24';
my $copyright = <<"END_COPYRIGHT" ;
[$date] (c) 2013-2020 by Pablo Gonzalez, pablgonz<at>yahoo.com
END_COPYRIGHT

my $title = "$program $nv $copyright";

### Log vars
my $LogFile = "$scriptname.log";
my $LogWrite;
my $LogTime = strftime("%y/%m/%d %H:%M:%S", localtime);

### Default values
my $skiptag  = 'noltximg'; # internal tag for regex
my $extrtag  = 'ltximg';   # internal tag for regex
my @extr_env_tmp;          # save extract environments
my @skip_env_tmp;          # save skip environments
my @verb_env_tmp;          # save verbatim environments
my @verw_env_tmp;          # save verbatim write environments
my @delt_env_tmp;          # save delete environments in output file
my @clean;                 # clean document options
my $outfile  = 0;          # write output file
my $outsrc   = 0;          # write src environment files
my $PSTexa   = 0;          # run extract PSTexample environments
my $STDenv   = 0;          # run extract standart environments
my $verbose  = 0;          # verbose info
my $gscmd;                 # ghostscript command name
my $log      = 0;          # log file
my @currentopt;            # storing current options for log file

### Hash to store Getopt::Long options
my %opts_cmd;
$opts_cmd{string}{prefix} = 'fig';
$opts_cmd{string}{dpi}    = '150';
$opts_cmd{string}{margin} = '0';
$opts_cmd{string}{imgdir} = 'images';
$opts_cmd{string}{myverb} = 'myverb';
$opts_cmd{clean}          = 'doc';

### Error in command line
sub errorUsage { die "@_ (run ltximg --help for more information)\n"; }

### Extended error messages
sub exterr () {
    chomp(my $msg_errno = $!);
    chomp(my $msg_extended_os_error = $^E);
    if ($msg_errno eq $msg_extended_os_error) {
        $msg_errno;
    }
    else {
        "$msg_errno/$msg_extended_os_error";
    }
}

### Funtion uniq
sub uniq {
    my %seen;
    return grep !$seen{$_}++, @_;
}

### Funtion array_minus
sub array_minus(\@\@) {
    my %e = map{ $_ => undef } @{$_[1]};
    return grep !exists $e{$_}, @{$_[0]};
}

### Funtion to create hash begin -> BEGIN, end -> END
sub crearhash {
    my %cambios;
    for my $aentra(@_){
        for my $initend (qw(begin end)) {
            $cambios{"\\$initend\{$aentra"} = "\\\U$initend\E\{$aentra";
            }
        }
    return %cambios;
}

### Write Log line and print msg (common)
sub Infoline {
    my $msg = shift;
    my $now  = strftime("%y/%m/%d %H:%M:%S", localtime);
    if ($log) { $LogWrite->print(sprintf "[%s] * %s\n", $now, $msg); }
    say $msg;
    return;
}

### Write Log line (no print msg and time stamp)
sub Logline {
    my $msg = shift;
    if ($log) { $LogWrite->print("$msg\n"); }
    return;
}

### Write Log line (time stamp)
sub Log {
    my $msg = shift;
    my $now  = strftime("%y/%m/%d %H:%M:%S", localtime);
    if ($log) { $LogWrite->print(sprintf "[%s] * %s\n", $now, $msg); }
    return;
}

### Write array env in Log
sub Logarray {
    my ($env_ref) = @_;
    my @env_tmp = @{ $env_ref }; # dereferencing and copying each array
    if ($log) {
        if (@env_tmp) {
            my $tmp  = join "\n", map { qq/* $_/ } @env_tmp;
            print {$LogWrite} "$tmp\n";
        }
        else {
            print {$LogWrite} "Not found\n";
        }
    }
    return;
}

### Extended print info for execute system commands using $ command
sub Logrun {
    my $msg = shift;
    my $now  = strftime("%y/%m/%d %H:%M:%S", localtime);
    if ($log) { $LogWrite->print(sprintf "[%s] \$ %s\n", $now, $msg); }
    if ($verbose) { print "* Running: $msg\r\n"; }
    return;
}

### Capture and execute system commands
sub RUNOSCMD {
    my $cmdname = shift;
    my $argcmd  = shift;
    my $captured = "$cmdname $argcmd";
    Logrun($captured);
    $captured = qx{$captured};
    if ($log) { $LogWrite->print($captured); }
    if ($? == -1) {
        print $captured;
        $cmdname = "* Error!!: ".$cmdname." failed to execute (%s)!\n";
        if ($log) { $LogWrite->print(sprintf "$cmdname", exterr); }
        die sprintf "$cmdname", exterr;
    } elsif ($? & 127) {
        $cmdname = "* Error!!: ".$cmdname." died with signal %d!\n";
        if ($log) { $LogWrite->print(sprintf "$cmdname", ($? & 127)); }
        die sprintf "$cmdname", ($? & 127);
    } elsif ($? != 0 ) {
        $cmdname = "* Error!!: ".$cmdname." exited with error code %d!\n";
        if ($log) { $LogWrite->print(sprintf "$cmdname", $? >> 8); }
        die sprintf "$cmdname",$? >> 8;
    }
    if ($verbose) { print $captured; }
    return;
}

### Help for command line
sub usage ($) {
find_ghostscript();

my $usage = <<"END_OF_USAGE";
${title}** Description
   LTXimg is a "perl" script that automates the process of extracting and
   converting "environments" provided by tikz, pstricks and other packages
   from LaTeX file to image formats and "standalone files" using ghostscript
   and poppler-utils. Generates a one file with only extracted environments
   and other with all extracted environments converted to \\includegraphics.

** Syntax
\$ ltximg [<compiler>] [<options>] [--] <filename>.<tex|ltx>

   Relative or absolute paths for directories and files is not supported.
   Options that accept a value require either a blank space or = between
   the option and the value. Multiple short options can be bundling and
   if the last option takes a comma separated list you need -- at the end.

** Usage
\$ ltximg --latex [<options>] <file.tex>
\$ ltximg --arara [<options>] <file.tex>
\$ ltximg [<options>] <file.tex>
\$ ltximg <file.tex>

   If used without [<compiler>] and [<options>] the extracted environments
   are converted to pdf image format and saved in the "./images" directory
   using "pdflatex" and "preview" package.

** Default environments extract
   preview pspicture tikzpicture pgfpicture psgraph postscript PSTexample

** Options
                                                                    [default]
-h, --help            Display command line help and exit            [off]
-v, --version         Display current version ($nv) and exit       [off]
-V, --verbose         Verbose printing information                  [off]
-l, --log             Write .log file with debug information        [off]
-t, --tif             Create .tif files using ghostscript           [$gscmd]
-b, --bmp             Create .bmp files using ghostscript           [$gscmd]
-j, --jpg             Create .jpg files using ghostscript           [$gscmd]
-p, --png             Create .png files using ghostscript           [$gscmd]
-e, --eps             Create .eps files using poppler-utils         [pdftops]
-s, --svg             Create .svg files using poppler-utils         [pdftocairo]
-P, --ppm             Create .ppm files using poppler-utils         [pdftoppm]
-g, --gray            Gray scale for images using ghostscript       [off]
-f, --force           Capture "\\psset" and "\\tikzset" to extract    [off]
-n, --noprew          Create images files whitout "preview" package [off]
-d <integer>, --dpi <integer>
                      Dots per inch resolution for images           [150]
-m <integer>, --margin <integer>
                      Set margins in bp for pdfcrop                 [0]
-o <filename>, --output <filename>
                      Create output file                            [off]
--imgdir <dirname>    Set name of directory to save images/files    [images]
--prefix <string>     Set prefix append to each generated files     [fig]
--myverb <macroname>  Add "\\macroname" to verbatim inline search    [myverb]
--clean (doc|pst|tkz|all|off)
                      Removes specific block text in output file    [doc]
--zip                 Compress files generated in .zip              [off]
--tar                 Compress files generated in .tar.gz           [off]
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
--nocrop              Don't run pdfcrop                             [off]
--norun               Run script, but no create images files        [off]
--nopdf               Don't create a ".pdf" image files             [off]
--extrenv <env1,...>  Add new environments to extract               [empty]
--skipenv <env1,...>  Skip default environments to extract          [empty]
--verbenv <env1,...>  Add new verbatim environments                 [empty]
--writenv <env1,...>  Add new verbatim write environments           [empty]
--deltenv <env1,...>  Delete environments in output file            [empty]

** Example
\$ ltximg --latex -e -p --srcenv --imgdir=mypics -o test-out test-in.ltx
\$ ltximg --latex -ep --srcenv --imgdir mypics -o test-out.ltx  test-in.ltx

   Create a "./mypics" directory (if it doesn’t exist) whit all extracted
   environments converted to individual files (.pdf, .eps, .png, .ltx), a
   file "test-in-fig-all.ltx" whit all extracted environments and the file
   "test-out.ltx" with all environments converted to \\includegraphics using
   latex>dvips>ps2pdf and preview package for <input file> and pdflatex for
   <output file>.

** Documentation
For full documentation use:
\$ texdoc ltximg

** Issues and reports
Repository   : https://github.com/pablgonz/ltximg
Bug tracker  : https://github.com/pablgonz/ltximg/issues
END_OF_USAGE
print $usage;
exit 0;
}

### Getopt configuration
my $result=GetOptions (
# image options
    'b|bmp'          => \$opts_cmd{image}{bmp}, # gs
    't|tif'          => \$opts_cmd{image}{tif}, # gs
    'j|jpg'          => \$opts_cmd{image}{jpg}, # gs
    'p|png'          => \$opts_cmd{image}{png}, # gs
    's|svg'          => \$opts_cmd{image}{svg}, # pdftocairo
    'e|eps'          => \$opts_cmd{image}{eps}, # pdftops
    'P|ppm'          => \$opts_cmd{image}{ppm}, # pdftoppm
# compilers
    'arara'          => \$opts_cmd{compiler}{arara},  # arara compiler
    'xetex'          => \$opts_cmd{compiler}{xetex},  # xelatex compiler
    'latex'          => \$opts_cmd{compiler}{latex},  # latex compiler
    'dvips'          => \$opts_cmd{compiler}{dvips},  # dvips compiler
    'luatex'         => \$opts_cmd{compiler}{luatex}, # lualatex compiler
    'dvipdf'         => \$opts_cmd{compiler}{dvipdf}, # dvipdfmx compiler
# bolean
    'zip'            => \$opts_cmd{boolean}{zip},    # zip images dir
    'tar'            => \$opts_cmd{boolean}{tar},    # tar images dir
    'nopdf'          => \$opts_cmd{boolean}{nopdf},  # no pdf image format
    'norun'          => \$opts_cmd{boolean}{norun},  # no run compiler
    'nocrop'         => \$opts_cmd{boolean}{nocrop}, # no run pdfcrop
    'subenv'         => \$opts_cmd{boolean}{subenv}, # subfile environments (bolean)
    'srcenv'         => \$opts_cmd{boolean}{srcenv}, # source files (bolean)
    'g|gray'         => \$opts_cmd{boolean}{gray},   # gray (boolean)
    'f|force'        => \$opts_cmd{boolean}{force},  # force (boolean)
    'n|noprew'       => \$opts_cmd{boolean}{noprew}, # no preview (boolean)
# string
    'd|dpi=i'        => \$opts_cmd{string}{dpi},    # integer
    'm|margin=i'     => \$opts_cmd{string}{margin}, # integer
    'extrenv=s{1,9}' => \@extr_env_tmp, # extract environments
    'skipenv=s{1,9}' => \@skip_env_tmp, # skip environments
    'verbenv=s{1,9}' => \@verb_env_tmp, # verbatim environments
    'writenv=s{1,9}' => \@verw_env_tmp, # verbatim write environments
    'deltenv=s{1,9}' => \@delt_env_tmp, # delete environments
    'o|output=s{1}'  => \$opts_cmd{string}{output}, # output file name (string)
    'imgdir=s{1}'    => \$opts_cmd{string}{imgdir}, # images dir name
    'verbcmd=s{1}'   => \$opts_cmd{string}{myverb}, # \myverb inline (string)
    'prefix=s{1}'    => \$opts_cmd{string}{prefix}, # prefix
    'clean=s{1}'     => \$opts_cmd{clean},          # clean output file
# internal
    'h|help'         => \$opts_cmd{internal}{help},    # help
    'v|version'      => \$opts_cmd{internal}{version}, # version
    'l|log'          => \$log,     # write log file
    'V|verbose'      => \$verbose, # verbose mode
    ) or do { $log = 0 ; die usage(0); };

### Open log file
if ($log) {
    if (!defined $ARGV[0]) { errorUsage '* Error!!: Input filename missing'; }
    my $tempname = $ARGV[0];
    $tempname =~ s/\.(tex|ltx)$//;
    if ($LogFile eq "$tempname.log") { $LogFile = "$scriptname-log.log"; }
    $LogWrite  = FileHandle->new("> $LogFile");
}

### Init log file
Log("$scriptname $nv was started in $workdir");
Log("Creating the temporary directory $tempDir");

### The next code it's part of pdfcrop (adapted from TexLive 2014)
Log('General information about the Perl instalation');
# Windows detection
my $Win = 0;
$Win = 1 if $^O =~ /mswin32/i;
$Win = 1 if $^O =~ /cygwin/i;

my $archname = $Config{'archname'};
$archname = 'unknown' unless defined $Config{'archname'};

# Get ghostscript command name
sub find_ghostscript () {
    return if $gscmd;
    if ($log) {
        print {$LogWrite} "* Perl executable: $^X\n";
        if ($] < 5.006) {
            print {$LogWrite} "* Perl version: $]\n";
        }
        else {
            printf {$LogWrite} "* Perl version: v%vd\n", $^V;
        }
        if (defined &ActivePerl::BUILD) {
            printf {$LogWrite} "* Perl product: ActivePerl, build %s\n", ActivePerl::BUILD();
        }
        printf {$LogWrite} "* Pointer size: $Config{'ptrsize'}\n";
        printf {$LogWrite} "* Pipe support: %s\n",
                (defined($Config{'d_pipe'}) ? 'yes' : 'no');
        printf {$LogWrite} "* Fork support: %s\n",
                (defined($Config{'d_fork'}) ? 'yes' : 'no');
    }
    my $system = 'unix';
    $system = "dos" if $^O =~ /dos/i;
    $system = "os2" if $^O =~ /os2/i;
    $system = "win" if $^O =~ /mswin32/i;
    $system = "cygwin" if $^O =~ /cygwin/i;
    $system = "miktex" if defined $ENV{"TEXSYSTEM"} and
                          $ENV{"TEXSYSTEM"} =~ /miktex/i;
    if ($log) {
        print {$LogWrite} "* OS name: $^O\n";
        print {$LogWrite} "* Arch name: $archname\n";
        print {$LogWrite} "* System: $system\n";
    }
    Log("General information about the Ghostscript");
    my %candidates = (
        'unix'   => [qw|gs gsc|],
        'dos'    => [qw|gs386 gs|],
        'os2'    => [qw|gsos2 gs|],
        'win'    => [qw|gswin32c gs|],
        'cygwin' => [qw|gs gswin32c|],
        'miktex' => [qw|mgs gswin32c gs|],
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
        'unix'   => q{},
        'dos'    => '.exe',
        'os2'    => '.exe',
        'win'    => '.exe',
        'cygwin' => '.exe',
        'miktex' => '.exe',
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
                if ($log) { print {$LogWrite} "* Found ($candidate): $file\n"; }
                last;
            }
            if ($log) { print {$LogWrite} "* Not found ($candidate): $file\n"; }
        }
        last if $found;
    }
    if (not $found and $Win) {
        $found = SearchRegistry();
    }
    if ($found) {
        if ($log) { print {$LogWrite} "* Autodetected ghostscript command: $gscmd\n"; }
    }
    else {
        $gscmd = $$candidates_ref[0];
        if ($log) { print {$LogWrite} "* Default ghostscript command: $gscmd\n"; }
    }
}

sub SearchRegistry () {
    my $found = 0;
    eval 'use Win32::TieRegistry qw|KEY_READ REG_SZ|;';
    if ($@) {
        if ($log) {
            print {$LogWrite} "* Registry lookup for Ghostscript failed:\n";
            my $msg = $@;
            $msg =~ s/\s+$//;
            foreach (split /\r?\n/, $msg) {
                print " $_\n";
            }
        }
        return $found;
    }
    my $open_params = {Access => KEY_READ(), Delimiter => q{/}};
    my $key_name_software = 'HKEY_LOCAL_MACHINE/SOFTWARE/';
    my $current_key = $key_name_software;
    my $software = new Win32::TieRegistry $current_key, $open_params;
    if (not $software) {
        if ($log) {
            print {$LogWrite} "* Cannot find or access registry key `$current_key'!\n";
        }
        return $found;
    }
    if ($log) { print {$LogWrite} "* Search registry at `$current_key'.\n"; }
    my %list;
    foreach my $key_name_gs (grep /Ghostscript/i, $software->SubKeyNames()) {
        $current_key = "$key_name_software$key_name_gs/";
        if ($log) { print {$LogWrite} "* Registry entry found: $current_key\n"; }
        my $key_gs = $software->Open($key_name_gs, $open_params);
        if (not $key_gs) {
            if ($log) { print {$LogWrite} "* Cannot open registry key `$current_key'!\n"; }
            next;
        }
        foreach my $key_name_version ($key_gs->SubKeyNames()) {
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            if ($log) { print {$LogWrite} "* Registry entry found: $current_key\n"; }
            if (not $key_name_version =~ /^(\d+)\.(\d+)$/) {
                if ($log) { print {$LogWrite} "  The sub key is not a version number!\n"; }
                next;
            }
            my $version_main = $1;
            my $version_sub = $2;
            $current_key = "$key_name_software$key_name_gs/$key_name_version/";
            my $key_version = $key_gs->Open($key_name_version, $open_params);
            if (not $key_version) {
                if ($log) { print {$LogWrite} "* Cannot open registry key `$current_key'!\n"; }
                next;
            }
            $key_version->FixSzNulls(1);
            my ($value, $type) = $key_version->GetValue('GS_DLL');
            if ($value and $type == REG_SZ()) {
                if ($log) { print {$LogWrite} "  GS_DLL = $value\n"; }
                $value =~ s|([\\/])([^\\/]+\.dll)$|$1gswin32c.exe|i;
                my $value64 = $value;
                $value64 =~ s/gswin32c\.exe$/gswin64c.exe/;
                if ($archname =~ /mswin32-x64/i and -f $value64) {
                    $value = $value64;
                }
                if (-f $value) {
                    if ($log) { print {$LogWrite} "EXE found: $value\n"; }
                }
                else {
                    if ($log) { print {$LogWrite} "EXE not found!\n"; }
                    next;
                }
                my $sortkey = sprintf '%02d.%03d %s',
                        $version_main, $version_sub, $key_name_gs;
                $list{$sortkey} = $value;
            }
            else {
                if ($log) { print {$LogWrite} "Missing key `GS_DLL' with type `REG_SZ'!\n"; }
            }
        }
    }
    foreach my $entry (reverse sort keys %list) {
        $gscmd = $list{$entry};
        if ($log) { print {$LogWrite} "* Found (via registry): $gscmd\n"; }
        $found = 1;
        last;
    }
    return $found;
} # end GS search

### Call GS
find_ghostscript();

### If windows
if ($Win and $gscmd =~ /\s/) { $gscmd = "\"$gscmd\"";}

### Help
if (defined $opts_cmd{internal}{help}) {
    usage(1);
    exit 0;
}

### Version
if (defined $opts_cmd{internal}{version}) {
    print $title;
    exit 0;
}

### Check the input file from command line
@ARGV > 0 or errorUsage '* Error!!: Input filename missing';
@ARGV < 2 or errorUsage '* Error!!: Unknown option or too many input files';

### Check input file extention
my @SuffixList = ('.tex', q{}, '.ltx'); # posibles
my ($name, $path, $ext) = fileparse($ARGV[0], @SuffixList);
$ext = '.tex' if not $ext;

### Read input file in memory
Log("Read input file $name$ext in memory");
open my $INPUTfile, '<:crlf', "$name$ext";
    my $ltxfile;
        {
            local $/;
            $ltxfile = <$INPUTfile>;
        }
close $INPUTfile;

### Set tmp random number for name-fig-tmp and others
my $tmp = int(rand(10000));

### Identification message in terminal
print $title;

### Remove white space and '=' in array captured from command line
s/^\s*(\=):?|\s*//mg foreach @extr_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @skip_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @verb_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @verw_env_tmp;
s/^\s*(\=):?|\s*//mg foreach @delt_env_tmp;

### Split comma separte list options from command line
@extr_env_tmp = split /,/,join q{},@extr_env_tmp;
@skip_env_tmp = split /,/,join q{},@skip_env_tmp;
@verb_env_tmp = split /,/,join q{},@verb_env_tmp;
@verw_env_tmp = split /,/,join q{},@verw_env_tmp;
@delt_env_tmp = split /,/,join q{},@delt_env_tmp;

### Validate environments options from comand line
if (grep /(^\-|^\.).*?/, @extr_env_tmp) {
    Log('Error!!: Invalid argument for --extrenv, some argument from list begin with -');
    die errorUsage '* Error!!: Invalid argument for --extrenv option';
}
if (grep /(^\-|^\.).*?/, @skip_env_tmp) {
    Log('Error!!: Invalid argument for --skipenv, some argument from list begin with -');
    die errorUsage '* Error!!: Invalid argument for --skipenv option';
}
if (grep /(^\-|^\.).*?/, @verb_env_tmp) {
    Log('Error!!: Invalid argument for --verbenv, some argument from list begin with -');
    die errorUsage '* Error!!: Invalid argument for --verbenv option';
}
if (grep /(^\-|^\.).*?/, @verw_env_tmp) {
    Log('Error!!: Invalid argument for --writenv, some argument from list begin with -');
    die errorUsage '* Error!!: Invalid argument for --writenv option';
}
if (grep /(^\-|^\.).*?/, @delt_env_tmp) {
    Log('Error!!: Invalid argument for --deltenv, some argument from list begin with -');
    die errorUsage '* Error!!: Invalid argument for --deltenv option';
}

### Default environment to extract
my @extr_tmp = qw (
    postscript tikzpicture pgfpicture pspicture psgraph PSTexample
    );
push @extr_env_tmp, @extr_tmp;

### Default verbatim environment
my @verb_tmp = qw (
    Example CenterExample SideBySideExample PCenterExample PSideBySideExample
    verbatim Verbatim BVerbatim LVerbatim SaveVerbatim PSTcode
    LTXexample tcblisting spverbatim minted listing lstlisting
    alltt comment chklisting verbatimtab listingcont boxedverbatim
    demo sourcecode xcomment pygmented pyglist program programl
    programL programs programf programsc programt
    );
push @verb_env_tmp, @verb_tmp;

### Default verbatim write environment
my @verbw_tmp = qw (
    scontents filecontents tcboutputlisting tcbexternal tcbwritetmp extcolorbox extikzpicture
    VerbatimOut verbatimwrite filecontentsdef filecontentshere filecontentsdefmacro
    filecontentsdefstarred filecontentsgdef filecontentsdefmacro filecontentsgdefmacro
    );
push @verw_env_tmp, @verbw_tmp;

########################################################################
# One problem that can arise is the filecontents environment, this can #
# contain a complete document and be anywhere, before dividing we will #
# make some replacements for this and comment lines                    #
########################################################################

### Create a Regex for verbatim write environment
@verw_env_tmp = uniq(@verw_env_tmp);
my $tmpverbw = join q{|}, map { quotemeta } sort { length $a <=> length $b } @verw_env_tmp;
$tmpverbw = qr/$tmpverbw/x;
my $tmp_verbw = qr {
                     (
                       (?:
                         \\begin\{$tmpverbw\*?\}
                           (?:
                             (?>[^\\]+)|
                             \\
                             (?!begin\{$tmpverbw\*?\})
                             (?!end\{$tmpverbw\*?\})|
                             (?-1)
                           )*
                         \\end\{$tmpverbw\*?\}
                       )
                     )
                   }x;

### A pre-regex for comment lines
my $tmpcomment = qr/^ \s* \%+ .+? $ /mx;

### Hash for replace in verbatim's and comment lines
my %document = (
    '\begin{document}' => '\BEGIN{document}',
    '\end{document}'   => '\END{document}',
    '\documentclass'   => '\DOCUMENTCLASS',
    '\pagestyle{'      => '\PAGESTYLE{',
    '\thispagestyle{'  => '\THISPAGESTYLE{',
    );

### Changes in input file for verbatim write and comment lines
while ($ltxfile =~ / $tmp_verbw | $tmpcomment /pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my  $encontrado = ${^MATCH};
        while (my($busco, $cambio) = each %document) {
            $encontrado =~ s/\Q$busco\E/$cambio/g;
        }
        substr $ltxfile, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos ($ltxfile) = $pos_inicial + length $encontrado;
}

### Now, split input file in $atbegindoc and contain % ltximg : <argument>
my ($atbegindoc, $document) = $ltxfile =~ m/\A (\s* .*? \s*) (\\documentclass.*)\z/msx;

### Capture options in preamble of input file
# % ltximg : extrenv : {extrenv1, extrenv2, ... , extrenvn}
# % ltximg : skipenv : {skipenv1, skipenv2, ... , skipenvn}
# % ltximg : verbenv : {verbwrt1, verbwrt2, ... , verbwrtn}
# % ltximg : writenv : {verbwrt1, verbwrt2, ... , verbwrtn}
# % ltximg : deltenv : {deltenv1, deltenv2, ... , deltenvn}
# % ltximg : options : {opt1=arg, opt2=arg, ... , booleans}

my $readoptfile = qr/
    ^ %+ \s* ltximg (?&SEPARADOR) (?<clave>(?&CLAVE)) (?&SEPARADOR) \{ (?<argumentos>(?&ARGUMENTOS)) \}
    (?(DEFINE)
    (?<CLAVE>      \w+       )
    (?<ARGUMENTOS> .+?       )
    (?<SEPARADOR>  \s* : \s* )
    )
/mx;

### Search options in input file and store in %opts_file
my %opts_file;
while ($atbegindoc =~ /$readoptfile/g) {
    my ($clave, $argumentos) = @+{qw(clave argumentos)};
    my  @argumentos = split /\s*,\s*?/, $argumentos;
    for (@argumentos) { s/^ \s* | \s* $//gx; }
        if  ($clave eq 'options') {
            for my $argumento (@argumentos) {
                if ($argumento =~ /(?<key>\S+) \s* = \s* (?<valor>\S+)/x) {
                    $opts_file{$clave}{$+{'key'}} = $+{'valor'};
                }
                else {
                    $opts_file{$clave}{$argumento} = 1;
                }
            }
        }
        else {
            push @{ $opts_file{ $clave } }, @argumentos;
    }
}

### Process options from input file (if exist)
if(%opts_file) {
    Log("Searching options for script in $name$ext");
    # Add extract options from input file
    if (exists $opts_file{extrenv}) {
        Infoline("Found \% ltximg\: extrenv\: \{...\} in $name$ext");
        if (grep /(^\-|^\.).*?/, @{$opts_file{extrenv}}) {
            Log('Error!!: Invalid argument for % ltximg: extrenv: {...}, some argument from list begin with -');
            die errorUsage '* Error!!: Invalid argument in % ltximg: extrenv: {...}';
        }
        Logarray(\@{$opts_file{extrenv}});
        push @extr_env_tmp, @{$opts_file{extrenv}};
    }
    # Add skipenv options from input file
    if (exists $opts_file{skipenv}) {
        Infoline("Found \% ltximg\: skipenv\: \{...\} in $name$ext");
        if (grep /(^\-|^\.).*?/, @{$opts_file{skipenv}}) {
            Log('Error!!: Invalid argument for % ltximg: skipenv: {...}, some argument from list begin with -');
            die errorUsage '* Error!!: Invalid argument in % ltximg: skipenv: {...}';
        }
        Logarray(\@{$opts_file{skipenv}});
        push @skip_env_tmp, @{$opts_file{skipenv}};
    }
    # Add verbenv options from input file
    if (exists $opts_file{verbenv}) {
        Infoline("Found \% ltximg\: verbenv\: \{...} in $name$ext");
        if (grep /(^\-|^\.).*?/, @{$opts_file{verbenv}}) {
            Log('Error!!: Invalid argument for % ltximg: verbenv: {...}, some argument from list begin with -');
            die errorUsage '* Error!!: Invalid argument in % ltximg: verbenv: {...}';
        }
        Logarray(\@{ $opts_file{verbenv}});
        push @verb_env_tmp, @{$opts_file{verbenv}};
    }
    # Add writenv options from input file
    if (exists $opts_file{writenv}) {
        Infoline("Found \% ltximg\: writenv\: \{...\} in $name$ext");
        if (grep /(^\-|^\.).*?/, @{ $opts_file{writenv}}) {
            Log('Error!!: Invalid argument for % ltximg: writenv: {...}, some argument from list begin with -');
            die errorUsage '* Error!!: Invalid argument in % ltximg: writenv: {...}';
        }
        Logarray(\@{ $opts_file{writenv}});
        push @verw_env_tmp, @{$opts_file{writenv}};
    }
    # Add deltenv options from input file
    if (exists $opts_file{deltenv}) {
        Infoline("Found \% ltximg\: deltenv\: \{...\} in $name$ext");
        if (grep /(^\-|^\.).*?/, @{$opts_file{deltenv}}) {
            Log('Error!!: Invalid argument for % ltximg: deltenv: {...}, some argument from list begin with -');
            die errorUsage '* Error!!: Invalid argument in % ltximg: deltenv: {...}';
        }
        Logarray(\@{ $opts_file{deltenv}});
        push @delt_env_tmp, @{$opts_file{deltenv}};
    }
    # Add all other options from input file
    if (exists $opts_file{options}) {
        Infoline("Found \% ltximg\: options\: \{...\} in $name$ext");
        # Add compilers from input file
        for my $opt (qw(arara xetex latex dvips dvipdf)) {
            if (exists $opts_file{options}{$opt}) {
                Infoline("Found [$opt] compiler option in $name$ext");
                $opts_cmd{compiler}{$opt} = 1;
            }
        }
        # Add image options
        for my $opt (qw(eps ppm svg png jpg bmp tif)) {
            if (exists $opts_file{options}{$opt}) {
                Infoline("Found [$opt] image option in $name$ext");
                $opts_cmd{image}{$opt} = 1;
            }
        }
        # Add boolean options
        for my $opt (qw(nopdf norun nocrop srcenv subenv zip tar gray force noprew)) {
            if (exists $opts_file{options}{$opt}) {
                Infoline("Found [$opt] option in $name$ext");
                $opts_cmd{boolean}{$opt} = 1;
            }
        }
        # Add string options
        for my $opt (qw(dpi myverb margins prefix imgdir output)) {
            if (exists $opts_file{options}{$opt}) {
                Infoline("Found [$opt = $opts_file{options}{$opt}] in $name$ext");
                $opts_cmd{string}{$opt} = $opts_file{options}{$opt};
            }
        }
        # Add clean option
        for my $opt (qw(doc off pst tkz all)) {
            if ($opts_file{options}{clean} eq "$opt" ) {
                Infoline("Found [clean = $opt] in $name$ext");
                $opts_cmd{clean} = $opt;
            }
        }
    }
}

### Validate  verbcmd = macro option
if (defined $opts_cmd{string}{myverb}) {
    if ($opts_cmd{string}{myverb} =~ /^(?:\\|\-).+?/) {
        Log('Error!!: Invalid argument for myverb, argument begin with - or \ ');
        die errorUsage '* Error!!: Invalid argument for --myverb';
    }
    else {
        Log("Set myverb = $opts_cmd{string}{myverb}");
    }
}

### Validate imgdir = string option
if (defined $opts_cmd{string}{imgdir}) {
    if ($opts_cmd{string}{imgdir} =~ /^(?:\\|\-).+?/) {
        Log('Error!!: Invalid argument for imgdir option, argument begin with -, \ or /');
        die errorUsage '* Error!!: Invalid argument for --imgdir';
    }
    else {
        Log("Set imgdir = $opts_cmd{string}{imgdir}");
    }
}

### Define key = pdf for image format
if (!$opts_cmd{boolean}{nopdf}) {
    Log('Add [pdf] image format');
    $opts_cmd{image}{pdf} = 1;
}

### Validate clean
my %clean = map { $_ => 1 } @clean;
$clean{doc} = 1; # by default clean = doc

### Pass $opts_cmd{clean} to $clean{$opt}
for my $opt (qw(doc off pst tkz all)) {
    if ($opts_cmd{clean} eq "$opt") {
        $clean{$opt} = 1;
        push @currentopt, "--clean=$opt";
    }
}

### Activate clean options for script
if ($clean{pst} or $clean{tkz}) { $clean{doc} = 1; }
if ($clean{all}) { @clean{qw(pst doc tkz)} = (1) x 3; }
if ($clean{off}) { undef %clean; }

### Validating the output file name
my $outext; # save extension of output file
if (defined $opts_cmd{string}{output}) {
    Log('Validating name and extension for output file');
    # Capture and split
    my ($outname, $outpath, $tmpext) = fileparse($opts_cmd{string}{output}, @SuffixList);
    if ($outname =~ /(^\-|^\.).*?/) {
        Log('The name of output file begin with dash -');
        die errorUsage "* Error!!: $opts_cmd{string}{output} it is not a valid name for output file";
    }
    if ($tmpext eq q{}) { # Check and set extension
        Log("Set extension for output file to $ext");
        $outext = $ext;
    }
    else {
        Log("Set extension for output file to $tmpext");
        $outext = $tmpext;
    }
    if ($outname eq $name) { # Check name
        Log("The name of the output file must be different that $name");
        Infoline("Changing the output file name to $name-out");
        $opts_cmd{string}{output} = "$name-out";
    }
    else {
        Log("Set name of the output file to $outname");
        $opts_cmd{string}{output} = $outname;
    }
    # If output name are ok, then $outfile = 1
    $outfile = 1;
}

### Rules to capture for regex
my $braces      = qr/ (?:\{)(.+?)(?:\}) /msx;
my $braquet     = qr/ (?:\[)(.+?)(?:\]) /msx;
my $no_corchete = qr/ (?:\[ .*? \])?    /msx;

### Array for capture new verbatim environments defined in input file
my @new_verb = qw (
    newtcblisting DeclareTCBListing ProvideTCBListing NewTCBListing
    lstnewenvironment NewListingEnvironment NewProgram specialcomment
    includecomment DefineVerbatimEnvironment newverbatim newtabverbatim
    );

### Regex to capture names for new verbatim environments from input file
my $newverbenv = join q{|}, map { quotemeta} sort { length $a <=> length $b } @new_verb;
$newverbenv = qr/\b(?:$newverbenv) $no_corchete $braces/msx;

### Array for capture new verbatim write environments defined in input file
my @new_verb_write = qw (
    renewtcbexternalizetcolorbox renewtcbexternalizeenvironment
    newtcbexternalizeenvironment newtcbexternalizetcolorbox newenvsc
    );

### Regex to capture names for new verbatim write environments from input file
my $newverbwrt = join q{|}, map { quotemeta} sort { length $a <=> length $b } @new_verb_write;
$newverbwrt = qr/\b(?:$newverbwrt) $no_corchete $braces/msx;

### Regex to capture MINTED related environments
my $mintdenv  = qr/\\ newminted $braces (?:\{.+?\})      /x;
my $mintcenv  = qr/\\ newminted $braquet (?:\{.+?\})     /x;
my $mintdshrt = qr/\\ newmint $braces (?:\{.+?\})        /x;
my $mintcshrt = qr/\\ newmint $braquet (?:\{.+?\})       /x;
my $mintdline = qr/\\ newmintinline $braces (?:\{.+?\})  /x;
my $mintcline = qr/\\ newmintinline $braquet (?:\{.+?\}) /x;

### Filter input file, now $ltxfile is pass to $filecheck

Log("Filter $name$ext \(remove % and comments\)");
my @filecheck = $ltxfile;
s/%.*\n//mg foreach @filecheck;    # del comments
s/^\s*|\s*//mg foreach @filecheck; # del white space
my $filecheck = join q{}, @filecheck;

### Search verbatim and verbatim write environments input file
Log("Search verbatim and verbatim write environments in $name$ext");

### Search new verbatim write names in input file
my @newv_write = $filecheck =~ m/$newverbwrt/xg;
if (@newv_write) {
    Log("Found new verbatim write environments in $name$ext");
    Logarray(\@newv_write);
    push @verw_env_tmp, @newv_write;
}

### Search new verbatim environments in input file (for)
my @verb_input = $filecheck =~ m/$newverbenv/xg;
if (@verb_input) {
    Log("Found new verbatim environments in $name$ext");
    Logarray(\@verb_input);
    push @verb_env_tmp, @verb_input;
}

### Search \newminted{$mintdenv}{options} need add "code" (for)
my @mint_denv = $filecheck =~ m/$mintdenv/xg;
if (@mint_denv) {
    Log("Found \\newminted\{envname\} in $name$ext");
    # Append "code"
    $mintdenv  = join "\n", map { qq/$_\Qcode\E/ } @mint_denv;
    @mint_denv = split /\n/, $mintdenv;
    Logarray(\@mint_denv);
    push @verb_env_tmp, @mint_denv;
}

### Search \newminted[$mintcenv]{lang} (for)
my @mint_cenv = $filecheck =~ m/$mintcenv/xg;
if (@mint_cenv) {
    Log("Found \\newminted\[envname\] in $name$ext");
    Logarray(\@mint_cenv);
    push @verb_env_tmp, @mint_cenv;
}

### Remove repetead again :)
@verb_env_tmp = uniq(@verb_env_tmp);

### Capture verbatim inline macros in input file
Log("Search verbatim macros in $name$ext");

### Store all minted inline/short in @mintline
my @mintline;

### Search \newmint{$mintdshrt}{options} (while)
my @mint_dshrt = $filecheck =~ m/$mintdshrt/xg;
if (@mint_dshrt) {
    Log("Found \\newmint\{macroname\} (short) in $name$ext");
    Logarray(\@mint_dshrt);
    push @mintline, @mint_dshrt;
}

### Search \newmint[$mintcshrt]{lang}{options} (while)
my @mint_cshrt = $filecheck =~ m/$mintcshrt/xg;
if (@mint_cshrt) {
    Log("Found \\newmint\[macroname\] (short) in $name$ext");
    Logarray(\@mint_cshrt);
    push @mintline, @mint_cshrt;
}

### Search \newmintinline{$mintdline}{options} (while)
my @mint_dline = $filecheck =~ m/$mintdline/xg;
if (@mint_dline) {
    Log("Found \\newmintinline\{macroname\} in $name$ext");
    # Append "inline"
    $mintdline  = join "\n", map { qq/$_\Qinline\E/ } @mint_dline;
    @mint_dline = split /\n/, $mintdline;
    Logarray(\@mint_dline);
    push @mintline, @mint_dline;
}

### Search \newmintinline[$mintcline]{lang}{options} (while)
my @mint_cline = $filecheck =~ m/$mintcline/xg;
if (@mint_cline) {
    Log("Found \\newmintinline\[macroname\] in $name$ext");
    Logarray(\@mint_cline);
    push @mintline, @mint_cline;
}

### Add standart mint, mintinline and lstinline
my @mint_tmp = qw(mint  mintinline lstinline);

### Join all inline verbatim macros captured
push @mintline, @mint_tmp;
@mintline = uniq(@mintline);

### Create a regex using @mintline
my $mintline = join q{|}, map { quotemeta } sort { length $a <=> length $b } @mintline;
$mintline = qr/\b(?:$mintline)/x;

### Reserved words in verbatim inline (while)
my %changes_in = (
    '%<*ltximg>'      => '%<*LTXIMG>',
    '%</ltximg>'      => '%</LTXIMG>',
    '%<*noltximg>'    => '%<*NOLTXIMG>',
    '%</noltximg>'    => '%</NOLTXIMG>',
    '%<*remove>'      => '%<*REMOVE>',
    '%</remove>'      => '%</REMOVE>',
    '\psset'          => '\PSSET',
    '\tikzset'        => '\TIKZSET',
    '\pspicture'      => '\TRICKS',
    '\endpspicture'   => '\ENDTRICKS',
    '\pgfpicture'     => '\PGFTRICKS',
    '\endpgfpicture'  => '\ENDPGFTRICKS',
    '\tikzpicture'    => '\TKZTRICKS',
    '\endtikzpicture' => '\ENDTKZTRICKS',
    '\psgraph'        => '\PSGRAPHTRICKS',
    '\endpsgraph'     => '\ENDPSGRAPHTRICKS',
    '\usepackage'     => '\USEPACKAGE',
    '{graphicx}'      => '{GRAPHICX}',
    '\graphicspath{'  => '\GRAPHICSPATH{',
    );

### Hash to replace \begin and \end in verbatim inline
my %init_end = (
    '\begin{' => '\BEGIN{',
    '\end{'   => '\END{',
    );

### Join changes in new hash (while) for verbatim inline
my %cambios = (%changes_in,%init_end);

### Variables and constantes
my $no_del = "\0";
my $del    = $no_del;

### Rules
my $llaves      = qr/\{ .+? \}                                                          /x;
my $no_llaves   = qr/(?: $llaves )?                                                     /x;
my $corchetes   = qr/\[ .+? \]                                                          /x;
my $delimitador = qr/\{ (?<del>.+?) \}                                                  /x;
my $scontents   = qr/Scontents [*]? $no_corchete                                        /ix;
my $verb        = qr/(?:((spv|(?:q|f)?v|V)erb|$opts_cmd{string}{myverb})[*]?)           /ix;
my $lst         = qr/(?:(lst|pyg)inline)(?!\*) $no_corchete                             /ix;
my $mint        = qr/(?: $mintline |SaveVerb) (?!\*) $no_corchete $no_llaves $llaves    /ix;
my $no_mint     = qr/(?: $mintline) (?!\*) $no_corchete                                 /ix;
my $marca       = qr/\\ (?:$verb | $lst |$scontents | $mint |$no_mint) (?:\s*)? (\S) .+? \g{-1}     /sx;
my $comentario  = qr/^ \s* \%+ .+? $                                                    /mx;
my $definedel   = qr/\\ (?: DefineShortVerb | lstMakeShortInline| MakeSpecialShortVerb ) [*]? $no_corchete $delimitador /ix;
my $indefinedel = qr/\\ (?: (Undefine|Delete)ShortVerb | lstDeleteShortInline) $llaves  /ix;

Log('Making changes to inline/multiline verbatim before extraction');

### Changes in input file for verbatim inline/multiline
while ($document =~
        / $marca
        | $comentario
        | $definedel
        | $indefinedel
        | $del .+? $del
        /pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my  $encontrado = ${^MATCH};
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
        substr $document, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos ($document) = $pos_inicial + length $encontrado;
    }
}

### Change "escaped braces" to <LTXSB.> (this label is not the one in the document)
$document =~ s/\\[{]/<LTXSBO>/g;
$document =~ s/\\[}]/<LTXSBC>/g;

### Regex for verbatim inline/multiline whit braces {...}
my $nestedbr   = qr /   ( [{] (?: [^{}]++ | (?-1) )*+ [}]  )                      /x;
my $fvextra    = qr /\\ (?: (Save|Esc)Verb [*]?) $no_corchete                     /x;
my $mintedbr   = qr /\\ (?:$mintline|pygment) (?!\*) $no_corchete $no_llaves      /x;
my $tcbxverb   = qr /\\ (?: tcboxverb [*]?| Scontents [*]? |$opts_cmd{string}{myverb} [*]?|lstinline) $no_corchete /x;
my $verb_brace = qr /   (?:$tcbxverb|$mintedbr|$fvextra) (?:\s*)? $nestedbr       /x;

### Change \verb*{code} for verbatim inline/multiline
while ($document =~ /$verb_brace/pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my  $encontrado = ${^MATCH};
    while (my($busco, $cambio) = each %cambios) {
        $encontrado =~ s/\Q$busco\E/$cambio/g;
    }
    substr $document, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
    pos ($document) = $pos_inicial + length $encontrado;
}

### We recovered the escaped braces
$document =~ s/<LTXSBO>/\\{/g;
$document =~ s/<LTXSBC>/\\}/g;

### Reverse changes for extract and output file
my %changes_out = (
    '\PSSET'            => '\psset',
    '\TIKZSET'          => '\tikzset',
    '\TRICKS'           => '\pspicture',
    '\ENDTRICKS'        => '\endpspicture',
    '\PGFTRICKS'        => '\pgfpicture',
    '\ENDPGFTRICKS'     => '\endpgfpicture',
    '\TKZTRICKS'        => '\tikzpicture',
    '\ENDTKZTRICKS'     => '\endtikzpicture',
    '\PSGRAPHTRICKS'    => '\psgraph',
    '\ENDPSGRAPHTRICKS' => '\endpsgraph',
    '\USEPACKAGE'       => '\usepackage',
    '{GRAPHICX}'        => '{graphicx}',
    '\GRAPHICSPATH{'    => '\graphicspath{',
    '\BEGIN{'           => '\begin{',
    '\END{'             => '\end{',
    '\DOCUMENTCLASS'    => '\documentclass',
    '\PAGESTYLE{'       => '\pagestyle{',
    '\THISPAGESTYLE{'   => '\thispagestyle{',
    );

### Reverse tags, need back in all file to extract
my %reverse_tag = (
    '%<*LTXIMG>'   => '%<*ltximg>',
    '%</LTXIMG>'   => '%</ltximg>',
    '%<*NOLTXIMG>' => '%<*noltximg>',
    '%</NOLTXIMG>' => '%</noltximg>',
    '%<*REMOVE>'   => '%<*remove>',
    '%</REMOVE>'   => '%</remove>',
    );

### First we do some security checks to ensure that they are verbatim and
### verbatim write environments are unique and disjointed
@verb_env_tmp = array_minus(@verb_env_tmp, @verw_env_tmp); #disjointed
my @verbatim = uniq(@verb_env_tmp);
my %verbatim = crearhash(@verbatim);

Log('The environments that are considered verbatim:');
Logarray(\@verbatim);

### Create a Regex for verbatim standart environment
my $verbatim = join q{|}, map { quotemeta } sort { length $a <=> length $b } @verbatim;
$verbatim = qr/$verbatim/x;
my $verb_std = qr {
                    (
                      (?:
                        \\begin\{$verbatim\*?\}
                          (?:
                            (?>[^\\]+)|
                            \\
                            (?!begin\{$verbatim\*?\})
                            (?!end\{$verbatim\*?\})|
                            (?-1)
                          )*
                        \\end\{$verbatim\*?\}
                      )
                    )
                  }x;

### Verbatim write
@verw_env_tmp = array_minus(@verw_env_tmp, @verb_env_tmp); #disjointed
my @verbatim_w = uniq(@verw_env_tmp);
my %verbatim_w = crearhash(@verbatim_w);

Log('The environments that are considered verbatim write:');
Logarray(\@verbatim_w);

### Create a Regex for verbatim write environment
my $verbatim_w = join q{|}, map { quotemeta } sort { length $a <=> length $b } @verbatim_w;
$verbatim_w = qr/$verbatim_w/x;
my $verb_wrt = qr {
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
                  }x;

### An array with all environments to extract
my @extract_env = qw (preview nopreview);
push @extract_env,@extr_env_tmp;
@extract_env = array_minus(@extract_env, @skip_env_tmp);
@extract_env = uniq(@extract_env);
my %extract_env = crearhash(@extract_env);

Log('The environments that will be searched for extraction:');
my @real_extract_env = grep !/nopreview/, @extract_env;
Logarray(\@real_extract_env);

### Create a regex to extract environments
my $environ = join q{|}, map { quotemeta } sort { length $a <=> length $b } @extract_env;
$environ = qr/$environ/x;
my $extr_tmp = qr {
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
                  }x;

### An array of environments to be removed from the output file
my @delete_env = uniq(@delt_env_tmp);
my %delete_env = crearhash(@delete_env);

Log('The environments that will be removed in output file:');
Logarray(\@delete_env);

### Create a Regex for delete environment in output file
my $delenv = join q{|}, map { quotemeta } sort { length $a <=> length $b } @delete_env;
$delenv = qr/$delenv/x;
my $delt_env = qr {
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
                  }x;

### An array of environments to be skiped from extraction
my @skipped = uniq(@skip_env_tmp);

Log('The environments that will be skiped for extraction:');
Logarray(\@skipped);

### Create a Regex for skip environment
my $skipenv = join q{|}, map { quotemeta } sort { length $a <=> length $b } @skipped;
$skipenv = qr/$skipenv/x;
my $skip_env = qr {
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
                  }x;

########################################################################
# In this first part the script only detects verbatim environments and #
# verbatim write don't distinguish between which ones are extracted,   #
# that's done in a second pass                                         #
########################################################################

Log('Making changes to verbatim/verbatim write environments before extraction');

### First, revert %<*TAGS> to %<*tags> in all document
my $ltxtags = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %reverse_tag;
$document =~ s/^($ltxtags)/$reverse_tag{$1}/gmsx;

### Create an array with the temporary extraction list, no verbatim environments
my @extract_tmp = array_minus(@extract_env, @verb_env_tmp);
@extract_tmp = array_minus(@extract_tmp, @verw_env_tmp);
@extract_tmp = uniq(@extract_tmp);
my %extract_tmp = crearhash(@extract_tmp);

### Hash and Regex for changes, this "regex" is re-used in ALL script
my %replace = (%verbatim, %extract_tmp, %changes_in, %document); # revert tags again :)
my $find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;

### We go line by line and make the changes (/p for ${^MATCH})
while ($document =~ /$verb_wrt | $verb_std /pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my $encontrado = ${^MATCH};
    if ($encontrado =~ /$verb_wrt/) {
        $encontrado =~ s/($find)/$replace{$1}/g;
        substr $document, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos ($document) = $pos_inicial + length $encontrado;
    }
    if ($encontrado =~ /$verb_std/) {
        %replace = (%verbatim_w, %extract_tmp, %changes_in, %document);
        $find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;
        $encontrado =~ s/($find)/$replace{$1}/g;
        substr $document, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos ($document) = $pos_inicial + length $encontrado;
    }
}

### Now split document
my ($preamble,$bodydoc,$enddoc) = $document =~ m/\A (.+?) (\\begin\{document\} .+?)(\\end\{document\}.*)\z/msx;

### Match <tags>, if they're matched, we turn them :)
my @tag_extract   = $bodydoc =~ m/(?:^\%<\*ltximg>.+?\%<\/ltximg>)/gmsx;
my @tag_noextract = $bodydoc =~ m/(?:^\%<\*noltximg>.+?\%<\/noltximg>)/gmsx;

if (@tag_extract) {
    Log('Pass extract tags %<*ltximg> ... %</ltximg> to \begin{preview} ... \end{preview}');
    $bodydoc =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                  \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
    ^\%<\*$extrtag>(.+?)\%<\/$extrtag>/\\begin\{preview\}$1\\end\{preview\}/gmsx;
}
if (@tag_noextract) {
    Log('Pass no extract tags %<*noltximg> ... %</noltximg> to \begin{nopreview} ... \end{nopreview}');
    $bodydoc =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                  \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
    ^\%<\*$skiptag>(.+?)\%<\/$skiptag>/\\begin\{nopreview\}$1\\end\{nopreview\}/gmsx;
}

########################################################################
# We now make the real changes for environment extraction. Since we    #
# don't know what kind of environments are passed, need to redefine    #
# the environments to make the changes                                 #
########################################################################

my @new_verb_tmp = array_minus(@verbatim, @extract_env);
$verbatim = join q{|}, map { quotemeta } sort { length $a <=> length $b } @new_verb_tmp;
$verbatim = qr/$verbatim/x;
$verb_std = qr {
                 (
                   (?:
                     \\begin\{$verbatim\*?\}
                       (?:
                         (?>[^\\]+)|
                         \\
                         (?!begin\{$verbatim\*?\})
                         (?!end\{$verbatim\*?\})|
                         (?-1)
                       )*
                     \\end\{$verbatim\*?\}
                   )
                 )
               }x;

my @new_verbw_tmp = array_minus(@verbatim_w, @extract_env);
$verbatim_w = join q{|}, map { quotemeta } sort { length $a <=> length $b } @new_verbw_tmp;
$verbatim_w = qr/$verbatim_w/x;
$verb_wrt = qr {
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
               }x;

### Regex using hash
%replace = (%extract_env);
$find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;

### We go line by line and make the changes (/p for ${^MATCH})
while ($bodydoc =~ /$verb_wrt | $verb_std /pgmx) {
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my $encontrado = ${^MATCH};
    $encontrado =~ s/($find)/$replace{$1}/g;
    substr $bodydoc, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
    pos ($bodydoc) = $pos_inicial + length $encontrado;
}

Log('Pass verbatim write environments to %<*ltximgverw> ... %</ltximgverw>');
$bodydoc  =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ($verb_wrt)/\%<\*ltximgverw>\n$1\n\%<\/ltximgverw>/gmsx;
$preamble =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ($verb_wrt)/\%<\*ltximgverw>\n$1\n\%<\/ltximgverw>/gmsx;

Log('Pass verbatim environments to %<*ltximgverw> ... %</ltximgverw>');
$bodydoc  =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ($verb_std)/\%<\*ltximgverw>\n$1\n\%<\/ltximgverw>/gmsx;
$preamble =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ($verb_std)/\%<\*ltximgverw>\n$1\n\%<\/ltximgverw>/gmsx;

### Check plain TeX syntax
my %plainsyntax = map { $_ => 1 } @extract_env; # anon hash

if (exists $plainsyntax{pspicture}) {
    Log('Convert plain \pspicture to LaTeX syntax');
    $bodydoc =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                  \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                  \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
                  \\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
    \\pspicture(\*)?(.+?)\\endpspicture/\\begin\{pspicture$1\}$2\\end\{pspicture$1\}/gmsx;
}

if (exists $plainsyntax{psgraph}) {
    Log('Convert plain \psgraph to LaTeX syntax');
    $bodydoc =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                  \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                  \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
                  \\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
    \\psgraph(\*)?(.+?)\\endpsgraph/\\begin\{psgraph$1\}$2\\end\{psgraph$1\}/gmsx;
}

if (exists $plainsyntax{tikzpicture}) {
    Log('Convert plain \tikzpicture to LaTeX syntax');
    $bodydoc =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                   \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                   \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
    \\tikzpicture(.+?)\\endtikzpicture/\\begin{tikzpicture}$1\\end{tikzpicture}/gmsx;
}

if (exists $plainsyntax{pgfpicture}) {
    Log('Convert plain \pgfpicture to LaTeX syntax');
    $bodydoc =~ s/ \%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                   \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                   \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
    \\pgfpicture(.+?)\\endpgfpicture/\\begin{pgfpicture}$1\\end{pgfpicture}/gmsx;
}

### Force mode for pstricks/psgraph/tikzpiture
if ($opts_cmd{boolean}{force}) {
    if (exists $plainsyntax{pspicture} or exists $plainsyntax{psgraph}) {
        Log('Force mode for pstricks and psgraph');
        $bodydoc =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                      \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                      \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
                      \\begin\{PSTexample\}.+?\\end\{PSTexample\}(*SKIP)(*F)|
                      \\begin\{postscript\}.+?\\end\{postscript\}(*SKIP)(*F)|
                      (?<code>
                         (?:\\psset\{(?:\{.*?\}|[^\{])*\}.+?)?  # if exist ...save
                         \\begin\{(?<env> pspicture\*?| psgraph)\} .+? \\end\{\k<env>\}
                      )
                    /\\begin\{preview\}\n$+{code}\n\\end\{preview\}/gmsx;
    }
    if (exists $plainsyntax{tikzpicture}) {
        Log('Force mode for pstricks and tikzpicture');
        $bodydoc =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                      \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                      \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
                      \\begin\{postscript\}.+?\\end\{postscript\}(*SKIP)(*F)|
                      (?<code>
                        (?:\\tikzset\{(?:\{.*?\}|[^\{])*\}.+?)?  # if exist ...save
                        \\begin\{(?<env> tikzpicture)\} .+? \\end\{\k<env>\}
                      )
                    /\\begin\{preview\}\n$+{code}\n\\end\{preview\}/gmsx;
    }
}

Log('Pass skip environments to \begin{nopreview} ... \end{nopreview}');
$bodydoc =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
              ($skip_env)/\\begin\{nopreview\}\n$1\n\\end\{nopreview\}\n/gmsx;

### Pass all captured environments in body \begin{preview} ... \end{preview}
Log('Pass all captured environments to \begin{preview} ... \end{preview}');
$bodydoc =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
              \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
              ($extr_tmp)/\\begin\{preview\}\n$1\n\\end\{preview\}/gmsx;

########################################################################
#  All environments are now classified:                                #
#  Extraction       ->    \begin{preview} ... \end{preview}            #
#  No Extraction    ->    \begin{nopreview} ... \end{nopreview}        #
#  Verbatim's       ->    %<\*ltximgverw> ... <\/ltximgverw>           #
########################################################################

### The %<*remove> ... %</remove> tags need a special treatment :)
$bodydoc  =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
               \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ^(\%<(?:\*|\/))(remove)(\>)/$1$2$tmp$3/gmsx;
$preamble =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
               \\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
               \\begin\{preview\}.+?\\end\{preview\}(*SKIP)(*F)|
               ^(\%<(?:\*|\/))(remove)(\>)/$1$2$tmp$3/gmsx;

### Pass \begin{preview} ... \end{preview} to \START{preview} ... \STOP{preview}
### Pass \begin{nopreview} ... \end{nopreview} to \START{nopreview} ... \STOP{nopreview}
$bodydoc =~ s/\\begin\{((no)?preview)\}/\\START\{$1\}/gmsx;
$bodydoc =~ s/\\end\{((no)?preview)\}/\\STOP\{$1\}/gmsx;

### Internal tag for regex ... safe if add $tmp ...
my $verbatimtag  = 'ltximgverw';

### Split $bodydoc by lines
my @lineas = split /\n/, $bodydoc;

### We restore the changes in body
my $NEWDEL;
for (@lineas) {
    %replace = (%changes_out);
    $find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;
    if (/\\START\{((no)?preview)(?{ $NEWDEL = "\Q$^N" })\}/ .. /\\STOP\{$NEWDEL\}/) {
        s/($find)/$replace{$1}/msgx;
    }
    if (/\%<\*($verbatimtag)(?{ $NEWDEL = "\Q$^N" })>/ .. /\%<\/$NEWDEL>/) {
        s/($find)/$replace{$1}/msgx;
    }
}

### Join lines in $bodydoc
$bodydoc = join "\n", @lineas;

### We restore the changes in preamble
while ($preamble =~ /\%<\*$verbatimtag>(.+?)\%<\/$verbatimtag>/pgmsx) {
    %cambios = (%changes_out);
    my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
    my  $encontrado = ${^MATCH};
    while (my($busco, $cambio) = each %cambios) {
        $encontrado =~ s/\Q$busco\E/$cambio/msxg;
    }
    substr $preamble, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
    pos ($preamble) = $pos_inicial + length $encontrado;
}

### We put back the environments and tags with a special mark :)
$bodydoc  =~ s/\\START\{((no)?preview)\}/\\begin\{$1\}\%$tmp/gmsx;
$bodydoc  =~ s/\\STOP\{((no)?preview)\}/\\end\{$1\}\%$tmp/gmsx;
$bodydoc  =~ s/($ltxtags)/$reverse_tag{$1}/gmsx;
$preamble =~ s/($ltxtags)/$reverse_tag{$1}/gmsx;

### First search PSTexample environment for extract
my $BE = '\\\\begin\{PSTexample\}';
my $EE = '\\\\end\{PSTexample\}';

my @exa_extract = $bodydoc =~ m/(\\begin\{PSTexample\}.+?\\end\{PSTexample\})/gms;
my $exaNo = scalar @exa_extract;

my $envEXA;
my $fileEXA;
if ($exaNo > 1) {
    $envEXA   = 'PSTexample environments';
    $fileEXA  = 'files';
}
else {
    $envEXA   = 'PSTexample environment';
    $fileEXA  = 'file';
}

### Check if PSTexample environment found, 1 = run script
if ($exaNo!=0) {
    $PSTexa = 1;
    Log("Found $exaNo $envEXA in $name$ext");
}

### Add [graphic={[...]...}] to \begin{PSTexample}[...]
if ($PSTexa) {
    Log('Append [graphic={[...]...}] to \begin{PSTexample}[...]');
    $exaNo = 1;
    while ($bodydoc =~ /\\begin\{PSTexample\}(\[.+?\])?/gsm) {
        my $swpl_grap = "graphic=\{\[scale=1\]$opts_cmd{string}{imgdir}/$name-$opts_cmd{string}{prefix}-exa";
        my $corchetes = $1;
        my ($pos_inicial, $pos_final) = ($-[1], $+[1]);
        if (not $corchetes) { $pos_inicial = $pos_final = $+[0]; }
        if (not $corchetes  or  $corchetes =~ /\[\s*\]/) {
            $corchetes = "[$swpl_grap-$exaNo}]";
        }
        else { $corchetes =~ s/\]/,$swpl_grap-$exaNo}]/; }
        substr($bodydoc, $pos_inicial, $pos_final - $pos_inicial) = $corchetes;
        pos($bodydoc) = $pos_inicial + length $corchetes;
    }
    continue { $exaNo++; }
    Log('Pass PSTexample environments to \begin{nopreview} ... \end{nopreview}');
    $bodydoc =~ s/\\begin\{preview\}%$tmp\n
                    (?<code>\\begin\{PSTexample\} .+? \\end\{PSTexample\})
                  \n\\end\{preview\}%$tmp
                 /\\begin\{nopreview\}%$tmp\n$+{code}\n\\end\{nopreview\}%$tmp/gmsx;
}

### Reset exaNo
$exaNo = scalar @exa_extract;

my $BP = "\\\\begin\{preview\}%$tmp";
my $EP = "\\\\end\{preview\}%$tmp";

my @env_extract = $bodydoc =~ m/(?<=$BP)(.+?)(?=$EP)/gms;
my $envNo = scalar @env_extract;

my $envSTD;
my $fileSTD;
if ($envNo > 1) {
    $envSTD   = 'standard environments';
    $fileSTD  = 'files';
}
else {
    $envSTD   = 'standard environment';
    $fileSTD  = 'file';
}

### Check if standard environments found, 1 = run script
if ($envNo!=0) {
    $STDenv = 1;
    Log("Found $envNo $envSTD in $name$ext");
}

### Image formats
my %format = (%{$opts_cmd{image}});
my $format = join q{, },grep { defined $format{$_} } keys %format;

if (!$opts_cmd{boolean}{norun}) {
    Log("Defined image formats for creating: $format");
}

### Check run and no images
if (!$opts_cmd{boolean}{norun} and $format eq q{}) {
    die errorUsage '* Error!!: --nopdf need --norun or an image option';
}

### Check dvips and no eps
if ($opts_cmd{compiler}{dvips} and !$opts_cmd{image}{eps} and !$opts_cmd{boolean}{norun}) {
    die errorUsage '* Error!!: Option --dvips need --eps';
}

### Check --srcenv and --subenv option from command line
if ($opts_cmd{boolean}{srcenv} && $opts_cmd{boolean}{subenv}) {
    die errorUsage '* Error!!: Options --srcenv and --subenv  are mutually exclusive';
}

### If --srcenv or --subenv option are OK then execute script
if ($opts_cmd{boolean}{srcenv}) {
    $outsrc = 1;
    $opts_cmd{boolean}{subenv} = 0;
}
if ($opts_cmd{boolean}{subenv}) {
    $outsrc = 1;
    $opts_cmd{boolean}{srcenv} = 0;
}

### Check if enviroment(s) found in input file
if ($envNo == 0 and $exaNo == 0) {
    die errorUsage "* Error!!: $scriptname can not find any environment to extract in $name$ext";
}

### Storing the current options of script
foreach my $key (keys %{$opts_cmd{boolean}}) {
    if (defined $opts_cmd{boolean}{$key}) { push @currentopt, "--$key"; }
}
foreach my $key (keys %{$opts_cmd{compiler}}) {
    if (defined $opts_cmd{compiler}{$key}) { push @currentopt, "--$key"; }
}
foreach my $key (keys %{$opts_cmd{image}}) {
    if (defined $opts_cmd{image}{$key}) { push @currentopt, "--$key"; }
}
foreach my $key (keys %{$opts_cmd{string}}) {
    if (defined $opts_cmd{string}{$key}) { push @currentopt, "--$key=$opts_cmd{string}{$key}"; }
}

@currentopt = grep !/--pdf/, @currentopt;
my @sorted_words = sort { length $a <=> length $b } @currentopt;

Log('The script will execute the following options:');
Logarray(\@sorted_words);

### Set directory to save generated files
if (-e $opts_cmd{string}{imgdir}) {
    Log("The generated file(s) will be saved in the directory $opts_cmd{string}{imgdir}");
}
else {
    Log("Creating the directory $opts_cmd{string}{imgdir}/ to save the generated file(s)");
    Logline("[perl] mkdir($opts_cmd{string}{imgdir},0744)");
    mkdir $opts_cmd{string}{imgdir},0744 or die errorUsage "* Error!!: Can't create the directory $opts_cmd{string}{imgdir}: $!\n";
}

### Set compiler name for terminal
my $compiler = $opts_cmd{compiler}{xetex}  ? 'xelatex'
             : $opts_cmd{compiler}{luatex} ? 'lualatex'
             : $opts_cmd{compiler}{latex}  ? 'latex'
             : $opts_cmd{compiler}{dvips}  ? 'latex'
             : $opts_cmd{compiler}{dvipdf} ? 'latex'
             : $opts_cmd{compiler}{arara}  ? 'arara'
             :                               'pdflatex'
             ;

if ($compiler eq 'arara') {
    Log("The file will be processed using $compiler, no ducks will be harmed in this process");
}
else {
    Log("The file will be processed using $compiler");
}

### Message in command line for compiler
my $msg_compiler = $opts_cmd{compiler}{xetex}  ? 'xelatex'
                 : $opts_cmd{compiler}{luatex} ? 'lualatex'
                 : $opts_cmd{compiler}{latex}  ? 'latex>dvips>ps2pdf'
                 : $opts_cmd{compiler}{dvips}  ? 'latex>dvips>ps2pdf'
                 : $opts_cmd{compiler}{dvipdf} ? 'latex>dvipdfmx'
                 : $opts_cmd{compiler}{arara}  ? 'arara'
                 :                               'pdflatex'
                 ;

### Define options for compiler, TeXLive and MikTeX
my $write18 = '-shell-escape'; # TeXLive
$write18 = '-enable-write18' if defined $ENV{"TEXSYSTEM"} and $ENV{"TEXSYSTEM"} =~ /miktex/i;

### Define options for compilers
my $opt_compiler = $opts_cmd{compiler}{arara} ? '--log -H'
                 :                              "$write18 -interaction=nonstopmode -recorder"
                 ;

Log("The options '$opt_compiler' will be passed to the $compiler");

### Append -q for system command line (gs, poppler-utils, dvips, dvipdfmx)
my $quiet = $verbose ? q{}
          :            '-q'
          ;

### Option for pdfcrop in command line (last version of pdfcrop https://github.com/ho-tex/pdfcrop)
my $opt_crop = $opts_cmd{compiler}{xetex}  ? "--xetex  --margins $opts_cmd{string}{margin}"
             : $opts_cmd{compiler}{luatex} ? "--luatex --margins $opts_cmd{string}{margin}"
             : $opts_cmd{compiler}{latex}  ? "--pdftex --margins $opts_cmd{string}{margin}"
             :                               "--pdftex --margins $opts_cmd{string}{margin}"
             ;

### Options for preview packpage
my $opt_prew = $opts_cmd{compiler}{xetex}  ? 'xetex,'
             : $opts_cmd{compiler}{latex}  ? q{}
             : $opts_cmd{compiler}{dvipdf} ? q{}
             : $opts_cmd{compiler}{arara}  ? q{}
             : $opts_cmd{compiler}{dvips}  ? q{}
             :                               'pdftex,'
             ;

### Options for ghostscript in command line
my %opt_gs_dev = (
    pdf  => "$gscmd $quiet -dNOSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress",
    gray => "$gscmd $quiet -dNOSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -sColorConversionStrategy=Gray -dProcessColorModel=/DeviceGray",
    png  => "$gscmd $quiet -dNOSAFER -sDEVICE=pngalpha -r$opts_cmd{string}{dpi}",
    bmp  => "$gscmd $quiet -dNOSAFER -sDEVICE=bmp32b -r$opts_cmd{string}{dpi}",
    jpg  => "$gscmd $quiet -dNOSAFER -sDEVICE=jpeg -r$opts_cmd{string}{dpi} -dJPEGQ=100 -dGraphicsAlphaBits=4 -dTextAlphaBits=4",
    tif  => "$gscmd $quiet -dNOSAFER -sDEVICE=tiff32nc -r$opts_cmd{string}{dpi}",
    );

### Options for poppler-utils in command line
my %opt_poppler = (
    eps => "pdftops $quiet -eps",
    ppm => "pdftoppm $quiet -r $opts_cmd{string}{dpi}",
    svg => "pdftocairo $quiet -svg",
    );

### Lines to add at begin document
my $preview = <<"EXTRA";
\\AtBeginDocument\{%
\\RequirePackage\[${opt_prew}active,tightpage\]\{preview\}%
\\renewcommand\\PreviewBbAdjust\{-60pt -60pt 60pt 60pt\}\}%
EXTRA

### Copy preamble and body for temp file with all environments
my $preamout = $preamble;
my $bodyout  = $bodydoc;

### Match \pagestyle and \thispagestyle in preamble
my $style_page = qr /(?:\\)(?:this)?(?:pagestyle\{) (.+?) (?:\})/x;
my @style_page = $preamout =~ m/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)| $style_page/gmsx;
my %style_page = map { $_ => 1 } @style_page; # anon hash

### Seting \pagestyle{empty} for subfiles and process
if (@style_page) {
    if (!exists $style_page{empty}) {
        Log("Replacing page style for generated files");
        $preamout =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                      (\\(this)?pagestyle)(?:\{.+?\})/$1\{empty\}/gmsx;
   }
}
else {
    Log('Add \pagestyle{empty} for generated files');
    $preamout = $preamout."\\pagestyle\{empty\}\n";
}

### Add $atbegindoc to $preamout for subfiles
my $sub_prea = $atbegindoc;
$sub_prea = $atbegindoc.$preamout;

### Add \begin{document} to $sub_prea
$sub_prea = $sub_prea.'\begin{document}';

### Remove %<*ltximgverw> ... %</ltximgverw> in preamble for subfiles
$sub_prea =~ s/\%<\*ltximgverw>\s*(.+?)\s*\%<\/ltximgverw>/$1/gmsx;

### Revert changes
%replace = (%changes_out);
$find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;
$sub_prea =~ s/($find)/$replace{$1}/g;

### Write standalone files for environments
if ($outsrc) {
    my $src_name = "$name-$opts_cmd{string}{prefix}-";
    my $srcNo    = 1;
    if ($opts_cmd{boolean}{srcenv}) {
        Log('Extract source code of all environments extracted without preamble');
        if ($STDenv) {
            Infoline("Creating $envNo $fileSTD $ext with source code for $envSTD");
            while ($bodydoc =~ m/$BP\s*(?<env_src>.+?)\s*$EP/gms) {
                open my $outexasrc, '>', "$opts_cmd{string}{imgdir}/$src_name$srcNo$ext";
                    print {$outexasrc} $+{env_src};
                close $outexasrc;
            }
            continue { $srcNo++; }
        }
        if ($PSTexa) {
            Infoline("Creating $exaNo $fileEXA $ext with source code for $envEXA");
            while ($bodydoc =~ m/$BE\[.+?(?<pst_exa_name>$opts_cmd{string}{imgdir}\/.+?-\d+)\}\]\s*(?<exa_src>.+?)\s*$EE/gms) {
                open my $outstdsrc, '>', "$+{'pst_exa_name'}$ext";
                    print {$outstdsrc} $+{'exa_src'};
                close $outstdsrc;
            }
        }
    }
    if ($opts_cmd{boolean}{subenv}) {
        Log('Extract source code of all environments extracted with preamble');
        # Removing content in preamble only for subfiles
        my @tag_remove_preamble = $sub_prea =~ m/(?:^\%<\*remove$tmp>.+?\%<\/remove$tmp>)/gmsx;
        if (@tag_remove_preamble) {
            Log('Removing the content between %<*remove> ... %</remove> in preamble for subfiles');
            $sub_prea =~ s/^\%<\*remove$tmp>\s*(.+?)\s*\%<\/remove$tmp>(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
        }
        if ($STDenv) {
            Infoline("Creating a $envNo $fileSTD $ext whit source code and preamble for $envSTD");
            while ($bodydoc =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms) {
                open my $outstdfile, '>', "$opts_cmd{string}{imgdir}/$src_name$srcNo$ext";
                    print {$outstdfile} "$sub_prea$+{'env_src'}\\end\{document\}";
                close $outstdfile;
            }
            continue { $srcNo++; }
        }
        if ($PSTexa) {
            Infoline("Creating a $exaNo $fileEXA $ext whit source code and preamble for $envEXA");
            while ($bodydoc =~ m/$BE\[.+?(?<pst_exa_name>$opts_cmd{string}{imgdir}\/.+?-\d+)\}\]\s*(?<exa_src>.+?)\s*$EE/gms) {
                open my $outexafile, '>', "$+{'pst_exa_name'}$ext";
                    print {$outexafile} "$sub_prea\n$+{'exa_src'}\n\\end\{document\}";
                close $outexafile;
            }
        }
    }
}

### Remove \begin{PSTexample}[graphic={...}]
$bodyout  =~ s/($BE)(?:\[graphic=\{\[scale=1\]$opts_cmd{string}{imgdir}\/.+?-\d+\}\])/$1/gmsx;
$bodyout  =~ s/($BE\[.+?)(?:,graphic=\{\[scale=1\]$opts_cmd{string}{imgdir}\/.+?-\d+\})(\])/$1$2/gmsx;

### Remove %<*ltximgverw> ... %</ltximgverw> in bodyout and preamout
$bodyout  =~ s/\%<\*ltximgverw>\s*(.+?)\s*\%<\/ltximgverw>/$1/gmsx;
$preamout =~ s/\%<\*ltximgverw>\s*(.+?)\s*\%<\/ltximgverw>/$1/gmsx;

### Reverse changes for temporary file with all env (no in -exa file)
$bodyout    =~ s/($find)/$replace{$1}/g;
$bodyout    =~ s/(\%$tmp)//g;
$bodyout    =~ s/(remove$tmp)/remove/g;
$sub_prea   =~ s/(remove$tmp)/remove/g;
$preamout   =~ s/($find)/$replace{$1}/g;
$atbegindoc =~ s/($find)/$replace{$1}/g;

### Create a one file whit "all" PSTexample environments extracted
if ($PSTexa) {
    Infoline("Creating $name-$opts_cmd{string}{prefix}-exa-$tmp$ext whit $exaNo $envEXA extracted");
    @exa_extract = undef;
    while ( $bodydoc =~ m/$BE\[.+? $opts_cmd{string}{imgdir}\/.+?-\d+\}\](?<exa_src>.+?)$EE/gmsx ) { # search $bodydoc
        push @exa_extract, $+{exa_src}."\\newpage\n";
        open my $allexaenv, '>', "$name-$opts_cmd{string}{prefix}-exa-$tmp$ext";
            print {$allexaenv} $sub_prea."@exa_extract"."\\end\{document\}";
        close $allexaenv;
    }
    if ($opts_cmd{boolean}{norun}) {
        Infoline("Moving and renaming $name-$opts_cmd{string}{prefix}-exa-$tmp$ext");
        say "* Running: mv $name-$opts_cmd{string}{prefix}-exa-$tmp$ext $name-$opts_cmd{string}{prefix}-exa-all$ext";
        Logline("[perl] move($workdir/$name-$opts_cmd{string}{prefix}-exa-$tmp$ext, $opts_cmd{string}{imgdir}/$name-$opts_cmd{string}{prefix}-exa-all$ext)");
        move("$workdir/$name-$opts_cmd{string}{prefix}-exa-$tmp$ext", "$opts_cmd{string}{imgdir}/$name-$opts_cmd{string}{prefix}-exa-all$ext")
        or die "* Error!!: Couldn't be renamed $name-$opts_cmd{string}{prefix}-exa-$tmp$ext to $opts_cmd{string}{imgdir}/$name-$opts_cmd{string}{prefix}-exa-all$ext";
    }
}

### Create a one file whit "all" standard environments extracted
if ($STDenv) {
    if ($opts_cmd{boolean}{noprew}) {
        Infoline("Creating $name-$opts_cmd{string}{prefix}-$tmp$ext whit $envNo $envSTD extracted [no preview]");
    }
    else {
        Infoline("Creating $name-$opts_cmd{string}{prefix}-$tmp$ext whit $envNo $envSTD extracted [preview]");
    }
    open my $allstdenv, '>', "$name-$opts_cmd{string}{prefix}-$tmp$ext";
    if ($opts_cmd{boolean}{noprew}) {
        my @env_extract;
        while ( $bodydoc =~ m/(?<=$BP)(?<env_src>.+?)(?=$EP)/gms ) { # search $bodydoc
            push @env_extract, $+{env_src}."\\newpage\n";
        }
        print {$allstdenv} $sub_prea."@env_extract"."\\end{document}";
    }
    else {
        print {$allstdenv} $atbegindoc.$preview.$preamout.$bodyout."\n\\end{document}";
    }
    close $allstdenv;
    if ($opts_cmd{boolean}{norun}) {
        Infoline("Moving and renaming $name-$opts_cmd{string}{prefix}-$tmp$ext");
        say "* Running: mv $name-$opts_cmd{string}{prefix}-$tmp$ext $name-$opts_cmd{string}{prefix}-all$ext";
        Logline("[perl] move($workdir/$name-$opts_cmd{string}{prefix}-$tmp$ext, $opts_cmd{string}{imgdir}/$name-$opts_cmd{string}{prefix}-all$ext)");
        move("$workdir/$name-$opts_cmd{string}{prefix}-$tmp$ext", "$opts_cmd{string}{imgdir}/$name-$opts_cmd{string}{prefix}-all$ext")
        or die "* Error!!: Couldn't be renamed $name-$opts_cmd{string}{prefix}-$tmp$ext to $opts_cmd{string}{imgdir}/$name-$opts_cmd{string}{prefix}-all$ext";
    }
}

if (!$opts_cmd{boolean}{norun}) {
Log("Compiler generate files whit all environment extracted");
opendir (my $DIR, $workdir);
    while (readdir $DIR) {
        if (/(?<name>$name-$opts_cmd{string}{prefix}(-exa)?)(?<type>-$tmp$ext)/) {
            Infoline("Compiling the file $+{name}$+{type} using [$msg_compiler]");
            if (!$verbose){ print "* Running: $compiler $opt_compiler\r\n"; }
            RUNOSCMD($compiler, "$opt_compiler $+{name}$+{type}");
            # Compiling file using latex>dvips>ps2pdf
            if ($opts_cmd{compiler}{dvips} or $opts_cmd{compiler}{latex}) {
                if (!$verbose){ print "* Running: dvips $quiet -Ppdf\r\n"; }
                RUNOSCMD("dvips $quiet -Ppdf", "-o $+{name}-$tmp.ps $+{name}-$tmp.dvi");
                if (!$verbose){ print "* Running: ps2pdf -dPDFSETTINGS=/prepress -dAutoRotatePages=/None\r\n"; }
                RUNOSCMD("ps2pdf -dPDFSETTINGS=/prepress -dAutoRotatePages=/None", "$+{name}-$tmp.ps  $+{name}-$tmp.pdf");
            }
            # Compiling file using latex>dvipdfmx
            if ($opts_cmd{compiler}{dvipdf}) {
                if (!$verbose){ print "* Running: dvipdfmx $quiet\r\n"; }
                RUNOSCMD("dvipdfmx $quiet", "$+{name}-$tmp.dvi");
            }
            Log("Move $+{name}$+{type} file whit all src code to $opts_cmd{string}{imgdir}");
            Infoline("Moving and renaming $+{name}$+{type}");
            if ($verbose){
                say "* Running: mv $workdir/$+{name}$+{type} $opts_cmd{string}{imgdir}/$+{name}-all$ext";
            } else { say "* Running: mv $+{name}$+{type} $+{name}-all$ext"; }
            Logline("[perl] move($workdir/$+{name}$+{type}, $opts_cmd{string}{imgdir}/$+{name}-all$ext)");
            move("$workdir/$+{name}$+{type}", "$opts_cmd{string}{imgdir}/$+{name}-all$ext")
            or die "* Error!!: Couldn't be renamed $+{name}$+{type} to $opts_cmd{string}{imgdir}/$+{name}-all$ext";
            # If option gray
            if ($opts_cmd{boolean}{gray}) {
                Infoline("Creating the file $+{name}-all.pdf [grayscale]");
                if (!$verbose) {
                    print "* Running: $gscmd $quiet -dNOSAFER -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress \n";
                    print "           -sColorConversionStrategy=Gray -dProcessColorModel=/DeviceGray \n";
                }
                RUNOSCMD("$opt_gs_dev{gray}","-o $tempDir/$+{name}-all.pdf $workdir/$+{name}-$tmp.pdf");
            }
            else {
                Infoline("Creating the file $+{name}-all.pdf");
                if ($verbose){
                    say "* Running: mv $workdir/$+{name}-$tmp.pdf $tempDir/$+{name}-all.pdf";
                }
                else { say "* Running: mv $+{name}-$tmp.pdf $+{name}-all.pdf"; }
                Logline("[perl] move($workdir/$+{name}-$tmp.pdf, $tempDir/$+{name}-all.pdf)");
                move("$workdir/$+{name}-$tmp.pdf", "$tempDir/$+{name}-all.pdf")
                or die "* Error!!: Couldn't be renamed $+{name}-$tmp.pdf to $tempDir/$+{name}-all.pdf";
                }
            if (!$opts_cmd{boolean}{crop}) {
                Infoline("Cropping the file $+{name}-all.pdf");
                if (!$verbose){ print "* Running: pdfcrop $opt_crop\r\n"; }
                RUNOSCMD("pdfcrop $opt_crop", "$tempDir/$+{name}-all.pdf $tempDir/$+{name}-all.pdf");
            }
        }
    }
closedir $DIR;
}

### Create image formats in separate files
if (!$opts_cmd{boolean}{norun}) {
    Log("Creating the image formats: $format");
    opendir(my $DIR, $tempDir);
        while (readdir $DIR) {
            # PDF/PNG/JPG/BMP/TIFF format suported by ghostscript
            if (/(?<name>$name-$opts_cmd{string}{prefix}(-exa)?)(?<type>-all\.pdf)/) {
                for my $var (qw(pdf png jpg bmp tif)) {
                    if (defined $opts_cmd{image}{$var}) {
                        print "Generating format [$var] from file $+{name}$+{type}\r\n";
                        if (!$verbose){ print "* Running: $opt_gs_dev{$var} \r\n"; }
                        RUNOSCMD("$opt_gs_dev{$var}", "-o $workdir/$opts_cmd{string}{imgdir}/$+{name}-%1d.$var $tempDir/$+{name}$+{type}");
                    }
                }
            }
            # EPS/PPM/SVG format suported by poppler-utils
            if (/(?<name>$name-$opts_cmd{string}{prefix}-exa)(?<type>-all\.pdf)/) { # pst-exa package
                for my $var (qw(eps ppm svg)) {
                    if (defined $opts_cmd{image}{$var}) {
                        print "Generating format [$var] from file $+{name}$+{type}\r\n";
                        if (!$verbose){ print "* Running: $opt_poppler{$var} \r\n"; }
                        for (my $epsNo = 1; $epsNo <= $exaNo; $epsNo++) {
                            RUNOSCMD("$opt_poppler{$var}", "-f $epsNo -l $epsNo $tempDir/$+{name}$+{type} $workdir/$opts_cmd{string}{imgdir}/$+{name}-$epsNo.$var");
                        }
                    }
                }
            }
            if (/(?<name>$name-$opts_cmd{string}{prefix})(?<type>-all\.pdf)/) {
                for my $var (qw(eps ppm svg)) {
                    if (defined $opts_cmd{image}{$var}) {
                        print "Generating format [$var] from file $+{name}$+{type}\r\n";
                        if (!$verbose){ print "* Running: $opt_poppler{$var} \r\n"; }
                        for (my $epsNo = 1; $epsNo <= $envNo; $epsNo++) {
                            RUNOSCMD("$opt_poppler{$var}", "-f $epsNo -l $epsNo $tempDir/$+{name}$+{type} $workdir/$opts_cmd{string}{imgdir}/$+{name}-$epsNo.$var");
                        }
                    }
                }
            }
        } # close while
    closedir $DIR;
    # Renaming PPM image files
    if (defined $opts_cmd{image}{ppm}) {
        Infoline("Renaming PPM image file(s)");
        opendir(my $DIR, $opts_cmd{string}{imgdir});
            while (readdir $DIR) {
                if (/(?<name>$name-$opts_cmd{string}{prefix}(-exa)?-\d+\.ppm)(?<sep>-\d+)(?<ppm>\.ppm)/) {
                    Logline("[perl] move($opts_cmd{string}{imgdir}/$+{name}$+{sep}$+{ppm}, $opts_cmd{string}{imgdir}/$+{name})");
                    move("$opts_cmd{string}{imgdir}/$+{name}$+{sep}$+{ppm}", "$opts_cmd{string}{imgdir}/$+{name}")
                    or die "* Error!!: Couldn't be renamed $+{name}$+{sep}$+{ppm} to $+{name}";
                }
            }
        closedir $DIR;
    }
} # close run

### Constant
my $USEPACK   = quotemeta'\usepackage';
my $CORCHETES = qr/\[ [^]]*? \]/x;
my $findgraphicx = 'true';

### pst-exa package
my $pstexa = qr/(?:\\ usepackage) \[\s*(.+?)\s*\] (?:\{\s*(pst-exa)\s*\} ) /x;
my @pst_exa;
my %pst_exa;

### Possible packages that load graphicx
my @pkgcandidates = qw (
    rotating epsfig lyluatex xunicode parsa xepersian-hm gregoriotex teixmlslides
    teixml fotex hvfloat pgfplots grfpaste gmbase hep-paper postage schulealt
    schule utfsym cachepic abc doclicense rotating epsfig semtrans mgltex
    graphviz revquantum mpostinl cmpj cmpj2 cmpj3 chemschemex register papercdcase
    flipbook wallpaper asyprocess draftwatermark rutitlepage dccpaper-base
    nbwp-manual mandi fmp toptesi isorot pinlabel cmll graphicx-psmin ptmxcomp
    countriesofeurope iodhbwm-templates fgruler combinedgraphics pax pdfpagediff
    psfragx epsdice perfectcut upmethodology-fmt ftc-notebook tabvar vtable
    teubner pas-cv gcard table-fct pdfpages keyfloat pdfscreen showexpl simplecd
    ifmslide grffile reflectgraphics markdown bclogo tikz-page pst-uml realboxes
    musikui csbulobalka lwarp mathtools sympytex mpgraphics miniplot.sty:77
    dottex pdftricks2 feupphdteses tex4ebook axodraw2 hagenberg-thesis dlfltxb
    hu-berlin-bundle draftfigure quicktype endofproofwd euflag othelloboard
    pdftricks unswcover breqn pdfswitch latex-make figlatex repltext etsvthor
    cyber xcookybooky xfrac mercatormap chs-physics-report tikzscale ditaa
    pst-poker gmp CJKvert asypictureb hletter tikz-network powerdot-fuberlin
    skeyval gnuplottex plantslabels fancytooltips ieeepes pst-vectorian
    phfnote overpic xtuformat stubs graphbox ucs pdfwin metalogo mwe
    inline-images asymptote UNAMThesis authorarchive amscdx pst-pdf adjustbox
    trimclip fixmetodonotes incgraph scanpages pst-layout alertmessage
    svg quiz2socrative realhats autopdf egplot decorule figsize tikzexternal
    pgfcore frontespizio textglos graphicx tikz tcolorbox pst-exa
    );

my $pkgcandidates = join q{|}, map { quotemeta } sort { length $a <=> length $b } @pkgcandidates;
$pkgcandidates = qr/$pkgcandidates/x;
my @graphicxpkg;

### \graphicspath
my $graphicspath= qr/\\ graphicspath \{ ((?: $llaves )+) \}/ix;
my @graphicspath;

### Replacing the extracted environments with \\includegraphics
if ($outfile) {
    Log("Convert standard extracted environments to \\includegraphics for $opts_cmd{string}{output}$outext");
    my $grap  =  "\\includegraphics[scale=1]{$name-$opts_cmd{string}{prefix}-";
    my $close =  '}';
    my $imgNo =  1;
    $bodydoc  =~ s/$BP.+?$EP/$grap@{[$imgNo++]}$close/msg;
    $preamble = "$atbegindoc$preamble";
    my @tag_remove_preamble = $preamble =~ m/(?:^\%<\*remove$tmp>.+?\%<\/remove$tmp>)/gmsx;
    if (@tag_remove_preamble) {
        Log("Removing the content between <*remove> ... </remove> tags in preamble for $opts_cmd{string}{output}$outext");
        $preamble =~ s/^\%<\*remove$tmp>\s*(.+?)\s*\%<\/remove$tmp>(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
    }
    # To be sure that the package is in the main document and not in a
    # verbatim write environment we make the changes using the hash and
    # range operator in a copy
    my %tmpreplace = (
        'graphicx'     => 'TMPGRAPHICXTMP',
        'pst-exa'      => 'TMPPSTEXATMP',
        'graphicspath' => 'TMPGRAPHICSPATHTMP',
    );
    my $findtmp    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %tmpreplace;
    my $preambletmp = $preamble;
    my @lineas = split /\n/, $preambletmp;
    # We remove the commented lines
    s/\%.*(?:[\t ]*(?:\r?\n|\r))?+//msg foreach @lineas;
    # We make the changes in the environments verbatim write
    my $DEL;
    for (@lineas) {
        if (/\\begin\{($verbatim_w\*?)(?{ $DEL = "\Q$^N" })\}/ .. /\\end\{$DEL\}/) {
            s/($findtmp)/$tmpreplace{$1}/g;
        }
    }
    $preambletmp = join "\n", @lineas; # Join lines in $preambletmp
    $preambletmp =~ s/^(?:[\t ]*(?:\r?\n|\r))?+//gmsx; # We removed the blank lines
    # Now we're trying to capture
    @graphicxpkg = $preambletmp =~ m/($pkgcandidates)/gmsx;
    if (@graphicxpkg) {
        Log("Found graphicx package in preamble for $opts_cmd{string}{output}$outext");
        $findgraphicx = 'false';
    }
    # Second search graphicspath
    @graphicspath = $preambletmp =~ m/graphicspath/msx;
    if (@graphicspath) {
        Log("Found \\graphicspath in preamble for $opts_cmd{string}{output}$outext");
        $findgraphicx = 'false';
        while ($preamble =~ /$graphicspath /pgmx) {
            my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
            my $encontrado = ${^MATCH};
            if ($encontrado =~ /$graphicspath/) {
                my  $argumento = $1;
                if ($argumento !~ /\{$opts_cmd{string}{imgdir}\/\}/) {
                    $argumento .= "\{$opts_cmd{string}{imgdir}/\}";
                    my  $cambio = "\\graphicspath{$argumento}";
                    substr $preamble, $pos_inicial, $pos_final-$pos_inicial, $cambio;
                    pos($preamble) = $pos_inicial + length $cambio;
                }
            }
        }
    }
    # Third search pst-exa
    @pst_exa  = $preambletmp =~ m/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|$pstexa/xg;
    %pst_exa = map { $_ => 1 } @pst_exa;
    if (@pst_exa) {
        Log("Comment pst-exa package in preamble for $opts_cmd{string}{output}$outext");
        $findgraphicx = 'false';
        $preamble =~ s/(\\usepackage\[)\s*(swpl|tcb)\s*(\]\{pst-exa\})/\%$1$2,pdf$3/msxg;
    }
    if (exists $pst_exa{tcb}) {
        Log("Suport for \\usepackage[tcb,pdf]\{pst-exa\} for $opts_cmd{string}{output}$outext");
        $bodydoc =~ s/(graphic=\{)\[(scale=\d*)\]($opts_cmd{string}{imgdir}\/$name-$opts_cmd{string}{prefix}-exa-\d*)\}/$1$2\}\{$3\}/gsmx;
    }
}

### Capture graphicx.sty in .log of LaTeX file
if ($findgraphicx eq 'true' and $outfile) {
    Log("Couldn't capture the graphicx package for $opts_cmd{string}{output}$ext in preamble");
    my $ltxlog;
    my @graphicx;
    # If norun and not arara
    if ($opts_cmd{boolean}{norun} and !$opts_cmd{compiler}{arara}) {
        Log("Creating $name-$opts_cmd{string}{prefix}-$tmp$ext with only preamble");
        open my $OUTfile, '>', "$name-$opts_cmd{string}{prefix}-$tmp$ext";
            print {$OUTfile} "$preamble\n\\stop";
        close $OUTfile;
        if ($opts_cmd{compiler}{latex}) { $compiler = 'pdflatex'; }
        my $captured = "$compiler $write18 -interaction=batchmode $name-$opts_cmd{string}{prefix}-$tmp$ext";
        Logrun($captured);
        $captured = qx{$captured};
        Log("Read $name-$opts_cmd{string}{prefix}-$tmp.log");
        open my $LaTeXlog, '<', "$name-$opts_cmd{string}{prefix}-$tmp.log";
            {
                local $/;
                $ltxlog = <$LaTeXlog>;
            }
        close $LaTeXlog;
        @graphicx = $ltxlog =~ m/.+? (graphicx\.sty)/xg; # capture graphicx
    }
    if (!$opts_cmd{boolean}{norun}) {
        # The file always exists unless "arara" it removed.
        if (-e "$name-$opts_cmd{string}{prefix}-$tmp.log") {
            Log("Read $name-$opts_cmd{string}{prefix}-$tmp.log");
            open my $LaTeXlog, '<', "$name-$opts_cmd{string}{prefix}-$tmp.log";
                {
                    local $/;
                    $ltxlog = <$LaTeXlog>;
                }
            close $LaTeXlog;
            @graphicx = $ltxlog =~ m/.+? (graphicx\.sty)/xg; # capture graphicx
        }
        else {
            Log('Read arara.log');
            open my $LaTeXlog, '<', 'arara.log';
                {
                    local $/;
                    $ltxlog = <$LaTeXlog>;
                }
            close $LaTeXlog;
            @graphicx = $ltxlog =~ m/.+? (graphicx\.sty)/xg; # capture graphicx
        }
    }
    if (@graphicx) {
        if ($opts_cmd{compiler}{arara}) {
            Log('Found graphicx package in arara.log');
        }
        else {
            Log("Found graphicx package in $name-$opts_cmd{string}{prefix}-$tmp.log");
        }
    }
    else {
        if ($opts_cmd{compiler}{arara}) {
            Log('Not found graphicx package in arara.log');
        }
        else {
            Log("Not found graphicx package in $name-$opts_cmd{string}{prefix}-$tmp.log");
        }
        Log("Add \\usepackage\{graphicx\} to preamble of $opts_cmd{string}{output}$outext");
        $preamble= "$preamble\n\\usepackage\{graphicx\}";
    }
}

# Regex for clean file (pst) in preamble
my $PALABRAS = qr/\b (?: pst-\w+ | pstricks (?: -add )? | psfrag |psgo |vaucanson-g| auto-pst-pdf )/x;
my $FAMILIA  = qr/\{ \s* $PALABRAS (?: \s* [,] \s* $PALABRAS )* \s* \}(\%*)?/x;

if ($clean{pst}) {
    Log("Remove pstricks packages in preamble for $opts_cmd{string}{output}$outext");
    $preamble =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                   ^ $USEPACK (?: $CORCHETES )? $FAMILIA \s*//msxg;
    $preamble =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                   (?: ^ $USEPACK \{ | \G) [^}]*? \K (,?) \s* $PALABRAS (\s*) (,?) /$1 and $3 ? ',' : $1 ? $2 : ''/gemsx;
    $preamble =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                   \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))+//gmsx;
    $preamble =~ s/\%<\*ltximgverw> .+?\%<\/ltximgverw>(*SKIP)(*F)|
                   \\SpecialCoor(?:[\t ]*(?:\r?\n|\r))+//gmsx;
    $preamble =~ s/^\\usepackage\{\}(?:[\t ]*(?:\r?\n|\r))+/\n/gmsx;
}

if (@pst_exa) {
    Log("Uncomment pst-exa package in preamble for $opts_cmd{string}{output}$outext");
    $preamble =~ s/(?:\%)(\\usepackage\[\s*)(swpl|tcb)(,pdf\s*\]\{pst-exa\})/$1$2$3/msxg;
}

### Add last lines
if ($outfile) {
    if (!@graphicspath) {
        Log("Not found \\graphicspath in preamble for $opts_cmd{string}{output}$outext");
        Log("Add \\graphicspath\{\{$opts_cmd{string}{imgdir}/\}\} to preamble for $opts_cmd{string}{output}$ext");
        $preamble= "$preamble\n\\graphicspath\{\{$opts_cmd{string}{imgdir}/\}\}";
    }
    Log("Add \\usepackage\{grfext\} to preamble for $opts_cmd{string}{output}$ext");
    $preamble = "$preamble\n\\usepackage\{grfext\}";
    Log("Add \\PrependGraphicsExtensions\*\{\.pdf\} to preamble for $opts_cmd{string}{output}$ext");
    $preamble = "$preamble\n\\PrependGraphicsExtensions\*\{\.pdf\}";
    $preamble =~ s/\%<\*ltximgverw>\s*(.+?)\s*\%<\/ltximgverw>/$1/gmsx;
    $preamble =~ s/^\\usepackage\{\}(?:[\t ]*(?:\r?\n|\r))+/\n/gmsx;
    $preamble =~ s/^(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
}

### We remove environments from the output file
if (%delete_env) {
    Log("Remove environments in body of $opts_cmd{string}{output}$ext");
    %replace = (%delete_env);
    $find    = join q{|}, map { quotemeta } sort { length $a <=> length $b } keys %replace;
    # We must prevent eliminating somewhere wrong
    # We re-create the regular expressions to make the changes
    my @new_verb_tmp = array_minus(@verbatim, @delete_env);
    $verbatim = join q{|}, map { quotemeta } sort { length $a <=> length $b } @new_verb_tmp;
    $verbatim = qr/$verbatim/x;
    $verb_std = qr {
                     (
                       (?:
                         \\begin\{$verbatim\*?\}
                           (?:
                             (?>[^\\]+)|
                             \\
                             (?!begin\{$verbatim\*?\})
                             (?!end\{$verbatim\*?\})|
                             (?-1)
                           )*
                         \\end\{$verbatim\*?\}
                       )
                     )
                   }x;

    my @new_verbw_tmp = array_minus(@verbatim_w, @delete_env);
    $verbatim_w = join q{|}, map { quotemeta } sort { length $a <=> length $b } @new_verbw_tmp;
    $verbatim_w = qr/$verbatim_w/x;
    $verb_wrt = qr {
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
                   }x;
    while ($bodydoc =~ /$verb_wrt | $verb_std /pgmx) {
        my ($pos_inicial, $pos_final) = ($-[0], $+[0]);
        my $encontrado = ${^MATCH};
        $encontrado =~ s/($find)/$replace{$1}/g;
        substr $bodydoc, $pos_inicial, $pos_final-$pos_inicial, $encontrado;
        pos ($bodydoc) = $pos_inicial + length $encontrado;
    }
    # Now remove
    $bodydoc =~ s/($delt_env)(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
}

### Create a <output file>
if ($outfile) {
    # Options for out_file (add $end to outfile)
    my $out_file = $clean{doc} ? "$preamble\n$bodydoc\n\\end\{document\}"
                :                "$preamble\n$bodydoc\n$enddoc"
                ;
    # Clean \psset content in output file
    if ($clean{pst}) {
        $out_file =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                       \%<\*ltximgverw> .+? \%<\/ltximgverw>(*SKIP)(*F)|
                       \\psset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
    }
    # Clean \tikzset content in output file
    if ($clean{tkz}) {
        $out_file =~ s/\\begin\{nopreview\}.+?\\end\{nopreview\}(*SKIP)(*F)|
                       \%<\*ltximgverw> .+? \%<\/ltximgverw>(*SKIP)(*F)|
                       \\tikzset\{(?:\{.*?\}|[^\{])*\}(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
    }
    # Revert all changes in outfile
    $out_file =~ s/\\begin\{nopreview\}%$tmp\s*(.+?)\s*\\end\{nopreview\}%$tmp/$1/gmsx;
    my @tag_remove_outfile = $out_file =~ m/(?:^\%<\*remove$tmp>.+?\%<\/remove$tmp>)/gmsx;
    if (@tag_remove_outfile) {
        Log("Removing the content between <*remove> ... </remove> tags in all $opts_cmd{string}{output}$outext");
        $out_file =~ s/^\%<\*remove$tmp>\s*(.+?)\s*\%<\/remove$tmp>(?:[\t ]*(?:\r?\n|\r))?+//gmsx;
    }
    # Remove internal mark for verbatim env
    $out_file =~ s/\%<\*ltximgverw>\s*(.+?)\s*\%<\/ltximgverw>/$1/gmsx;
    %replace = (%changes_out);
    $find    = join q{|}, map {quotemeta} sort { length $a <=> length $b } keys %replace;
    $out_file =~ s/($find)/$replace{$1}/g;
    if (-e "$opts_cmd{string}{output}$outext") {
        Infoline("Rewriting the file $opts_cmd{string}{output}$outext");
    }
    else{
        Infoline("Creating the file $opts_cmd{string}{output}$outext");
    }
    open my $OUTfile, '>', "$opts_cmd{string}{output}$outext";
        print {$OUTfile} $out_file;
    close $OUTfile;
    # Process the output file
    if (!$opts_cmd{boolean}{norun}) {
        if ($opts_cmd{compiler}{latex}) {
            $compiler     = 'pdflatex';
            $msg_compiler = 'pdflatex';
        }
        Infoline("Compiling the file $opts_cmd{string}{output}$outext using [$msg_compiler]");
        if (!$verbose){ print "* Running: $compiler $opt_compiler\r\n"; }
        RUNOSCMD($compiler, "$opt_compiler $opts_cmd{string}{output}$outext");
        if ($opts_cmd{compiler}{dvips}) {
            if (!$verbose){ print "* Running: dvips $quiet -Ppdf\r\n"; }
            RUNOSCMD("dvips $quiet -Ppdf", "$opts_cmd{string}{output}.dvi");
            if (!$verbose){ print "* Running: ps2pdf -dPDFSETTINGS=/prepress -dAutoRotatePages=/None\r\n"; }
            RUNOSCMD("ps2pdf -dPDFSETTINGS=/prepress -dAutoRotatePages=/None", "$opts_cmd{string}{output}.ps $opts_cmd{string}{output}.pdf");
        }
        if ($opts_cmd{compiler}{dvipdf}) {
            if (!$verbose){ print "* Running: dvipdfmx $quiet\r\n"; }
            RUNOSCMD("dvipdfmx $quiet", "$opts_cmd{string}{output}.dvi");
        }
    }
} # close outfile file

### Compress ./images with generated files
my $archivetar;
if ($opts_cmd{boolean}{zip} or $opts_cmd{boolean}{tar}) {
    my $stamp = strftime("%Y-%m-%d", localtime);
    $archivetar = "$opts_cmd{string}{imgdir}-$stamp";

    my @savetozt;
    find(\&zip_tar, $opts_cmd{string}{imgdir});
    sub zip_tar{
        my $filesto = $_;
        if (-f $filesto && $filesto =~ m/$name-$opts_cmd{string}{prefix}-.+?$/) { # search
            push @savetozt, $File::Find::name;
        }
        return;
    }
    Log('The files are compress are:');
    Logarray(\@savetozt);
    if ($opts_cmd{boolean}{zip}) {
        Infoline("Creating  the file $archivetar.zip");
        zip \@savetozt => "$archivetar.zip";
        Log("The file $archivetar.zip are in $workdir");
    }
    if ($opts_cmd{boolean}{tar}) {
        Infoline("Creating the file $archivetar.tar.gz");
        my $imgdirtar = Archive::Tar->new();
        $imgdirtar->add_files(@savetozt);
        $imgdirtar->write( "$archivetar.tar.gz" , 9 );
        Log("The file $archivetar.tar.gz are in $workdir");
    }
}

### Remove temporary files
my @tmpfiles;
my @protected = qw();
my $flsline = 'OUTPUT';
my @flsfile;

if (defined $opts_cmd{string}{output}) {
    push @protected, "$opts_cmd{string}{output}$outext", "$opts_cmd{string}{output}.pdf";
}

find(\&aux_files, $workdir);
sub aux_files{
    my $findtmpfiles = $_;
    if (-f $findtmpfiles && $findtmpfiles =~ m/$name-$opts_cmd{string}{prefix}(-exa)?-$tmp.+?$/) { # search
        push @tmpfiles, $_;
    }
    return;
}

if (-e 'arara.log') {
    push @flsfile, 'arara.log';
}
if (-e "$name-$opts_cmd{string}{prefix}-$tmp.fls") {
    push @flsfile, "$name-$opts_cmd{string}{prefix}-$tmp.fls";
}
if (-e "$name-$opts_cmd{string}{prefix}-exa-$tmp.fls") {
    push @flsfile, "$name-$opts_cmd{string}{prefix}-exa-$tmp.fls";
}
if (-e "$opts_cmd{string}{output}.fls") {
    push @flsfile, "$opts_cmd{string}{output}.fls";
}

for my $filename(@flsfile){
    open my $RECtmp, '<', $filename;
        push @tmpfiles, grep /^$flsline/,<$RECtmp>;
    close $RECtmp;
}

foreach (@tmpfiles) { s/^$flsline\s+|\s+$//g; }
push @tmpfiles, @flsfile;

@tmpfiles = uniq(@tmpfiles);
@tmpfiles = array_minus(@tmpfiles, @protected);

Log('The files that will be deleted are:');
Logarray(\@tmpfiles);

### Only If exist
if (@tmpfiles) {
    Infoline("Remove temporary files created in $workdir");
    foreach my $tmpfiles (@tmpfiles) {
        move($tmpfiles, $tempDir);
    }
}

### Find dirs created by minted
my @deldirs;
my $mintdir    = "\_minted\-$name-$opts_cmd{string}{prefix}-$tmp";
my $mintdirexa = "\_minted\-$name-$opts_cmd{string}{prefix}-exa-$tmp";
if (-e $mintdir) { push @deldirs, $mintdir; }
if (-e $mintdirexa) { push @deldirs, $mintdirexa; }

Log('The directory that will be deleted are:');
Logarray(\@deldirs);

### Only If exist
if (@deldirs) {
    Infoline("Remove temporary directories created by minted in $workdir");
    foreach my $deldirs (@deldirs) {
        remove_tree($deldirs);
    }
}

### End of script process
if (!$opts_cmd{boolean}{norun} and ($opts_cmd{boolean}{srcenv} or $opts_cmd{boolean}{subenv})) {
    Log("The image file(s): $format and subfile(s) are in $workdir/$opts_cmd{string}{imgdir}");
}
if (!$opts_cmd{boolean}{norun} and (!$opts_cmd{boolean}{srcenv} and !$opts_cmd{boolean}{subenv})) {
    Log("The image file(s): $format are in $workdir/$opts_cmd{string}{imgdir}");
}
if ($opts_cmd{boolean}{norun} and ($opts_cmd{boolean}{srcenv} or $opts_cmd{boolean}{subenv})) {
    Log("The subfile(s) are in $workdir/$opts_cmd{string}{imgdir}");
}
if ($outfile) {
    Log("The file $opts_cmd{string}{output}$ext are in $workdir");
}

Infoline("The execution of $scriptname has been successfully completed");

__END__
