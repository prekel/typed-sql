open! Base

(** Values accepted by the GraphQL parser. Applications check argument types
    against their own schema before building typed-sql expressions. *)
module Value : sig
  (** A parsed constant value after request variables have been substituted. *)
  type t = Graphql_parser.const_value

  (** Accept [Null] or an [Int] in the signed 32-bit GraphQL range.
      Out-of-range values and other value types return an error. *)
  val optional_int : t -> (int option, string) Result.t

  (** Accept [Null] or a string value; other GraphQL value kinds return an error. *)
  val optional_string : t -> (string option, string) Result.t

  (** Accept only an enum literal. Strings are not coerced to enum names. *)
  val enum : t -> (string, string) Result.t
end

(** A field after aliases and variable references have been resolved. *)
module Field : sig
  (** A selected field with its schema name, response alias, resolved
      arguments and child selections. Names still require application-schema validation. *)
  type t =
    { name : string (** Field name to validate against the application schema. *)
    ; response_name : string (** Response key after applying any alias. *)
    ; arguments : (string * Value.t) list
      (** Resolved arguments; omitted nullable variables leave no entry. *)
    ; selections : t list (** Nested selected fields in request order. *)
    }
end

(** Parsing is deliberately independent of database descriptors. The caller
    validates field and argument names against its schema and constructs the
    typed-sql query. Fragment and directive expansion is not supported. *)
module Request : sig
  (** A validated single-root query request, independent of database descriptors. *)
  type t = { root : Field.t (** The single root field accepted by the request parser. *) }

  (** Accept one query operation with one root field. Variables may have Int
      or String types; defaults, fragments, directives, mutations and
      subscriptions are rejected. Duplicate argument and response names are
      rejected at each level. An omitted nullable variable omits its argument or
      input-object field; an explicit null remains present. In a list, an omitted
      nullable variable occupies a null element without changing list positions.
      Int variables and literals must be in the signed 32-bit range, including
      literals nested in lists and input objects. *)
  val parse : query:string -> variables:(string * Value.t) list -> (t, string) Result.t
end

(** Reusable JSON decoding for dynamically selected typed-sql expressions. *)
module Json_projection : sig
  (** Select an expression and encode its decoded value under [key].
      The encoder runs on results; it does not alter SQL or bind values. *)
  val field
    :  key:string
    -> ('a, 'requirements) Typed_sql.Expr.t
    -> encode:('a -> Yojson.Safe.t)
    -> (string * Yojson.Safe.t, 'requirements) Typed_sql.Projection.t

  (** The list must contain at least one SQL expression: typed-sql rejects a
      SELECT projection containing only returned constants. *)
  val object_
    :  (string * Yojson.Safe.t, 'requirements) Typed_sql.Projection.t list
    -> (Yojson.Safe.t, 'requirements) Typed_sql.Projection.t
end
