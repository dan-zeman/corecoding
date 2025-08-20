#!/usr/bin/env perl
# Surveys auxiliaries in a UD release.
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use JSON::Parse 'json_file_to_perl';

my $udpath = '/net/data/universal-dependencies-2.16';
my $folder = 'UD_English-*';
# Read the auxiliaries registered for the given language in UD.
my $data = json_file_to_perl("$udpath/tools/data/data.json")->{auxiliaries}{'en'};
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
        $stats{nwords}++;
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
        my $lemma = $f[2];
        # Only words that were seen (or registered in UD) as auxiliaries.
        #next if(!exists($stats{l}{$lemma}));
        next if(!exists($data->{$lemma}));
        # Also non-AUX occurrences. It could be VERB but also a completely unrelated homonym.
        my $upos = $f[3];
        #next if($upos eq 'AUX');
        # Create a pseudo-UPOS COP, which will swallow all AUX that have the cop DEPREL.
        $upos = 'COP' if($upos eq 'AUX' && $f[7] =~ m/^cop(:|$)/);
        $stats{lu}{$lemma}{$upos}++;
    }
}
close(IN);
# Print statistics.
#my @lemmas = sort(keys(%{$stats{l}}));
my @lemmas = sort(keys(%{$data}));
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
# Generate bar plot for LaTeX.
my %alerted;
foreach my $lemma (@lemmas)
{
    foreach my $upos (keys(%{$stats{lu}{$lemma}}))
    {
        unless($upos =~ m/^(AUX|COP|VERB|other)$/)
        {
            $stats{lu}{$lemma}{other} += $stats{lu}{$lemma}{$upos};
        }
    }
    $alerted{$lemma} = $stats{lu}{$lemma}{AUX}==0 && $stats{lu}{$lemma}{COP}==0 ? "\\alert{$lemma}" : $lemma;
}
my $symbolic_x_coords = join(',', map {$alerted{$_}} (@lemmas));
my $counts_aux = join(' ', map {$y = ($stats{lu}{$_}{AUX}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
my $counts_cop = join(' ', map {$y = ($stats{lu}{$_}{COP}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
my $counts_verb = join(' ', map {$y = ($stats{lu}{$_}{VERB}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
my $counts_other = join(' ', map {$y = ($stats{lu}{$_}{other}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
print <<EOF
\\begin{tikzpicture}
  \\begin{axis}[
    ybar stacked,
    width=\\textwidth, height=0.8\\textheight,
    symbolic x coords={$symbolic_x_coords},
    xtick=data,
    x tick label style={rotate=45,anchor=east},
    xlabel=16 auxiliaries,
    ylabel={\\% of all tokens}
  ]
    \\addplot coordinates {$counts_aux};
    \\addplot coordinates {$counts_cop};
    \\addplot coordinates {$counts_verb};
    \\addplot coordinates {$counts_other};
    \\legend{AUX,COP,VERB,other}
  \\end{axis}
\\end{tikzpicture}
EOF
;
