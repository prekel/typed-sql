# Обработка ошибок

Адаптеры возвращают обычный `('output, error) Result.t Lwt.t`. Для перевода
ошибок БД в ошибки приложения есть `Error.is_constraint_violation` и
`Error.constraint_violation`. `Statement.t` остаётся с тремя параметрами;
транзакции выполняются через обычный callback `transaction ~f`.

## Обработка по категории

Например, ошибка FK при создании дочерней записи:

```ocaml
module Adapter = Typed_sql_caqti_lwt

type create_error =
  | Missing_parent
  | Storage of Adapter.error

let classify = function
  | Ok value -> Ok value
  | Error error
    when Adapter.Error.is_constraint_violation
           ~kind:Typed_sql.Constraint_error.Foreign_key error ->
    Error Missing_parent
  | Error error -> Error (Storage error)

let create conn statement input =
  Adapter.run ~conn statement input |> Lwt.map classify
```

Категории общие для Caqti и PG'OCaml: `Unique`, `Foreign_key`, `Not_null`,
`Check`, `Restrict`, `Exclusion`, `Other`. `Unique` включает нарушения PK,
если драйвер различает их; драйвер может сообщить только `Other`. Если у
операции несколько FK, категория сама по себе не определяет, какой из них
нарушен. В таком случае оставьте общую ошибку приложения либо используйте
имя, если драйвер его предоставляет.

## Обработка конкретного ограничения

PG'OCaml сохраняет поля протокола PostgreSQL. Можно обработать конкретный
UNIQUE, не разбирая текст сообщения:

```ocaml
module Adapter = Typed_sql_pgocaml_lwt

type registration_error =
  | Email_taken
  | Storage of Adapter.error

let classify = function
  | Ok user -> Ok user
  | Error error
    when Adapter.Error.is_constraint_violation
           ~kind:Typed_sql.Constraint_error.Unique
           ~schema_name:"public"
           ~table_name:"users"
           ~constraint_name:"users_email_key"
           error ->
    Error Email_taken
  | Error error -> Error (Storage error)
```

Все заданные фильтры должны совпасть. Если БД не сообщила имя, проверка имени
вернёт `false`; сообщение, похожее на имя ограничения, не считается
подтверждением. Имена constraints могут повторяться в разных таблицах,
поэтому при необходимости укажите schema и table.

Для собственного обработчика можно получить record:

```ocaml
match Adapter.Error.constraint_violation error with
| Some { kind = Not_null; column_name = Some "email"; _ } ->
  Error `Email_required
| Some details -> Error (`Integrity details)
| None -> Error (`Storage error)
```

`Typed_sql.Constraint_error.t` содержит категорию, сообщение, SQLSTATE,
имена constraint/schema/table/column, detail и hint. Дополнительные поля
имеют тип `string option`. Это диагностика БД, а не заранее вычисленный
набор возможных ошибок statement. Нет обязательного каталога, специальных
вариантов на каждую таблицу или анализа возможных нарушений AST.

## Различия адаптеров и исходная ошибка

PG'OCaml предоставляет перечисленные поля, если PostgreSQL их прислал.
Caqti предоставляет переносимую категорию через общий API, но не
SQLSTATE или имена объектов. Поэтому в общем record Caqti эти поля равны
`None`; для специфичных сведений доступна исходная ошибка драйвера:

```ocaml
Typed_sql_caqti_lwt.Error.cause error
(* Caqti.Error.t option *)

Typed_sql_pgocaml_lwt.Error.cause error
(* exn option *)
```

Исходная причина сохраняется и после классификации `Constraint_violation`.
Ошибки compile, parameter и codec не получают выдуманную причину драйвера.
`Error.to_string` и `Error.pp` подходят для диагностики; прежние
`error_to_string` и `pp_error` тоже доступны. Текст и detail могут содержать
значения из БД: приложение само выбирает, что писать в лог и показывать
пользователю.

## Транзакции и COMMIT

Обрабатывайте результат всей транзакции: отложенный FK может нарушиться
только при `COMMIT`, после успешных команд внутри callback.

```ocaml
let create_in_transaction conn statement input =
  Adapter.transaction ~conn ~f:(fun conn ->
    Adapter.run ~conn statement input)
  |> Lwt.map classify
```

`Ok` приводит к commit, `Error` — к rollback. Для нескольких statements
callback использует обычные Lwt и Result; отдельного transaction DSL нет.

Если rollback также завершился ошибкой, результат содержит
`Rollback_failed { error; rollback_error }`. Обе причины сохранены,
`Error.to_string` показывает их вместе, а `Error.cause` возвращает исходную
причину первого сбоя. `Error.is_constraint_violation` для такой составной
ошибки возвращает `false`: общий `Storage` fallback сохраняет весь сбой
транзакции. Отмена через `Lwt.Canceled` не превращается в обычный `Error`,
даже если попытка rollback после отмены не удалась.

## Основа решения

Выбран простой вариант из [ADR 0003](adr/0003-constraint-errors.md), с
уточнениями в [ADR 0004](adr/0004-runtime-errors.md). Общая категория и
необязательные поля следуют подходу
[Diesel DatabaseErrorInformation](https://docs.rs/diesel/latest/diesel/result/trait.DatabaseErrorInformation.html).
[Протокол PostgreSQL](https://www.postgresql.org/docs/current/protocol-error-fields.html)
разделяет SQLSTATE, текст и поля объектов; последние могут отсутствовать.
Это позволяет писать обработчики по структуре, сохраняя fallback для
неизвестных ошибок.
