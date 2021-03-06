
   
open RiscvISA
open Printf
open Ustring.Op

(*************** Exported types and exceptions ********************)

exception Decode_error
exception Unsupported_encoding




(*************** Local types and exceptions ***********************)


(*************** Local functions **********************************)

(* Decoding of opcode for R, R4, I, B, L, and J Types *)
let d_op low = low land 0b1111111

(* Decoding of rd for R, R4, I, and L Types *)
let d_rd high = high lsr 11 

(* Decoding of rs1 for R, R4, I, and B Types *)
let d_rs1 high = (high lsr 6) land 0b11111 

(* Decoding of rs2 for R, R4, and B Types  *)
let d_rs2 high = (high lsr 1) land 0b11111 

(* Decoding of rs3 for the R4 type *)
let d_rs3 high low = ((high land 1) lsl 4) lor (low lsr 12) 

(* Decoding of 12 bit immediate for I-Type *)
let d_imI high low = ((high land 0b111111) lsl 6) lor (low lsr 10) 

(* Decoding of 12 bit immediate for B-Type *)
let d_imB high low = ((high lsr 11) lsl 7) lor ((high land 1) lsl 6) 
                     lor (low lsr 10)

(* Decoding of 20 bit immediate for L-Type *)
let d_imL high low = ((high land 0b11111111111) lsl 9) lor (low lsr 7)

(* Decoding of 25 bit jump offset for J-Type *)
let d_offJ high low = (high lsl 9) lor (low lsr 7)

(* Decoding of 10 bit funct opcode field for R-Type *)
let d_funR high low = ((high land 1) lsl 9) lor (low lsr 7)

(* Decoding of 5 bit funct opcode field for R4-Type *)
let d_funR4 low = (low lsr 7) land 0b11111

(* Decoding of 3 bit funct opcode field for I and B Types *)
let d_funIB low = (low lsr 7) land 0b111

(* Error reporting if we have an unknown instruction *)
let failinst h l = 
  failwith (sprintf "ERROR: Unknown instruction %x,%x,%x,%x\n" 
            (h lsr 8) (h land 0xff) (l lsr 8) (l land 0xff))

(* Decodes the top 7 bits funct opcode of the R-Type, excluding rm field *)
let d_fp_funR h l = ((h land 1) lsl 6) lor ((l lsr 12) lsl 2) lor
                    ((l lsr 7) land 0b11)


             
(* Decodes one 32 bit instruction *)
let decode_32inst h l =
  let fi = Info(0, usid"", 4) in
  match d_op l with
    (* Unconditonal Jump Instructions *)
  | 0b1100111 -> MIUncondJmp(fi, OpJ, d_offJ h l)
  | 0b1101111 -> MIUncondJmp(fi, OpJAL, d_offJ h l)
    (* Conditional Jump Instructions *)
  | 0b1100011 -> 
      let op = match d_funIB l with 0b000 -> OpBEQ | 0b001 -> OpBNE  | 0b100 -> OpBLT |
                                    0b101 -> OpBGE | 0b110 -> OpBLTU | 0b111 -> OpBGEU | 
                                    _ -> failinst h l in
    MICondJmp(fi, op, d_rs1 h, d_rs2 h, d_imB h l) 
    (* Indirect Jump Instructions *)
  | 0b1101011 -> 
      let op = match d_funIB l with 0b000 -> OpJALR_C | 0b001 -> OpJALR_R | 
                                    0b010 -> OpJALR_J | 0b100 -> OpRDNPC | 
                                    _ -> failinst h l in
      MIIndJmp(fi, op, d_rd h, d_rs1 h, d_imI h l)
    (* Load Memory Instructions *)
  | 0b0000011 -> 
      let op = match d_funIB l with 0b000 -> OpLB  | 0b001 -> OpLH  | 0b010 -> OpLW |
                                    0b011 -> OpLD  | 0b100 -> OpLBU | 0b101 -> OpLHU |
                                    0b110 -> OpLWU | _ -> failinst h l in
      MILoad(fi, op, d_rd h, d_rs1 h, d_imI h l)
    (* Store Memory Instructions *)
  | 0b0100011 ->
      let op = match d_funIB l with 0b000 -> OpSB | 0b001 -> OpSH | 
                                    0b010 -> OpSW | 0b011 -> OpSD | _ -> failinst h l in
      MIStore(fi, op, d_rs1 h, d_rs2 h, d_imB h l)
    (* Atomic Memory Instructions *)
  | 0b0101011 ->
      let op = match d_funR h l with 0b000010 -> OpAMOADD_W  | 0b001010 -> OpAMOSWAP_W |
                                     0b010010 -> OpAMOAND_W  | 0b011010 -> OpAMOOR_W |
                                     0b100010 -> OpAMOMIN_W  | 0b101010 -> OpAMOMAX_W |
                                     0b110010 -> OpAMOMINU_W | 0b111010 -> OpAMOMAXU_W |
                                     0b000011 -> OpAMOADD_D  | 0b001011 -> OpAMOSWAP_D |
                                     0b010011 -> OpAMOAND_D  | 0b011011 -> OpAMOOR_D |
                                     0b100011 -> OpAMOMIN_D  | 0b101011 -> OpAMOMAX_D |
                                     0b110011 -> OpAMOMINU_D | 0b111011 -> OpAMOMAXU_D |
                                     _ -> failinst h l in
      MIAtomic(fi, op, d_rd h, d_rs1 h, d_rs2 h)
     (* Integer Register-Immediate Compute Instructions *)
  | 0b0010011 ->
      let im12 = d_imI h l in
      let imop = im12 lsr 6 in
      let op = match d_funIB l with 0b000 -> OpADDI  | 0b001 -> OpSLLI | 0b010 -> OpSLTI |
                                    0b011 -> OpSLTIU | 0b100 -> OpXORI | 
                                    0b101 when imop = 0 -> OpSRLI |
                                    0b101 when imop = 1 -> OpSRAI |
                                    0b110 -> OpORI   | 0b111 -> OpANDI |
                                    _ -> failinst h l in
      let im = match op with OpSLLI | OpSRLI | OpSRAI -> im12 land 0b111111 | _ -> im12 in
      MICompImm(fi, op, d_rd h, d_rs1 h, im)
  | 0b0110111 -> MICompImm(fi, OpLUI, d_rd h, 0, d_imL h l)
  | 0b0011011 ->
      let im12 = d_imI h l in
      let imop = im12 lsr 5 in
      let op = match d_funIB l with 0b000 -> OpADDIW | 0b001 -> OpSLLIW | 
                                    0b101 when imop = 0b00 -> OpSRLIW |
                                    0b101 when imop = 0b10 -> OpSRAIW |
                                    _ -> failinst h l in
      let im = match op with OpSRLIW | OpSRAIW -> im12 land 0b11111 | _ -> im12 in
      MICompImm(fi, op, d_rd h, d_rs1 h, im)
     (* Integer Register-Register Compute Instructions *)
  | 0b0110011 ->
      let op = match d_funR h l with 0b0000000000 -> OpADD    | 0b1000000000 -> OpSUB   |
                                     0b0000000001 -> OpSLL    | 0b0000000010 -> OpSLT   |
                                     0b0000000011 -> OpSLTU   | 0b0000000100 -> OpXOR   | 
                                     0b0000000101 -> OpSRL    | 0b1000000101 -> OpSRA   | 
                                     0b0000000110 -> OpOR     | 0b0000000111 -> OpAND   |
                                     0b0000001000 -> OpMUL    | 0b0000001001 -> OpMULH  |
                                     0b0000001010 -> OpMULHSU | 0b0000001011 -> OpMULHU |
                                     0b0000001100 -> OpDIV    | 0b0000001101 -> OpDIVU  |
                                     0b0000001110 -> OpREM    | 0b0000001111 -> OpREMU  |
                                     _ -> failinst h l in
      MICompReg(fi, op, d_rd h, d_rs1 h, d_rs2 h)
  | 0b0111011 ->
      let op = match d_funR h l with 0b0000000000 -> OpADDW   | 0b1000000000 -> OpSUBW  |
                                     0b0000000001 -> OpSLLW   | 0b0000000101 -> OpSRLW  |
                                     0b1000000101 -> OpSRAW   | 0b0000001000 -> OpMULW  |
                                     0b0000001100 -> OpDIVW   | 0b0000001101 -> OpDIVUW |
                                     0b0000001110 -> OpREMW   | 0b0000001111 -> OpREMUW |
                                     _ -> failinst h l in
      MICompReg(fi, op, d_rd h, d_rs1 h, d_rs2 h)
  (* Miscellaneous Memory Instructions *)
  | 0b0101111 ->
       let op = match d_funIB l with 0b001 -> OpFENCE_I | 0b010 -> OpFENCE |
                                           _ -> failinst h l in
       MIMiscMem(fi, op, d_rd h, d_rs1 h, d_imI h l)
  (* System Instructions *)
  | 0b1110111 ->
       let op = match d_funR h l with 0b0000000000 -> OpSYSCALL  | 0b0000000001 -> OpBREAK |
                                      0b0000000100 -> OpRDCYCLE  | 0b0000001100 -> OpRDTIME |
                                      0b0000010100 -> OpRDINSTRET | _ -> failinst h l in
       MISys(fi, op, d_rd h)
  | _ -> failinst h l


(* Encode the R-type *)
let encR rd rs1 rs2 opfunct17 =
  let high = (rd lsl 11) lor (rs1 lsl 6) lor (rs2 lsl 1) lor (opfunct17 lsr 16) in
  let low = opfunct17 land 0xffff in
  (high,low)

(* Encode the R4-type *)
let encR4 rd rs1 rs2 rs3 opfunct12 =
  let high = (rd lsl 11) lor (rs1 lsl 6) lor (rs2 lsl 1) lor (rs3 lsr 4) in
  let low = ((rs3 land 0b1111) lsl 12) lor opfunct12 in
  (high,low)

(* Encode the I-type *)
let encI rd rs1 imm12 opfunct10 =
  let high = (rd lsl 11) lor (rs1 lsl 6) lor (imm12 lsr 6) in
  let low = ((imm12 land 0b111111) lsl 10) lor opfunct10 in
  (high,low)

(* Encode the B-type *)
let encB rs1 rs2 imm12 opfunct10 =
  let high = ((imm12 lsr 7) lsl 11) lor (rs1 lsl 6) lor (rs2 lsl 1) lor ((imm12 lsr 6) land 1) in
  let low = ((imm12 land 0b111111) lsl 10) lor opfunct10 in
  (high,low)

(* Encode the L-type *)
let encL rd imm20 op7 =
  let high = (rd lsl 11) lor (imm20 lsr 9) in
  let low = ((imm20 land 0b111111111) lsl 7) lor op7 in
  (high,low)

(* Encode the J-type *)
let encJ offset25 op7 =
  let high = offset25 lsr 9 in
  let low = ((offset25 land 0b111111111) lsl 7) lor op7 in
  (high,low)

let encUncondJmp op = match op with
  | OpJ -> 0b1100111 | OpJAL -> 0b1101111

let encCondJmp op = match op with
  | OpBEQ -> 0b0001100011 | OpBNE  -> 0b0011100011 | OpBLT  -> 0b1001100011 
  | OpBGE -> 0b1011100011 | OpBLTU -> 0b1101100011 | OpBGEU -> 0b1111100011
  
let encIndJmp op = match op with
  | OpJALR_C -> 0b0001101011 | OpJALR_R -> 0b0011101011 
  | OpJALR_J -> 0b0101101011 | OpRDNPC  -> 0b1001101011

let encLoad op = match op with
  | OpLB  -> 0b0000000011 | OpLH  -> 0b0010000011 | OpLW  -> 0b0100000011  
  | OpLD  -> 0b0110000011 | OpLBU -> 0b1000000011 | OpLHU -> 0b1010000011  
  | OpLWU -> 0b1100000011

let encStore op = match op with
  | OpSB -> 0b0000100011 | OpSH -> 0b0010100011 | OpSW -> 0b0100100011 
  | OpSD -> 0b0110100011 

let encAtomic op = match op with
  | OpAMOADD_W  -> 0b00000000100101011 | OpAMOSWAP_W -> 0b00000010100101011 
  | OpAMOAND_W  -> 0b00000100100101011 | OpAMOOR_W   -> 0b00000110100101011 
  | OpAMOMIN_W  -> 0b00001000100101011 | OpAMOMAX_W  -> 0b00001010100101011
  | OpAMOMINU_W -> 0b00001100100101011 | OpAMOMAXU_W -> 0b00001110100101011
  | OpAMOADD_D  -> 0b00000000110101011 | OpAMOSWAP_D -> 0b00000010110101011
  | OpAMOAND_D  -> 0b00000100110101011 | OpAMOOR_D   -> 0b00000110110101011 
  | OpAMOMIN_D  -> 0b00001000110101011 | OpAMOMAX_D  -> 0b00001010110101011
  | OpAMOMINU_D -> 0b00001100110101011 | OpAMOMAXU_D -> 0b00001110110101011

let encCompImm op = match op with
  | OpADDI  -> 0b0000010011 | OpSLLI  -> 0b0010010011 | OpSLTI  -> 0b0100010011  
  | OpSLTIU -> 0b0110010011 | OpXORI  -> 0b1000010011 | OpSRLI  -> 0b1010010011 
  | OpSRAI  -> 0b1010010011 | OpORI   -> 0b1100010011 | OpANDI  -> 0b1110010011 
  | OpLUI   -> 0b0110111    | OpADDIW -> 0b0000011011 | OpSLLIW -> 0b0010011011
  | OpSRLIW -> 0b1010011011 | OpSRAIW -> 0b1010011011

let encCompReg op = match op with
  | OpADD    -> 0b00000000000110011 | OpSUB   -> 0b10000000000110011   
  | OpSLL    -> 0b00000000010110011 | OpSLT   -> 0b00000000100110011   
  | OpSLTU   -> 0b00000000110110011 | OpXOR   -> 0b00000001000110011  
  | OpSRL    -> 0b00000001010110011 | OpSRA   -> 0b10000001010110011   
  | OpOR     -> 0b00000001100110011 | OpAND   -> 0b00000001110110011 
  | OpMUL    -> 0b00000010000110011 | OpMULH  -> 0b00000010010110011 
  | OpMULHSU -> 0b00000010100110011 | OpMULHU -> 0b00000010110110011
  | OpDIV    -> 0b00000011000110011 | OpDIVU  -> 0b00000011010110011
  | OpREM    -> 0b00000011100110011 | OpREMU  -> 0b00000011110110011 
  | OpADDW   -> 0b00000000000111011 | OpSUBW  -> 0b10000000000111011
  | OpSLLW   -> 0b00000000010111011 | OpSRLW  -> 0b00000001010111011
  | OpSRAW   -> 0b10000001010111011 | OpMULW  -> 0b00000010000111011
  | OpDIVW   -> 0b00000011000111011 | OpDIVUW -> 0b00000011010111011
  | OpREMW   -> 0b00000011100111011 | OpREMUW -> 0b00000011110111011

let encMiscMem op = match op with
  | OpFENCE_I -> 0b0010101111  | OpFENCE -> 0b0100101111  

let encSys op = match op with
  | OpSYSCALL   -> 0b00000000001110111 | OpBREAK  -> 0b00000000011110111    
  | OpRDCYCLE   -> 0b00000001001110111 | OpRDTIME -> 0b00000011001110111
  | OpRDINSTRET -> 0b00000101001110111


(* Encodes one 32 bit instructions. Returns a tuple with two parcels. *)
let encode_32inst inst =
  match inst with 
  (* Unconditional Jump *)
  | MIUncondJmp(fi,op,imm25) -> encJ imm25 (encUncondJmp op)
  (* Conditional Jump *)
  | MICondJmp(fi,op,rs1,rs2,imm12) -> encB rs1 rs2 imm12 (encCondJmp op)
  (* Indirect Jump *)
  | MIIndJmp(fi,op,rd,rs1,imm12) -> encI rd rs1 imm12 (encIndJmp op)
  (* Load Memory *)
  | MILoad(fi,op,rd,rs1,imm12) -> encI rd rs1 imm12 (encLoad op) 
  (* Store Memory *)
  | MIStore(fi,op,rs1,rs2,imm12) -> encB rs1 rs2 imm12 (encStore op)
  (* Atomic Memory *)
  | MIAtomic(fi,op,rd,rs1,rs2) -> encR rd rs1 rs2 (encAtomic op)
  (* Integer Register-Immediate Computation *)
  | MICompImm(fi,op,rd,rs1,immv) -> 
     if op = OpLUI then encL rd immv (encCompImm op) else 
     let imm = immv lor (match op with OpSRAI | OpSRAIW -> 0b1000000 | _ -> 0) in
     encI rd rs1 imm (encCompImm op)
  (* Integer Register-Register Computation *)
  | MICompReg(fi,op,rd,rs1,rs2) -> encR rd rs1 rs2 (encCompReg op)
  (* Misc memory instructions *)
  | MIMiscMem(fi,op,rd,rs1,imm12) -> encI rd rs1 imm12 (encMiscMem op)
  (* System instructions *)
  | MISys(fi,op,rd) -> encR rd 0 0 (encSys op)


(* Encode a 32 bit instruction to a string at a specific index. *)
let encode_to_str bige inst s i = 
  let (h,l) = encode_32inst inst in
  let (ah,al) = if bige then (0,1) else (1,0) in 
  s.[i+ah] <- (char_of_int (l lsr 8));
  s.[i+al] <- (char_of_int (l land 0xff));
  s.[i+ah+2] <- (char_of_int (h lsr 8));
  s.[i+al+2] <- (char_of_int (h land 0xff))
  



(**************** Exported functions *******************************)


let decode bige data pos = 
  let parcel high low =
    let h = int_of_char high in
    let l = int_of_char low in
     if bige then (h lsl 8) lor l else  (l lsl 8) lor h in
  let size = String.length data in
  if pos+2 > size then raise Decode_error else
  let p1 = parcel data.[pos] data.[pos+1] in
  if (p1 land 0b11) <> 0b11 then raise Unsupported_encoding else
  if (p1 land 0b11111) = 0b11111 then raise Unsupported_encoding else
  if pos+4 > size then raise Decode_error else
  let p2 = parcel data.[pos+2] data.[pos+3] in
  (decode_32inst p2 p1, pos+4) 


let decode_interval bige data pos len = 
  let rec loop p len acc = 
    if len > 0 then 
      let (inst,p2) = decode bige data p in
      loop p2 (len - (p2-p)) (inst::acc)
    else acc
  in
  List.rev (loop pos len []) 

let decode_all bige data = 
  decode_interval bige data 0 (String.length data) 


let encode bige inst = 
  let s = String.create(4) in
  encode_to_str bige inst s 0;
  s
  

let encode_all bige instlst = 
  let s = String.create((List.length instlst)*4) in
  List.iteri (fun k inst -> encode_to_str bige inst s (k*4)) instlst;
  s

  

