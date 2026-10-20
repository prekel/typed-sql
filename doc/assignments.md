# Общие назначения DML

`Assignment.t` хранит типизированную колонку и присваиваемое выражение.
Один immutable список может использоваться в нескольких builders; source
identity целевого запроса добавляется при присоединении списка.

```ocaml
open! Base
open Typed_sql

module Person = struct
  type row

  let table : row Table.t = Table.v_exn "people"
  let name_column = Column.v_exn table "name" Db_type.text
  let nickname_column = Column.nullable_v_exn table "nickname" Db_type.text
end
```

```ocaml
let insert_person name =
  Insert.(
    into Person.table
    |> values
         Assignment.
           [ value Person.name_column name; value_opt Person.nickname_column (Some None) ]
    |> command)
;;

let update_person name =
  Update.(
    table Person.table
    |> set Assignment.[ value Person.name_column name ]
    |> all_rows
    |> command)
;;
```

`Assignment.value` захватывает OCaml-константу текущего AST. Runtime input
статического statement по-прежнему вводится через `Parameters`; для его
expression применяется `Assignment.expr column expression` или оператор
`Assignment.(column := expression)`.

В `Assignment.[...]` имена конструкторов локально открыты. Для переменной
с именем `value` подходит обычный список `[Assignment.value column value]`.

`Assignment.value_opt column None` и `expr_opt column None` пропускают
назначение. `value_opt nullable_column (Some None)` записывает SQL `NULL`.
Пропущенные назначения не участвуют в проверках пустоты и дубликатов.
`Assignment.default` означает SQL `DEFAULT` и требует PostgreSQL.

Compiler проверяет владельца колонки, SQL descriptors, область видимости,
агрегаты и дубликаты. `Update.set_nullable_expr` остаётся специальным явным
разрешением записать nullable-выражение в обязательную колонку; ошибка
`NOT NULL` в этом случае возвращается execution adapter.

## Переход со старого API

| Прежняя форма | Новая форма |
| --- | --- |
| `Insert.set column new_value` | `Insert.values Assignment.[value column new_value]` |
| `Insert.set_expr column expression` | `Insert.values Assignment.[column := expression]` |
| `Update.set column new_value` | `Update.set Assignment.[value column new_value]` |
| `Update.set_expr column expression` | `Update.set Assignment.[column := expression]` |
| `set_opt` / `set_expr_opt` | `Assignment.value_opt` / `Assignment.expr_opt` внутри списка |
| `Insert.default` / `Update.default` | `Assignment.default` внутри списка |
| `Conflict_update.set_expr column expression` | `Conflict_update.set Assignment.[column := expression]` |
| `Merge.Assignments.(empty |> set ...)` | общий список `Assignment.[...]` |

`Insert.rows table` принимает список списков назначений вместо row callbacks.
Каждая строка должна содержать одинаковый непустой набор колонок. Порядок
строк сохраняется; порядок колонок определяется первой строкой.

UPSERT сохраняет `Insert.Conflict_update.empty`, `set` со списком назначений
и `where`. UPDATE сохраняет обязательный `where` или явный `all_rows`.
Параметры, проекции и execution API не меняются.
