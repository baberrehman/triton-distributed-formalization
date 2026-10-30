PAPER := main
LATEX := pdflatex
BIBTEX := bibtex
LATEXFLAGS := -interaction=nonstopmode -halt-on-error

.PHONY: all pdf clean distclean

all: pdf

pdf: $(PAPER).pdf

$(PAPER).pdf: $(PAPER).tex references.bib lipics-v2021.cls
	$(LATEX) $(LATEXFLAGS) $(PAPER).tex
	$(BIBTEX) $(PAPER)
	$(LATEX) $(LATEXFLAGS) $(PAPER).tex
	$(LATEX) $(LATEXFLAGS) $(PAPER).tex

clean:
	rm -f $(PAPER).aux $(PAPER).bbl $(PAPER).blg $(PAPER).log \
	      $(PAPER).out $(PAPER).vtc $(PAPER).toc $(PAPER).synctex.gz

distclean: clean
	rm -f $(PAPER).pdf
