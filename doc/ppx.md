# SQL quotations через подготовленные metadata

`typed-sql-pgocaml-ppx` сохраняет выполняющие quotations `[%pgsql ...]` и
`[%pgsql.object ...]`. `typed-sql-ppx` создаёт `Result_query.t`, `Command.t`
и `Statement.t`. Оба используют кеш версии 3, подготовленный через PostgreSQL
Prepare/Describe.

- [Подключение выполняющего PG’OCaml PPX](../ppx/README.md).
- [Проверка в приложении](../ppx/TRY_IN_APP.md).
- [Quotations для typed-sql и adapters](../query-ppx/README.md).
- [Планы развития](ppx_roadmap.md).

## Жизненный цикл

1. Применить миграции тестовой БД.
2. Запустить `typed-sql-pgocaml-queries prepare --output queries.json FILE.ml...`.
3. Встроить кеш через `codegen` и подключить provider в Dune `(pps ...)`.
4. Собирать приложение и пользоваться LSP без подключения к БД.
5. При изменении SQL или схемы обновить metadata; `check` проверяет актуальность
   без записи файла.

SQL проверяет PostgreSQL. `prepare/check` используют read-only транзакцию и
не выполняют пользовательские DML. Роль, search path и настройки соединения
должны соответствовать приложению. При сборке выполняются поиск точного SQL,
выбор конвертеров и генерация bindings.

Кеш хранит логические имена типов, их nested metadata, поля результата,
nullability, statement kind и ограничения вложения. Значения binds, OID,
connections и credentials в нём отсутствуют. Общая таблица типов исключает
повторение metadata; [формат файла](query_cache.md) описывает ссылки и порядок.

## Выполняющие quotations

```ocaml
open! Base

let find conn id =
  [%pgsql.object conn "SELECT id, name, note FROM people WHERE id = $id"]
;;

let rename conn id name =
  [%pgsql conn "UPDATE people SET name = $name WHERE id = $id RETURNING name"]
;;

let remove conn id : unit =
  [%pgsql conn "DELETE FROM people WHERE id = $id"]
;;
```

SQL — строковый literal с фиксированной формой. `$value` передаёт обязательное
значение, `$?value` — option; `${expression}` и `$?{expression}` принимают
OCaml expressions. Каждое вхождение вычисляется один раз при вызове и получает
свой bind slot. Strings, identifiers, dollar quotes и комментарии SQL
сохраняются без интерпретации подстановок внутри них.

Scalar rows возвращаются списком, несколько колонок — списком tuples.
`pgsql.object` формирует методы по именам полей; повторяющиеся и некорректные
имена отклоняются. DML без RETURNING возвращает `unit`.

Для прямой колонки nullability определяется `pg_attribute.attnotnull`, для
вычисляемого поля — nullable. Флаг `"nullable-results"` делает все поля optional,
в частности для outer JOIN. Типы и nullability задаются сохранёнными metadata.

## Типы и конвертеры

Встроенные PostgreSQL types используют PG’OCaml codecs. `int2` имеет тип `int`,
`int4` — `int32`, `int8` — `int64`, numeric/json/jsonb — `string`.
Одномерные native arrays имеют тип `'a option list`, nullable array добавляет
внешний option. Wire format массивов обрабатывает `typed-sql-pgocaml-ppx.runtime`.

Пользовательские scalar, enum, domain и opaque types выбирают
`PGOCaml.string_of_TYPENAME` и `PGOCaml.TYPENAME_of_string`. Эти функции
разрешаются через локальный модуль приложения. Имя схемы не входит в имя
функции; допустимы ASCII-буквы, цифры, `_` и `'`.

Domain использует собственную пару конвертеров, пока его имя присутствует в
metadata. Для одиночного domain в результате Describe обычно возвращает base
type; для элемента массива domain сохраняется. Подробности и пример —
[в руководстве](../ppx/README.md#конвертеры-пользовательских-типов).

## Выполнение

Runtime вызывает Prepare/Execute через `PGOCaml` приложения и переиспользует
prepared statements. Соединения, monad и транзакции принадлежат приложению.
SQLSTATE и runtime exceptions следуют PG’OCaml-контракту.

Для совместного выполнения quotations и DSL в Lwt-транзакции используйте
`Typed_sql_pgocaml_lwt.Make (PGOCaml)` с одним соединением.
[Integration test](../ppx/test/mixed_transaction_postgresql_test.ml) проверяет
commit, rollback и object → record.

## Ограничения

- Ровно один embedded query cache на PPX-драйвер.
- SQL должен присутствовать в кеше с точным совпадением bytes.
- `$@list` и флаг `execute` не поддерживаются; используйте native array bind.
- Из флагов доступен `nullable-results`.
- Многомерные arrays и явные нестандартные bounds при чтении отклоняются.
- Sexp config, `load_custom_from` и `PGCUSTOM_CONVERTERS_CONFIG` не поддерживаются.
- Для SQL, создаваемого другим PPX, нужен одинаковый `--pp COMMAND` при
  `prepare/check` и preprocessing обычной сборки.

Для нового `typed-sql-ppx` дополнительно действуют ограничения raw PostgreSQL
queries: некоторые запросы допустимы только на верхнем уровне. Кеш хранит эти
ограничения, а compiler проверяет размещение при композиции с DSL.
