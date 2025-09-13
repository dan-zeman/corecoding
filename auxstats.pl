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
use udlib;

###!!! If we want to also enable the original command where we directly ask for
###!!! one language, we may want to reuse the code below; adjustments needed!
if(0)
{
    my $lname;
    my $lcode;
    my $lflag;
    my $lscript; # macro to use (if any) around lemmas in XeLaTeX to turn on the correct script
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
}

my $udpath = '/net/data/universal-dependencies-2.16';
my $lhash = udlib::get_language_hash('/net/work/people/zeman/unidep/docs-automation/codes_and_flags.yaml');
# Read the auxiliaries registered for individual languages in UD.
my $data = json_file_to_perl("$udpath/tools/data/data.json")->{auxiliaries};
my @folders = udlib::list_ud_folders($udpath);
print("Found ", scalar(@folders), " UD treebanks in $udpath.\n");
# Cluster the treebanks by language.
my %treebanks_by_languages;
my $n_folders_processed = 0;
my $n_folders_skipped_text = 0;
my $n_folders_skipped_lemmas = 0;
my $n_languages_processed = 0;
my $n_languages_without_auxiliaries = 0;
my $n_languages_with_copula_only = 0;
my $n_languages_with_copula_attached_as_aux = 0;
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
    elsif($metadata->{'Lemmas'} eq 'not available')
    {
        print("Skipping $folder (no lemmas).\n");
        $n_folders_skipped_lemmas++;
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
    # Get rid of lemmas that are registered as pronominal copulas only.
    my $copula_seen = 0;
    my $non_copula_seen = 0;
    foreach my $lemma (keys(%{$data->{$lcode}}))
    {
        my @functions = grep {$_->{function} ne 'cop.PRON'} (@{$data->{$lcode}{$lemma}{functions}});
        if(scalar(@functions) == 0)
        {
            ###!!! This will also delete all undocumented auxiliaries. If we want to report anything about them, we will have to modify the code.
            delete($data->{$lcode}{$lemma});
        }
        else
        {
            foreach my $function (@functions)
            {
                if($function->{function} eq 'cop.AUX')
                {
                    $copula_seen = 1;
                }
                else
                {
                    $non_copula_seen = 1;
                }
            }
        }
    }
    my @lemmas = sort(keys(%{$data->{$lcode}}));
    if(scalar(@lemmas) == 0)
    {
        #print("$lname has no documented auxiliaries.\n");
        $n_languages_without_auxiliaries++;
        next;
    }
    if($copula_seen && !$non_copula_seen)
    {
        #print("$lname has copula but no other auxiliary functions.\n");
        $n_languages_with_copula_only++;
    }
    my @files;
    foreach my $fc (@{$treebanks_by_languages{$lcode}})
    {
        push(@files, map {"$udpath/$fc->{folder}/$_"} (@{$fc->{files}}));
    }
    my %stats;
    # We may want to work with transliterated lemmas in languages that use foreign
    # writing systems. In the CoNLL-U files, we may be able to obtain them from MISC.
    # But no transliteration is available in the JSON files for the validator, so we
    # should cache the known transliterations and use them there.
    my %ltranslit;
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
            # For lemmas that are registered as possible auxiliaries, we want to
            # collect their UPOS even if it is not AUX in this context. It could be
            # VERB but also a completely unrelated homonym.
            my $lemma = $f[2];
            next if(!exists($data->{$lcode}{$lemma}));
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
            if(scalar(@{$data->{$lcode}{$lemma}{functions}}) == 1 && $data->{$lcode}{$lemma}{functions}[0]{function} eq 'cop.AUX' && $deprel =~ m/^aux(:|$)/)
            {
                $stats{cop_as_aux}{$lemma}++;
            }
        }
    }
    close(IN);
    # Print statistics.
    #print_statistics(\%stats, \%ltranslit, $data->{$lcode}, @lemmas);
    # Generate bar plot for LaTeX.
    print_latex_bar_plot($lname, $lflag, $lscript, \%stats, \%ltranslit, @lemmas);
    if(exists($stats{cop_as_aux}))
    {
        $n_languages_with_copula_attached_as_aux++;
    }
}
print("Skipped $n_folders_skipped_text treebanks because their underlying text is not accessible.\n");
print("Skipped $n_folders_skipped_lemmas treebanks because they have no lemmas.\n");
print("Processed $n_folders_processed treebanks ($n_languages_processed languages).\n");
print("$n_languages_without_auxiliaries languages have no documented auxiliaries.\n");
print("$n_languages_with_copula_only have copula but no other documented auxiliary functions.\n");
print("$n_languages_with_copula_attached_as_aux languages have examples of words whose only documented function is copula, yet they are attached as aux.\n");



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



#------------------------------------------------------------------------------
# Generates statistics of the auxiliaries in the data and prints them to
# STDOUT.
#------------------------------------------------------------------------------
sub print_statistics
{
    my $stats = shift;
    my $ltranslit = shift;
    my $data = shift; # only the subset for the current language
    my @lemmas = @_;
    foreach my $lemma (@lemmas)
    {
        print("$lemma");
        if(exists($ltranslit->{$lemma}))
        {
            print("\t$ltranslit->{$lemma}");
        }
        print("\n");
        # Print the auxiliary functions registered with the validator.
        my $functions = join(', ', map {$_->{function}} (@{$data->{$lemma}{functions}}));
        print("\tFunctions: $functions\n");
        my @deprels = sort(keys(%{$stats->{ld}{$lemma}}));
        foreach my $deprel (@deprels)
        {
            print("\t$deprel\t$stats->{ld}{$lemma}{$deprel}\n");
        }
        my @uposes = sort(keys(%{$stats->{lu}{$lemma}}));
        foreach my $upos (@uposes)
        {
            print("\t$upos\t$stats->{lu}{$lemma}{$upos}\n");
        }
    }
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
