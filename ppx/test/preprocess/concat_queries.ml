open! Base

let%concat common_select =
  {sql|SELECT id, name, note, mood, tag, nums FROM query_cache_test.people|sql}
;;

let%concat id_select = {sql|SELECT id FROM query_cache_test.people|sql}
let%concat common_end = {sql|ORDER BY id|sql}
let find dbh id = [%pgsql.object dbh [%concat common_select {sql|WHERE id = $id|sql}]]

let optional dbh id =
  [%pgsql dbh "nullable-results" [%concat id_select {sql|WHERE id = $?id|sql}]]
;;

let enums dbh moods =
  [%pgsql dbh [%concat id_select {sql|WHERE mood = ANY($moods)|sql} common_end]]
;;
