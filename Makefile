SRC=rtl/passthrough.vhd rtl/i2c_passthrough.vhd tb/tb.vhd
OPTS=--std=93 --workdir=work
WAVE=waveforms.ghw
SAVE=waveforms.gtkw
GTKW=gtkwave
LOG=out.log

test: $(SRC)
	mkdir -p work
	for f in $(SRC); do ghdl -a $(OPTS) $$f; done
	ghdl -e $(OPTS) tb

run: test
	ghdl -r $(OPTS) tb

$(WAVE): test
	ghdl -r $(OPTS) tb --wave=$@ | tee $(LOG) | tail -n20

wave: $(WAVE)
	if [ -f $(SAVE) ]; then $(GTKW) $(SAVE); else $(GTKW) $<; fi

clean:
	rm -f *.o $(WAVE) $(LOG)
	rm -rf work

.PHONY: test clean
