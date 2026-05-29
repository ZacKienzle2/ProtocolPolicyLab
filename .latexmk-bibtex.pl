#!/usr/bin/env perl
use strict;
use warnings;
use FindBin ();
use File::Basename ();
use Unicode::Normalize qw(NFD);

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
# ABSTRACT/TITLE/SHORTTITLE/NOTE/ANNOTE/KEYWORDS/COPYRIGHT values (single-
# or multi-line) whose contents contain internal " characters so the
# parser does not silently drop the entry.
# Writes back to the source path; subsequent runs are no-ops on already
# patched entries.
# ---------------------------------------------------------------------
# UTF-8 -> LaTeX transliteration. BibTeX (unlike biber) is not Unicode
# aware, so Zotero's smart quotes, dashes, symbols and accented letters
# must be rewritten to LaTeX control sequences before the engine parses
# the file. Accented Latin letters are handled generically via NFD
# decomposition; anything still non-ASCII (emoji, CJK) is dropped.
# ---------------------------------------------------------------------
my %TYPO = (
    "\x{2018}" => "`",  "\x{2019}" => "'",  "\x{201A}" => ",",
    "\x{201C}" => "``", "\x{201D}" => "''", "\x{201E}" => ",,",
    "\x{2013}" => "--", "\x{2014}" => "---", "\x{2015}" => "---",
    "\x{2026}" => "\\ldots{}", "\x{00A0}" => "~", "\x{2009}" => "\\,",
    "\x{2007}" => "~", "\x{202F}" => "\\,", "\x{2212}" => "-",
    "\x{00D7}" => "\$\\times\$", "\x{00B7}" => "\\textperiodcentered{}",
    "\x{2022}" => "\\textbullet{}", "\x{00B0}" => "\\textdegree{}",
    "\x{20AC}" => "\\texteuro{}", "\x{00A3}" => "\\pounds{}",
    "\x{00A9}" => "\\textcopyright{}", "\x{00AE}" => "\\textregistered{}",
    "\x{2122}" => "\\texttrademark{}", "\x{00BD}" => "1/2",
    "\x{00BC}" => "1/4", "\x{00BE}" => "3/4", "\x{2032}" => "'",
    "\x{2033}" => "''", "\x{2192}" => "\$\\to\$",
);
my %SPECIAL = (
    "\x{00F8}" => "\\o{}", "\x{00D8}" => "\\O{}", "\x{0142}" => "\\l{}",
    "\x{0141}" => "\\L{}", "\x{00DF}" => "\\ss{}", "\x{00E6}" => "\\ae{}",
    "\x{00C6}" => "\\AE{}", "\x{0153}" => "\\oe{}", "\x{0152}" => "\\OE{}",
    "\x{00F0}" => "\\dh{}", "\x{00FE}" => "\\th{}", "\x{0111}" => "\\dj{}",
    "\x{0110}" => "\\DJ{}", "\x{00E5}" => "\\r{a}", "\x{00C5}" => "\\r{A}",
);
my %ACCENT = (
    "\x{0301}" => "'", "\x{0300}" => "`", "\x{0302}" => "^", "\x{0308}" => '"',
    "\x{0303}" => "~", "\x{0304}" => "=", "\x{0307}" => ".", "\x{030C}" => "v",
    "\x{0306}" => "u", "\x{0327}" => "c", "\x{030A}" => "r", "\x{0328}" => "k",
    "\x{0323}" => "d", "\x{0331}" => "b", "\x{0341}" => "'", "\x{0340}" => "`",
    "\x{0342}" => "^",
);

sub _apply_accents {
    my ($base, $marks) = @_;
    my $out = $base;
    for my $m (split //, $marks) {
        my $cmd = $ACCENT{$m};
        next unless defined $cmd && length $cmd;
        $out = "\\$cmd\{$out\}";
    }
    # Brace-wrap so a diaeresis (\") cannot terminate a "-delimited field.
    return "{" . $out . "}";
}

sub latexify_unicode {
    my ($s) = @_;
    $s =~ s/([\x{2018}\x{2019}\x{201A}\x{201C}\x{201D}\x{201E}\x{2013}\x{2014}\x{2015}\x{2026}\x{00A0}\x{2009}\x{2007}\x{202F}\x{2212}\x{00D7}\x{00B7}\x{2022}\x{00B0}\x{20AC}\x{00A3}\x{00A9}\x{00AE}\x{2122}\x{00BD}\x{00BC}\x{00BE}\x{2032}\x{2033}\x{2192}])/$TYPO{$1}/ge;
    $s =~ s/([\x{00F8}\x{00D8}\x{0142}\x{0141}\x{00DF}\x{00E6}\x{00C6}\x{0153}\x{0152}\x{00F0}\x{00FE}\x{0111}\x{0110}\x{00E5}\x{00C5}])/$SPECIAL{$1}/ge;
    $s = NFD($s);
    $s =~ s/([A-Za-z])([\x{0300}-\x{036F}]+)/_apply_accents($1, $2)/ge;
    $s =~ s/[\x{0300}-\x{036F}]//g;   # orphan combining marks
    $s =~ s/[^\x{0000}-\x{007F}]//g;  # any residue (emoji, CJK, unmapped)
    return $s;
}

# Idempotent in-place bib patcher. Run before each bibtex invocation to
# bridge biblatex-named fields (DATE, JOURNALTITLE) into BibTeX-named
# aliases (YEAR, JOURNAL), rewrap values whose contents contain internal
# " characters, and transliterate UTF-8 to LaTeX so the non-Unicode
# engine parses the file. Writes back to the source; subsequent runs are
# no-ops on already patched, already ASCII entries.
sub patch_bib_in_place {
    my ($src) = @_;
    return unless -f $src;

    open my $in, '<:raw', $src or return;
    local $/;
    my $content = <$in>;
    close $in;
    utf8::decode($content);
    my $original = $content;

    $content =~ s{
        ^(\s+(?:ABSTRACT|TITLE|SHORTTITLE|NOTE|ANNOTE|KEYWORDS|COPYRIGHT)\s+=\s+)
        "(.*?)"
        ([ \t]*,?[ \t]*)
        (?=\r?\n\s*(?:[A-Z][A-Za-z]*\s*=|\}))
    }{
        my ($head, $val, $tail) = ($1, $2, $3);
        $val =~ /"/ ? ($head . '{' . $val . '}' . $tail) : ($head . '"' . $val . '"' . $tail);
    }gmsxe;

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

    $content = latexify_unicode($content);

    return if $content eq $original;
    utf8::encode($content);
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
