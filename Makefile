.PHONY: all test m64k-test m68k-m00-test soc-test reference-test decode-check audit-check clean

all: test

test: m68k-m00-test soc-test

m64k-test: test

m68k-m00-test:
	$(MAKE) -C sim/m68k/m00 test

soc-test:
	$(MAKE) -C sim/soc test

reference-test:
	$(MAKE) -C sim/m68k/m00 reference-test

decode-check:
	$(MAKE) -C sim/m68k/m00 decode-check

audit-check:
	$(MAKE) -C sim/m68k/m00 audit-check

clean:
	$(MAKE) -C sim/m68k/m00 clean
	$(MAKE) -C sim/soc clean
	$(RM) -r build
