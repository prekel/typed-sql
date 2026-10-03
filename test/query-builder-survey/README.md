<!-- SPDX-License-Identifier: MIT -->

# Обзор библиотек построения запросов

Каталог содержит сценарии запросов из десяти библиотек, реализации на typed-sql
и проверяемые снимки SQL. Markdown-файлы обрабатываются OCaml MDX через Dune;
расширение `.md` позволяет читать их как обычную документацию на GitHub.

Проверка сценариев из корня репозитория:

<!-- $MDX skip -->
```sh
opam exec -- dune runtest test/query-builder-survey
```

Команда проверяет исполняемые блоки и ожидаемый вывод typed-sql.
Примеры на языках исходных библиотек служат справочным материалом.

## Поддерживаемые SQL-диалекты

Обзор десяти библиотек из этого каталога. Документация и исходники проверены
03.10.2026. Это обзор заявленной поддержки, а не результат выполнения сценариев
survey на всех перечисленных СУБД. SQL в карточках сценариев преимущественно
показан для PostgreSQL; в `ef-core.md` большинство примеров относится к SQL Server.

Поддержка СУБД, SQL-диалект и драйвер подключения — разные вещи. Например,
PGlite исполняет PostgreSQL, а Cloudflare D1 использует SQLite: отдельная
интеграция с ними не обязательно означает новый синтаксический диалект.
Наличие backend также не гарантирует переносимость каждого запроса: различаются
`RETURNING`, UPSERT, JSON, оконные функции, DDL и доступные версии SQL.

## Сводная таблица

| Библиотека | Поддержка в основном проекте | Дополнительная поддержка и условия | Источник |
| --- | --- | --- | --- |
| [jOOQ](jooq.md), 3.21 | Open Source: PostgreSQL, MySQL, MariaDB, SQLite, ClickHouse, Derby, DuckDB, Firebird, H2, HSQLDB, Trino, YugabyteDB | Коммерческие редакции добавляют Oracle, SQL Server, Access и другие СУБД; редакция также определяет поддержку старых версий | [Редакции и СУБД](https://www.jooq.org/download/#databases), [версии СУБД](https://www.jooq.org/download/support-matrix) |
| [Kysely](kysely.md) | PostgreSQL, MySQL, SQL Server, SQLite; также встроенная интеграция PGlite | Отдельные пакеты организации для Postgres.js и SingleStore Data API; community-пакеты для Oracle, Firebird, MariaDB, BigQuery, ClickHouse и других систем | [Каталог диалектов](https://kysely.dev/docs/dialects) |
| [EF Core](ef-core.md) | Реляционные провайдеры Microsoft: SQL Server / Azure SQL / Azure Synapse и SQLite | PostgreSQL, MySQL, MariaDB, Oracle, Firebird, Db2, Informix, Access, Spanner, Snowflake, YDB, DuckDB и другие — через отдельные провайдеры других разработчиков | [Каталог провайдеров](https://learn.microsoft.com/en-us/ef/core/providers/) |
| [SQLAlchemy Core](sqlalchemy.md), 2.0 | PostgreSQL, MySQL, MariaDB, SQLite, Oracle, SQL Server | Внешние диалекты для Db2 / Informix, Firebird, Snowflake, BigQuery, ClickHouse и других систем | [Встроенные и внешние диалекты](https://docs.sqlalchemy.org/en/20/dialects/) |
| [SeaQuery](seaquery.md) | PostgreSQL, MySQL, SQLite | SQL Server доступен через коммерческий SeaORM X; он не входит в три открытых backend-флага SeaQuery | [README и backend-флаги](https://github.com/SeaQL/sea-query#seaquery) |
| [Esqueleto](esqueleto.md), сценарии для 3.6.0.0 | PostgreSQL, MySQL, SQLite через SQL-backends Persistent | Есть отдельные модули функций для этих СУБД; произвольный backend Persistent не означает автоматически поддержку Esqueleto | [README](https://github.com/bitemyapp/esqueleto#rdbms-specific) |
| [LINQ to DB](linq2db.md) | PostgreSQL, MySQL, MariaDB, SQL Server, SQLite, Oracle, Access, Db2 LUW / z/OS, Firebird, Informix, SQL Server Compact, SAP HANA, SAP/Sybase ASE, ClickHouse, YDB, DuckDB | Провайдеры и варианты диалектов находятся в основном исходном дереве; для подключения нужен подходящий ADO.NET-драйвер | [ProviderName.cs](https://github.com/linq2db/linq2db/blob/master/Source/LinqToDB/ProviderName.cs) |
| [SqlKata](sqlkata.md) | PostgreSQL, MySQL, SQL Server, SQLite, Oracle, Firebird | Шесть встроенных компиляторов; выполнение запросов подключается отдельно. MariaDB не выделена в отдельный встроенный компилятор | [Документация](https://sqlkata.com/docs/compilers), [исходники компиляторов](https://github.com/sqlkata/querybuilder/tree/main/QueryBuilder/Compilers) |
| [Beam](beam.md), сценарии для 0.10 | `beam-postgres`, `beam-sqlite`; актуальная документация также описывает `beam-duckdb` | `beam-mysql` для MySQL / MariaDB и `beam-firebird` поддерживаются отдельно; наличие DuckDB в текущей документации не подтверждает совместимость с зафиксированной в survey версией 0.10 | [Обзор backend-пакетов](https://haskell-beam.github.io/beam/), [beam-duckdb](https://haskell-beam.github.io/beam/user-guide/backends/beam-duckdb/) |
| [Diesel](diesel.md), 2.3 | PostgreSQL, MySQL / MariaDB, SQLite | Сторонние backend для Oracle, Firebird, DuckDB; это отдельные проекты с собственной совместимостью | [Backend-флаги Diesel 2.3](https://docs.diesel.rs/2.3.x/diesel/index.html#crate-feature-flags), [каталог community-проектов](https://diesel.rs/) |

Для библиотек без версии в таблице использована текущая документация либо ветка
исходников по ссылке. Это не фиксация версии релиза. Сторонние расширения приведены
как примеры; их список не исчерпывающий и не приравнен к поддержке основного проекта.

## Существенные различия

**jOOQ.** Выбор диалекта через `SQLDialect` влияет на SQL и bind values.
Professional добавляет Oracle всех редакций, SQL Server всех редакций, Access,
Redshift, CockroachDB, MemSQL и облачные варианты MySQL / PostgreSQL / SQL Server.
Express ограничивает Oracle и SQL Server редакциями Express. Enterprise дополнительно
покрывает BigQuery, Databricks, Db2, Exasol, HANA, Informix, Snowflake, Spanner,
Sybase ASE / SQL Anywhere, Teradata и Vertica. Возможности отдельных конструкций
указываются через `@Support`; jOOQ умеет эмулировать часть отсутствующих конструкций.
Источники: [редакции](https://www.jooq.org/download/#databases),
[модель диалектов](https://www.jooq.org/doc/3.21/manual/sql-building/dsl-context/sql-dialects/).

**EF Core.** SQL генерирует провайдер. Версии EF Core и провайдера нужно фиксировать
вместе: совместимость между major-версиями обычно отсутствует. Cosmos DB, MongoDB,
Couchbase и InMemory присутствуют в экосистеме провайдеров, но не считаются здесь
реляционными SQL-диалектами. Каталог содержит и провайдеры только для старых версий
EF Core, поэтому его строки нельзя считать единой матрицей поддержки последнего
релиза. Источник: [провайдеры EF Core](https://learn.microsoft.com/en-us/ef/core/providers/).

**Kysely и SQLAlchemy.** Их документация явно отделяет встроенную поддержку от
внешних пакетов. Дополнительный драйвер для уже поддерживаемой СУБД нужно отличать
от нового SQL-компилятора. У SQLAlchemy подходящий DBAPI-драйвер устанавливается
отдельно. Источники: [Kysely](https://kysely.dev/docs/dialects),
[SQLAlchemy](https://docs.sqlalchemy.org/en/20/dialects/).

**Beam, Esqueleto и Diesel.** Backend влияет на доступные конструкции DSL.
Beam использует ограничения type classes и ссылается на матрицу возможностей
в [обзоре backend](https://haskell-beam.github.io/beam/).
Esqueleto явно не ставит целью скрывать различия СУБД и предоставляет
[специальные модули](https://github.com/bitemyapp/esqueleto#rdbms-specific).
В Diesel отсутствие реализации `QueryFragment` для выбранного backend может
выявить неподдерживаемый запрос при компиляции; для SQLite `RETURNING` нужен
соответствующий feature-флаг и SQLite 3.35+.
Источник: [документация Diesel 2.3](https://docs.diesel.rs/2.3.x/diesel/index.html).

## Значение для survey typed-sql

Из списка следует, что PostgreSQL и SQLite подходят как общие цели сравнения:
для обеих СУБД у всех десяти библиотек есть встроенная поддержка либо профильный
провайдер/backend. Это вывод о доступности backend, а не о переносимости всех
сценариев. У EF Core провайдер PostgreSQL поддерживает команда Npgsql.

Следующий возможный этап сравнения — MySQL / MariaDB, затем SQL Server. При этом
MariaDB нельзя автоматически считать отдельным поддержанным диалектом библиотеки,
которая заявляет только MySQL. Для SQL Server у SeaQuery потребуется коммерческое
расширение, у jOOQ — подходящая редакция, а у Beam, Esqueleto и Diesel в проверенных
основных backend-наборах его нет.

Для каждого исполняемого сценария следует фиксировать библиотеку, backend-пакет,
версию СУБД и ожидаемую семантику. Смена quoting или плейсхолдеров сама по себе
не подтверждает переносимость запроса.
