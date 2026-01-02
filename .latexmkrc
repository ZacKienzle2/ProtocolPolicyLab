$pdflatex = 'pdflatex --shell-escape %O %S';
$bibtex_use = 2; # Use Biber only when necessary
$cleanup_includes_generated = 1;
$cleanup_includes_cusdep_generated = 1;
@generated_exts = (@generated_exts, 'synctex.gz', 'bbl', 'bcf', 'run.xml');
