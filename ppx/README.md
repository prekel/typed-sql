# Offline-замена pgocaml_ppx

`typed-sql-pgocaml-ppx` проверяет SQL по заранее сохранённой схеме PostgreSQL.
Во время компиляции подключение к БД не требуется. Приложение сохраняет
`[%pgsql ...]`, `[%pgsql.object ...]`, соединения и выполнение через `PGOCaml`.
Переходить на query builder для этого не нужно.

Пакет экспериментальный: поддерживается описанное ниже подмножество SQL,
а не все возможности PostgreSQL и upstream PPX. Текущая зависимость —
`pgocaml >= 4.3.0`. PG’OCaml 4.3.0 требует OCaml младше 5.0;
для этой связки используйте OCaml 4.14.1. На OCaml 5 используйте PG’OCaml 4.4.0
или совместимую более новую версию.

У PG’OCaml 4.3.0 Unix-путь из `PGHOST` нужно передавать явно:
`PGOCaml.connect ?host:(Stdlib.Sys.getenv_opt "PGHOST") ()`.
Дампер делает это сам; offline PPX не создаёт соединений.

## 1. Сохранить схему

После применения миграций создайте snapshot версии 3:

```sh
typed-sql-pgocaml-schema-dump postgresql:// > schema.json
```

Дампер устанавливается с пакетом `typed-sql-schema-pgocaml-lwt`. Подключение
настраивается через URI или переменные `PGHOST`, `PGPORT`, `PGUSER`,
`PGPASSWORD`, `PGDATABASE`. БД нужна на этом шаге, но не при последующей сборке.

Вместо него можно использовать `typed-sql-schema-dump` из
`typed-sql-schema-caqti-lwt`: формат snapshot одинаковый. Используйте актуальный
дампер, чтобы сохранить metadata для enum, domain и arrays.

Snapshot содержит описание схемы, а не данные таблиц или параметры подключения.
Его можно хранить в репозитории. После изменения схемы обновляйте snapshot
и пересобирайте приложение. Подробнее — [формат snapshot](../doc/schema_snapshot.md).

## 2. Подключить PPX в Dune

Нужны пакеты `typed-sql-schema` (команда `typed-sql-codegen`),
`typed-sql-pgocaml-ppx`, `pgocaml` и `base` для примеров ниже.
Дампер нужен только для получения snapshot.

Минимальная структура каталога:

```text
dune
schema.json
queries.ml
```

Содержимое `dune`:

```lisp
(rule
 (target schema_ppx.ml)
 (deps schema.json)
 (action
  (with-stdout-to
   %{target}
   (run %{bin:typed-sql-codegen} --target pgocaml-ppx %{dep:schema.json}))))

(library
 (name app_schema_ppx)
 (modules schema_ppx)
 (kind ppx_rewriter)
 (libraries base typed-sql-schema typed-sql-pgocaml-ppx))

(library
 (name queries)
 (modules queries)
 (libraries base pgocaml)
 (preprocess (pps app_schema_ppx)))
```

Здесь списки `modules` разделяют сгенерированный PPX-модуль и код приложения.
В существующем проекте можно разместить schema PPX в отдельном каталоге.

Dune генерирует `schema_ppx.ml` и связывает схему с PPX-драйвером. При изменении
`schema.json` драйвер пересобирается автоматически. Вручную генерировать
или коммитить `schema_ppx.ml` не требуется.

В приложении с upstream PPX замените `pgocaml_ppx` в `preprocess` на
`app_schema_ppx`, сохранив остальные preprocessors, например `ppx_let`
или свой deriving. Одновременно подключать оба SQL PPX нельзя: они регистрируют
одинаковые extension names. В одном драйвере должна быть ровно одна schema PPX
библиотека.

Путь к JSON через флаг PPX передавать не нужно: схема встроена в драйвер.
Это работает и при обработке файлов OCaml LSP в Zed. Для выполнения приложения
файл snapshot и дампер не требуются.

## 3. Писать запросы

Примеры `queries.ml` предполагают таблицу `public.people` с колонками
`id integer NOT NULL`, `name text NOT NULL`, `note varchar NULL`.
Они используют обычный синхронный `PGOCaml`; соединением `dbh` управляет
приложение.

```ocaml
open! Base

let names dbh (id : int32) : string list =
  [%pgsql dbh "SELECT name FROM people WHERE id = $id ORDER BY id"]
;;

let people dbh ~limit ~offset : (int32 * string * string option) list =
  [%pgsql dbh
    {sql|SELECT id, name, note FROM people
         ORDER BY id LIMIT $limit OFFSET $offset|sql}]
;;

let rename dbh ~id ~name : unit =
  [%pgsql dbh "UPDATE people SET name = $name WHERE id = $id"]
;;

let delete dbh ~id : int32 list =
  [%pgsql dbh "DELETE FROM people WHERE id = $id RETURNING id"]
;;
```

Одна колонка возвращается списком значений, несколько — списком tuples.
INSERT/UPDATE/DELETE без RETURNING возвращают `unit`; с RETURNING действуют
те же правила, что для SELECT. В приложении с монадным модулем `PGOCaml`
результат остаётся в его монаде.

### Объекты и существующий object → record converter

```ocaml
type person =
  { identifier : int32
  ; name : string
  ; note : string option
  }

let person_of_pgocaml row =
  { identifier = row#identifier; name = row#name; note = row#note }
;;

let find dbh ~id =
  let rows =
    [%pgsql.object dbh
      {sql|SELECT id AS identifier, name, note
           FROM people WHERE id = $id|sql}]
  in
  List.map rows ~f:person_of_pgocaml
;;
```

Object methods получают имена колонок или aliases из `AS`. Они должны быть
уникальными и допустимыми OCaml method names. Если существующий deriving
приложения генерирует такой converter, его можно оставить: при совпадении
типов методов вызов `List.map ... ~f:t_of_pgocaml` сохраняется.
У `[%pgsql.object ...]` для DML обязательно наличие RETURNING.

### Параметры и NULL

| Синтаксис | Значение |
| --- | --- |
| `$id` | OCaml-переменная `id` |
| `${Int32.succ id}` | OCaml-выражение |
| `$?note` | Значение `option`: `None` отправляется как SQL NULL |
| `$?{expression}` | OCaml-выражение типа `option` |

Тип параметра выводится из SQL. Например, `integer` использует `int32`,
`bigint` — `int64`, `smallint` — `int`, `numeric` — `string`,
а LIMIT/OFFSET — `int64`. Значения передаются отдельно от SQL как bind parameters.
Обычные OCaml-строки, `{|...|}` и `{sql|...|sql}` поддерживаются.

`WHERE note = $?note` с `None` сохраняет SQL-семантику сравнения с NULL:
это не проверка `IS NULL` и не удаление условия.

Native array передаётся одним параметром и представлен как `'a option list`:

```ocaml
let find_many dbh (ids : int32 option list) : int32 list =
  [%pgsql dbh "SELECT id FROM people WHERE id = ANY($ids) ORDER BY id"]
;;
```

Здесь `[ Some 1l; Some 2l ]` — array из двух чисел, `[]` — пустой array,
а `None` внутри списка — NULL-элемент. Для SQL NULL всего array используется
optional-подстановка `$?ids` с внешним `option`.

## Вместе с query builder в одной транзакции

Подключите `typed-sql-pgocaml-lwt`, `typed-sql` и `lwt.unix` к библиотеке
приложения. Quotations генерируют вызовы модуля с именем `PGOCaml`;
query builder должен использовать адаптер того же модуля:

```ocaml
module PGOCaml = Typed_sql_pgocaml_lwt.Pgocaml
module Adapter = Typed_sql_pgocaml_lwt.Make (PGOCaml)
```

Внутри `Adapter.transaction ~conn ~f` передавайте полученный `conn` как
в `Adapter.run ~conn statement input`, так и в `[%pgsql conn ...]` или
`[%pgsql.object conn ...]`. Quotations с таким модулем возвращают `Lwt.t`.
Оба способа выполнения видят изменения друг друга до commit.

Callback транзакции возвращает `Result.t Lwt.t`: `Ok` фиксирует все изменения,
`Error` откатывает их. Исключение quotation также приводит к rollback
и преобразуется в ошибку адаптера. Для прикладного Lwt-модуля `PGOCaml`
используйте `Typed_sql_pgocaml_lwt.Make (PGOCaml)` с этим модулем;
дополнительное соединение или вложенная транзакция для PPX не нужны.

[Полный тест](test/mixed_transaction_postgresql_test.ml) показывает запись
и чтение обоими способами, object → record, commit и два варианта rollback.
Он запускается через `make test-postgres`; обычный `make test` не требует БД.

## Ограничения и совместимость

- **Форма SQL только статическая.** SQL, число placeholders и тип результата
  фиксируются при компиляции. List-подстановки `$@ids` и их варианты пока
  отклоняются. Native arrays через `ANY($ids)` сохраняют статическую форму.
- Поддерживаются SELECT, INSERT/UPDATE/DELETE с RETURNING и без него,
  WHERE с AND/OR/NOT, сравнениями и IS NULL, LIMIT/OFFSET, JOIN,
  expressions, известные aggregates, GROUP BY/HAVING, подзапросы, CTE
  и UNION/INTERSECT/EXCEPT, LATERAL derived SELECT, window functions,
  unnest/generate_series в FROM и SELECT, ROWS FROM с ordinality, GROUP BY
  по primary key, UPDATE FROM / DELETE USING. E-strings и dollar-quoted literals
  также доступны. У каждой группы есть ограничения;
  [полный список](../doc/ppx.md) описывает поддержанные формы.
- Поддерживаются enum как `string`, domain через базовый codec и одномерные
  arrays. Многомерные arrays не поддерживаются.
- Nullability следует правилам PG’OCaml. Например, `count(*)` даёт
  `int64 option list`. Прямая NOT NULL колонка на nullable стороне outer JOIN
  сохраняет исходный тип: используйте флаг `"nullable-results"` перед SQL,
  чтобы все поля результата стали `option`.
- Неквалифицированные таблицы разрешаются в `public`. Для других схем пишите
  `schema.table`. При выполнении схема и `search_path` соединения должны
  соответствовать snapshot. Сервер проверяет ограничения данных и права доступа.
- Поддержаны lower/upper, length, trim, позиционный substring, replace,
  concat, abs/round, JSON extraction и IS DISTINCT FROM. Произвольные SQL
  functions/operators, прочие table functions и regex-overloads substring пока
  отклоняются. Обращения в БД для уточнения типов нет.
- Несколько SRF в SELECT или функций в ROWS FROM разворачиваются совместно
  с дополнением коротких результатов NULL. Для них доступны scalar wrappers,
  вложенность в SELECT и aliases; действуют контекстные запреты PostgreSQL
  для WHERE, CASE/COALESCE, аргументов агрегатов/окон и DML RETURNING.
- Доступны cardinality, array_length и array_to_string; для GROUP BY по полному
  non-deferrable PK обновите snapshot с metadata deferrability версии 3.
- Для точных same-type casts varchar/numeric и временных колонок обновите
  snapshot: optional typmod metadata сохраняются в версии 3. Старые snapshots
  читаются, но неоднозначный cast без нужных metadata даёт diagnostic.
- Custom Type Conversions, sexp config, `load_custom_from` и
  `PGCUSTOM_CONVERTERS_CONFIG` пока не поддерживаются. Они запланированы последними
  и требуют отдельного согласования реализации.
- `%pgsql.query`, `%pgsql.query.object`, `%pgsql.statement` и
  `%pgsql.statement.object` находятся в roadmap. Текущие quotations выполняют
  запрос через `PGOCaml`, а не возвращают `Result_query.t` или `Statement.t`.

Array runtime `typed-sql-pgocaml-ppx.runtime` Dune подключает автоматически.
При ручном запуске PPX и компилятора его нужно добавить самостоятельно.

## Если сборка не проходит

- Ошибка отсутствующей схемы: проверьте, что в `pps` подключена именно
  сгенерированная `app_schema_ppx`, а не только `typed-sql-pgocaml-ppx`.
- Ошибка нескольких схем: оставьте одну schema PPX библиотеку в драйвере.
- Не найдена таблица, колонка или native metadata: обновите snapshot актуальным
  дампером и проверьте квалификацию имён. Snapshot версии 2 для этого PPX
  не подходит.
- Ошибка типа параметра: проверьте представление PG’OCaml, например `int32`
  для `integer`. Типы OCaml не всегда совпадают с типами query builder.

Подробности: [руководство](../doc/ppx.md), [roadmap](../doc/ppx_roadmap.md),
[происхождение кода](ORIGIN.md) и [лицензия](COPYING).
