# История изменений

## Не выпущено

### Добавлено

- Backend-independent typed expression, projection и deferred SELECT DSL.
- Детерминированная компиляция PostgreSQL и SQLite с bind parameters.
- Lwt execution adapter для Caqti и SQLite integration tests.
- Типизированные `INNER JOIN`/`LEFT JOIN`; правая сторона `LEFT JOIN` получает
  отдельный nullable table reference.
- Schema-nullable columns через `Column.nullable_v`; nullability outer join
  корректно flatten'ится в один `option`.
- Single-row `INSERT`, scoped `UPDATE`/`DELETE`, portable `RETURNING`,
  `Command.t`, `Result_query.t` и `Affected_rows`.
- Разделённые normalize, validation, lowering и rendering этапы compiler.
- Shape включает identity mapped codec и типы projection, но исключает значения
  параметров и generated source IDs.
- Адаптер `typed-sql-pgocaml-lwt` без PPX и без тестового подключения к серверу.
