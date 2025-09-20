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

my $family_to_process = '';
my $genus_to_process = 'Germanic';
my @lcodes_to_process = (qw());
my $udpath = '/net/data/universal-dependencies-2.16';
# Get information about languages.
my $lhash_by_names = udlib::get_language_hash('/net/work/people/zeman/unidep/docs-automation/codes_and_flags.yaml');
my $lhash_by_codes = {};
foreach my $lname (keys(%{$lhash_by_names}))
{
    $lhash_by_names->{$lname}{name} = $lname;
    $lhash_by_codes->{$lhash_by_names->{$lname}{lcode}} = $lhash_by_names->{$lname};
}
my @lcodes = sort
{
    my $aname = $lhash_by_codes->{$a}{name};
    my $bname = $lhash_by_codes->{$b}{name};
    my $afamily = $lhash_by_names->{$aname}{family};
    my $bfamily = $lhash_by_names->{$bname}{family};
    my $agenus = $lhash_by_names->{$aname}{genus};
    my $bgenus = $lhash_by_names->{$bname}{genus};
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
(keys(%{$lhash_by_codes}));
# Prepare language filtering if needed.
if($family_to_process || $genus_to_process)
{
    @lcodes_to_process = ();
    foreach my $lcode (@lcodes)
    {
        if($family_to_process)
        {
            if($lhash_by_codes->{$lcode}{family} eq $family_to_process)
            {
                push(@lcodes_to_process, $lcode);
            }
        }
        elsif($genus_to_process)
        {
            if($lhash_by_codes->{$lcode}{genus} eq $genus_to_process)
            {
                push(@lcodes_to_process, $lcode);
            }
        }
    }
}
# Get information about treebanks (folders).
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
# Collect and print the statistics for the languages requested.
my %stats;
foreach my $lcode (@lcodes_to_process)
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
    my $files = join(' ', @files);
    #open(IN, "cat $files |") or die("Cannot read CoNLL-U from $lname: $!");
    open(IN, "cat $files | udapy -s util.Eval node='if node.udeprel != \"root\": node.xpos = node.parent.lemma' 2>/dev/null |") or die("Cannot read and process CoNLL-U from $lname: $!");
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
            $stats{$lcode}{nwords}++;
            my $lemma = $f[2];
            my $plemma = $f[4]; # instead of XPOS, prepared with Udapi above
            my $upos = $f[3];
            my $deprel = $f[7];
            #next if($upos eq 'PRON' || $f[5]=~m/PronType/); ####!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! temporarily looking at non-pronominal stuff only
            if($deprel =~ m/^(nsubj|obj|iobj|obl:arg)(:|$)/)
            {
                $stats{$lcode}{deprel}{$1}++;
                $stats{$lcode}{vdeprel}{$plemma}{$1}++;
                $stats{$lcode}{nv}{$plemma}++;
            }
            else
            {
                $stats{$lcode}{deprel}{'other'}++;
                $stats{$lcode}{vdeprel}{$plemma}{'other'}++;
            }
        }
    }
    close(IN);
    $n_languages_without_iobj++ if(!exists($stats{$lcode}{deprel}{'iobj'}) || $stats{$lcode}{deprel}{'iobj'} == 0);
    # Print statistics.
    print_statistics($lname, $stats{$lcode});
}
# Generate bar plot for LaTeX.
my $title = $family_to_process ? "$family_to_process Languages" : $genus_to_process ? "$genus_to_process Languages" : join(', ', @lcodes_to_process);
print_latex_bar_plot($title, \%stats, $lhash_by_codes, @lcodes_to_process);
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
    my $focus_deprel = 'iobj';
    if($stats->{deprel}{$focus_deprel} > 0)
    {
        my @verbs = keys(%{$stats->{vdeprel}});
        @verbs = grep {$stats->{vdeprel}{$_}{$focus_deprel} > 0} (@verbs);
        @verbs = sort {
            my $r = $stats->{vdeprel}{$b}{$focus_deprel} <=> $stats->{vdeprel}{$a}{$focus_deprel};
            unless($r)
            {
                $r = $stats->{vdeprel}{$b}{$focus_deprel}/$stats->{nv}{$b} <=> $stats->{vdeprel}{$a}{$focus_deprel}/$stats->{nv}{$a};
            }
            $r
        } (@verbs);
        splice(@verbs, 5);
        if(@verbs)
        {
            my $verbs = join(', ', map {sprintf("$_ $stats->{vdeprel}{$_}{$focus_deprel} (%f)", $stats->{vdeprel}{$_}{$focus_deprel}/$stats->{nv}{$_})} (@verbs));
            print("\t$verbs\n");
        }
    }
}



#------------------------------------------------------------------------------
# Generates LaTeX code of a bar plot that shows the distribution of the
# auxiliaries in the data and prints it to STDOUT.
#------------------------------------------------------------------------------
sub print_latex_bar_plot
{
    my $title = shift;
    my $stats = shift;
    my $lhash = shift;
    my @lcodes = @_;
    # Discard languages for which we did not see any word.
    @lcodes = grep
    {
        my $ok = $stats->{$_}{nwords};
        if(!$ok)
        {
            print("Found no words in language [$_].\n");
        }
        $ok
    }
    (@lcodes);
    my $symbolic_x_coords = join(',', map {$lhash->{$_}{name}} (@lcodes));
    my $counts_nsubj = join(' ', map {$y = ($stats->{$_}{deprel}{nsubj}//0)/$stats->{$_}{nwords}*100; "($lhash->{$_}{name},$y)"} (@lcodes));
    my $counts_obj = join(' ', map {$y = ($stats->{$_}{deprel}{obj}//0)/$stats->{$_}{nwords}*100; "($lhash->{$_}{name},$y)"} (@lcodes));
    my $counts_iobj = join(' ', map {$y = ($stats->{$_}{deprel}{iobj}//0)/$stats->{$_}{nwords}*100; "($lhash->{$_}{name},$y)"} (@lcodes));
    my $counts_oblarg = join(' ', map {$y = ($stats->{$_}{deprel}{'obl:arg'}//0)/$stats->{$_}{nwords}*100; "($lhash->{$_}{name},$y)"} (@lcodes));
    my $sum_first_language = ($stats->{$lcodes[0]}{deprel}{nsubj} + $stats->{$lcodes[0]}{deprel}{obj} + $stats->{$lcodes[0]}{deprel}{iobj}) / $stats->{$lcodes[0]}{nwords};
    my $sum_last_language = ($stats->{$lcodes[-1]}{deprel}{nsubj} + $stats->{$lcodes[-1]}{deprel}{obj} + $stats->{$lcodes[-1]}{deprel}{iobj}) / $stats->{$lcodes[-1]}{nwords};
    my $legend_placement = $sum_first_language < $sum_last_language ? 'west' : 'east';
    print("$sum_first_language\t$sum_last_language\t$legend_placement\n");
    print("\n\n\n");
    print <<EOF
\\begin{frame}{$title}
  \\begin{tikzpicture}
    \\begin{axis}[
      ybar stacked,
      width=\\textwidth, height=0.8\\textheight,
      symbolic x coords={$symbolic_x_coords},
      xtick=data,
      x tick label style={rotate=45,anchor=east},
      ylabel={\\% of all tokens},
      ymin=0,
      enlargelimits=0.1,
      legend pos={north $legend_placement}
    ]
      \\addplot coordinates {$counts_nsubj};
      \\addplot coordinates {$counts_obj};
      \\addplot coordinates {$counts_iobj};
      \\addplot coordinates {$counts_oblarg};
      \\legend{nsubj,obj,iobj,obl:arg}
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
