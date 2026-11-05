.PHONY: all clean proofs

# Use the locally bundled, unchanged LIPIcs class.
# Do not search another manuscript directory for auxiliary files.

all:
	latexmk -pdf -interaction=nonstopmode -halt-on-error main.tex

proofs:
	cd .. && lake build && lake env lean TTIRFormal/Audit.lean

clean:
	latexmk -c main.tex