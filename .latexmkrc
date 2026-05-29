$pdflatex = 'pdflatex --shell-escape %O %S';
$bibtex_use = 2; # Use Biber only when necessary

# Route bibtex through the in-tree wrapper that patches biblatex field
# aliases and re-wraps values containing internal " characters before the
# classic engine parses them. Root resolved at rc-read time (run latexmk
# from the repository root, per README) to avoid hard-coded paths.
use Cwd qw(getcwd);
my $ppl_root = getcwd();
$bibtex = "perl \"$ppl_root/.latexmk-bibtex.pl\" %O %B";
$cleanup_includes_generated = 1;
$cleanup_includes_cusdep_generated = 1;
@generated_exts = (@generated_exts, 'synctex.gz', 'bbl', 'bcf', 'run.xml');
