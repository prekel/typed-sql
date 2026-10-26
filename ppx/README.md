# PG’OCaml quotations с подготовленным кешем

`typed-sql-pgocaml-ppx` раскрывает `[%pgsql ...]` и `[%pgsql.object ...]`
по описаниям запросов, полученным через PostgreSQL Prepare/Describe.
PostgreSQL проверяет SQL и определяет типы при явном запуске `prepare/check`.
Компиляция и OCaml LSP используют встроенные metadata без подключения к БД.
Запросы выполняются через модуль `PGOCaml` приложения.

[Проверка в приложении](TRY_IN_APP.md) и [публичный контракт](../doc/ppx.md).
Для quotations, создающих `Statement.t`, `Result_query.t` и `Command.t`,
используйте [typed-sql-ppx](../query-ppx/README.md).

## Подготовить кеш

Установите `typed-sql-pgocaml-ppx` и примените миграции тестовой БД.
Подключение задаётся через `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`,
`PGDATABASE`. Пароли не записывайте в Dune и JSON.

```sh
PGDATABASE=my_app typed-sql-pgocaml-queries prepare \
  --output queries.json src/people.ml src/orders.ml
```

Команда читает OCaml AST перечисленных файлов и описывает запросы в read-only
транзакции. Пользовательский SQL, включая DML, не выполняется.
По умолчанию `search_path=public`; другой путь передайте через `--search-path`.

`queries.json` версии 2 содержит точный SQL, порядок и логические типы параметров,
поля результата, nullability, kind, ограничения вложения и контекст роли/search
path. OID, credentials и значения параметров не сохраняются. Имена OCaml binds
и locations не входят в ключ; пробелы и комментарии SQL входят.
Каждое вхождение подстановки получает свой номер `$1`, `$2` и далее.

После изменения SQL или схемы запускайте `prepare` с полным списком файлов.
Обновление атомарно: при ошибке прежний файл сохраняется. Проверка актуальности
не меняет файлы и требует ту же БД, роль, search path и исходники:

```sh
PGDATABASE=my_app typed-sql-pgocaml-queries check \
  --cache queries.json src/people.ml src/orders.ml
```

## Подключить к Dune

```lisp
(rule
 (target queries_ppx.ml)
 (deps queries.json)
 (action
  (with-stdout-to
   %{target}
   (run %{bin:typed-sql-pgocaml-queries} codegen %{dep:queries.json}))))

(library
 (name app_queries_ppx)
 (modules queries_ppx)
 (kind ppx_rewriter)
 (libraries base typed-sql-pgocaml-ppx))

(library
 (name app_queries)
 (modules people orders)
 (libraries base pgocaml)
 (preprocess (pps app_queries_ppx)))
```

В каждом PPX-драйвере регистрируется ровно один query cache. Сгенерированный
модуль встраивает JSON; при раскрытии quotation файлы не открываются, поэтому
драйвер работает и из другого рабочего каталога. При отсутствии запроса
сборка сообщает о необходимости запустить `prepare`.

Храните JSON и правила Dune в репозитории. Генерируемый `.ml` Dune создаёт сам.
Dune подключает `typed-sql-pgocaml-ppx.runtime` автоматически.
При ручной компиляции результата PPX добавьте эту библиотеку явно.

## Quotations

```ocaml
open! Base

let find conn id =
  [%pgsql.object conn
    "SELECT id, name, note FROM people WHERE id = $id"]
;;

let update conn id note =
  [%pgsql conn
    "UPDATE people SET note = $?note WHERE id = $id RETURNING note"]
;;

let remove conn id : unit =
  [%pgsql conn "DELETE FROM people WHERE id = $id"]
;;
```

`$value` принимает обязательное значение, `$?value` — `option`, `${expression}`
и `$?{expression}` — OCaml expression. Каждое вхождение вычисляется один раз
при вызове quotation. Значения передаются через bind parameters.
Strings, quoted identifiers, dollar quotes и комментарии SQL не раскрывают binds.

Scalar SELECT возвращает список значений; несколько колонок дают tuples,
`pgsql.object` — объекты с методами по именам полей. DML без RETURNING возвращает
`unit`; object quotation требует поля результата. Некорректные имена методов
и повторяющиеся имена отклоняются при компиляции.

Nullability следует PG’OCaml: для поля с происхождением используется
`pg_attribute.attnotnull`, для вычисляемых полей — nullable. Для outer JOIN,
способного вернуть NULL в исходно обязательной колонке, добавьте флаг
`"nullable-results"` перед SQL: он делает все поля результата optional.

Встроенные codecs: bool, int2 (`int`), int4 (`int32`), int8 (`int64`), float4/8
(`float`), text/varchar/bpchar/numeric/json/jsonb (`string`), bytea, date, time,
timestamp, timestamptz, interval, uuid и inet — через функции PGOCaml.
`inet` сохраняет адрес, IPv4/IPv6 host bits и длину префикса.

Одномерные native arrays представлены как `'a option list`; nullable array
имеет внешний option. NULL-элемент отличается от строки `"NULL"`. Многомерные
arrays и явные нестандартные bounds при чтении возвращают `PGOCaml.Error`.

### Конвертеры пользовательских типов

Пользовательские scalar, enum, domain и opaque types выбирают
функции по собственному имени SQL-типа: `PGOCaml.string_of_typ123` для записи
и `PGOCaml.typ123_of_string` для чтения. Domain не разворачивается до базового
codec. Встроенные типы сохраняют прежние функции, например `int4 → int32`
и `inet → inet`. Конвертеры задаются локальным модулем приложения:

```ocaml
open! Base

type typ123 = Typ123 of string

module PGOCaml = struct
  include PGOCaml

  let string_of_typ123 (Typ123 value) = value
  let typ123_of_string value = Typ123 value
end
```

Выбор автоматический и не требует config. Отсутствие функций обнаруживает
OCaml typechecker при сборке приложения.

Для native arrays рекурсивно используются конвертеры элементов; domain над
массивом использует одну собственную пару функций для всего значения.
Имена схем не входят в имена функций: одноимённые типы разных схем выбирают
одни конвертеры. Имя типа должно состоять из ASCII-букв, цифр, `_` и `'`;
остальные имена отклоняются с явной диагностикой.

Конвертер выбирается по типу, сохранённому PostgreSQL Describe. Для одиночного
domain в результате сервер обычно сообщает базовый тип: например,
`SELECT $value::typ123` принимает `typ123`, но возвращает `string option`,
если domain определён над text. В массиве domain сохраняется как тип элемента,
поэтому чтение использует `typ123_of_string`. PPX не восстанавливает утраченное
имя domain по тексту SQL или имени колонки.

Sexp config, `load_custom_from` и `PGCUSTOM_CONVERTERS_CONFIG` не поддерживаются.

## SQL fragments и preprocessing

Если SQL создаётся другим PPX, применяйте одинаковый preprocessing при
`prepare` и `check` через `--pp COMMAND`. Команда получает путь очередного
`.ml` последним аргументом и выводит OCaml source или binary AST.
Binary AST сохраняет locations. Ошибки preprocessing обнаруживаются до
подключения к БД и не перезаписывают кеш.

Пример отдельного драйвера `ppx_concat` — в
[инструкции для приложения](TRY_IN_APP.md#sql-из-другого-ppx).
Deriving, преобразующий object results в records, остаётся в обычном `pps`.

## Выполнение и ограничения

Соединение, monad, транзакции и обработка ошибок принадлежат `PGOCaml`
приложения. Сгенерированный код использует Prepare/Execute и переиспользует
prepared statement для неизменного SQL. Runtime exceptions сохраняют
PG’OCaml-контракт, включая SQLSTATE и ошибку nullability.

Для совместных транзакций с DSL используйте
`Typed_sql_pgocaml_lwt.Make (PGOCaml)` и тот же connection.
[Integration test](test/mixed_transaction_postgresql_test.ml) проверяет commit,
rollback и object → record. Дополнительное соединение для PPX не требуется.

SQL должен иметь статическую форму. `$@list`, флаг `execute`, произвольные
флаги и конфигурация Custom Type Conversions не поддерживаются. Используйте
native arrays как один bind parameter. Роль, search path, encoding и настройки
PostgreSQL при выполнении должны соответствовать подготовке.

Нужен PG’OCaml >= 4.3.0; на OCaml 5 — PG’OCaml >= 4.4.0.
Для PG’OCaml 4.3.0 передавайте Unix socket из `PGHOST` явно:
`PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") ()`.
