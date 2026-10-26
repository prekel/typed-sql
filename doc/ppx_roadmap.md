# Дорожная карта SQL PPX

PPX используют PostgreSQL Prepare/Describe и встроенный query cache версии 3.
`typed-sql-pgocaml-ppx` выполняет quotations через модуль `PGOCaml` приложения;
`typed-sql-ppx` строит `Result_query.t`, `Command.t` и статические `Statement.t`.

[Подключение](ppx.md), [PG’OCaml PPX](../ppx/README.md) и
[typed-sql PPX](../query-ppx/README.md) описывают действующий контракт.
Архитектурные решения зафиксированы в [ADR](adr/0005-cache-only-ppx.md).

## Metadata и офлайн-сборка

- [x] Собирать literal quotations из OCaml AST с сохранением locations.
- [x] Описывать параметры и результаты через Prepare/Describe без выполнения SQL.
- [x] Сохранять точные логические PostgreSQL types, enum/domain/array metadata,
  nullability, kind и ограничения размещения, без OID и credentials.
- [x] Предоставить `prepare/check/codegen` с атомарным обновлением metadata.
- [x] Хранить общую таблицу типов со стабильными именами и ссылки из запросов;
  сохранять читаемый JSON, встраивать компактный JSON и индексировать SQL.
- [x] Встраивать JSON в Dune provider; сборка и LSP не требуют БД или чтения JSON.
- [x] Поддержать `--pp COMMAND` для SQL, создаваемого другими PPX, включая
  OCaml source и binary AST с locations.
- [x] Проверять отсутствие и несколько регистраций кеша, отсутствующие запросы,
  изменение SQL, схемы, роли и search path.
- [ ] Улучшать диагностику рассогласованных metadata и воспроизводимость
  подготовки на реальных приложениях.

## Выполнение через PG’OCaml

- [x] Поддержать `pgsql` и `pgsql.object`, scalar/tuple/object results, команды
  без RETURNING, `$value`, `$?value` и OCaml expression binds.
- [x] Сохранить модуль приложения, monad, соединения, prepared statements,
  транзакции, SQLSTATE и object → record converters.
- [x] Использовать встроенные scalar codecs, inet и одномерные native arrays.
- [x] Выбирать конвертеры пользовательских types по имени через локальный
  `PGOCaml`, включая domain, enum, opaque types и array elements.
- [x] Проверять NULL, строку `"NULL"`, array escapes, object names и порядок binds.
- [x] Проверять сборку без БД и выполнение на PostgreSQL, включая PG’OCaml 4.3.0
  на OCaml 4.14.1 и PG’OCaml 4.4.0 на OCaml 5.
- [ ] Расширять differential-тесты с upstream и проверки на реальных приложениях.

## Quotations typed-sql

- [x] Поддержать `.query`, `.query.object` и `.command` через raw PostgreSQL API.
- [x] Поддержать `.statement` и `.statement.object` с runtime input pattern,
  tuple/record input, getters и компиляцией Statement при определении.
- [x] Сохранять typed-sql descriptors, детерминированные binds, shape и compiler
  diagnostics при композиции raw SQL с DSL.
- [x] Выполнять через Caqti и PG’OCaml adapters на тех же соединениях и транзакциях.
- [x] Совместно подключать PG’OCaml- и typed-sql providers с независимыми registry.
- [ ] Уточнять ergonomics input patterns и диагностики по результатам внедрения.

## Дальнейшие возможности

- [ ] Рассмотреть динамические list binds отдельно: они меняют SQL shape,
  нумерацию binds и prepared statement identity.
- [ ] **Отложено по запросу пользователя:** специальная поддержка views и их
  metadata. Не добавлять отдельную реализацию на текущем этапе.
- [ ] Добавлять новые PG’OCaml flags только с отдельным контрактом и regression.

## Custom Type Conversions — последними, по отдельному согласию

Эта работа относится к конфигурации конвертеров, а не к функциям
`PGOCaml.string_of_TYPENAME` / `PGOCaml.TYPENAME_of_string` в модуле приложения.
Выполняется после остальных согласованных задач roadmap.

Пока не поддерживать sexp config, `load_custom_from=...` и
`PGCUSTOM_CONVERTERS_CONFIG`. Даже при поручении «сделай всё из roadmap» сначала
спросить «Custom Type Conversions тоже?» и дождаться ответа. Отдельный явный
запрос пользователя или уже полученное согласие разрешает работу без повторного
вопроса.

- [ ] Добавить sexp config и выбор файла через `load_custom_from` или env config.
- [ ] Сделать config явной Dune dependency и проверить пересборку при изменении.
- [ ] Поддержать согласованные сочетания `show`, object quotations и converters.
- [ ] Добавить regression, compile-fail и PostgreSQL-проверки выбора функций,
  неправильного config и OCaml-типов.

Критерий завершения: отдельно согласованные converters работают по контракту
upstream, а конфигурация не требует доступа к БД при компиляции.
