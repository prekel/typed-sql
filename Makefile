all: build

PACKAGES = ./typed-sql.opam ./typed-sql-caqti-lwt.opam ./typed-sql-pgocaml-lwt.opam \
	./typed-sql-schema.opam ./typed-sql-schema-caqti-lwt.opam \
	./typed-sql-schema-pgocaml-lwt.opam
OCAML_VERSION ?= 5.1.1

.PHONY: create_switch
create_switch:
	opam update default
	opam switch create . $(OCAML_VERSION) --no-install -y

.PHONY: deps
deps:
	opam install --deps-only $(PACKAGES) -y

.PHONY: deps_all
deps_all:
	opam pin add bisect_ppx https://github.com/aantron/bisect_ppx.git\#2d8dffbbfc0c431a37319d4d9a143836c9ec542e -yn
	opam install --deps-only --with-test --with-doc --with-dev-setup $(PACKAGES) -y

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
	opam lint $(PACKAGES)

.PHONY: smoke
smoke:
	opam exec -- dune build -p typed-sql @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-schema @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-caqti-lwt @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-pgocaml-lwt @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-schema,typed-sql-schema-caqti-lwt @install @runtest
	opam exec -- dune build --only-packages typed-sql,typed-sql-pgocaml-lwt,typed-sql-schema,typed-sql-schema-pgocaml-lwt @install @runtest

.PHONY: check
check: fmt build test coverage coverage-all coverage-mega doc package

.PHONY: coverage coverage-all coverage-mega
coverage:
	opam exec -- bash test/coverage.sh public

coverage-all:
	opam exec -- bash test/coverage.sh all

coverage-mega:
	opam exec -- bash test/coverage.sh mega

.PHONY: release-check
release-check: check
	git diff --check

.PHONY: clean
clean:
	opam exec -- dune clean --root .
