#!/usr/bin/env perl
# Statistics about UD 2.14 for a paper.
# Copyright © 2024 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Carp;
use udlib;

my $udpath = '/net/data/universal-dependencies-2.14';
#my $udpath = 'C:/Users/Dan/Documents/Lingvistika/Projekty/universal-dependencies';
my @folders = udlib::list_ud_folders($udpath);
my $dev_udpath = '/net/work/people/zeman/unidep';
#my $dev_udpath = 'C:/Users/Dan/Documents/Lingvistika/Projekty/universal-dependencies';
my $lhash = udlib::get_language_hash($dev_udpath.'/docs-automation/codes_and_flags.yaml');
my %families;
my %folders_by_families;
foreach my $folder (@folders)
{
    my ($language, $treebank) = udlib::decompose_repo_name($folder);
    if(defined($language))
    {
        if(exists($lhash->{$language}))
        {
            my $family = $lhash->{$language}{family};
            my $genus = '';
            if($family =~ m/^(.+), (.+)$/)
            {
                $family = $1;
                $genus = $2;
            }
            # Skip special pseudo-families.
            next if($family =~ m/^(Creole|Code switching|Sign Language)$/);
            # Ignore treebanks that do not contain underlying text.
            my $metadata = udlib::read_readme($folder, $udpath);
            next if($metadata->{'Includes text'} ne 'yes');
            # Remember folders by languages and families they belong to.
            push(@{$folders_by_families{$family}{$language}}, $folder);
            #my $ltcode = $lhash->{$language}{lcode};
            #$ltcode .= '_'.lc($treebank) unless($treebank eq '');
            $families{$family}{$language}++;
        }
        else
        {
            confess("Unknown language '$language'");
        }
    }
    else
    {
        confess("Cannot parse repo name '$folder'");
    }
}
my %family_sizes; map {foreach my $l (keys(%{$families{$_}})) {$family_sizes{$_} += $families{$_}{$l}}} (keys(%families));
#my @families = sort {my $r = scalar(keys(%{$families{$b}})) <=> scalar(keys(%{$families{$a}})); unless($r) {$r = $a cmp $b} $r} (keys(%families));
my @families = sort {my $r = $family_sizes{$b} <=> $family_sizes{$a}; unless($r) {$r = $a cmp $b} $r} (keys(%families));
foreach my $family (@families)
{
    my $languages = join(', ', sort(map {"$_ ($families{$family}{$_})"} (keys(%{$families{$family}}))));
    my $n = scalar(keys(%{$families{$family}}));
    print("$family: $family_sizes{$family}: $n: $languages\n");
    my @languages = sort(keys(%{$folders_by_families{$family}}));
    foreach my $language (@languages)
    {
        # We can either process each treebank separately, or join all treebanks of a language.
        if(0)
        {
            foreach my $folder (@{$folders_by_families{$family}{$language}})
            {
                print("--------------------------------------------------------------------------------\n");
                print("$folder\n");
                system("cat $udpath/$folder/*.conllu | udapy read.Conllu bundles_per_doc=1000 my.CoreCoding arg=all 2>/dev/null | ./summary.pl");
                print("\n");
            }
        }
        else # all treebanks of one language together
        {
            print("--------------------------------------------------------------------------------\n");
            print("$language\n");
            my $language_underscores = $language;
            $language_underscores =~ s/ /_/g;
            my $command = "cat $udpath/UD_$language_underscores*/*.conllu | udapy read.Conllu bundles_per_doc=1000 my.CoreCoding arg=all 2>/dev/null | ./summary.pl";
            #system($command);
            open(SUMMARY, "$command|") or die("Cannod pipe from '$command': $!");
            while(<SUMMARY>)
            {
                if(m/^SV --> ([0-9]*\.[0-9]+) --> VS$/)
                {
                    $svs{$language} = $1;
                }
                if(m/^OV --> ([0-9]*\.[0-9]+) --> VO$/)
                {
                    $ovo{$language} = $1;
                }
                print;
            }
            close(SUMMARY);
            print("\n");
        }
    }
}
# Print tikz code of the SVS/OVO language plot.
print('\begin{tikzpicture}[scale=3]', "\n");
print("  \\draw[step=1cm,gray,very thin] (-0.2cm,-0.2cm) grid (10cm,10cm);\n");
print("  \\draw[gray] (-0.5cm,0cm) node{SV};\n");
print("  \\draw[gray] (-0.5cm,10cm) node{VS};\n");
print("  \\draw[gray] (0cm,-0.5cm) node{OV};\n");
print("  \\draw[gray] (10cm,-0.5cm) node{VO};\n");
#foreach my $language (sort(keys(%svs)))
#{
#    my $lcode = $lhash->{$language}{lcode};
#    my $y = ($svs{$language} // 0) * 10;
#    my $x = ($ovo{$language} // 0) * 10;
#    print("\\draw (${x}cm,${y}cm) node{$lcode};\n");
#}
# Zkusit rezervovat pro každý jazyk 5 mm na šířku a 2,5 mm na výšku, aby se kódy jazyků nepřepisovaly přes sebe.
# Matice s 20 prvky na šířku (10 cm) a 40 prvky na výšku (10 cm).
# K dispozici je 800 pozic na 148 jazyků.
my @languages = sort {distance($ovo{$a}, $svs{$a}) <=> distance($ovo{$b}, $svs{$b})} (keys(%svs));
foreach my $language (@languages)
{
    my $lcode = $lhash->{$language}{lcode};
    my $y = $svs{$language} // 0;
    my $x = $ovo{$language} // 0;
    my ($xcell, $ycell) = find_cell($x, $y);
    ($x, $y) = cell2cm($xcell, $ycell);
    if($lhash->{$language}{family} =~ m/^IE/)
    {
        $lcode = "\\textcolor{blue}{$lcode}";
    }
    elsif($lhash->{$language}{family} =~ m/^Uralic/)
    {
        $lcode = "\\textcolor{teal}{$lcode}";
    }
    elsif($lhash->{$language}{family} =~ m/^Afro-Asiatic/)
    {
        $lcode = "\\textcolor{orange}{$lcode}";
    }
    elsif($lhash->{$language}{family} =~ m/^Turkic/)
    {
        $lcode = "\\textcolor{red}{$lcode}";
    }
    elsif($lhash->{$language}{family} =~ m/^Tupian/)
    {
        $lcode = "\\textcolor{violet}{$lcode}";
    }
    elsif($lhash->{$language}{family} =~ m/^Sino-Tibetan/)
    {
        $lcode = "\\textcolor{magenta}{$lcode}";
    }
    elsif($lhash->{$language}{family} =~ m/^Austronesian/)
    {
        $lcode = "\\textcolor{cyan}{$lcode}";
    }
    elsif($lhash->{$language}{family} =~ m/^Dravidian/)
    {
        $lcode = "\\textcolor{olive}{$lcode}";
    }
    print("  \\draw (${x}cm,${y}cm) node{$lcode}; \% $language\n");
}
print('\end{tikzpicture}', "\n");



#------------------------------------------------------------------------------
# Finds the cell that is available and its distance from the ideal cell is
# minimal.
#------------------------------------------------------------------------------
my @matrix;
sub find_cell
{
    my $x = shift;
    my $y = shift;
    ###!!! There is probably a better algorithm that searches the cells in increasing distance from ideal and stops when an empty cell is found.
    my ($minxc, $minyc, $mindistance);
    for(my $i = 0; $i < 20; $i++)
    {
        for(my $j = 0; $j < 40; $j++)
        {
            if(!defined($matrix[$i][$j]))
            {
                my $distance = distance(cell2coord($i, $j), $x, $y);
                if(!defined($mindistance) || $distance < $mindistance)
                {
                    $mindistance = $distance;
                    $minxc = $i;
                    $minyc = $j;
                }
            }
        }
    }
    $matrix[$minxc][$minyc] = 1;
    return ($minxc, $minyc);
}



#------------------------------------------------------------------------------
# Computes distance of two points. If only one point is given, computes its
# distance from [0;0].
#------------------------------------------------------------------------------
sub distance
{
    my $x1 = shift // 0;
    my $y1 = shift // 0;
    my $x0 = shift // 0;
    my $y0 = shift // 0;
    return sqrt(($x1-$x0)**2 + ($y1-$y0)**2);
}



#------------------------------------------------------------------------------
# Converts 0-1 coordinates to cell coordinates (rounding the numbers to the
# cell to which the original point falls).
#------------------------------------------------------------------------------
sub coord2cell
{
    my $x = shift;
    my $y = shift;
    # Project $x from <0;1> to <0;19>.
    my $xcell = sprintf("%d", $x*19+0.5);
    # Project $y from <0;1> to <0;39>.
    my $ycell = sprintf("%d", $y*39+0.5);
    return ($xcell, $ycell);
}



#------------------------------------------------------------------------------
# Converts cell coordinates to 0-1 coordinates (giving the center of the
# cell).
#------------------------------------------------------------------------------
sub cell2coord
{
    my $xcell = shift;
    my $ycell = shift;
    # Project $xcell from <0;19> to <0;1>.
    my $x = $xcell/19;
    # Project $ycell from <0;39> to <0;1>.
    my $y = $ycell/39;
    return ($x, $y);
}



#------------------------------------------------------------------------------
# Converts cell coordinates to metric coordinates (for the purpose of tikz
# positioning, giving the center of the cell).
#------------------------------------------------------------------------------
sub cell2cm
{
    my $xcell = shift;
    my $ycell = shift;
    my $x = 0.25 + $xcell * 0.5;
    my $y = 0.125 + $ycell * 0.25;
    return ($x, $y);
}
