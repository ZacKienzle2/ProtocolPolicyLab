#!/usr/bin/env perl
use strict;
use warnings;
use FindBin ();
use File::Basename ();

my $UTF8_CHAR = qr/[\xC2-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF]{2}|[\xF0-\xF4][\x80-\xBF]{3}/;
my $AUTHOR_FIELD = qr/(?:author|editor)\s*=\s*(?:\{((?:[^{}]|\{[^{}]*\})*)\}|"([^"]*)")/is;
my $LONE_LEAD_PATCH = qr{
    ([\xC2-\xF4])(?![\x80-\xBF])
    (\.~?\s?)
    ((?:[A-Za-z\-']|\\[A-Za-z]+|\{[^{}]*\}|$UTF8_CHAR)+)
}x;

sub aux_path {
    for (reverse @_) {
        next if /^-/;
        return /\.aux$/i ? $_ : "$_.aux";
    }
    return undef;
}

sub locate_bibs {
    my ($aux) = @_;
    return () unless $aux && -f $aux;

    my (@bibs, %seen);
    open my $fh, '<', $aux or return ();
    while (<$fh>) {
        next unless /\\bibdata\{([^}]+)\}/;
        for my $name (split /,/, $1) {
            $name =~ s/\A\s+|\s+\z//g;
            next unless length $name;
            $name .= '.bib' unless $name =~ /\.bib$/i;
            next if $seen{$name}++;

            my $path;
            my @candidates = ($name, "./$name", "References/$name", "refs/$name", "bib/$name");
            push @candidates, map { "$_/$name" } grep { defined && length } ($FindBin::Bin, "$FindBin::Bin/References");
            for my $cand (@candidates) {
                $path = $cand, last if -f $cand;
            }
            unless ($path) {
                if (open my $kfh, '-|', 'kpsewhich', $name) {
                    chomp(my $kp = <$kfh> // '');
                    close $kfh;
                    $path = $kp if length $kp && -f $kp;
                }
            }
            push @bibs, $path if $path;
        }
    }
    close $fh;
    return @bibs;
}

sub split_author {
    my ($author) = @_;
    $author =~ s/\A\s+|\s+\z//g;
    return () unless length $author;

    my ($surname, $given);
    if ($author =~ /^([^,]+),\s*(.+)\z/s) {
        ($surname, $given) = ($1, $2);
    } else {
        my @parts = split /\s+/, $author;
        return () if @parts < 2;
        $surname   = pop @parts;
        $given = join ' ', @parts;
    }

    $surname =~ s/\\[A-Za-z]+\s*//g;
    $surname =~ tr/{}//d;
    $surname =~ s/\A\s+|\s+\z//g;
    $given =~ s/\A[\s{]+//;
    return () unless length $surname && length $given;
    return ($surname, $given);
}

sub index_initials {
    my (@bibs) = @_;
    my %fix;
    for my $bib (@bibs) {
        open my $fh, '<:raw', $bib or next;
        local $/;
        my $content = <$fh>;
        close $fh;

        while ($content =~ /$AUTHOR_FIELD/g) {
            for my $author (split /\s+and\s+/i, $1 // $2) {
                my ($surname, $given) = split_author($author) or next;
                next unless $given =~ /\A($UTF8_CHAR)/;
                my $char = $1;
                $fix{$surname . substr($char, 0, 1)} //= $char;
            }
        }
    }
    return \%fix;
}

sub strip_macros {
    my ($s) = @_;
    $s =~ s/\\[A-Za-z]+\s*//g;
    $s =~ tr/{}//d;
    return $s;
}

sub patch_bbl {
    my ($bbl, $fix) = @_;
    return 0 unless $bbl && -f $bbl && %$fix;

    open my $fh, '<:raw', $bbl or return 0;
    local $/;
    my $content = <$fh>;
    close $fh;

    my $hits = 0;
    $content =~ s/$LONE_LEAD_PATCH/
        my ($lead, $sep, $surname) = ($1, $2, $3);
        my $full = $fix->{strip_macros($surname) . $lead};
        defined $full ? ($hits++, $full . $sep . $surname)[1] : $lead . $sep . $surname;
    /ge;

    return 0 unless $hits;
    open my $out, '>:raw', $bbl or return 0;
    print $out $content;
    close $out;
    return $hits;
}

sub strip_blg_summary {
    my ($blg) = @_;
    return unless $blg && -f $blg;
    open my $fh, '<:raw', $blg or return;
    local $/;
    my $log = <$fh>;
    close $fh;
    return unless $log =~ s/^\(There were \d+ error messages\)\s*\z//m;
    open my $out, '>:raw', $blg or return;
    print $out $log;
    close $out;
}

sub native_path {
    my ($p) = @_;
    return $p unless defined $p && length $p;
    $p =~ s{^/([A-Za-z])/}{uc($1) . ':/'}e;
    return $p;
}

my $proj_root = native_path($FindBin::Bin);
my $sep = $^O eq 'MSWin32' || $proj_root =~ /^[A-Za-z]:/ ? ';' : ':';
$ENV{BIBINPUTS} = join $sep, $proj_root, "$proj_root/build", grep { length } ($ENV{BIBINPUTS} // '');
$ENV{BSTINPUTS} = join $sep, $proj_root, grep { length } ($ENV{BSTINPUTS} // '');

# Idempotent in-place bib patcher. Run before each bibtex invocation to
# bridge biblatex-named fields (DATE, JOURNALTITLE) into BibTeX-named
# aliases (YEAR, JOURNAL) the classic engine actually reads, and rewrap
# single-line ABSTRACT/TITLE/NOTE/KEYWORDS values whose contents contain
# internal " characters so the parser does not silently drop the entry.
# Writes back to the source path; subsequent runs are no-ops on already
# patched entries.
sub patch_bib_in_place {
    my ($src) = @_;
    return unless -f $src;

    open my $in, '<:raw', $src or return;
    local $/;
    my $content = <$in>;
    close $in;
    my $original = $content;

    $content =~ s{^(\s+(?:ABSTRACT|TITLE|NOTE|KEYWORDS)\s+=\s+)"((?:[^"\\]|\\.|"(?=.*"))*?)"(\s*,?\s*)$}{
        my ($head, $val, $tail) = ($1, $2, $3);
        $val =~ /"/ ? ($head . '{' . $val . '}' . $tail) : ($head . '"' . $val . '"' . $tail);
    }gme;

    $content =~ s{
        (\@[A-Za-z]+\{[^,]+,\s*\n)
        ((?:(?!\@[A-Za-z]+\{).)*?)
        (\n\}\s*(?:\n|\z))
    }{
        my ($header, $body, $tail) = ($1, $2, $3);
        my ($year)    = $body =~ /^\s+YEAR\s+=\s+["\{]?(\d{4})/im;
        my ($date)    = $body =~ /^\s+DATE\s+=\s+["\{]?(\d{4})/im;
        my $has_journ = $body =~ /^\s+JOURNAL\s+=/im;
        my ($jt)      = $body =~ /^\s+JOURNALTITLE\s+=\s+(.+?)\s*,?\s*$/im;
        my @inject;
        push @inject, qq{  YEAR    = "$date",\n}    if !$year && $date;
        push @inject, qq{  JOURNAL = $jt,\n}        if !$has_journ && defined $jt && length $jt;
        @inject ? $header . join('', @inject) . $body . $tail : $header . $body . $tail;
    }gxse;

    return if $content eq $original;
    open my $out, '>:raw', $src or return;
    print $out $content;
    close $out;
}

my @args = @ARGV;
my $aux  = aux_path(@args);
my @bibs = locate_bibs($aux);

# Patch every .bib referenced from the .aux in place, then call bibtex.
patch_bib_in_place($_) for @bibs;

my $rc       = system 'bibtex', @args;
my $exit_raw = $rc == -1 ? 1 : $rc >> 8;

(my $bbl = $aux // '') =~ s/\.aux$/.bbl/i;
(my $blg = $aux // '') =~ s/\.aux$/.blg/i;

if ($bbl && -f $bbl) {
    my $fix = index_initials(@bibs);
    patch_bbl($bbl, $fix);
    strip_blg_summary($blg);
    exit $exit_raw if $exit_raw > 1;
    exit 0;
}

exit($exit_raw || 1);
