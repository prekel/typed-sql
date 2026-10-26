open! Base

module PGOCaml = struct
  include PGOCaml

  let string_of_ppx_inet_domain = string_of_inet
  let ppx_inet_domain_of_string = inet_of_string
end

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
