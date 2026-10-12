open! Base
open Typed_sql

let%test_module "constraint error matching" =
  (module struct
    let email =
      Constraint_error.create
        ~kind:Unique
        ~message:"duplicate email"
        ~sqlstate:"23505"
        ~constraint_name:"users_email_key"
        ~schema_name:"public"
        ~table_name:"users"
        ~column_name:"email"
        ~detail:"duplicate value"
        ~hint:"choose another email"
        ()
    ;;

    let%test "a named violation can be mapped to an application error" =
      let classify error =
        if Constraint_error.matches ~kind:Unique ~constraint_name:"users_email_key" error
        then
          `Email_taken
        else
          `Storage_error
      in
      match classify email with
      | `Email_taken -> true
      | `Storage_error -> false
    ;;

    let%test "a name in a human-readable message is not an identity" =
      let unnamed =
        Constraint_error.create
          ~kind:Unique
          ~message:"duplicate key violates constraint users_email_key"
          ()
      in
      not (Constraint_error.matches ~constraint_name:"users_email_key" unnamed)
    ;;

    let%test "repeated constraint names can be qualified by table and schema" =
      Constraint_error.matches
        ~constraint_name:"users_email_key"
        ~schema_name:"public"
        ~table_name:"users"
        email
      && (not
            (Constraint_error.matches
               ~constraint_name:"users_email_key"
               ~table_name:"other_users"
               email))
      && not
           (Constraint_error.matches
              ~constraint_name:"users_email_key"
              ~schema_name:"archive"
              email)
    ;;

    let%test "a reported NOT NULL column identifies a field error" =
      let missing =
        Constraint_error.create
          ~kind:Not_null
          ~message:"missing value"
          ~table_name:"users"
          ~column_name:"email"
          ()
      in
      Constraint_error.matches
        ~kind:Not_null
        ~table_name:"users"
        ~column_name:"email"
        missing
      && not (Constraint_error.matches ~column_name:"name" missing)
    ;;

    let%test "absent object names do not satisfy exact filters" =
      let unknown =
        Constraint_error.create
          ~kind:Foreign_key
          ~message:"FOREIGN KEY constraint failed"
          ()
      in
      Constraint_error.matches ~kind:Foreign_key unknown
      && (not (Constraint_error.matches ~constraint_name:"parent_fk" unknown))
      && (not (Constraint_error.matches ~schema_name:"public" unknown))
      && (not (Constraint_error.matches ~table_name:"children" unknown))
      && not (Constraint_error.matches ~column_name:"parent_id" unknown)
    ;;

    let%test "unfiltered matching permits a generic integrity fallback" =
      Constraint_error.matches
        (Constraint_error.create ~kind:Other ~message:"integrity failure" ())
    ;;

    let%test "category filters never confuse independent constraint kinds" =
      let kinds =
        Constraint_error.
          [ Unique; Foreign_key; Not_null; Check; Restrict; Exclusion; Other ]
      in
      List.for_all kinds ~f:(fun kind ->
        let error = Constraint_error.create ~kind ~message:"constraint failed" () in
        Constraint_error.matches ~kind error
        && not
             (Constraint_error.matches
                ~kind:
                  (match kind with
                   | Unique -> Foreign_key
                   | _ -> Unique)
                error))
    ;;

    let%test "protocol details are retained independently of matching" =
      Option.equal String.equal email.sqlstate (Some "23505")
      && Option.equal String.equal email.detail (Some "duplicate value")
      && Option.equal String.equal email.hint (Some "choose another email")
    ;;

    let%expect_test "readable categories for diagnostics" =
      List.iter
        Constraint_error.
          [ Unique; Foreign_key; Not_null; Check; Restrict; Exclusion; Other ]
        ~f:(fun kind ->
          Constraint_error.create ~kind ~message:"rejected" ()
          |> Constraint_error.to_string
          |> Stdlib.print_endline);
      [%expect
        {|
        unique constraint violation: rejected
        foreign key constraint violation: rejected
        not null constraint violation: rejected
        check constraint violation: rejected
        restrict constraint violation: rejected
        exclusion constraint violation: rejected
        integrity constraint violation: rejected
      |}]
    ;;
  end)
;;
