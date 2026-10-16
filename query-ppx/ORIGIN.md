# Происхождение реализации

Обработка payload в [cache/query_source.ml](cache/query_source.ml) адаптирована
из PG’OCaml 4.4.0 `ppx_pgsql.ml`. Copyright (C) 2005–2016 Richard Jones and
other authors. Сохраняется GNU Library General Public License версии 2 или
позднее: [COPYING](COPYING).

Scanner, классификатор внешней команды, логические metadata и генератор вызовов
`Typed_sql.Raw_sql` написаны для этого проекта. Новый пакет распространяется
под LGPL-2.0-or-later. MIT-лицензия ядра typed-sql не меняется.

Проверка OCaml method names в [typed_sql_ppx.ml](typed_sql_ppx.ml) повторно
использует helper совместимого генератора `ppx/expand.ml`; в файле сохранена
ссылка на его upstream-происхождение. Генерация raw SQL API, typed input и
Statement выполнения PG’OCaml-код не копирует.
