all: build

PACKAGES = ./typed-sql.opam ./typed-sql-caqti-lwt.opam

.PHONY: create_switch
create_switch:
	opam update default
	opam switch create . 5.5.1 --no-install -y

.PHONY: deps
deps:
	opam install --deps-only $(PACKAGES) -y

.PHONY: deps_all
deps_all:
	opam install --deps-only --with-test --with-doc --with-dev-setup $(PACKAGES) -y

.PHONY: build
build:
	opam exec -- dune build --root . @all

.PHONY: test
test:
	opam exec -- dune runtest --root .

.PHONY: fmt
fmt:
	opam exec -- dune build --root . @fmt

.PHONY: doc
doc:
	opam exec -- dune build --root . @doc

.PHONY: package
package: smoke
	opam exec -- dune build --root . @install
	opam lint $(PACKAGES)

.PHONY: smoke
smoke:
	opam exec -- dune build -p typed-sql @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-caqti-lwt @install @runtest

.PHONY: check
check: fmt build test doc package

.PHONY: release-check
release-check: check
	git diff --check

.PHONY: clean
clean:
	opam exec -- dune clean --root .
