#!/usr/bin/env perl
# Statistics about UD for a paper.
# Copyright © 2024–2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use Getopt::Long;
use udlib;

sub usage
{
    print STDERR ("Usage: $0 --release 2.17\n");
    print STDERR ("Searches the official UD release at its ÚFAL location (hardcoded).\n");
    print STDERR ("Prints the percentual representation of language families.\n");
}

my $udrelease = '2.17';
GetOptions
(
    'release=s' => \$udrelease
);

my $udpath = "/net/data/universal-dependencies-$udrelease";
my @folders = udlib::list_ud_folders($udpath);
my $dev_udpath = '/net/work/people/zeman/unidep';
my $lhash = udlib::get_language_hash($dev_udpath.'/docs-automation/codes_and_flags.yaml');
my %families;
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
            my $ltcode = $lhash->{$language}{lcode};
            $ltcode .= '_'.lc($treebank) unless($treebank eq '');
            # $tbkstats is a hash {'nsent', 'ntok', 'nfus', 'nword'}
            my $tbkstats = udlib::collect_statistics_about_ud_treebank("$udpath/$folder", $ltcode);
            # We can either count treebanks per language, or take the size of the treebank into account, too.
            #$families{$family}{$language}++;
            $families{$family}{$language} += $tbkstats->{nword};
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
}
