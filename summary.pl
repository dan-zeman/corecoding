#!/usr/bin/env perl
# Collects reports on core argument coding and prints a summary.
# Copyright © 2024 Dan Zeman <zeman@ufal.mff.cuni.cz>
# License: GNU GPL

use utf8;
use open ':utf8';
binmode(STDIN, ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

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
print("WORDER:\n");
my $n = $h{WORDER}{SV}+$h{WORDER}{VS};
my $svs = $n>0 ? $h{WORDER}{VS} / $n : 0;
$n = $h{WORDER}{OV}+$h{WORDER}{VO};
my $ovo = $n>0 ? $h{WORDER}{VO} / $n : 0;
print("SV --> $svs --> VS\n");
print("OV --> $ovo --> VO\n");
