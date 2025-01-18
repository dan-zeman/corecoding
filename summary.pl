#!/usr/bin/env perl
# Collects reports on core argument coding and prints a summary.
# Copyright © 2024 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# We read the output of udapy my.CoreCoding. The output lines may look like this:
# SUBJECT finite nsubj NOUN+Nom SV
# OBJECT obj NOUN+Acc SVO
# IOBJECT iobj PRON+Dat SVOI
# AGREEMENT finite Number=Sing|Person=3
# Clause types are 'finite' or 'nonfin' and they are not printed for objects.
# Argument type could be 'nsubj' or 'csubj' for SUBJECT, 'obj' or 'ccomp' for OBJECT etc.
while(<>)
{
    chomp;
    # We want to summarize several types of hits separately, with relative
    # frequencies within the type.
    my $type = '';
    my $label = '';
    if(m/^(SUBJECT|OBJECT|IOBJECT|AGREEMENT)\s*(.+)$/)
    {
        $type = $1;
        $label = $2;
        # In the SUBJECT type, we may see word order tags 'SV' and 'VS' (or nothing at all when no overt subject is present).
        # In the OBJECT type, we may see 'OV' and 'VO' (these cover cases where object is present but subject is not)
        # and also 'SOV', 'OSV', 'SVO', 'OVS', 'VSO', 'VOS' where both subject and object are present.
        ###!!! In the current setting, we can either ignore SV/VS of intransitive verbs, or we must count SV/VS of transitive verbs twice.
        if($label =~ m/ ([SOV]{2,3})$/)
        {
            my $worder = $1;
            # If only one of the two arguments is present, simply remember its position w.r.t. the verb.
            if($worder =~ m/^(SV|VS|OV|VO)$/)
            {
                $h{WORDER}{$worder}++;
            }
            # If both subject and object are present, decompose the tag to subject-verb and object-verb coordinate.
            else
            {
                ###!!! The SV/VS coordinate has been already counted separately in the SUBJECT section.
                #if($worder =~ m/^(SOV|OSV|SVO)$/)
                #{
                #    $h{WORDER}{SV}++;
                #}
                #if($worder =~ m/^(VSO|VOS|OVS)$/)
                #{
                #    $h{WORDER}{VS}++;
                #}
                if($worder =~ m/^(SOV|OSV|OVS)$/)
                {
                    $h{WORDER}{OV}++;
                }
                if($worder =~ m/^(VSO|VOS|SVO)$/)
                {
                    $h{WORDER}{VO}++;
                }
            }
        }
        # Aggregate hits where a NOUN or PRON subject had morphological case
        # vs. hits where it did not. Same for objects and indirect objects,
        # but only for the nominal versions (nsubj, obj, iobj), not clauses.
        if($type =~ m/^(SUBJECT|OBJECT|IOBJECT)$/ && $label =~ m/^(?:(?:finite|nonfin) nsubj|obj|iobj) (NOUN|PRON)\+(\S+)/)
        {
            my $upos = $1;
            my $case = $2;
            # Case may include adposition(s), e.g. 'от+NoCase' or 'в+Nom'.
            my $mcase = $case;
            my $adp = '';
            if($case =~ m/^(.+)\+([^\+]+)$/)
            {
                $adp = $1;
                $mcase = $2;
            }
            # Count whether there is or is not adposition. Disregard morphological case.
            if($adp)
            {
                $h{ADPOSITION}{$upos.'1'}++;
                $h{CASE}{$type}{$case}++;
            }
            else
            {
                $h{ADPOSITION}{$upos.'0'}++;
                # Count whether there is morphological case. Only if there is no adposition.
                # Distinguish 'NoCase' (the treebank has features but this word does not have
                # 'Case' feature) from 'NOCASE' (the treebank has no features).
                if($mcase eq 'NoCase')
                {
                    $h{MORPHCASE}{$upos.'0'}++;
                }
                elsif($mcase ne 'NOCASE')
                {
                    $h{MORPHCASE}{$upos.'1'}++;
                    $h{CASE}{$type}{$mcase}++;
                }
            }
        }
    }
    else
    {
        $label = $_;
    }
    $h{$type}{$label}++;
    $n{$type}++;
    $n++;
}
# Summarize each type.
foreach my $type (qw(SUBJECT OBJECT IOBJECT AGREEMENT))
{
    print("$type:\n");
    my @keys = sort {my $r = $h{$type}{$b} <=> $h{$type}{$a}; unless($r) {$r = $a cmp $b} $r} (keys(%{$h{$type}}));
    my $portion = 0;
    foreach my $key (@keys)
    {
        my $padded = $key.(' ' x (40-length($key)));
        my $rel = $h{$type}{$key} / $n{$type};
        print("$padded\t$h{$type}{$key}\t$rel\n");
        $portion += $rel;
        last if($portion >= 0.85);
    }
}
# Summarize word order tendencies for subjects and objects.
print("WORDER:\n");
my $n = $h{WORDER}{SV}+$h{WORDER}{VS};
my $svs = $n>0 ? $h{WORDER}{VS} / $n : 0;
$n = $h{WORDER}{OV}+$h{WORDER}{VO};
my $ovo = $n>0 ? $h{WORDER}{VO} / $n : 0;
printf("SV --> %.6f --> VS\n", $svs);
printf("OV --> %.6f --> VO\n", $ovo);
# Summarize presence of case markers for nouns and pronouns.
print('ADP NOUN 0 ', $h{ADPOSITION}{NOUN0}, "\n");
print('ADP NOUN 1 ', $h{ADPOSITION}{NOUN1}, "\n");
print('ADP PRON 0 ', $h{ADPOSITION}{PRON0}, "\n");
print('ADP PRON 1 ', $h{ADPOSITION}{PRON1}, "\n");
print("CASE MARKERS (nsubj+obj+iobj together):\n");
$n = $h{ADPOSITION}{'NOUN0'}+$h{ADPOSITION}{'NOUN1'};
my $nounadp = $n>0 ? $h{ADPOSITION}{'NOUN1'} / $n : 0;
$n = $h{ADPOSITION}{'PRON0'}+$h{ADPOSITION}{'PRON1'};
my $pronadp = $n>0 ? $h{ADPOSITION}{'PRON1'} / $n : 0;
printf("NOUN without ADP --> %.6f --> with ADP\n", $nounadp);
printf("PRON without ADP --> %.6f --> with ADP\n", $pronadp);
# Summarize presence of morphological cases only if at least one treebank of the
# language has features and thus MORPHCASE exists in the hash.
if(exists($h{MORPHCASE}))
{
    print('CASE NOUN 0 ', $h{MORPHCASE}{NOUN0}, "\n");
    print('CASE NOUN 1 ', $h{MORPHCASE}{NOUN1}, "\n");
    print('CASE PRON 0 ', $h{MORPHCASE}{PRON0}, "\n");
    print('CASE PRON 1 ', $h{MORPHCASE}{PRON1}, "\n");
    $n = $h{MORPHCASE}{'NOUN0'}+$h{MORPHCASE}{'NOUN1'};
    my $nouncase = $n>0 ? $h{MORPHCASE}{'NOUN1'} / $n : 0;
    $n = $h{MORPHCASE}{'PRON0'}+$h{MORPHCASE}{'PRON1'};
    my $proncase = $n>0 ? $h{MORPHCASE}{'PRON1'} / $n : 0;
    printf("NOUN without Case (and ADP) --> %.6f --> with Case (but without ADP)\n", $nouncase);
    printf("PRON without Case (and ADP) --> %.6f --> with Case (but without ADP)\n", $proncase);
}
if(exists($h{CASE}))
{
    foreach my $type (qw(SUBJECT OBJECT IOBJECT))
    {
        if(exists($h{CASE}{$type}))
        {
            my @cases = sort {$h{CASE}{$type}{$b} <=> $h{CASE}{$type}{$a}} (keys(%{$h{CASE}{$type}}));
            my $cases = join(', ', map {"$_:$h{CASE}{$type}{$_}"} (@cases));
            print("CASES $type ==> $cases\n");
        }
    }
}
