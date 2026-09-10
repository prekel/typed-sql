# История изменений

## Не выпущено

### Добавлено

- `Projection` реализует `Base.Applicative.S` и поддерживает `let%map` через
  `Let_syntax`. Вместо `pure` используется `return`; функции `map`, `map2`,
  `map3` принимают `~f`. Обёртка Lwt в PG'OCaml реализует `Base.Monad.S`.
- Отдельный `typed-sql.backend` для авторов адаптеров: codec views, packed
  values, `Projection.Make`, `Template.map` и shape. Codec views и packed values
  доступны только для чтения. Адаптеры принимают compiled values приложения
  без преобразований; `Typed_sql` содержит только пользовательский DSL,
  компиляцию, SQL и ошибки.

- Полный интерфейс приложения и документация в `typed_sql.mli`.
  Внутренняя библиотека `typed_sql_private` содержит реализации без локальных
  `.mli`; facade `typed-sql` реэкспортирует только публичные модули.

- Внутренняя библиотека для white-box тестов даёт доступ к AST, внутренним
  constructors/accessors и отдельным этапам compiler; regression tests
  проверяют нормализацию, validation и сохранение bind parameters.

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
