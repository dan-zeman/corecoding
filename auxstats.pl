#!/usr/bin/env perl
# Surveys auxiliaries in a UD release.
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $udpath = '/net/data/universal-dependencies-2.16';
my $folder = 'UD_English-EWT';
my %stats;
# We are not interested in the train-dev-test split. Simply read all CoNLL-U files.
open(IN, "cat $udpath/$folder/*.conllu |") or die("Cannot read CoNLL-U from $folder: $!");
while(<IN>)
{
    # Only basic nodes (no comments, MWTs, abstract nodes).
    if(m/^[0-9]+\t/)
    {
        chomp;
        my @f = split(/\t/);
        my @feats = $f[5] ne '_' ? split(/\|/, $f[5]) : ();
        my @misc = $f[9] ne '_' ? split(/\|/, $f[9]) : ();
        # No foreign words (code switching). No typos.
        next if(grep {m/^(Foreign|Typo)=Yes$/} (@feats) || grep {m/^Lang=/} (@misc));
        # Only auxiliaries (UPOS=AUX).
        next if($f[3] ne 'AUX');
        my $lemma = $f[2];
        # We are interested in deprels aux, cop (incl. subtypes), or other.
        my $deprel = $f[7];
        $deprel = 'other' unless($deprel =~ m/^(aux|cop)(:|$)/);
        $stats{ld}{$lemma}{$deprel}++;
        $stats{l}{$lemma}++;
    }
}
close(IN);
# Read the data second time and look for non-AUX occurrences of the words that can be AUX.
open(IN, "cat $udpath/$folder/*.conllu |") or die("Cannot read CoNLL-U from $folder: $!");
while(<IN>)
{
    # Only basic nodes (no comments, MWTs, abstract nodes).
    if(m/^[0-9]+\t/)
    {
        chomp;
        my @f = split(/\t/);
        my @feats = $f[5] ne '_' ? split(/\|/, $f[5]) : ();
        my @misc = $f[9] ne '_' ? split(/\|/, $f[9]) : ();
        # No foreign words (code switching). No typos.
        next if(grep {m/^(Foreign|Typo)=Yes$/} (@feats) || grep {m/^Lang=/} (@misc));
        # Only words that were seen as auxiliaries.
        my $lemma = $f[2];
        next if(!exists($stats{l}{$lemma}));
        # Also non-AUX occurrences. It could be VERB but also a completely unrelated homonym.
        my $upos = $f[3];
        #next if($upos eq 'AUX');
        $stats{lu}{$lemma}{$upos}++;
    }
}
close(IN);
# Print statistics.
my @lemmas = sort(keys(%{$stats{l}}));
foreach my $lemma (@lemmas)
{
    print("$lemma\n");
    my @deprels = sort(keys(%{$stats{ld}{$lemma}}));
    foreach my $deprel (@deprels)
    {
        print("\t$deprel\t$stats{ld}{$lemma}{$deprel}\n");
    }
    my @uposes = sort(keys(%{$stats{lu}{$lemma}}));
    foreach my $upos (@uposes)
    {
        print("\t$upos\t$stats{lu}{$lemma}{$upos}\n");
    }
}
