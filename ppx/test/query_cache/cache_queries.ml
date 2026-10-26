open! Base

module PGOCaml = struct
  include PGOCaml

  let string_of_mood = string_of_string
  let mood_of_string = string_of_string
  let string_of_tag = string_of_int32
  let tag_of_string = int32_of_string
end

let find dbh id =
  [%pgsql.object
    dbh
      "SELECT id, name, note, mood, tag, nums FROM query_cache_test.people WHERE id = $id"]
;;

let insert dbh ~id ~name ~mood ~tag ~nums =
  [%pgsql
    dbh
      "INSERT INTO query_cache_test.people (id, name, mood, tag, nums) VALUES ($id, $name, $mood, $tag, $nums)"]
;;

let update dbh ~id ~note =
  [%pgsql
    dbh "UPDATE query_cache_test.people SET note = $?note WHERE id = $id RETURNING note"]
;;

let remove dbh id = [%pgsql dbh "DELETE FROM query_cache_test.people WHERE id = $id"]

let grouped dbh =
  [%pgsql
    dbh
      "SELECT count(*) FROM query_cache_test.people GROUP BY GROUPING SETS ((name), ()) ORDER BY count(*)"]
;;

let regex dbh pattern = [%pgsql dbh "SELECT substring('abc123' from $pattern)"]

let enums dbh moods =
  [%pgsql
    dbh "SELECT id FROM query_cache_test.people WHERE mood = ANY($moods) ORDER BY id"]
;;

let optional dbh id =
  [%pgsql dbh "nullable-results" "SELECT id FROM query_cache_test.people WHERE id = $?id"]
;;

let expression dbh value = [%pgsql dbh "SELECT ${Int32.succ value}::int4"]

let left_join dbh =
  [%pgsql.object
    dbh
      "nullable-results"
      "SELECT b.id AS missing FROM query_cache_test.people a LEFT JOIN query_cache_test.people b ON b.id = -1"]
;;
