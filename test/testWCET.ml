
open MipsCfg
open MipsSys
open MipsUtils
open Ustring.Op
open Printf
open Str
open Utest
       
let tmpfile = "temp-file-090916-070704.tmp"

let compile_file filename fname args optimize debug =
  (try
     MipsSys.pic32_compile [filename] false optimize tmpfile
   with Sys_error e ->
     e |> eprintf "Error %s");
  let prog = MipsSys.get_program tmpfile |>  MipsUtils.add_branch_symbols in
  let (prog,cfgmap) = MipsCfg.make_cfgmap fname prog in
  let program_code = MipsCfg.pprint_ocaml_cps_from_cfgmap true fname cfgmap prog in
  let stdout = MipsSys.wcet_compile "array_mul" false program_code args in
  try
    let regex = Str.regexp "BCET:[^0-9]*\\([0-9]+\\)\\(.\\|\n\\)*WCET:[^0-9]*\\([0-9]+\\)" in
    let _ = Str.search_forward regex stdout 0 in
    let bcet, wcet = int_of_string (Str.matched_group 1 stdout), int_of_string (Str.matched_group 3 stdout) in
    (bcet,wcet)                                                 
  with Not_found ->
    (eprintf "Error: BCET/WCET Not_Found\n";
     raise Not_found)
       
let main =
  Utest.init "WCET";
  
  let bcet,wcet = compile_file "test/demo/array_mul.c" "array_mul" ["a0=[1,2]";"a1=[1,4]";"a2=[1,3]"] 0 false in
  Utest.test_int "array_mul.c: Non optimized." bcet 98;
  Utest.test_int "array_mul.c: Non optimized." wcet 1279;
  let bcet,wcet = compile_file "test/demo/array_mul.c" "array_mul" ["a0=[1,2]";"a1=[1,4]";"a2=[1,3]"] 3 false in
  Utest.test_int "array_mul.c: Optimized." bcet 41;
  Utest.test_int "array_mul.c: Optimized." wcet 282;
  let bcet,wcet = compile_file "test/demo/fact.c" "fact" ["a0=[1,6]"] 0 false in
  Utest.test_int "fact.c: Not optimized." bcet 15;
  Utest.test_int "fact.c: Not optimized." wcet 70;
  let bcet,wcet = compile_file "test/demo/fact.c" "fact" ["a0=[1,6]"] 3 false in
  Utest.test_int "fact.c: Optimized." bcet 3;
  Utest.test_int "fact.c: Optimized." wcet 30;
  (* NS.C *)
  let bcet,wcet = compile_file "test/wcet_tests/mdh/ns.c" "foo" ["a0=[1,10]"] 0 false in
  Utest.test_int "ns.c: BCET Not Optimized." bcet 114;
  Utest.test_int "ns.c: WCET Not Optimized." wcet 24250;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/ns.c" "foo" ["a0=[1,10]"] 1 false in
  Utest.test_int "ns.c: BCET Optimized: -O1." bcet 31;
  Utest.test_int "ns.c: WCET Optimized: -O1." wcet 3536;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/ns.c" "foo" ["a0=[1,10]"] 2 false in
  Utest.test_int "ns.c: BCET Optimized: -O2." bcet 32;
  Utest.test_int "ns.c: WCET Optimized: -O2." wcet 3912;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/ns.c" "foo" ["a0=[1,10]"] 3 false in
  Utest.test_int "ns.c: BCET Optimized: -O3." bcet 29;
  Utest.test_int "ns.c: WCET Optimized: -O3." wcet 1394;
  (* FAC.C *)
(*
  let bcet,wcet = compile_file "test/wcet_tests/mdh/fac.c" "fac" ["a0=[1,10]"] 0 false in
  Utest.test_int "fac.c: BCET Not Optimized." bcet ?;
  Utest.test_int "fac.c: WCET Not Optimized." wcet ?;
 *)
  let bcet,wcet = compile_file "test/wcet_tests/mdh/fac.c" "fac" ["a0=[1,10]"] 1 false in
  Utest.test_int "fac.c: BCET Optimized: -O1." bcet 16;
  Utest.test_int "fac.c: WCET Optimized: -O1." wcet 133;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/fac.c" "fac" ["a0=[1,10]"] 2 false in
  Utest.test_int "fac.c: BCET Optimized: -O2." bcet 9;
  Utest.test_int "fac.c: WCET Optimized: -O2." wcet 54;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/fac.c" "fac" ["a0=[1,10]"] 3 false in
  Utest.test_int "fac.c: BCET Optimized: -O3." bcet 9;
  Utest.test_int "fac.c: WCET Optimized: -O3." wcet 54;
  (* RECURSION.C *)
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "kalle" ["a0=[0,10]"] 0 false in
  Utest.test_int "recursion.c (kalle): BCET Not Optimized." bcet 15;
  Utest.test_int "recursion.c (kalle): WCET Not Optimized." wcet 185;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "kalle" ["a0=[0,10]"] 1 false in
  Utest.test_int "recursion.c (kalle): BCET Optimized: -O1." bcet 3;
  Utest.test_int "recursion.c (kalle): WCET Optimized: -O1." wcet 73;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "kalle" ["a0=[0,10]"] 2 false in
  Utest.test_int "recursion.c (kalle): BCET Optimized: -O2." bcet 3;
  Utest.test_int "recursion.c (kalle): WCET Optimized: -O2." wcet 25;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "kalle" ["a0=[0,10]"] 3 false in
  Utest.test_int "recursion.c (kalle): BCET Optimized: -O3." bcet 23;
  Utest.test_int "recursion.c (kalle): WCET Optimized: -O3." wcet 33;

  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "anka" ["a0=[0,10]"] 0 false in
  Utest.test_int "recursion.c (anka): BCET Not Optimized." bcet 15;
  Utest.test_int "recursion.c (anka): WCET Not Optimized." wcet 185;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "anka" ["a0=[0,10]"] 1 false in
  Utest.test_int "recursion.c (anka): BCET Optimized: -O1." bcet 3;
  Utest.test_int "recursion.c (anka): WCET Optimized: -O1." wcet 73;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "anka" ["a0=[0,10]"] 2 false in
  Utest.test_int "recursion.c (anka): BCET Optimized: -O2." bcet 3;
  Utest.test_int "recursion.c (anka): WCET Optimized: -O2." wcet 28;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "anka" ["a0=[0,10]"] 3 false in
  Utest.test_int "recursion.c (anka): BCET Optimized: -O3." bcet 3;
  Utest.test_int "recursion.c (anka): WCET Optimized: -O3." wcet 47;

 (* let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "fib" ["a0=[0,10]"] 0 false in
  Utest.test_int "recursion.c (fib): BCET Not Optimized." bcet 15;
  Utest.test_int "recursion.c (fib): WCET Not Optimized." wcet 185;*)
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "fib" ["a0=[0,10]"] 1 false in
  Utest.test_int "recursion.c (fib): BCET Optimized: -O1." bcet 3;
  Utest.test_int "recursion.c (fib): WCET Optimized: -O1." wcet 1675;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "fib" ["a0=[0,10]"] 2 false in
  Utest.test_int "recursion.c (fib): BCET Optimized: -O2." bcet 11;
  Utest.test_int "recursion.c (fib): WCET Optimized: -O2." wcet 1386;
  let bcet,wcet = compile_file "test/wcet_tests/mdh/recursion.c" "fib" ["a0=[0,10]"] 3 false in
  Utest.test_int "recursion.c (fib): BCET Optimized: -O3." bcet 3;
  Utest.test_int "recursion.c (fib): WCET Optimized: -O3." wcet 993;

  Utest.result()
