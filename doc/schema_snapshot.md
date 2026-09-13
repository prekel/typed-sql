# Сохранение схемы для offline codegen

`Schema_snapshot.to_string` сохраняет `Schema_ir.t` в JSON,
`Schema_snapshot.of_string` восстанавливает его и возвращает `Result.t`.
Эти операции чистые. Файл хранит metadata схемы, а не строки из таблиц или
параметры подключения.

Версия 1 имеет корневые поля `version` и `tables`. Все описанные ниже поля
обязательны; отсутствие optional-значения представлено `null`.

```json
{
  "version": 1,
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

`db_type.kind` принимает `bool`, `int`, `int64`, `float`, `text`, `bytes`,
`date`, `timestamp`, `uuid` или `unsupported`. Последний требует дополнительное
строковое поле `database_type`, например
`{"kind":"unsupported","database_type":"numeric(20,4)"}`. Snapshot сохраняет
неподдерживаемый SQL-тип; codegen возвращает для него свою обычную ошибку.

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

`typed-sql-codegen schema.json` читает файл, `typed-sql-codegen -` читает stdin.
Результат выводится в stdout после успешного разбора и генерации. При ошибке
stdout пуст, diagnostic находится в stderr, exit code равен 1. Неправильное
число аргументов даёт exit code 2; `--help` и `-h` выводят справку с кодом 0.
Перенаправление stdout средствами shell может заранее создать или очистить
выходной файл; Dune rule из README управляет generated target при сборке.

Snapshot обновляется отдельным шагом после изменения схемы. CLI не применяет
миграции и не обращается к БД. Для обычной сборки достаточно сохранённого JSON,
`typed-sql-codegen` и зависимостей generated-модуля: `base`, `typed-sql`,
`ppx_let`.
