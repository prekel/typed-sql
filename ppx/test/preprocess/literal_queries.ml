open! Base

let find dbh id =
  [%pgsql.object
    dbh
      "SELECT id, name, note, mood, tag, nums FROM query_cache_test.people WHERE id = $id"]
;;

let optional dbh id =
  [%pgsql dbh "nullable-results" "SELECT id FROM query_cache_test.people WHERE id = $?id"]
;;

let enums dbh moods =
  [%pgsql
    dbh "SELECT id FROM query_cache_test.people WHERE mood = ANY($moods) ORDER BY id"]
;;
