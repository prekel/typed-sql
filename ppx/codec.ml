open! Base

type t =
  | Scalar of string
  | Array of t

let rec to_string = function
  | Scalar name -> name
  | Array element -> to_string element ^ " option list"
;;
