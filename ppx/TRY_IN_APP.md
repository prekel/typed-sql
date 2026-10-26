# Подключить PPX к приложению

Примеры используют библиотеку `src/db/app_db` и модуль приложения `PGOCaml`.
Сохраните исходную сборку и тесты с upstream `pgocaml_ppx` для сравнения.
Для подготовки metadata используйте тестовую БД с применёнными миграциями
и ролью приложения.

## Установить пакеты

Для локального checkout:

```sh
TYPED_SQL_CHECKOUT=/absolute/path/to/typed-sql

opam pin add --no-action --kind=path typed-sql "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-schema "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-ppx "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-pgocaml-ppx "$TYPED_SQL_CHECKOUT"
opam install typed-sql-pgocaml-ppx
```

После изменения checkout переустановите пакет через
`opam reinstall typed-sql-pgocaml-ppx` в switch приложения.
PG’OCaml >= 4.3.0 поддерживается на OCaml 4.14.1; для OCaml 5 нужен >= 4.4.0.

## Подготовить и подключить metadata

```bash
export PGHOST=/path/to/postgresql/socket
export PGPORT=5432
export PGUSER=my_app
export PGDATABASE=my_app_test

mkdir -p offline_sql_ppx/cache
shopt -s globstar

opam exec -- typed-sql-pgocaml-queries prepare \
  --output offline_sql_ppx/cache/queries.json \
  --search-path public src/db/**/*.ml
```

Не включайте `_build` и исходники, относящиеся к другой БД.
Команда описывает SQL без выполнения пользовательских запросов.
Используйте свой `search_path`, если приложение отличается от `public`.

Создайте `offline_sql_ppx/cache/dune`:

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
```

В `src/db/dune` подключите `app_queries_ppx` вместо upstream `pgocaml_ppx`:

```lisp
(preprocess (pps ppx_let app_queries_ppx app_deriving))
```

`app_deriving` обозначает существующий deriving приложения; добавлять его
специально для PPX не нужно. В драйвере должен быть ровно один query cache.
Для пользовательских типов определите `PGOCaml.string_of_TYPENAME` и
`PGOCaml.TYPENAME_of_string` в локальном модуле приложения:
[пример и правила](README.md#конвертеры-пользовательских-типов).

```sh
opam exec -- dune build src/db/app_db.cma
```

Для проверки metadata без изменения JSON:

```bash
opam exec -- typed-sql-pgocaml-queries check \
  --cache offline_sql_ppx/cache/queries.json \
  --search-path public src/db/**/*.ml
```

## SQL из другого PPX

Если SQL собирается другим PPX, например из общих fragments через
`let%concat` и `[%concat ...]`, применяйте тот же preprocessing при
`prepare` и `check` с параметром `--pp`.

Для `ppx_concat`, зарегистрированного через `Driver.register_transformation
~preprocess_impl ~rules`, создайте `offline_sql_ppx/concat_driver.ml`:

```ocaml
open! Base

let () = Ppxlib.Driver.standalone ()
```

В `offline_sql_ppx/dune` укажите установленную в приложении библиотеку PPX:

```lisp
(executable
 (name concat_driver)
 (modules concat_driver)
 (libraries base ppxlib ppx_concat)
 (link_flags -linkall))
```

`-linkall` включает модуль с регистрацией преобразования.
Драйвер должен содержать preprocessing, создающий SQL, и оставлять `%pgsql`
для сборщика. Не добавляйте сюда `pgocaml_ppx` или query-cache
provider. Поэтому этот драйвер можно собрать до подготовки первого кеша:

```sh
opam exec -- dune build offline_sql_ppx/concat_driver.exe
```

Подготовка и проверка кеша используют одну команду preprocessing:

```bash
shopt -s globstar
sql_pp='_build/default/offline_sql_ppx/concat_driver.exe -dump-ast --impl'

opam exec -- typed-sql-pgocaml-queries prepare \
  --output offline_sql_ppx/cache/queries.json \
  --search-path public --pp "$sql_pp" src/db/**/*.ml

opam exec -- typed-sql-pgocaml-queries check \
  --cache offline_sql_ppx/cache/queries.json \
  --search-path public --pp "$sql_pp" src/db/**/*.ml
```

`--pp` запускает shell-команду из текущего рабочего каталога и добавляет
экранированный путь очередного `.ml` последним аргументом. Stdout должен
содержать только OCaml source или binary AST; stderr остаётся каналом
диагностик. В примере `-dump-ast` сохраняет исходные locations, включая номера
строк после удаления `let%concat`. Текстовый вывод тоже принимается, но его
номера строк относятся к результату preprocessing. Временные файлы удаляются
после обработки. При ошибке команды или разбора её результата сборщик
завершается до подключения к БД и сохраняет прежний кеш.

Обычная сборка приложения продолжает использовать оба PPX:

```lisp
(preprocess (pps ppx_concat ppx_let app_queries_ppx app_deriving))
```

Ppxlib запускает `preprocess_impl` до правил раскрытия `%pgsql`, поэтому
SQL fragments становятся литералами до поиска запроса в кеше. Используйте
одинаковые версии, параметры и cookies `ppx_concat` в отдельном драйвере и
обычной сборке; параметры драйвера можно включить в строку `--pp`.
Изменение общего fragment требует повторной подготовки кеша, как изменение
обычного SQL literal. Та же опция работает при подготовке кеша для новых
`.query`, `.command` и `.statement` quotations.

## Проверить приложение

Запустите тесты на той же БД. Сравните OCaml-типы, object → record converters,
NULL, порядок строк, SQLSTATE, DML-побочные эффекты и транзакции.
Для outer JOIN используйте `"nullable-results"`, если требуется.

Проверьте сборку и LSP с недоступной БД:

```sh
opam exec -- dune clean
PGHOST=/nonexistent/offline-ppx opam exec -- dune build src/db/app_db.cma
```

Тесты, выполняющие SQL, требуют работающего подключения. Если другие зависимости
используют upstream PPX с обращением к БД, переведите и их quotations на кеш.
Храните JSON и Dune-конфигурацию в репозитории; генерируемый provider Dune
создаёт сам. В приложении при выполнении JSON не нужен.

[typed-sql-ppx](../query-ppx/README.md) позволяет создавать query/command/statement
quotations и выполнять их через Caqti или PG’OCaml adapters.
