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
my $lname;
my $lcode;
my $lflag;
my $lscript; # makro to use (if any) around lemmas in XeLaTeX to turn on the correct script
if(scalar(@ARGV) >= 3)
{
    $lname = shift(@ARGV);
    $lcode = shift(@ARGV);
    $lflag = shift(@ARGV);
    $lscript = shift(@ARGV);
}
else
{
    die("Expected 3 or 4 arguments: language name, language code, flag code, script makro");
}

my $folder = "UD_$lname-*";
# Read the auxiliaries registered for the given language in UD.
my $data = json_file_to_perl("$udpath/tools/data/data.json")->{auxiliaries}{$lcode};
my %stats;
# We may want to work with transliterated lemmas in languages that use foreign
# writing systems. In the CoNLL-U files, we may be able to obtain them from MISC.
# But no transliteration is available in the JSON files for the validator, so we
# should cache the known transliterations and use them there.
my %ltranslit;
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
        # For lemmas that are registered as possible auxiliaries, we want to
        # collect their UPOS even if it is not AUX in this context. It could be
        # VERB but also a completely unrelated homonym.
        my $lemma = $f[2];
        next if(!exists($data->{$lemma}));
        if(!exists($ltranslit{$lemma}))
        {
            $ltranslit{$lemma} = get_ltranslit($lemma, @misc);
        }
        my $upos = $f[3];
        # Create a pseudo-UPOS COP, which will swallow all AUX that have the cop DEPREL.
        $upos = 'COP' if($upos eq 'AUX' && $f[7] =~ m/^cop(:|$)/);
        $stats{lu}{$lemma}{$upos}++;
        # For auxiliaries (UPOS=AUX or COP), also collect their DEPREL.
        next if($upos !~ m/^(AUX|COP)$/);
        # We are interested in deprels aux, cop (incl. subtypes), or other.
        my $deprel = $f[7];
        $deprel = 'other' unless($deprel =~ m/^(aux|cop)(:|$)/);
        $stats{ld}{$lemma}{$deprel}++;
        $stats{l}{$lemma}++;
    }
}
close(IN);
# Print statistics.
#my @lemmas = sort(keys(%{$stats{l}}));
my @lemmas = sort(keys(%{$data}));
foreach my $lemma (@lemmas)
{
    print("$lemma");
    if(exists($ltranslit{$lemma}))
    {
        print("\t$ltranslit{$lemma}");
    }
    print("\n");
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
print("\n\n\n");
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
    my $ltranslit = exists($ltranslit{$lemma}) ? $ltranslit{$lemma} : $lemma;
    my $scriptlemma = $lscript ? "\\$lscript\{$ltranslit\}" : $ltranslit;
    $alerted{$lemma} = $stats{lu}{$lemma}{AUX}==0 && $stats{lu}{$lemma}{COP}==0 ? "\\alert{$scriptlemma}" : $scriptlemma;
}
my $nlemmas = scalar(@lemmas);
my $xlabel = $nlemmas==1 ? '1 auxiliary' : "$nlemmas auxiliaries";
my $symbolic_x_coords = join(',', map {$alerted{$_}} (@lemmas));
my $counts_aux = join(' ', map {$y = ($stats{lu}{$_}{AUX}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
my $counts_cop = join(' ', map {$y = ($stats{lu}{$_}{COP}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
my $counts_verb = join(' ', map {$y = ($stats{lu}{$_}{VERB}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
my $counts_other = join(' ', map {$y = ($stats{lu}{$_}{other}//0)/$stats{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
print <<EOF
\\begin{frame}{\\Flag{$lflag}~UD 2.16 $lname}
  \\begin{tikzpicture}
    \\begin{axis}[
      ybar stacked,
      width=\\textwidth, height=0.8\\textheight,
      symbolic x coords={$symbolic_x_coords},
      xtick=data,
      x tick label style={rotate=45,anchor=east},
      xlabel=$xlabel,
      ylabel={\\% of all tokens},
      ymin=0,
      enlargelimits=0.1,
      legend pos={north east}
    ]
      \\addplot coordinates {$counts_aux};
      \\addplot coordinates {$counts_cop};
      \\addplot coordinates {$counts_verb};
      \\addplot coordinates {$counts_other};
      \\legend{AUX,COP,VERB,other}
    \\end{axis}
  \\end{tikzpicture}
\\end{frame}
EOF
;



#------------------------------------------------------------------------------
# Takes LEMMA and MISC. Returns LTranslit if MISC contains it, otherwise
# returns LEMMA.
#------------------------------------------------------------------------------
sub get_ltranslit
{
    my $lemma = shift;
    my @misc = @_;
    my @ltranslit = grep {m/^LTranslit=.+/} (@misc);
    my $result = $lemma;
    if(scalar(@ltranslit) > 0)
    {
        $result = $ltranslit[0];
        $result =~ s/^LTranslit=//;
    }
    return $result;
}
