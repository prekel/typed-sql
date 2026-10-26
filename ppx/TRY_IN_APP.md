# Как попробовать оба режима в существующем приложении

Начните с одной библиотеки приложения, в которой уже есть `[%pgsql ...]`
и `[%pgsql.object ...]`. Ниже это каталог `src/db` и библиотека `app_db`.
Подставьте свои имена и сохраните существующие
`libraries`, параметры Dune и остальные PPX.

SQL, модуль `PGOCaml`, его Lwt-реализацию, соединения, транзакции и прикладной
deriving для object → record менять не нужно. В частности, остаётся рабочим
`List.map results ~f:t_of_pgocaml`. Оба режима генерируют выполнение запроса,
а не `Statement.t` или `Result_query.t`.

## Подготовить окружение и исходную проверку

Создайте ветку в приложении и выполните его обычные сборку и тесты с upstream
`pgocaml_ppx`, чтобы зафиксировать исходное состояние. Для дальнейших проверок
используйте тестовую БД с применёнными миграциями и ролью приложения.

Режим кеша доступен начиная с v0.5.0. Для описанных ниже возможностей,
включая `--pp` и `inet`, в opam switch приложения закрепите необходимые
пакеты на текущем релизе v0.5.3:

```bash
typed_sql_packages=(
  typed-sql
  typed-sql-schema
  typed-sql-ppx
  typed-sql-pgocaml-lwt
  typed-sql-schema-pgocaml-lwt
  typed-sql-pgocaml-ppx
)
for package in "${typed_sql_packages[@]}"; do
  opam pin add -yn "$package" 'git+https://github.com/prekel/typed-sql.git#v0.5.3'
done
opam install typed-sql-pgocaml-ppx typed-sql-schema-pgocaml-lwt
```

Чтобы попробовать изменения из локального checkout вместо релизного тега,
используйте path pins:

```sh
TYPED_SQL_CHECKOUT=/absolute/path/to/typed-sql

opam pin add --no-action --kind=path typed-sql "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-schema "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-ppx "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-pgocaml-lwt "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-schema-pgocaml-lwt "$TYPED_SQL_CHECKOUT"
opam pin add --no-action --kind=path typed-sql-pgocaml-ppx "$TYPED_SQL_CHECKOUT"
opam install typed-sql-pgocaml-ppx typed-sql-schema-pgocaml-lwt
```

`--kind=path` берёт файлы рабочего дерева, включая ещё не закоммиченные изменения.
Сохраняйте текущую версию `pgocaml`, если она совместима с зависимостями:
минимальная — 4.3.0 на OCaml 4.14.1, для OCaml 5 нужна 4.4.0 или совместимая
более новая версия. Установка adapter и дампера не требует менять способ
работы приложения с PGOCaml. После дальнейшего изменения checkout обновляйте
установленные pins через `opam reinstall` соответствующих пакетов.

Пример подключения к тестовой БД; пароль при необходимости задайте через
`PGPASSWORD`, не записывая его в Dune и JSON:

```sh
export PGHOST=/path/to/postgresql/socket
export PGPORT=5432
export PGUSER=my_app
export PGDATABASE=my_app_test

mkdir -p offline_sql_ppx/schema offline_sql_ppx/cache
```

Если приложение использует собственный `search_path`, передайте его в
`prepare/check` через `--search-path`. Для начала удобно использовать
`public` и запросы с явно указанными схемами. Snapshot-режим разрешает
неквалифицированные таблицы в `public`.

## Попробовать snapshot схемы

Сохраните актуальную схему:

```sh
opam exec -- typed-sql-pgocaml-schema-dump > offline_sql_ppx/schema/schema.json
```

Создайте `offline_sql_ppx/schema/dune`:

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
```

В `src/db/dune` замените только `pgocaml_ppx` на `app_schema_ppx`.
Например, существующий список:

```lisp
(preprocess (pps ppx_let pgocaml_ppx app_deriving))
```

станет таким:

```lisp
(preprocess (pps ppx_let app_schema_ppx app_deriving))
```

`app_deriving` здесь обозначает существующий PPX приложения. Сохраните его
реальное имя; добавлять новый deriving не требуется. Соберите `app_db` и
запустите соответствующие тесты приложения:

```sh
opam exec -- dune build src/db/app_db.cma
```

В этом режиме SQL проверяет собственный parser по snapshot. Если встретилась
неподдержанная конструкция, сохраните diagnostic и попробуйте тот же запрос
в режиме кеша. После изменения схемы обновляйте `schema.json`; изменение SQL
не требует повторного дампа, если сохранённая схема всё ещё актуальна.

## Попробовать кеш описаний запросов

В Bash используйте рекурсивный glob для `.ml` файлов выбранной библиотеки.
Оболочка раскроет его в список файлов, включая вложенные каталоги. Файлы без
quotations тоже можно включать. Ограничьте glob каталогом нужных исходников,
чтобы не захватить `_build`, копии и библиотеки, использующие другую БД:

```bash
shopt -s globstar

opam exec -- typed-sql-pgocaml-queries prepare \
  --output offline_sql_ppx/cache/queries.json \
  --search-path public \
  src/db/**/*.ml
```

PostgreSQL определит типы через Prepare/Describe. Пользовательские запросы,
в том числе DML, не выполняются. Ошибка выводится с расположением quotation;
исходники не обязаны собираться с новым PPX до первой подготовки кеша.

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

Теперь в том же `src/db/dune` замените `app_schema_ppx` на `app_queries_ppx`:

```lisp
(preprocess (pps ppx_let app_queries_ppx app_deriving))
```

Снова соберите `src/db/app_db.cma` и запустите те же тесты приложения.
Собственный SQL parser в этом режиме не используется. При изменении SQL или
схемы снова запускайте `prepare` с полным списком файлов. Для проверки
актуальности без изменения кеша используйте ту же БД, роль и search path:

```bash
shopt -s globstar

opam exec -- typed-sql-pgocaml-queries check \
  --cache offline_sql_ppx/cache/queries.json \
  --search-path public \
  src/db/**/*.ml
```

## SQL из другого PPX

Если SQL собирается другим PPX, например из общих fragments через
`let%concat` и `[%concat ...]`, применяйте тот же preprocessing при
`prepare` и `check` с параметром `--pp`, доступным начиная с v0.5.3.

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
для сборщика. Не добавляйте сюда `pgocaml_ppx`, schema PPX или query-cache
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

## Сравнить результаты и проверить офлайн-сборку

Оба каталога metadata могут существовать в проекте одновременно. Переключение
делается одним именем в `pps`: `app_schema_ppx` либо `app_queries_ppx`.
В один PPX-драйвер подключайте только один источник metadata и уберите из него
upstream `pgocaml_ppx`. Остальные библиотеки приложения могут временно оставаться
на upstream, если используют отдельные PPX-драйверы.

Для каждого режима сравните с исходным приложением OCaml-типы, object methods,
NULL, порядок строк, побочные эффекты DML и поведение транзакций. Собственные
соединения и транзакции приложения продолжают использоваться напрямую.
Во время проверки особенно полезны существующие object → record converters:
несовпадение формы результата проявится при компиляции.

После перевода всех SQL PPX в зависимостях выбранной цели проверьте реальную
пересборку с недоступной БД, например после `dune clean`:

```sh
opam exec -- dune clean
PGHOST=/nonexistent/offline-ppx opam exec -- dune build src/db/app_db.cma
```

Этот override предназначен для сборки; тесты, выполняющие запросы, запускайте
с настоящим подключением. Если зависимости цели всё ещё используют upstream
PPX или иные правила с обращением к БД, они сохраняют собственную потребность
в подключении. В Zed/LSP откройте файл и проверьте diagnostics: JSON встроен
в драйвер, относительный путь к нему при раскрытии quotation не используется.

Храните выбранный JSON и Dune-конфигурацию в репозитории. Сгенерированные
`schema_ppx.ml` / `queries_ppx.ml` Dune создаёт сам; в приложении при выполнении
не нужны ни JSON, ни дампер, ни команда подготовки кеша.

Общие ограничения: статическая форма SQL, поддержанные codecs и флаги.
`$@list`, `execute`, Custom Type Conversions пока не поддерживаются.
В режиме кеша пользовательские типы, включая enum/domain, требуют функций
`PGOCaml.string_of_TYPENAME` и `PGOCaml.TYPENAME_of_string` в модуле приложения;
это отдельный механизм без sexp config.
[Пример и правила миграции](README.md#конвертеры-пользовательских-типов).
Для quotations, создаваемых другими PPX, используйте `--pp`, описанный выше;
deriving, который только генерирует object → record converter, этого не требует.
Для outer JOIN при необходимости сохраните `"nullable-results"`.
Подробнее о nullability и codecs — в [README](README.md).

## Дальше: query/command без выполнения внутри quotation

После проверки совместимого PPX можно переносить по одному запросу на
[`typed-sql-ppx`](../query-ppx/README.md). Он использует кеш v2 и `Expr.t`,
строит `Result_query.t` / `Command.t` и выполняется через обычный Statement.
Руководство показывает static input, сохранение object → record и переход
на Caqti. Это отдельная миграция; для первого шага замены PPX она не нужна.
