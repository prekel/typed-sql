# ADR 0003: анализ возможных нарушений ограничений и типизированные ошибки

- Статус: отложено; реализация сохранена как эксперимент
- Дата: 7 октября 2026 года
- Основа экспериментальной ветки: `b1f46a1` (`Release v0.4.5`)
- Эксперимент: ветка `experiment/typed-constraint-errors`, коммит `4bcdb71`
- Связанное решение: [ADR 0001](0001-static-statement-api.md)

## Контекст и решение

Прикладному коду полезно знать до выполнения команды, какие ограничения
схемы она *может* нарушить, и различать подтверждённые нарушения после
выполнения. Особенно это важно для `UPDATE` и `DELETE`: внешний ключ может
находиться в другой таблице. Нарушение отложенного FK может появиться только
при `COMMIT`, когда отдельная команда уже вернула успех.

Текущий `master` сообщает переносимый `Constraint_violation` с категорией
`Unique`, `Foreign_key`, `Not_null` и другими, но не связывает ошибку с
конкретным ограничением схемы. Эксперимент добавил каталог ограничений,
`Statement.possible_violations`, типизированный `Known_constraint` и программу
`Transaction` для ошибок на `COMMIT`.

**Решение:** не переносить экспериментальный публичный API в `master` сейчас.
Ветка сохраняет работающий прототип и результаты проверок. Следующий вариант
нужно выбрать по прикладным обработчикам ошибок: цена четвёртого параметра
`Statement.t` и вложенных типов ошибок пока выше достигнутой точности. Сам
анализ возможных нарушений и структурированная диагностика остаются
перспективными частями решения, но ADR не утверждает их будущие сигнатуры.

## Что получилось хорошо

- Каталог находится в backend-independent ядре. Introspection и codegen
передают в него PK, UNIQUE, FK, NOT NULL, CHECK, EXCLUSION, действия FK,
время проверки и сведения о полноте снимка. Значения параметров и
соединение не входят в результат анализа.
- Анализ обходит semantic AST, включая DML внутри CTE и вложенных запросов.
Для `UPDATE` и `DELETE` он учитывает входящие FK; `CASCADE`, `SET NULL` и
`SET DEFAULT` могут привести к дальнейшим нарушениям в дочерних таблицах.
- `Statement.possible_violations` возвращает консервативный список для
выбранной формы и диалекта. Для динамической формы или `choose` переданный
input позволяет рассмотреть только выбранную ветку. Неполный каталог и
триггеры представлены как `Unknown`, а не скрыты.
- Адаптер возвращает `Known_constraint` только при однозначном соответствии
диагностики одному кандидату из каталога. Остальные ошибки остаются в
`Other`. Для отложенных ограничений `execute_transaction` собирает кандидатов
только из фактически выполненных statements.
- Проверки покрыли входящие FK, каскадные действия, ветвление по input и
диалекту и SQLite `:memory:` с ошибкой на `COMMIT`.

Ручное объявление каталога в маленьком примере выглядит громоздко. В обычном
сценарии его создаёт генератор схемы; приложению остаются table/column
descriptors и обработчик результата.

## Примеры использования

В примерах `Child` — модуль таблицы приложения, `parent_id_column` — его
дескриптор колонки. Код ниже сравнивает доступный API с экспериментом;
экспериментальные вызовы отсутствуют на `master`.

### Текущий `master`: категория без личности FK

```ocaml
let statement =
  Statement.command ~dialect:Dialect.sqlite
    Insert.(into Child.table |> set Child.parent_id_column 999L |> command)

let classify = function
  | Error
      (Typed_sql_caqti_lwt.Constraint_violation
         { kind = Typed_sql_caqti_lwt.Foreign_key; _ }) ->
    Error `Missing_parent
  | Error error -> Error (`Storage error)
  | Ok affected -> Ok affected

let result =
  Typed_sql_caqti_lwt.run ~conn statement ()
  |> Lwt.map classify
```

`result` имеет тип `Lwt.t`. Если у таблицы несколько FK, категория
`Foreign_key` сама по себе не различает их.

### Эксперимент: список кандидатов и подтверждённая ошибка

```ocaml
let statement =
  Statement.command ~dialect:Dialect.sqlite
    Insert.(into Deferred_child.table
            |> set Deferred_child.id_column 999L
            |> command)

let possible =
  Statement.possible_violations ~dialect:Dialect.sqlite statement
(* Ok [Known { id = "deferred_children.parent_fk"; ... }] *)

let classify = function
  | Error
      (Typed_sql_caqti_lwt.Known_constraint
         (Deferred_child.Parent_fk, details)) ->
    Error (`Missing_parent details.constraint_id)
  | Error (Typed_sql_caqti_lwt.Other error) -> Error (`Storage error)
  | Ok affected -> Ok affected

let result =
  Typed_sql_caqti_lwt.run ~conn statement ()
  |> Lwt.map classify
```

`Deferred_child.Parent_fk` — конструктор тестового дескриптора. Для
сгенерированной схемы обработчик дополнительно раскрывает `Constraint_error`
и общий вариант ограничений. Например, возможен шаблон вида:

```ocaml
User_profile.Constraint_error
  Typed_sql_generated_constraints.Public_advanced_not_null_payload
```

Он *типизируется* даже для операции над `User_profile`, хотя относится к
другой таблице. Список `possible_violations` уже, чем тип
`Known_constraint`; это главный эргономический недостаток прототипа.

### Эксперимент: ошибка отложенного FK на `COMMIT`

```ocaml
let result =
  Typed_sql_caqti_lwt.execute_transaction ~conn
    Transaction.(run statement ())
```

После ожидания `result` можно сопоставить с
`Error (Known_constraint (Deferred_child.Parent_fk, details))`. Успех
отдельного `INSERT` ещё не означает успеха транзакции. Обычный callback
`transaction ~f` не хранит типовые эффекты выполненных запросов и потому
может вернуть эту ошибку только как `Other`.

### Эксперимент: удаление родителя

В тестовом каталоге `Fixture.child_foreign_key` задан как `ON DELETE SET NULL`,
а `child.parent_id` объявлен `NOT NULL`:

```ocaml
let delete_parent =
  Statement.command ~dialect:Dialect.sqlite
    Delete.(from Fixture.parent |> all_rows |> command)

let possible =
  Statement.possible_violations ~dialect:Dialect.sqlite delete_parent
(* Known "child.parent_fk" and Known "child.parent_id.not_null" *)
```

Это верхняя оценка: без данных БД нельзя узнать, существуют ли зависимые
строки. Для `UPDATE` родительского ключа анализ аналогично учитывает входящий
FK и его `ON UPDATE` действие.

## Что выяснилось об OCaml

`Table.t` уже использует phantom-тип строки для разделения таблиц.
Эксперимент использовал тот же тип как свидетель ошибки. Это позволило
протащить известные нарушения через `Insert`, `Update`, `Delete`, CTE и
`Statement` без небезопасного приведения типов. Но у строки и ошибки разные
роли; добавление нового параметра почти ко всем связующим типам затронуло
большую часть DSL.

Обычные варианты OCaml номинальны: два независимых типа ошибок нельзя
автоматически объединить в третий. `Statement.choose` и `Transaction.bind`
используют `Constraint_effect.either`. После нескольких ветвей обработчик
видит вложенные `Left`/`Right`, а `Transaction.map` добавляет даже ветвь с
пустым типом. GADT помогает сохранять связь типа с выбранной веткой, но не
сделает это представление удобным само по себе. [Руководство OCaml по
GADT](https://ocaml.org/manual/5.3/gadts-tutorial.html) описывает именно
такие ограничения и уточнения параметров типов.

Каталог, AST и выбранная форма dynamic statement — значения времени
выполнения. Обычный вывод типов OCaml не превращает результат обхода AST в
новый точный статический набор вариантов. Генератор сейчас выпускает один
номинальный вариант **на всю схему** и вкладывает его в каждую таблицу.
Поэтому тип допускает ограничения, которые конкретный statement никогда не
заявлял. Полиморфные варианты могли бы выразить открытые наборы тегов, но
потребовали бы отдельного решения о генерации тегов, закрытии rows и качестве
сообщений компилятора; это кандидат для прототипа, не доказанное упрощение.
[Руководство OCaml по полиморфным
вариантам](https://ocaml.org/manual/5.1/polyvariant.html) отмечает сложность
их типизации.

## Что выяснилось о SQL и диагностике

- Возможность нарушения следует из схемы и формы операции, а факт нарушения
зависит от данных, конкурирующих транзакций и состояния БД. `UPDATE`
неключевой колонки может получить консервативный список ограничений всей
таблицы; этот список не означает, что каждый пункт реально достижим.
- Внешний ключ направлен в обе стороны: запись дочернего ключа проверяет
родителя, а изменение или удаление родителя может нарушить входящий FK.
Действия по ссылке способны вызвать новые проверки; например, `SET DEFAULT`
не гарантирует допустимого значения. [PostgreSQL о действиях
FK](https://www.postgresql.org/docs/current/ddl-constraints.html).
- Отложенный FK проверяется при `COMMIT`. SQLite отдельно уточняет, что
`RESTRICT` может выдать ошибку сразу даже для отложенного FK. Поэтому
эффекты одного statement не описывают все точки отказа транзакции.
[Документация SQLite по FK](https://www.sqlite.org/foreignkeys.html).
- PostgreSQL даёт `SQLSTATE` и дополнительные поля, но имена таблицы,
колонки и ограничения присутствуют не для каждой ошибки и не должны
считаться обязательными. [Коды
SQLSTATE](https://www.postgresql.org/docs/current/errcodes-appendix.html),
[поля протокола](https://www.postgresql.org/docs/current/protocol-error-fields.html).
SQLite различает категории через расширенные коды, но сообщение
`FOREIGN KEY constraint failed` не называет конкретный FK. Поэтому при
нескольких кандидатах корректный результат — неопределённая личность
ограничения, а не случайно выбранный вариант. [Коды
SQLite](https://www.sqlite.org/rescode.html).
- Триггеры, неполный снимок схемы, миграции после codegen и ошибки самого
драйвера не исчезают от добавления статического типа. `Other` или
эквивалентная открытая ветвь необходима даже при полном каталоге.

## Как поступают другие библиотеки

Сравнение касается публичной формы ошибки. Оно не означает, что библиотека
заранее вычисляет набор нарушений для конкретного запроса.

| Система | Что получает обработчик | Вывод для typed-sql |
| --- | --- | --- |
| [JDBC](https://docs.oracle.com/javase/tutorial/jdbc/basics/sqlexception.html), [класс 23](https://docs.oracle.com/en/java/javase/26/docs/api/java.sql/java/sql/SQLIntegrityConstraintViolationException.html) | `SQLException` с `SQLState`, vendor code и цепочкой причин; драйвер может использовать `SQLIntegrityConstraintViolationException` для класса 23 | Категорию можно стандартизировать, личность ограничения зависит от драйвера |
| [ADO.NET](https://learn.microsoft.com/dotnet/api/system.data.common.dbexception.sqlstate), [SqlClient](https://learn.microsoft.com/dotnet/api/microsoft.data.sqlclient.sqlexception.number), [Npgsql](https://www.npgsql.org/doc/api/Npgsql.PostgresException.html) | `DbException.SqlState` может быть `null`; SQL Server даёт `Number`, Npgsql — `SqlState` и необязательный `ConstraintName` | Сохранить исходные диагностические поля и provider-specific различия |
| [Hibernate](https://docs.jboss.org/hibernate/orm/7.1/javadocs/org/hibernate/exception/ConstraintViolationException.html) | `ConstraintViolationException` с видом и nullable `getConstraintName()`; документация предупреждает, что БД не всегда сообщает имя | Имя ограничения нельзя обещать как обязательное |
| [EF Core](https://learn.microsoft.com/en-us/ef/core/saving/concurrency) | `DbUpdateConcurrencyException` для конфликта оптимистической конкуренции; уникальность при вставке даёт provider-specific ошибку | Не смешивать конфликт версии строки и нарушение UNIQUE |
| [SQLAlchemy](https://docs.sqlalchemy.org/en/20/errors.html) | `IntegrityError` оборачивает исключение DB-API; подробности приходят от драйвера | Переносимая категория и исходная ошибка могут сосуществовать |
| [Django](https://docs.djangoproject.com/en/5.2/topics/db/transactions/) | `IntegrityError` ловят вокруг `atomic`; после ошибки транзакции требуется rollback | Границу обработки ошибки `COMMIT` нужно показывать пользователю явно |
| [Active Record](https://api.rubyonrails.org/classes/ActiveRecord/RecordNotUnique.html), [InvalidForeignKey](https://api.rubyonrails.org/classes/ActiveRecord/InvalidForeignKey.html) | Отдельные классы для частых видов нарушений | Категории полезны и без типа ошибки для каждого statement |
| [Prisma](https://docs.prisma.io/docs/orm/reference/error-reference) | `PrismaClientKnownRequestError` с кодами `P2002` для UNIQUE и `P2003` для FK, плюс metadata | Стабильный код даёт простую обработку, но не исчерпывает возможные ошибки запроса |
| [jOOQ](https://www.jooq.org/doc/latest/manual/sql-execution/exception-handling/) | `DataAccessException` и подкласс `IntegrityConstraintViolationException` на основе SQLSTATE класса 23 | Даже SQL builder оставляет ошибки выполнения динамическими |
| [Diesel](https://docs.rs/diesel/latest/diesel/result/enum.Error.html), [diagnostics](https://docs.rs/diesel/latest/diesel/result/trait.DatabaseErrorInformation.html) | `DatabaseError(DatabaseErrorKind, info)`; `constraint_name()` возвращает `Option` и сейчас доступен только для PostgreSQL | `Result` с категорией и необязательной личностью — простой типизированный минимум |

Примеры внешних обработчиков показывают характерный уровень точности:

```java
catch (SQLException error) {
    if ("23503".equals(error.getSQLState())) {
        handleForeignKeyViolation(error);
    }
}
```

```csharp
catch (PostgresException error)
    when (error.SqlState == "23503"
          && error.ConstraintName == "child_parent_fk")
{
    HandleMissingParent(error);
}
```

Первый код использует PostgreSQL `SQLSTATE 23503` через JDBC; второй —
дополнительное поле Npgsql, которое может отсутствовать. Оба узнают причину
после обращения к БД, не из типа построенного запроса.

## Альтернативы для следующей итерации

### 1. Список возможностей и структурированная ошибка во время выполнения

Сохранить `Statement.t` с тремя параметрами. Дать запросу
`possible_violations` и вернуть из adapter `Constraint_violation` с
`kind`, `constraint_id : string option` и исходной диагностикой. Приложение
сопоставляет стабильный ID, если он однозначно найден:

```ocaml
match result with
| Error
    (Constraint_violation
       { constraint_id = Some "child.parent_fk"; _ }) ->
  Error `Missing_parent
| Error error -> Error (`Storage error)
| Ok affected -> Ok affected
```

Это эскиз, не API `master`. Он не даёт проверки полноты `match` по
ограничениям конкретного запроса, зато не меняет типы всего DSL. Если
приоритет — читаемый прикладной код и диагностика, начать следует с этого
варианта.

### 2. Сохранить типовые эффекты, но сузить их

Генерировать типы ограничений по таблице или операции, а не общий вариант
всей схемы. Для `DELETE` нужен анализ входящих FK, для `MERGE` и CTE —
объединение эффектов. При таком выборе сначала показать на реальных
обработчиках, как скрыть вложенные `Left`/`Right` и как совместить
статическую верхнюю оценку с `Other`. Простая замена общего варианта на
варианты таблиц без решения композиции проблему не устраняет.

### 3. Генерировать специализированные эффекты из формы запроса

PPX или отдельная кодогенерация могли бы выпустить точный вариант для
конкретного статического statement. Это потребует нового этапа сборки,
стабильной схемы при генерации и отдельной истории для dynamic statements.
Выбирать такой путь имеет смысл только если прикладные сценарии покажут
существенную пользу от исчерпывающего сопоставления ошибок.

## Условие для пересмотра

Сравнить альтернативы на одинаковых обработчиках: `INSERT` с UNIQUE и FK,
`UPDATE` дочернего ключа, `DELETE` родителя с входящим FK, каскадный
`SET NULL` на обязательной колонке, ветвление `choose` и несколько команд с
отложенным FK на `COMMIT`. Для каждого примера нужны сгенерированная схема,
код обработчика, тип результата и проверка неоднозначной диагностики.
Предпочесть вариант, который не обещает более точную статическую информацию,
чем может подтвердить схема и драйвер.

На момент выноса эксперимента проходили `make build`, `make test`, `make fmt`,
`make doc` и публичный `make coverage` (96,79% при пороге 96,5%).
`make coverage-all` давал 98,78% при пороге 99%; это дополнительная причина
не считать ветку готовой к слиянию.
