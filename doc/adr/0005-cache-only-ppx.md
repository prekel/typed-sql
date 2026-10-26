# ADR 0005: PPX только из подготовленного кеша

- Статус: принято.
- Дата: 26 октября 2026.
- Версия: 0.6.0.

## Контекст

В typed-sql существовали две реализации выполняющего PG’OCaml PPX: собственный
SQL parser/inference по schema snapshot и кеш Prepare/Describe. Дублирование
семантики PostgreSQL требовало поддерживать grammar, scopes, overloads,
coercions, nullability и diagnostics отдельно от сервера.

Пользователь выбрал единственный кешовый путь и отказ от обратной совместимости.
Следующая версия — 0.6.0. Runtime- и PostgreSQL-регрессии сохраняются через кеш.

## Решение

SQL проверяет PostgreSQL при явном `prepare/check`. При компиляции PPX сканирует
подстановки, находит точный SQL во встроенном кеше и генерирует runtime-вызовы.
Parser, semantic AST, schema inference, schema-регистрация, `Sql.parse`,
`Statement_plan.create`, `Schema_codegen.generate_pgocaml_ppx` и target
`typed-sql-codegen --target pgocaml-ppx` удалены. Переходных API и заглушек нет.

Поддерживается только логический формат кеша v2. Reader/writer v1 и сохранённые
PG’OCaml codecs удалены; оба PPX используют общий формат metadata. Диагностики
и типы подстановок принадлежат `Query_bind`; отдельного модуля `Sql` нет.

Общий lexical scanner сохраняется для binds, string/comment boundaries и
классификации kind/placement. Эта классификация нужна compiler при композиции
raw queries; она не проверяет SQL-типы и не заменяет Prepare/Describe.

Schema snapshots, дамперы и DSL descriptor codegen сохраняются как независимые
части проекта. Новые metadata не меняют semantic AST или backend-neutral ядро.

## Последствия

- PostgreSQL требуется при подготовке и проверке metadata; сборка и LSP офлайн.
- Изменение SQL или схемы требует повторного `prepare`.
- Исторические ограничения собственного parser больше не определяют API PPX.
- Runtime-tests используют сохранённые серверные кеши. Integration tests
  повторно описывают fixtures в отдельной временной БД и сравнивают metadata.
- Удалённые режимы и миграционные пояснения не описываются в актуальных
  руководствах; история решения остаётся в ADR и changelog.
