all: build

PACKAGES = ./typed-sql.opam ./typed-sql-caqti-lwt.opam
PGOCAML_PACKAGE = ./_build/default/typed-sql-pgocaml-lwt.opam

.PHONY: create_switch
create_switch:
	opam update default
	opam switch create . 5.1.1 --no-install -y

.PHONY: deps
deps:
	opam exec -- dune build --root . typed-sql-pgocaml-lwt.opam
	opam install --deps-only $(PACKAGES) $(PGOCAML_PACKAGE) -y

.PHONY: deps_all
deps_all:
	opam pin add bisect_ppx https://github.com/aantron/bisect_ppx.git\#2d8dffbbfc0c431a37319d4d9a143836c9ec542e -yn
	opam exec -- dune build --root . typed-sql-pgocaml-lwt.opam
	opam install --deps-only --with-test --with-doc --with-dev-setup $(PACKAGES) $(PGOCAML_PACKAGE) -y

.PHONY: build
build:
	opam exec -- dune build --root . @all

.PHONY: test
test:
	opam exec -- dune runtest --root .

.PHONY: test-postgres
test-postgres:
	opam exec -- bash test/postgresql.sh

.PHONY: fmt
fmt:
	opam exec -- dune build --root . @fmt

.PHONY: doc
doc:
	opam exec -- dune build --root . @doc

.PHONY: package
package: smoke
	opam exec -- dune build --root . @install
	opam exec -- dune build --root . typed-sql-pgocaml-lwt.opam
	opam lint $(PACKAGES) $(PGOCAML_PACKAGE)

.PHONY: smoke
smoke:
	opam exec -- dune build -p typed-sql @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-caqti-lwt @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-pgocaml-lwt @install @runtest

.PHONY: check
check: fmt build test doc package

.PHONY: coverage coverage-all
coverage:
	opam exec -- bash test/coverage.sh public

coverage-all:
	opam exec -- bash test/coverage.sh all

.PHONY: release-check
release-check: check
	git diff --check

.PHONY: clean
clean:
	opam exec -- dune clean --root .
