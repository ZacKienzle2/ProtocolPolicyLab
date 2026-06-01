$pdflatex = 'pdflatex -synctex=1 --shell-escape %O %S';

# biblatex uses the biber backend; latexmk auto-detects the .bcf and runs
# biber. biber is Unicode-aware, so no .bib pre-processing wrapper is
# needed. $bibtex_use = 2 lets latexmk run the backend as needed and clean
# its generated files even when a .bib is absent.
$bibtex_use = 2;

$cleanup_includes_generated = 1;
$cleanup_includes_cusdep_generated = 1;
@generated_exts = (@generated_exts, 'synctex.gz', 'bbl', 'bcf', 'run.xml', 'bcf-SAVE-ERROR');
