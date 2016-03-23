


open Printf
open AbstractMIPS 
open Ustring.Op

(* -- Basic Block Identifiers -- *)

let exp1_   = 0
let loop_   = 1
let return_ = 2


(* -- Start of analysis -- *)

      
let rec main =
  let s =
    init 0x100        |>
    lii  t1 (-7) 100  |>
    addi v0 zero 77   |>
    add  t0 v0 v0     |>
    add  t2 t1 v0     |>
    add  t3 t1 t2            
        
  in
  uprint_endline (pprint_pstate s 32)


(* -- Program code -- *)

and exp1 ps = ps       |>   
    addi  v0 zero 0    |>
    next

and loop ps = ps       |>
    add   v0 v0 a0     |>
    addi  a0 a0 (-1)   |>	
    bne	  a0 a1 loop_  

and return ps = ps     |>
    jr	  ra           


(* -- Basic Block Info -- *)


let blocks =
[
  {func=exp1;   nextid=loop_;   addr=0};
  {func=loop;   nextid=return_; addr=4};
  {func=return; nextid=exit_;   addr=16};
]
    


(*
  priority queue


type pqueue = distance * blockid * count * list pstate

*)

