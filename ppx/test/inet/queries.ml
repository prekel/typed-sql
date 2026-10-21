open! Base

let scalar conn (address : PGOCaml.inet option) : PGOCaml.inet option list =
  [%pgsql conn "SELECT $?address::inet"]
;;

let array conn (addresses : PGOCaml.inet option list option)
  : PGOCaml.inet option list option list
  =
  [%pgsql conn "SELECT $?addresses::inet[]"]
;;

let domain conn (address : PGOCaml.inet option) : PGOCaml.inet option list =
  [%pgsql conn "SELECT $?address::ppx_inet_domain"]
;;

let object_row conn (address : PGOCaml.inet) =
  [%pgsql.object
    conn "SELECT address, optional_address FROM ppx_inet_table WHERE address = $address"]
;;
