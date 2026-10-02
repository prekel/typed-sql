# Сохранение схемы для offline codegen

`Schema_snapshot.to_string` сохраняет `Schema_ir.t` в JSON,
`Schema_snapshot.of_string` восстанавливает его и возвращает `Result.t`.
Эти операции чистые. Файл хранит metadata схемы, а не строки из таблиц или
параметры подключения.

Версия 2 имеет корневые поля `version` и `tables`. Reader также принимает
снимки версии 1. Все описанные ниже поля
обязательны; отсутствие optional-значения представлено `null`.

```json
{
  "version": 2,
  "tables": [
    {
      "schema": "public",
      "name": "people",
      "columns": [
        {
          "name": "id",
          "db_type": { "kind": "int64" },
          "nullable": false,
          "default": null,
          "generated": false,
          "primary_key_position": 1
        }
      ],
      "foreign_keys": [],
      "unique_constraints": []
    }
  ]
}
```

`db_type.kind` принимает `bool`, `int`, `int64`, `float`, `numeric`, `text`,
`bytes`, `date`, `timestamp` (с часовым поясом),
`timestamp_without_timezone`, `interval`, `json`, `jsonb`, `uuid`, `enum`,
`domain`, `array`, `named` или `unsupported`. Для `enum` записываются
`schema`, `name` и `labels`; для `domain` — `schema`, `name` и вложенный `base`;
для `array` — вложенный `element`. `named` хранит `schema` и `name` типа,
требующего пользовательского codec. `unsupported` требует дополнительное
строковое поле `database_type`, например
`{"kind":"unsupported","database_type":"numeric(20,4)"}`. Snapshot сохраняет
неизвестный SQL-тип; без правила codegen возвращает явную ошибку.

В `foreign_keys` каждый объект содержит `columns` — список имён колонок,
`referenced_schema` — строку или `null`, `referenced_table` — строку и
`referenced_columns` — список имён. В `unique_constraints` каждый объект
содержит `name` — строку или `null` — и `columns` — список имён.

`default` сохраняется как непрозрачная строка SQL либо `null`.
`primary_key_position` — целое число либо `null`. Snapshot проверяет структуру
документа и SQL identifiers по правилам `Identifier`, но не проверяет
существование referenced tables или корректность relational constraints.

Сериализатор сохраняет порядок таблиц, колонок, ключей и колонок внутри ключей.
Это существенно для projections и разрешения коллизий OCaml-имён. Порядок
полей JSON-объектов фиксирован при записи и свободен при чтении. Выход имеет
отступы и завершающий перевод строки. Повторная сериализация восстановленной
схемы даёт тот же канонический текст.

Reader отклоняет неизвестные версии, неизвестные и повторные поля, пропущенные
обязательные поля и значения неверного JSON-типа. Diagnostics содержат путь,
например `$.tables[0].name: SQL identifier must not be empty`. Ошибки разбора
JSON относятся к корню `$`.

## CLI

`typed-sql-schema-dump` из пакета `typed-sql-schema-caqti-lwt` и
`typed-sql-pgocaml-schema-dump` из `typed-sql-schema-pgocaml-lwt` читают PostgreSQL
схему и создают одинаковый JSON snapshot. Оба принимают необязательный
PostgreSQL URI и повторяемый `--exclude-table SCHEMA.TABLE`. Без URI
подключение берёт параметры из `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE` и
`PGPASSWORD`. PG’OCaml дампер поддерживает стандартные host, port, user,
password и database в URI, а также `?host=/path/to/socket`; остальные
URI-параметры отклоняет.

`typed-sql-codegen` устанавливается с `typed-sql-schema`.
`typed-sql-codegen schema.json` читает файл, `typed-sql-codegen -` читает stdin.
`typed-sql-codegen --type-rules rules.json schema.json` применяет правила
пользовательских типов. Повторяемый параметр
`--exclude-table SCHEMA.TABLE` исключает таблицу из генерации по точной паре
имён схемы и таблицы. Для имён с точкой, кавычкой или пробелом используйте
quoted SQL identifiers: `--exclude-table '"schema.name"."table name"'`.
Исключение отсутствующей таблицы завершает CLI с ошибкой. FK-метаданные
оставшихся таблиц сохраняются, даже если они ссылаются на исключённую таблицу.
Не повторяйте в codegen исключение, уже применённое при создании snapshot:
таблица там отсутствует и поэтому считается неизвестной. Чтобы сохранить полный
snapshot и фильтровать только `.ml`, не задавайте `--exclude-table` у dump CLI.
Файл правил имеет вид:

```json
{
  "version": 1,
  "rules": [
    {
      "priority": 10,
      "sql_type": "timestamp without time zone",
      "column": "public[.]events[.]elapsed_seconds",
      "module": "App_codecs.Elapsed_seconds"
    },
    {
      "priority": 0,
      "sql_type": "pg_catalog[.]inet",
      "column": null,
      "module": "App_codecs.Inet"
    }
  ]
}
```

`sql_type` и `column` — регулярные выражения с совпадением по всей строке.
Хотя бы одно из них должно быть задано. `column` имеет вид
`schema.table.column`; правила проверяются по убыванию `priority`, при равном
приоритете — в порядке файла. Каждое правило ссылается на OCaml-модуль с
`type t` и `val db_type : t Db_type.t`. Его `Db_type.map` может задать
собственный encoder и decoder даже для базового SQL-типа. Для именованного
типа представление следует оборачивать в `Db_type.Postgresql.named`, чтобы
параметр получил нужное приведение SQL-типа. Правило для отдельной колонки
применяется и к базовым типам, например timestamp или integer. Правило для
элемента массива применяется внутри массива; его codec обязан кодировать
отдельный элемент. При изменении правил Dune должен пересобрать generated
модуль и приложение, содержащее указанные OCaml-модули.

Результат выводится в stdout после успешного разбора и генерации. При ошибке
stdout пуст, diagnostic находится в stderr, exit code равен 1. Неправильное
число аргументов даёт exit code 2; `--help` и `-h` выводят справку с кодом 0.
Перенаправление stdout средствами shell может заранее создать или очистить
выходной файл. Для атомарного обновления сначала пишите во временный файл и
переносите его в исходный каталог только после успешной генерации. Пример —
`test/schema/regenerate.sh`.

Snapshot и сгенерированный `.ml` обновляются отдельным шагом после изменения
схемы. CLI не применяет миграции и не обращается к БД. Обычная сборка
использует сохранённый `.ml` без повторной генерации; тест может проверить его
совпадение с результатом CLI.
