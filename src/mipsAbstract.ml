
open Ustring.Op
open Printf
open MipsAst
open AInt32


(* ---------------------------------------------------------------------*)
type astate = {
  register_at : aint32;
  register_v0 : aint32;
  register_v1 : aint32;
  register_a0 : aint32;
  register_a1 : aint32;
  register_a2 : aint32;
  register_a3 : aint32;
  register_t0 : aint32;
  register_t1 : aint32;
  register_t2 : aint32;
  register_t3 : aint32;
  register_t4 : aint32;
  register_t5 : aint32;
  register_t6 : aint32;
  register_t7 : aint32;
  register_s0 : aint32;
  register_s1 : aint32;
  register_s2 : aint32;
  register_s3 : aint32;
  register_s4 : aint32;
  register_s5 : aint32;
  register_s6 : aint32;
  register_s7 : aint32;
  register_t8 : aint32;
  register_t9 : aint32;
  register_k0 : aint32;
  register_k1 : aint32;
  register_gp : aint32;
  register_sp : aint32;
  register_fp : aint32;
  register_ra : aint32;

  pc : int;
}

type distance = int array

(* ---------------------------------------------------------------------*)

let merge_when_more_than_states = 2

type step_failure =
| StepFail_JumpOverflow
  
exception Exception_in_step of step_failure
  
             

  
(* Enable this flag to pretty print debug info *)
let debug = true

let sll_max_vals = 64
  
(* ---------------------------------------------------------------------*)

  


    
(* Returns a tuple (true_list,false_list) *)
let aint32_blez xlst =
  List.fold_left
      (fun (tacc,facc) (xl,xu) ->
        if xu <= 0 then ((xl,xu)::tacc,facc)
        else if xl > 0 then (tacc,(xl,xu)::facc)
        else ((xl,0)::tacc,(1,xu)::facc)) ([],[]) xlst

    
(* Shift into unique values if fewer than sll_max_vals. Used for jump tables *)
let aint32_sll xlst shift =
  let sleft x b = (x lsl b) land 0xffffffff in
  match xlst with
  | [(l,u)] when u - l <= sll_max_vals ->
    let rec mk k =
      let k' = sleft k shift in
      if k = u then [(k',k')] else (k',k')::(mk (k+1)) in mk l  
  | _ -> List.map (fun (l,u) -> (sleft l shift, sleft u shift)) xlst

    


    
  
 
  

let init_state =
  let reg_init = AInt32.make 0 in
  {
  register_at = reg_init;
  register_v0 = reg_init;
  register_v1 = reg_init;
  register_a0 = reg_init;
  register_a1 = reg_init;
  register_a2 = reg_init;
  register_a3 = reg_init;
  register_t0 = reg_init;
  register_t1 = reg_init;
  register_t2 = reg_init;
  register_t3 = reg_init;
  register_t4 = reg_init;
  register_t5 = reg_init;
  register_t6 = reg_init;
  register_t7 = reg_init;
  register_s0 = reg_init;
  register_s1 = reg_init;
  register_s2 = reg_init;
  register_s3 = reg_init;
  register_s4 = reg_init;
  register_s5 = reg_init;
  register_s6 = reg_init;
  register_s7 = reg_init;
  register_t8 = reg_init;
  register_t9 = reg_init;
  register_k0 = reg_init;
  register_k1 = reg_init;
  register_gp = reg_init;
  register_sp = reg_init;
  register_fp = reg_init;
  register_ra = reg_init;

  pc = 0;
  }


(* ---------------------------------------------------------------------*)
let reg0 = AInt32.make 0 
let reg state reg = 
  match reg with
  | 0 -> reg0
  | 1 -> state.register_at
  | 2 -> state.register_v0 
  | 3 -> state.register_v1 
  | 4 -> state.register_a0
  | 5 -> state.register_a1 
  | 6 -> state.register_a2
  | 7 -> state.register_a3 
  | 8 -> state.register_t0 
  | 9 -> state.register_t1 
  | 10 -> state.register_t2 
  | 11 -> state.register_t3 
  | 12 -> state.register_t4 
  | 13 -> state.register_t5
  | 14 -> state.register_t6
  | 15 -> state.register_t7 
  | 16 -> state.register_s0 
  | 17 -> state.register_s1 
  | 18 -> state.register_s2 
  | 19 -> state.register_s3 
  | 20 -> state.register_s4 
  | 21 -> state.register_s5 
  | 22 -> state.register_s6 
  | 23 -> state.register_s7 
  | 24 -> state.register_t8 
  | 25 -> state.register_t9 
  | 26 -> state.register_k0
  | 27 -> state.register_k1 
  | 28 -> state.register_gp 
  | 29 -> state.register_sp 
  | 30 -> state.register_fp
  | 31 -> state.register_ra
  | _ -> failwith "Illegal register."

(* ---------------------------------------------------------------------*)
let wreg reg v state =
  match reg with
  | 0 -> state
  | 1 -> {state with register_at=v}
  | 2 -> {state with register_v0=v} 
  | 3 -> {state with register_v1=v} 
  | 4 -> {state with register_a0=v}
  | 5 -> {state with register_a1=v} 
  | 6 -> {state with register_a2=v}
  | 7 -> {state with register_a3=v} 
  | 8 -> {state with register_t0=v} 
  | 9 -> {state with register_t1=v} 
  | 10 -> {state with register_t2=v} 
  | 11 -> {state with register_t3=v} 
  | 12 -> {state with register_t4=v} 
  | 13 -> {state with register_t5=v}
  | 14 -> {state with register_t6=v}
  | 15 -> {state with register_t7=v} 
  | 16 -> {state with register_s0=v} 
  | 17 -> {state with register_s1=v} 
  | 18 -> {state with register_s2=v} 
  | 19 -> {state with register_s3=v} 
  | 20 -> {state with register_s4=v} 
  | 21 -> {state with register_s5=v} 
  | 22 -> {state with register_s6=v} 
  | 23 -> {state with register_s7=v} 
  | 24 -> {state with register_t8=v} 
  | 25 -> {state with register_t9=v} 
  | 26 -> {state with register_k0=v}
  | 27 -> {state with register_k1=v} 
  | 28 -> {state with register_gp=v} 
  | 29 -> {state with register_sp=v} 
  | 30 -> {state with register_fp=v}
  | 31 -> {state with register_ra=v} 
  | _ -> failwith "Illegal register."
  

(* ---------------------------------------------------------------------*)
let pprint_astate astate =
  let p_no no = let x = MipsUtils.pprint_reg no in 
                if (Ustring.length x) < 3 then x ^. us" " else x in
  let p_reg r = us" = " ^. Ustring.spaces_after (AInt32.pprint (reg astate r) ^. us"  ") 17 in
  let rec regs no str =
    if no >= 8 then str else
      regs (no+1) (str ^.
      p_no no      ^. p_reg (no) ^.
      p_no (no+8)  ^. p_reg (no+8) ^.
      p_no (no+16) ^. p_reg (no+16) ^.
      p_no (no+24) ^. p_reg (no+24) ^. us"\n")
  in
    us (sprintf "PC  0x%08x \n" astate.pc) ^.
    regs 0 (us"")
  
    
    
(* ---------------------------------------------------------------------*)
let rec step prog s =
  (* Compute the new instruction *)
  let inst = prog.code.((s.pc - prog.text_sec.addr)/4) in
  
  (* Increment the program counter and return the new state *)
  let pc inc s = {s with pc = s.pc + inc} in

  (* Compute the new PC for a specific address and return the new state *)
  let branch addr s = {s with pc = addr} in
  
  (* Evaluate the delay slot and return the new state. *)
  let eval_delayslot s =
    (match step prog (pc 4 s) with
     | [s'] -> s'
     | _ -> failwith (sprintf "Failed to execute delay slot at address 0x%x" s.pc))
  in  

  (* Match and execute each instruction *)
  match inst  with 
  | MipsADDU(rd,rs,rt) ->
      [wreg rd (AInt32.add (reg s rs) (reg s rt)) s |> pc 4]
  | MipsADDIU(rt,rs,imm) ->
      [wreg rt (AInt32.add (reg s rs) (AInt32.make imm)) s |> pc 4]      
  | MipsBLEZ(rs,imm,_) ->
      let s' = eval_delayslot s in
      let (tval,fval) = aint32_blez (reg s rs) in
      let s2 = if List.length tval = 0 then []
                else [wreg  rs tval s' |> branch (imm*4 + 4 + s.pc)] in
      if List.length fval = 0 then s2 else (wreg  rs fval s'|> pc 4)::s2
(*  | MipsBNEL(rs,rt,imm,s) ->
       if Int32.compare (reg rs) (reg rt) <> 0 then branch (imm*4 + 4 + state.pc)
    else (pc 8; hook()) *)
  | MipsJR(rs) ->
      let s' = eval_delayslot s in
      List.map (fun (l,u) ->
        if l=u then s' |> branch l 
               else raise (Exception_in_step StepFail_JumpOverflow))  (reg s rs) 
  | MipsSLL(rd,rt,shamt) ->
     [wreg rd (aint32_sll (reg s rt) shamt) s  |> pc 4]      
  | _ -> failwith ("Unknown instruction: " ^
                    Ustring.to_utf8 (MipsUtils.pprint_inst inst))


(* ---------------------------------------------------------------------*)
let merge_states states =
  (* TODO: Implement merge *)
  List.hd states

    
(* ---------------------------------------------------------------------*)
(* Performs multiple steps and accumulates all finished states into
   [accfinished]. *)
let rec multistep prog statelst dist accfinished  =
  (* Map distances to states, that is, create an associative list *)
  let map_dist states =
    List.map (fun s ->
      if s.pc = 0 then (max_int,s)
      else (dist.((s.pc - prog.text_sec.addr)/4), s)) states
  in

  (* Sorts new states into previous states, using the sort order of distances *)
  let rec insert_dist_states prev_states new_states =
      List.fold_left (fun acc dist_s ->
        let rec insert (dist,state) lst =
          match lst with
          | (d,sl)::next ->
              if dist = d then (d,state::sl)::next
              else if dist > d
              then (dist,[state])::lst
              else (d,sl)::(insert (dist,state) next)
          | [] -> [(dist,[state])]              
        in
          insert dist_s acc
      ) prev_states new_states
  in
  
  (* Selects which state to process next and merge states if they
     are at the same program point and are more than merge_when_more_than_states *)
  let select_and_merge_states states =
    match states with
    | [s] -> (s,[])
    | s::ls -> 
        let (lspc,lsrest) = List.partition (fun s2 -> s2.pc = s.pc) ls in
        if (List.length lspc + 1) > merge_when_more_than_states 
        then (merge_states (s::lspc), lsrest)
        else (s,ls)          
    | [] -> failwith "Should not happen. No states."
  in

  (* Check if the new states has finished (pc = 0). If so, add then
     to finished states. Returns a tuple with finished states and the
     remaining states. *)
  let rec check_finished accf accr newstates =
    match newstates with
    | s::ls -> if s.pc = 0 then check_finished (s::accf) accr ls
                           else check_finished accf (s::accr) ls
    | [] -> (accf,accr)
  in  

  (* Process the next state on the working list *)  
  match statelst with
  | (d,[])::next -> multistep prog next dist accfinished
  | (d,states)::next ->
       (* Select which state to process next. Merge states if necessary *)
       let (s,ls) = select_and_merge_states states in

       (* Perform a single step. Potentially get back multiple states *)
       let newstates = step prog s in

       (* Check if a state has terminated. If so, add to [accfinished] *)
       let (accfinished', newstates') = check_finished accfinished [] newstates in
       
       (* Insert and sort the new states into the working list *)
       let statelst' = insert_dist_states ((d,ls)::next) (map_dist newstates') in

       (* Repeat and process next states *)
       multistep prog statelst' dist accfinished'
         
  | [] -> merge_states accfinished

    


    
(* ---------------------------------------------------------------------*)
let init prog func args =
  (* Set the PC address to the address given by the func parameter *)
  let pc_addr = List.assoc func prog.symbols
  in
   (* Set program counter *)
   {init_state with pc = pc_addr}

   (* Set the global pointer *)
   |> wreg reg_gp (AInt32.make prog.gp)

   (* Set the stack pointer *)     
   |> wreg reg_sp (AInt32.make prog.sp)

   (* Set the arguments. For now, max 4 arguments. *)
   |> (fun state ->
     List.fold_left (fun (i,acc) argv ->
       if i < 4 then (i+1, wreg (reg_a0 + i) argv acc)
       else (i,acc)
     ) (0,state) args |> snd
   )

  

      
(* ---------------------------------------------------------------------*)
let distance prog func args =
  let len = Array.length prog.code in
  Array.mapi (fun i _ -> len - i) (Array.make len 0)
  

    
(* ---------------------------------------------------------------------*)
let eval  ?(bigendian=false)  prog state dist timeout =
  let state' = multistep prog [(max_int,[state])] dist [] in
  let wcet = 0 in
  let result = true in
  (result, wcet, state')

    
    
(* ---------------------------------------------------------------------*)
let main argv =
  let s = init_state in
  let s2 = wreg reg_t4 (AInt32.make 7) s  in
  printf "hello:";
  uprint_endline (AInt32.pprint (reg s2 reg_t4));
  let v1 = AInt32.make 7 in
  let v2 = AInt32.make_intervals [(2,8);(10,20)] in
  let v3 = AInt32.make_intervals [(-2,100)] in
  uprint_endline (AInt32.pprint v1);
  uprint_endline (AInt32.pprint v2);
  uprint_endline (AInt32.pprint (AInt32.add v1 v2));
  uprint_endline (AInt32.pprint (AInt32.add v2 v3));
  uprint_endline (AInt32.pprint (AInt32.add v2 v2))
  
  











    
