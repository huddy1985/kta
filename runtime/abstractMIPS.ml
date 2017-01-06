
(*

  Execute the main experiment using the following example
  >> ocamlbuild experiment.native -lib Str -- v0=[1,100]
*)


open Aint32relint
open Aregsimple
  
open Ustring.Op
open Printf
open Amemory
open Scanf
open Config
open Str

let dbg = false
let dbg_trace = true  (* Note that you should compile with exper.d.byte *)  
let dbg_inst = true
let dbg_mstate_sizes = false
let dbg_debug_intervals = false
  


(* ------------------------ TYPES ------------------------------*)  

type blockid = int     (* The block ID type *)
type distance = int    (* The type for describing distances of blocks *)

  
(** Abstract program state. Contains a concrete value
    for the program counter and abstract values for 
    registers and memory *)
type progstate = {
  reg  : aregister;
  mem  : amemory;
  bcet : int;
  wcet : int;
}

  
(** Basic block ID na_ means "not applicable". *)
let  na_ = -1

(** Priority queue type *)
type pqueue = (distance * blockid * progstate list) list

type specialbranch =
  (blockid *         
   registers * registers *
  (aint32 * aint32) option *
  (aint32 * aint32) option)
  
(** The basic block info entry type is one element in the
    basic block table. This table provides all information about
    how basic blocks are related, which distances they have etc. *)  
type bblock_info =
{
  func    : mstate -> mstate;  (* The function that represents the basic block *)
  name    : string;            (* String used for debugging *)
  nextid  : blockid;           (* The identifier that shows the next basic block *)
  dist    : distance;          (* The distance to the exit (the number of edges) *)
  addr    : int;               (* Address to the first instruction in the basic block *)
  caller  : bool;              (* true if the node is a function call node *)
}

(** Main state of the analysis *)
and mstate = {
  cblock   : blockid;                  (* Current basic block *)
  pc       : int;                      (* Current program counter *)
  pstate   : progstate;                (* Current program state *)
  batch    : progstate list;           (* Current batch of program states *)
  bbtable  : bblock_info array;        (* Basic block info table *)
  prio     : pqueue;                   (* Overall priority queue *)
  returnid : blockid;                  (* Block id when returning from a call *)
  cstack   : (blockid * pqueue) list;  (* Call stack *)
  sbranch  : specialbranch option;     (* special branch. Used between slt and beq *)
}


  
(* ------------------------ REGISTERS ------------------------------*)

    

let zero = R0
let at = R1
let v0 = R2
let v1 = R3
let a0 = R4
let a1 = R5
let a2 = R6
let a3 = R7
let t0 = R8
let t1 = R9
let t2 = R10
let t3 = R11
let t4 = R12
let t5 = R13
let t6 = R14
let t7 = R15
let s0 = R16
let s1 = R17
let s2 = R18
let s3 = R19
let s4 = R20
let s5 = R21
let s6 = R22
let s7 = R23
let t8 = R24
let t9 = R25
let k0 = R26
let k1 = R27
let gp = R28
let sp = R29
let fp = R30
let ra = R31

(* Used for instructions mflo and mfhi *)  
let internal_lo = R32
let internal_hi = R33
  
let reg2str r =
  match r with
  | R0 -> "zero" | R8  -> "t0" | R16 -> "s0" | R24 -> "t8"
  | R1 -> "at"   | R9  -> "t1" | R17 -> "s1" | R25 -> "t9"
  | R2 -> "v0"   | R10 -> "t2" | R18 -> "s2" | R26 -> "k0"
  | R3 -> "v1"   | R11 -> "t3" | R19 -> "s3" | R27 -> "k1"
  | R4 -> "a0"   | R12 -> "t4" | R20 -> "s4" | R28 -> "gp"
  | R5 -> "a1"   | R13 -> "t5" | R21 -> "s5" | R29 -> "sp"
  | R6 -> "a2"   | R14 -> "t6" | R22 -> "s6" | R30 -> "fp"
  | R7 -> "a3"   | R15 -> "t7" | R23 -> "s7" | R31 -> "ra"
  | R32 -> "internal_lo"       | R33 -> "internal_hi"

let reg2ustr r = reg2str r |> us
    
let int2reg x =
  match x with
  | 0 -> R0 | 8  -> R8  | 16 -> R16 | 24 -> R24
  | 1 -> R1 | 9  -> R9  | 17 -> R17 | 25 -> R25
  | 2 -> R2 | 10 -> R10 | 18 -> R18 | 26 -> R26
  | 3 -> R3 | 11 -> R11 | 19 -> R19 | 27 -> R27
  | 4 -> R4 | 12 -> R12 | 20 -> R20 | 28 -> R28
  | 5 -> R5 | 13 -> R13 | 21 -> R21 | 29 -> R29
  | 6 -> R6 | 14 -> R14 | 22 -> R22 | 30 -> R30
  | 7 -> R7 | 15 -> R15 | 23 -> R23 | 31 -> R31
  | 32 -> R32 | 33 -> R33
  | _ -> failwith "Unknown register."

let str2reg str =
  match str with
  | "zero" -> Some R0 | "t0" -> Some R8  | "s0" -> Some R16 | "t8" -> Some R24
  | "at"   -> Some R1 | "t1" -> Some R9  | "s1" -> Some R17 | "t9" -> Some R25
  | "v0"   -> Some R2 | "t2" -> Some R10 | "s2" -> Some R18 | "k0" -> Some R26
  | "v1"   -> Some R3 | "t3" -> Some R11 | "s3" -> Some R19 | "k1" -> Some R27
  | "a0"   -> Some R4 | "t4" -> Some R12 | "s4" -> Some R20 | "gp" -> Some R28
  | "a1"   -> Some R5 | "t5" -> Some R13 | "s5" -> Some R21 | "sp" -> Some R29
  | "a2"   -> Some R6 | "t6" -> Some R14 | "s6" -> Some R22 | "fp" -> Some R30
  | "a3"   -> Some R7 | "t7" -> Some R15 | "s7" -> Some R23 | "ra" -> Some R31
  | "internal_lo" -> Some R32            | "internal_hi" -> Some R33
  | _ -> None
    
(** Creates an initial any state of the program state 
    ps = The program counter value *)
let init_pstate =
  {
    reg = areg_init;
    mem = mem_init;
    bcet  = 0;
    wcet = 0;
}

(** Join two program states, assuming they have the same program counter value *)
let join_pstates ps1 ps2 =
{
   reg   = areg_join [ps1.reg;ps2.reg];
   mem   = mem_join [ps1.mem;ps2.mem];
   bcet  = min ps1.bcet ps2.bcet;
   wcet  = max ps1.wcet ps2.wcet;
}
    
     
(* ---------------  INPUT ARGUMENT HANDLING -----------------*)

(** Returns a new program state that is updated with input from
    the command line using args (a list of arguments) *)
let rec pstate_input ps args =
  let make_error a = raise (Failure ("Unknown argument: " ^ a)) in
  (* No more args? *)
  match args with
  | [] -> ps 
  | a::next_args -> (    
    (* Is a register definition? *)
    match split (regexp "=") a with
    | [reg;value] ->
         (match str2reg reg with
         | Some(regval) ->
             (* Is concrete value? *)
            (try (let aval = aint32_const (int_of_string value) in
                  pstate_input {ps with reg = (setreg regval aval ps.reg)} next_args)
             with _ -> (
               (* Is abstract interval value? *)
               (match (try bscanf (Scanning.from_string value) "[%d,%d]" (fun x y -> Some(x,y))
                         with _ -> None)
               with
               | Some(l,h) ->
                   let aval = aint32_interval l h in
                   pstate_input {ps with reg = (setreg regval aval ps.reg)} next_args
               | None -> make_error a)))
          | None -> make_error a)
    | _ -> make_error a)


(* ----------------------- DEBUG FUNCTIONS  -------------------------*)
let should_not_happen no = failwith (sprintf "ERROR: Should not happen ID = %d" no)

    
(** Pretty prints the entire program state 
    ps = program state
    noregs = number of registers to print *)
let pprint_pstate noregs ps =
  let rec pregs x s =
    if x < noregs then
      let r = int2reg x in
      let (_,v) = getreg r ps.reg in
      let n = reg2ustr r ^. us" = " ^. (aint32_pprint false v) in      
      let n' = Ustring.spaces_after n 18 ^. us(if x mod 4 = 0 then "\n" else "") in
      pregs (x+1) (s ^. n')        
    else s
  in      
    pregs 1 (us"") 

(* Debug print a program queue element *)
let print_pqueue_elem noregs elem =
  let (dist,id,progs) = elem in
  printf "ID: %d dist: %d\n" id dist;
  List.iter (fun ps ->
    uprint_endline (pprint_pstate noregs ps);
    printf "------\n";
  ) progs
  

(* Debug print the program queue *)
let print_pqueue noregs pqueue =
  List.iter (print_pqueue_elem noregs) pqueue 
      
let prn_inst_main linebreak ms str =
  if dbg_inst then
    (printf "%10s | %s" ms.bbtable.(ms.cblock).name (Ustring.to_utf8 str);
     if linebreak then printf "\n" else ())
  else ()
    

let prn_inst = prn_inst_main true
    
let prn_inst_no_linebreak = prn_inst_main false
    
let preg rt r =
    aint32_pprint dbg_debug_intervals (getreg rt r |> snd) 

let pprint_true_false_choice t f =
  let prn v =
    match v with
    | None -> us"none"
    | Some(v1,v2) -> us"(" ^. (aint32_pprint false v1) ^. us"," ^.
                     (aint32_pprint false v2) ^. us")"
  in
    us"T:" ^. prn t ^. us" F:" ^. prn f 
  
        
(* ---------------  BASIC BLOCKS AND PRIORITY QUEUE -----------------*)           
    
(* Enqueue a basic block *)  
let enqueue blockid ps ms =  
  let bi = ms.bbtable.(blockid) in
  let dist = bi.dist in
  let rec work queue = 
    (match queue with
    (* Distance larger? Go to next *)
    | (d,bid,pss)::qs when d > dist ->
      (d,bid,pss)::(work qs)
    (* Same dist?  *)
    | (d,bid,pss)::qs when dist = d ->
      (* Same block id *)                          
      if bid = blockid  then(
          (* Yes, enqueue *)       
        (d,bid,ps::pss)::qs)
      else
        (* No. Go to next *)
        (d,bid,pss)::(work qs)
    (* Block not found. Enqueue *)
    | qs ->
        (dist,blockid,[ps])::qs
    )
  in
    {ms with prio = work ms.prio}
  

let max_batch_size pss =
  if List.length pss > !config_max_batch_size then
    [List.fold_left join_pstates (List.hd pss) (List.tl pss)]
  else
    pss
  
(** Picks the block with highest priority.
    Returns the block id,
    the size of the program state list, and the program state list *)
let dequeue ms =
  (* Process the batch program states first *)
  match ms.batch with
  (* Found a batch state? *)
  | ps::pss -> {ms with pstate=ps; batch = pss}
  (* No more batch states. Find the next in the priority queue *)
  | [] -> 
    (match ms.prio with
    (* Have we finished a call? Dist = 0? *)
    | (0,blockid,ps::pss)::rest ->
       (* Is it the final node? *)
      if blockid=0 then 
         (* Join all final program states *)
         let ps' = List.fold_left join_pstates ps pss in
         {ms with cblock = 0; pstate=ps'; prio=rest} 
       else
         (* No, just pop from the call stack *)
         (match ms.cstack with
          | (retid,prio')::cstackrest ->  
             {ms with cblock=blockid; pstate=ps; batch=max_batch_size pss;
               prio=prio'; returnid = retid; cstack=cstackrest;}
          | [] -> should_not_happen 1)
        
    (* Dequeue the top program state *)  
    | (dist,blockid,ps::pss)::rest ->
       (* Is this a calling node? *)
       let bs = ms.bbtable.(blockid) in
       if bs.caller then
         (* Yes, add to the call stack *)        
         {ms with
           cblock=blockid; pstate=ps; batch=max_batch_size pss; prio=[];
           cstack = (ms.bbtable.(blockid).nextid,rest)::ms.cstack}
       else
         (* No, just get the last batch *)
         {ms with cblock=blockid; pstate=ps; batch=max_batch_size pss; prio=rest;}
    (* This should never happen. It should end with a terminating 
           block id zero block. *)    
    | _ -> should_not_happen 2)
  
  
(* ------------------------ CONTINUATION  -------------------------*)

(* Continue and execute the next basic block in turn *)
let continue ms =
  (* Debug output for the mstate *)
  if dbg && dbg_mstate_sizes then (
    printf "-----------------\n";
    printf "blockid = %d, pc = %d, batch size = %d, prio queue size = %d\n"
      ms.cblock ms.pc (List.length ms.batch) (List.length ms.prio);
    printf "cstack size %d\n" (List.length ms.cstack))
  else ();
  let ms = dequeue ms in
  let ms = {ms with pc = ms.bbtable.(ms.cblock).addr} in 
  let bi = ms.bbtable.(ms.cblock) in
  bi.func ms 


    
let to_mstate ms ps =
  {ms with pstate = ps}

let tick n ps =  
  {ps with bcet = ps.bcet + n; wcet = ps.wcet + n} 

let update r ps =
  {ps with reg = r}

let updatemem r m ps =
  {ps with reg = r; mem = m}
    
(* ------------------------ INSTRUCTIONS -------------------------*)

let r_instruction binop rd rs rt ms =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_rs) = getreg rs r in
  let (r,v_rt) = getreg rt r in
  let r' = setreg rd (binop v_rs v_rt) r in
  if dbg && dbg_inst then uprint_endline (us" " ^. 
        (reg2ustr rd) ^. us"=" ^. (preg rd r') ^. us" " ^.
        (reg2ustr rs) ^. us"=" ^. (preg rs r) ^. us" " ^.
        (reg2ustr rt) ^. us"=" ^. (preg rt r) ) else ();
  ps |> update r' |> tick 1 |> to_mstate ms

let debug_r_instruction str binop rd rs rt ms =
  prn_inst_no_linebreak ms str;
  r_instruction binop rd rs rt ms
      
let add =
  if dbg then debug_r_instruction (us"add") aint32_add
  else r_instruction aint32_add

let addu =
  if dbg then debug_r_instruction (us"addu") aint32_add
  else r_instruction aint32_add
    
let mul =
  if dbg then debug_r_instruction (us"mul") aint32_mul
  else r_instruction aint32_mul

(* TODO: handle 64-bit. Right now, we only use 32-bit multiplication. *)    
let mult rs rt ms =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_rs) = getreg rs r in
  let (r,v_rt) = getreg rt r in
  let r = setreg internal_lo (aint32_mul v_rs v_rt) r in
  let r = setreg internal_hi (aint32_any) r in
  if dbg then prn_inst ms (us"addi ");
  ps |> update r |> tick 1 |> to_mstate ms
      

let mflo rd ms = 
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_lo) = getreg internal_lo r in
  let r = setreg rd v_lo r in
  if dbg then prn_inst ms (us"mflo ");
  ps |> update r |> tick 1 |> to_mstate ms
  
  
let mfhi rd ms =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_hi) = getreg internal_hi r in
  let r = setreg rd v_hi r in
  if dbg then prn_inst ms (us"mfhi ");
  ps |> update r |> tick 1 |> to_mstate ms
      
    
let addi rt rs imm ms  =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_rs) = getreg rs r in
  let r' = setreg rt (aint32_add v_rs (aint32_const imm)) r in             
  if dbg then prn_inst ms (us"addi " ^. 
        (reg2ustr rt) ^. us"=" ^. (preg rt r') ^. us" " ^.
        (reg2ustr rs) ^. us"=" ^. (preg rs r) ^. us" " ^.
         us(sprintf "imm=%d" imm));
  ps |> update r' |> tick 1 |> to_mstate ms 

      
let addiu = addi

  
let sll rd rt shamt ms =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_rt) = getreg rt r in
  let mval = aint32_const (1 lsl shamt) in
  let r' = setreg rd (aint32_mul v_rt mval) r in
  if dbg then prn_inst ms (us"sll " ^. 
        (reg2ustr rd) ^. us"=" ^. (preg rd r') ^. us" " ^.
        (reg2ustr rt) ^. us"=" ^. (preg rt r) ^. us" " ^.
         us(sprintf "shamt=%d" shamt));
  ps |> update r' |> tick 1 |> to_mstate ms 

      
let sra rd rt shamt ms =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_rt) = getreg rt r in
  let mval = aint32_const (1 lsl shamt) in
  let r' = setreg rd (aint32_div v_rt mval) r in
  if dbg then prn_inst ms (us"sra " ^. 
        (reg2ustr rd) ^. us"=" ^. (preg rd r') ^. us" " ^.
        (reg2ustr rt) ^. us"=" ^. (preg rt r) ^. us" " ^.
         us(sprintf "shamt=%d" shamt));
  ps |> update r' |> tick 1 |> to_mstate ms 


(* used by next and branch_equality *)
let enq blabel regt regf bval ms =
  match bval with
  | Some(tval,fval) ->
    let ps = {ms.pstate with reg = setreg regt tval
        (setreg regf fval ms.pstate.reg)} in
    enqueue blabel ps ms
  | None -> ms

      
let branch_main equal dslot op rs rt label ms =
  match ms.sbranch with
  | None -> (
    (* Ordinary branch equality check *)
    let ps = tick 1 ms.pstate in    
    let r = ps.reg in
    let (r,v_rs) = getreg rs r in
    let (r,v_rt) = getreg rt r in
    let ms = update r ps |> to_mstate ms in
    let bi = ms.bbtable.(ms.cblock) in
    let (tb,fb) = op v_rs v_rt in
    let (tbranch,fbranch) = if equal then (tb,fb) else (fb,tb) in
    if dslot then
      {ms with sbranch = Some(label,rs,rt,tbranch,fbranch)}
    else      
      continue (ms |> enq label rs rt tbranch |> enq bi.nextid rs rt fbranch))

  | Some(_,r1,r2,tb,fb) -> (
    (* Special branch handling when beq or bne is checking with $0 and  
       there is another instruction such as slt that has written 
       information in ms.sbranch *)      
    let bi = ms.bbtable.(ms.cblock) in
    let (tbranch,fbranch) = if equal then (fb,tb) else (tb,fb) in
    if dbg then (
        let r = ms.pstate.reg in
        prn_inst ms ((if equal then us"beq " else us"bne ") ^.
        (reg2ustr rs) ^. us"=" ^. (preg rs r) ^. us" " ^.
        (reg2ustr rt) ^. us"=" ^. (preg rt r) ^. us" " ^.
        us(ms.bbtable.(label).name) ^. us" " ^. us(ms.bbtable.(bi.nextid).name) ^.
        us" " ^. pprint_true_false_choice tbranch fbranch ^. us" (sbranch)"));
    if dslot then 
      {ms with sbranch = Some(label,r1,r2,tbranch,fbranch)}
    else      
      let ms = {ms with sbranch = None} in
      continue (ms |> enq label r1 r2 tbranch |> enq bi.nextid r1 r2 fbranch))

let debug_branch str equal dslot op rs rt label ms =
  prn_inst ms str;
  branch_main equal dslot op rs rt label ms


(* Instruction: beq
   From official MIPS32 manual: 
   "Branch on Equal
   To compare GPRs then do a PC-relative conditional branch." *)
let beq =
  if dbg then debug_branch (us"beq")
                   true false aint32_test_equal
  else branch_main true false aint32_test_equal

(* Same as above, but with branch delay slots enabled *)    
let beqds =
  if dbg then debug_branch (us"beqds")
                   true true aint32_test_equal
  else branch_main true true aint32_test_equal

(* Instruction: bne
   From official MIPS32 manual: 
   "Branch on Not Equal
   To compare GPRs then do a PC-relative conditional branch" *)
let bne =
  if dbg then debug_branch (us"bne")
                   false false aint32_test_equal
  else branch_main false false aint32_test_equal

    
(* Same as above, but with branch delay slots enabled *)    
let bneds =
  if dbg then debug_branch (us"bneds")
                   false true aint32_test_equal
  else branch_main false true aint32_test_equal

(* Instruction: beql
   From official MIPS32 manual: 
   "Branch on Equal Likely. 
   To compare GPRs then do a PC-relative conditional branch; 
   execute the delay slot only if the branch is taken. " 
   NOTE: the generated code need to insert a "likely" node
   to make this correct. *)
let beqlds =
  if dbg then debug_branch (us"beqlds")
                   true true aint32_test_equal
  else branch_main true true aint32_test_equal

    
(* Instruction: bnel
   From official MIPS32 manual: 
   "Branch on Not Equal Likely. 
   To compare GPRs then do a PC-relative conditional branch; 
   execute the delay slot only if the branch is taken." 
   NOTE: the generated code need to insert a "likely" node
   to make this correct. *)
let bnelds =
  if dbg then debug_branch (us"bnelds")
                   false true aint32_test_equal
  else branch_main false true aint32_test_equal

    
(* Instruction: blez
   From official MIPS32 manual: 
   "Branch on Less Than or Equal to Zero
   To test a GPR then do a PC-relative conditional branch." *)
let blez rs label ms =
  if dbg then debug_branch (us"blez")
                   true false aint32_test_less_than_equal rs zero label ms
  else branch_main true false aint32_test_less_than_equal rs zero label ms

    
(* Same as above, but with branch delay slots enabled *)    
let blezds rs label ms =
  if dbg then debug_branch (us"blezds")
                   true true aint32_test_less_than_equal rs zero label ms
  else branch_main true true aint32_test_less_than_equal rs zero label ms


let lui rt imm ms =
  if dbg then prn_inst ms (us"lui ");
  let ps = ms.pstate in
  let r = ps.reg in
  let r = setreg rt (aint32_const (imm lsl 16)) r in
  ps |> update r |> tick 1 |> to_mstate ms 


  
      
(* Count cycles for the return. The actual jump is performed
   by the pseudo instruction 'ret'. The reason is that
   all functions should only have one final basic block node *)    
let jr rs ms =
  if dbg then prn_inst ms (us"jr " ^. (reg2ustr rs));
  if rs = ra then ms
(*    let nextid = ms.bbtable.(ms.cblock).nextid in
      continue (enqueue nextid (tick 2 ms.pstate) ms) *)
  else failwith "Not yet implemented."

let jrds rs ms =
  if dbg then prn_inst ms (us"jrds " ^. (reg2ustr rs));
  if rs = ra then ms
(*    let nextid = ms.bbtable.(ms.cblock).nextid in
      continue (enqueue nextid (tick 2 ms.pstate) ms) *)
  else failwith "Not yet implemented."

    
let jal label ms =
  if dbg then prn_inst ms (us"jal " ^. us(ms.bbtable.(label).name));
  continue (enqueue label ms.pstate ms)

let jalds label ms =
  if dbg then prn_inst ms (us"jalds " ^. us(ms.bbtable.(label).name));
  {ms with sbranch = Some(label,zero,zero,Some(aint32_const 0,aint32_const 0),None)}

    
let jds label ms =
  if dbg then prn_inst ms (us"jds " ^. us(ms.bbtable.(label).name));
  {ms with sbranch = Some(label,zero,zero,Some(aint32_const 0,aint32_const 0),None)}
  
    
let sw rt imm rs ms =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_rt) = getreg rt r in
  let (r,v_rs) = getreg rs r in
  let con_v_rs = aint32_to_int32 v_rs in
  let m = set_memval (imm + con_v_rs) v_rt ps.mem in
  if dbg then(
    prn_inst ms (us"sw " ^. 
         (reg2ustr rt) ^. us"=" ^. (preg rt r) ^.
         us(sprintf " imm=%d(" imm) ^.
         (reg2ustr rs) ^. us"=" ^. (preg rs r) ^. us")")) else ();
  ps |> updatemem r m |> tick 1 |> to_mstate ms 


let lw rt imm rs ms =
  let ps = ms.pstate in
  let r = ps.reg in
  let (r,v_rt) = getreg rt r in
  let (r,v_rs) = getreg rs r in
  let con_v_rs = aint32_to_int32 v_rs in
  let (m,v) = get_memval (imm + con_v_rs) ps.mem in
  let r' = setreg rt v r in
  if dbg then(
    prn_inst ms (us"lw " ^. 
         (reg2ustr rt) ^. us"=" ^. (preg rt r') ^.
         us(sprintf " imm=%d(" imm) ^.
         (reg2ustr rs) ^. us"=" ^. (preg rs r) ^. us")")) else ();
  ps |> updatemem r' m |> tick 1 |> to_mstate ms 

      
let slt_main signed r v_rs v_rt rd rs rt ms =
  let ps = ms.pstate in    
  let (t,f) = (if signed then aint32_test_less_than else
               aint32_test_less_than_unsigned) v_rs v_rt in
  let ms = {ms with sbranch = Some (0,rs,rt,t,f)} in
  let rd_v = match t,f with
    | _,None -> aint32_const 1
    | None,_ -> aint32_const 0
    | _,_ -> aint32_interval 0 1
  in
  let r' = setreg rd rd_v r in
  if dbg then
    prn_inst ms ((if signed then us"slt " else us"sltu ") ^.
      (reg2ustr rd) ^. us"=" ^. (preg rd r') ^. us" " ^.
      (reg2ustr rs) ^. us"=" ^. (preg rs r) ^. us" " ^.
      (reg2ustr rt) ^. us"=" ^. (preg rt r) ^.
      us" " ^. pprint_true_false_choice t f);
  ps |> update r' |> tick 1 |> to_mstate ms

           
let slt rd rs rt ms = 
  let (r,v_rs) = getreg rs ms.pstate.reg in
  let (r,v_rt) = getreg rt r in
  slt_main true r v_rs v_rt rd rs rt ms

    
let sltu rd rs rt ms = 
  let (r,v_rs) = getreg rs ms.pstate.reg in
  let (r,v_rt) = getreg rt r in
  slt_main false r v_rs v_rt rd rs rt ms
    

let slti rd rs imm ms =
  let (r,v_rs) = getreg rs ms.pstate.reg in
  slt_main true r v_rs (aint32_const imm) rd rs zero ms
  
  
(* Removes special branch if variables are changed between set and 
   jump. Should be inserted by the compiler  *)  
let nosbranch ms =
  {ms with sbranch = None}



      
(* -------------------- PSEUDO INSTRUCTIONS -------------------------*)
      
        
(* Go to next basic block. Special handling if branch delay slot. *)
let next ms =
  (* Get the block info for the current basic block *)
 let bi = ms.bbtable.(ms.cblock) in
  (match ms.sbranch with
  | None -> 
    if dbg then prn_inst ms (us(sprintf "next id=%d" bi.nextid));
    (* Ordinary branch equality check *)
    (* Enqueue the current program state with the next basic block *)
    let ms' = enqueue bi.nextid ms.pstate ms in
    (* Continue and process next block *)
    continue ms'
    
  | Some(label,r1,r2,tb,fb) -> 
    if dbg then prn_inst ms
      (us(sprintf "next (delay slot) label=%d nextid=%d" label bi.nextid));
    (* Special branch handling branch delay slots *)      
    let ms = {ms with sbranch = None} in
    continue (ms |> enq label r1 r2 tb |> enq bi.nextid r1 r2 fb))

  

    

(* Return from a function. Pseudo-instruction that does not take time *)    
let ret ms =
  if dbg then prn_inst ms (us(sprintf "ret returnid=%d" ms.returnid));
  continue (enqueue ms.returnid ms.pstate ms)

(* load immediate interval *)
let lii rd l h ms =
  if dbg then prn_inst ms (us"lii");
  let ps = ms.pstate in
  let r = ps.reg in
  let r = setreg rd (aint32_interval l h) r in
  ps |> update r |> to_mstate ms
  

(* ------------------- MAIN ANALYSIS FUNCTIONS ----------------------*)
    
(** Main function for analyzing an assembly function *)
let analyze_main startblock bblocks args =
  (* Get the block info of the first basic block *)  
  let bi = bblocks.(startblock) in

  (* Update the program states with abstract inputs from program arguments *)
  let ps = 
    try pstate_input init_pstate args
      with Failure s -> (printf "Error: %s\n" s; exit 1) in 


  (* Initiate the stack pointer *)
  let stack_addr = 0x80000000 - 8 in
  let ps = {ps with reg = (setreg sp (aint32_const stack_addr) ps.reg)} in
       
  
  (* Create the main state *)
  let mstate = {
    cblock= startblock;   (* N/A, since the process has not yet started *)    
    pc = bi.addr;
    pstate = ps;          (* New program state *)
    batch = [];
    bbtable = bblocks;    (* Stores a reference to the basic block info table *)
    prio = [];            (* Starts with an empty priority queue *)
    returnid = 0;         (* Should finish by returning to the final block *)
    cstack = [(0,[])];    (* The final state *)
    sbranch = None;       (* Special branch. Just dummy values *)
  } in
  
  let mstate = enqueue startblock ps mstate in

  (* Continue the process and execute the next basic block from the queue *)
  continue mstate 



let _ = if dbg && dbg_trace then Printexc.record_backtrace true else ()

(** Print main state info *)
let print_mstate ms =
  printf "Counter: %d\n" !counter;
  printf "BCET:  %d cycles\n" ms.pstate.bcet;
  printf "WCET:  %d cycles\n" ms.pstate.wcet;
  uprint_endline (pprint_pstate 32 ms.pstate)

    
let analyze startblock bblocks defaultargs =
  let args = (Array.to_list Sys.argv |> List.tl) in
  let args = if args = [] then defaultargs else args in
  if dbg && dbg_trace then
    let v =     
      try analyze_main startblock bblocks args |> print_mstate
      with _ -> (Printexc.print_backtrace stdout; raise Not_found)
    in v
  else
    analyze_main startblock bblocks args |> print_mstate

    
    
  

















  
  