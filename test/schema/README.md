# Тесты схемы и генератора

Здесь находятся snapshot и codegen regression tests, пользовательские codecs
и проверка использования сгенерированного модуля. Тесты runtime
PostgreSQL-типов находятся в `test/`, а интроспекции — в драйверных пакетах.
`schema_fixture.sql` — единственная миграция тестовой схемы. `make test-postgres`
применяет её к отдельной пустой базе, получает snapshot через живую
интроспекцию и сравнивает его с `schema_fixture.json` побайтно.

`schema_fixture.json` и `generated_schema.ml` — обычные файлы в исходном
каталоге. Dune компилирует сохранённый модуль и при `make test` сравнивает оба
файла с текущим выводом генераторов. Dune rules не создают их в `_build`.

После изменения fixture, правил или генератора обновите файлы командой:

```sh
bash test/schema/regenerate.sh
```

Скрипт сначала записывает оба результата во временный каталог и переносит их
в `test/schema/` только после успешной генерации.

Чтобы получить код из своей PostgreSQL-базы, задайте `PGHOST`, `PGPORT`,
`PGUSER`, `PGDATABASE` и выполните из корня проекта:

```sh
opam exec -- dune exec --root . caqti-lwt/schema/typed_sql_schema_dump.exe > schema.json
opam exec -- dune exec --root . bin/typed_sql_codegen.exe -- \
  --type-rules test/schema/schema_type_rules.json schema.json > schema.ml
```

Для схемы без пользовательских типов и переопределений удалите
`--type-rules ...`; для своей схемы задайте собственный файл правил.
