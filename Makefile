# The path to the current UD is hard-coded in familystats-corecoding.pl.
# The output log contains various statistics and at the end it contains the LaTeX source of the word order plot.
all:
	perl familystats-corecoding.pl |& tee familystats-corecoding.log
