#!/usr/bin/env perl
# Surveys indirect objects in a UD release.
# Copyright © 2025 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');
use JSON::Parse 'json_file_to_perl';
use udlib;

my $udpath = '/net/data/universal-dependencies-2.16';
my $lhash = udlib::get_language_hash('/net/work/people/zeman/unidep/docs-automation/codes_and_flags.yaml');
my @folders = udlib::list_ud_folders($udpath);
print("Found ", scalar(@folders), " UD treebanks in $udpath.\n");
# Cluster the treebanks by language.
my %treebanks_by_languages;
my $n_folders_processed = 0;
my $n_folders_skipped_text = 0;
my $n_languages_processed = 0;
my $n_languages_without_iobj = 0;
foreach my $folder (@folders)
{
    my $metadata = udlib::read_readme($folder, $udpath);
    # Skip treebanks that have no visible text or no lemmas.
    if($metadata->{'Includes text'} eq 'no')
    {
        print("Skipping $folder (no text).\n");
        $n_folders_skipped_text++;
        next;
    }
    $n_folders_processed++;
    my $fc = udlib::get_ud_files_and_codes($folder, $udpath);
    push(@{$treebanks_by_languages{$fc->{lcode}}}, $fc);
}
my @lcodes = sort
{
    my $aname = $treebanks_by_languages{$a}[0]{lname};
    my $bname = $treebanks_by_languages{$b}[0]{lname};
    my $afamily = $lhash->{$aname}{family};
    my $bfamily = $lhash->{$bname}{family};
    my $agenus = $lhash->{$aname}{genus};
    my $bgenus = $lhash->{$bname}{genus};
    my $r = $afamily cmp $bfamily;
    unless($r)
    {
        $r = $agenus cmp $bgenus;
        unless($r)
        {
            $r = $aname cmp $bname;
        }
    }
    $r
}
(keys(%treebanks_by_languages));
foreach my $lcode (@lcodes)
{
    my $n_treebanks = scalar(@{$treebanks_by_languages{$lcode}});
    next if($n_treebanks == 0);
    my $lname = $treebanks_by_languages{$lcode}[0]{lname};
    my $lflag = $lhash->{$lname}{flag};
    my $lscript = 'ipa'; #$lcode =~ m/^(kk|ky|tt|sah)$/ ? 'ru' : $lcode eq 'ug' ? 'ar' : $lcode eq 'ja' ? 'ja' : undef; ###!!! ad hoc hack at the moment
    #print("Processing $n_treebanks treebanks of $lname...\n");
    $n_languages_processed++;
    my @files;
    foreach my $fc (@{$treebanks_by_languages{$lcode}})
    {
        push(@files, map {"$udpath/$fc->{folder}/$_"} (@{$fc->{files}}));
    }
    my %stats;
    my $files = join(' ', @files);
    open(IN, "cat $files |") or die("Cannot read CoNLL-U from $lname: $!");
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
            my $lemma = $f[2];
            my $upos = $f[3];
            my $deprel = $f[7];
            if($deprel =~ m/^(nsubj|obj|iobj)(:|$)/)
            {
                $stats{deprel}{$1}++;
            }
            else
            {
                $stats{deprel}{'other'}++;
            }
        }
    }
    close(IN);
    $n_languages_without_iobj++ if(!exists($stats{deprel}{'iobj'}) || $stats{deprel}{'iobj'} == 0);
    # Print statistics.
    print_statistics($lname, \%stats);
    # Generate bar plot for LaTeX.
    #print_latex_bar_plot($lname, $lflag, $lscript, \%stats, \%ltranslit, @lemmas);
}
print("Skipped $n_folders_skipped_text treebanks because their underlying text is not accessible.\n");
print("Processed $n_folders_processed treebanks ($n_languages_processed languages).\n");
print("$n_languages_without_iobj languages have no attested iobj.\n");



#------------------------------------------------------------------------------
# Generates statistics of the indirect objects in the data and prints them to
# STDOUT.
#------------------------------------------------------------------------------
sub print_statistics
{
    my $lname = shift;
    my $stats = shift;
    my @deprels = sort {$stats->{deprel}{$b} <=> $stats->{deprel}{$a}} (keys(%{$stats->{deprel}}));
    my @percentages = map {sprintf("%s (%d%%%s)", $_, $stats->{deprel}{$_}/$stats->{nwords}*100+0.5, $_ eq 'other' ? '' : sprintf(" CORE %d%%", $stats->{deprel}{$_}/($stats->{nwords}-$stats->{deprel}{'other'})*100+0.5))} (@deprels);
    my $npad = length($lname) < 20 ? 20-length($lname) : 0;
    print(join("\t", ($lname.(' ' x $npad), @percentages)), "\n");
}



#------------------------------------------------------------------------------
# Generates LaTeX code of a bar plot that shows the distribution of the
# auxiliaries in the data and prints it to STDOUT.
#------------------------------------------------------------------------------
sub print_latex_bar_plot
{
    my $lname = shift; # for the frame title
    my $lflag = shift; # for the frame title
    my $lscript = shift; # e.g. 'ru' will result in $lemma being printed as \ru{$lemma}
    my $stats = shift;
    my $ltranslit = shift;
    my @lemmas = @_;
    print("\n\n\n");
    my %alerted;
    foreach my $lemma (@lemmas)
    {
        foreach my $upos (keys(%{$stats->{lu}{$lemma}}))
        {
            unless($upos =~ m/^(AUX|COP|VERB|other)$/)
            {
                $stats->{lu}{$lemma}{other} += $stats->{lu}{$lemma}{$upos};
            }
        }
        my $translitlemma = exists($ltranslit->{$lemma}) ? $ltranslit->{$lemma} : $lemma;
        my $scriptlemma = $lscript ? "\\$lscript\{$translitlemma\}" : $translitlemma;
        $alerted{$lemma} = $stats->{lu}{$lemma}{AUX}==0 && $stats->{lu}{$lemma}{COP}==0 ? "\\alert{$scriptlemma}" : $scriptlemma;
    }
    my $nlemmas = scalar(@lemmas);
    my $xlabel = $nlemmas==1 ? '1 auxiliary' : "$nlemmas auxiliaries";
    my $symbolic_x_coords = join(',', map {$alerted{$_}} (@lemmas));
    my $counts_aux = join(' ', map {$y = ($stats->{lu}{$_}{AUX}//0)/$stats->{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
    my $counts_cop = join(' ', map {$y = ($stats->{lu}{$_}{COP}//0)/$stats->{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
    my $counts_verb = join(' ', map {$y = ($stats->{lu}{$_}{VERB}//0)/$stats->{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
    my $counts_other = join(' ', map {$y = ($stats->{lu}{$_}{other}//0)/$stats->{nwords}*100; "($alerted{$_},$y)"} (@lemmas));
    my $sum_first_lemma = $stats->{lu}{$lemmas[0]}{AUX} + $stats->{lu}{$lemmas[0]}{COP} + $stats->{lu}{$lemmas[0]}{VERB} + $stats->{lu}{$lemmas[0]}{other};
    my $sum_last_lemma = $stats->{lu}{$lemmas[-1]}{AUX} + $stats->{lu}{$lemmas[-1]}{COP} + $stats->{lu}{$lemmas[-1]}{VERB} + $stats->{lu}{$lemmas[-1]}{other};
    my $legend_placement = $sum_first_lemma < $sum_last_lemma ? 'west' : 'east';
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
      legend pos={north $legend_placement}
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
    print("\n\n\n");
}



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
