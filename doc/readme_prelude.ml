#require "ppx_let"

open! Base
open Typed_sql

module Department = struct
  type row

  let table : row Table.t = Table.v_exn "departments"
  let person_id_col = Column.v_exn table "person_id" Db_type.int64
  let name_col = Column.v_exn table "name" Db_type.text
  let person_id row = Expr.column row person_id_col
  let name row = Expr.column row name_col
end

module Article = struct
  type row

  let table : row Table.t = Table.v_exn "articles"
  let id_col = Column.v_exn table "id" Db_type.int64
  let id row = Expr.column row id_col
end

module Comment = struct
  type row

  let table : row Table.t = Table.v_exn "comments"
  let article_id_col = Column.v_exn table "article_id" Db_type.int64
  let created_at_col = Column.v_exn table "created_at" Db_type.timestamp
  let article_id row = Expr.column row article_id_col
  let created_at row = Expr.column row created_at_col
  let projection row = Projection.pair (article_id row) (created_at row)
end

module Book = struct
  type row

  let table : row Table.t = Table.v_exn "books"
  let id_column = Column.v_exn table "id" Db_type.int64
end

module Pgocaml = Typed_sql_pgocaml_lwt.Pgocaml
