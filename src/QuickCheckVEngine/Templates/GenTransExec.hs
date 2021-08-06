--
-- SPDX-License-Identifier: BSD-2-Clause
--
-- Copyright (c) 2019-2020 Peter Rugg
-- Copyright (c) 2019, 2020 Alexandre Joannou
-- Copyright (c) 2021 Jonathan Woodruff
-- Copyright (c) 2021 Franz Fuchs
-- All rights reserved.
--
-- This software was developed by SRI International and the University of
-- Cambridge Computer Laboratory (Department of Computer Science and
-- Technology) under DARPA contract HR0011-18-C-0016 ("ECATS"), as part of the
-- DARPA SSITH research programme.
--
-- Redistribution and use in source and binary forms, with or without
-- modification, are permitted provided that the following conditions
-- are met:
-- 1. Redistributions of source code must retain the above copyright
--    notice, this list of conditions and the following disclaimer.
-- 2. Redistributions in binary form must reproduce the above copyright
--    notice, this list of conditions and the following disclaimer in the
--    documentation and/or other materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
-- ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
-- IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
-- FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
-- DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
-- OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
-- HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
-- LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
-- OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
-- SUCH DAMAGE.
--

module QuickCheckVEngine.Templates.GenTransExec (
  gen_data_scc_verify
, gen_sbc_cond_1_verify
, gen_inst_scc_verify
, gen_sbc_jumps_verify
, gen_sbc_exceptions_verify
, gen_stc_verify
) where

import InstrCodec
import Test.QuickCheck
import RISCV.RV32_I
import RISCV.RV64_I
import RISCV.RV32_Xcheri
import RISCV.RV32_Zicsr
import RISCV.RV32_F
import RISCV.RV32_D
import QuickCheckVEngine.Template
import QuickCheckVEngine.Templates.GenMemory
import QuickCheckVEngine.Templates.Utils
import QuickCheckVEngine.RVFI_DII.RVFI
import QuickCheckVEngine.Templates.GenMemory
import Data.Bits

genDataSCCTorture :: Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Template
genDataSCCTorture capReg tmpReg bitsReg sldReg nopermReg authReg = Random $ do
  srcAddr  <- src
  srcData  <- src
  dest     <- dest
  imm      <- bits 12
  longImm  <- bits 20
  fenceOp1 <- bits 3
  fenceOp2 <- bits 3
  size     <- getSize
  csrAddr  <- frequency [ (1, return 0xbc0), (1, return 0x342), (1, bits 12) ]
  src1     <- frequency [ (1, return capReg), (1, return tmpReg), (1, return bitsReg), (1, return sldReg) ]
  src2     <- frequency [ (1, return capReg), (1, return tmpReg), (1, return bitsReg), (1, return sldReg) ]
  let rv32_xcheri_misc_alt = filter (/= (cspecialrw tmpReg csrAddr src1)) (rv32_xcheri_misc src1 src2 csrAddr imm tmpReg)
  return $  (Distribution [ (1, uniformTemplate $ rv32_xcheri_arithmetic src1 src2 imm tmpReg)
                          , (1, uniformTemplate $ rv32_xcheri_misc_alt)
                          , (1, Single $ cinvoke src2 src1)
                          , (1, Single $ cload tmpReg tmpReg 0x08)
                          ])

genInstSCCTorture :: Template
genInstSCCTorture = Random $ do
  let src1 = 20
  let src2 = 21
  let tmpReg = 22
  let tmpReg2 = 23
  let capReg2 = 24
  let imm = 0x40
  let zeroReg = 0
  let capReg = 11
  return $ Sequence [ ( Single $ cjalr zeroReg capReg)
                    , ( Single $ auipc capReg2 0x0)
                    , ( Single $ cload tmpReg2 capReg2 0xb)
                    ]


genSBC_Cond_1_Torture :: Template
genSBC_Cond_1_Torture = Random $ do
  imm_rand      <- bits 12
  longImm_rand  <- bits 20
  fenceOp1      <- bits 3
  fenceOp2      <- bits 3
  srcData       <- src
  let zeroReg = 0
  let addrReg = 5
  let tmpReg = 10
  let src1 = 12
  let src2 = 13
  let captmpReg = 14
  let capsrc1 = 15
  let capsrc2 = 16
  let dest = 17
  -- immediate has to be divisible by 8
  let imm = (imm_rand `shiftR` 0x3) `shiftL` 0x3
  -- long immediate has to be divisible by 4
  let longImm = (longImm_rand `shiftR` 0x2) `shiftL` 0x2
  return $ (Distribution  [ (1, uniformTemplate $ rv64_i_arith src1 src2 imm tmpReg)
                          , (1, uniformTemplate $ rv32_i_arith src1 src2 imm longImm tmpReg)
                          , (1, uniformTemplate $ rv64_i_mem addrReg srcData dest imm)
                          , (1, uniformTemplate $ rv32_i_mem addrReg srcData dest imm fenceOp1 fenceOp2)
                          , (1, Single $ jal zeroReg longImm)
                          , (1, uniformTemplate $ rv32_xcheri_mem capsrc1 capsrc2 imm 0xb tmpReg)
                          ])

genSBC_Jumps_Torture :: Template
genSBC_Jumps_Torture = Random $ do
  imm_branches <- bits 7
  longImm_jumps <- bits 8
  imm <- bits 12
  longImm <- bits 20
  imm_jumps <- bits 7
  -- sbcRegs can return on of the following: 22,23,24,25,26,27,28,29
  src1 <- sbcRegs
  src2 <- sbcRegs
  dest <- sbcRegs
  let zeroReg = 0
  let retReg = 1
  dest_jumps <- frequency [ (1, return zeroReg), (1, return retReg) ]
  let regJump = 10
  return $ (Distribution  [ (1, uniformTemplate $ rv64_i_arith src1 src2 dest imm)
                          , (1, uniformTemplate $ rv32_i_arith src1 src2 dest imm longImm)
                          , (1, uniformTemplate $ rv32_i_ctrl_jumps regJump dest_jumps imm_jumps longImm_jumps)
                          , (1, uniformTemplate $ rv32_i_ctrl_branches src1 src2 imm_branches)
                          ])

genSBC_Excps_Torture :: Integer -> Template
genSBC_Excps_Torture tmpReg = Random $ do
  imm <- bits 12
  longImm <- bits 20
  src1 <- sbcRegs
  src2 <- sbcRegs
  src3 <- sbcRegs
  dest <- sbcRegs
  let rm = 0x7 -- dynamic rounding mode
  let fenceOp1 = 17
  let fenceOp2 = 18
  return $ (Distribution  [ (1, uniformTemplate $ rv64_i_arith src1 src2 dest imm)
                          , (1, uniformTemplate $ rv32_i_arith src1 src2 dest imm longImm)
                          , (1, uniformTemplate $ rv64_i_mem src1 src2 dest imm)
                          , (1, uniformTemplate $ rv32_i_mem src1 src2 dest imm fenceOp1 fenceOp2)
                          , (1, uniformTemplate $ rv32_i_exc)
                          , (1, uniformTemplate $ rv32_xcheri_mem src1 src2 imm 0xb tmpReg)
                          , (1, uniformTemplate $ rv32_xcheri_arithmetic src1 src2 imm dest)
                          , (1, uniformTemplate $ rv32_xcheri_inspection src1 dest)
                          , (1, uniformTemplate $ rv32_f_macc src1 src2 src3 dest rm)
                          , (1, uniformTemplate $ rv32_f_arith src1 src2 dest rm)
                          ])


genSTCTorture :: Template
genSTCTorture = Random $ do
  imm_bits <- bits 10
  longImm <- bits 20
  src1 <- choose(16,18)
  src2 <- sbcRegs
  dest <- sbcRegs
  let fenceOp1 = 19
  let fenceOp2 = 20
  let sstatus = 0x100
  let imm = (imm_bits `shiftR` 3) `shiftL` 3
  let access_inst = (Distribution  [ --(1, uniformTemplate $ rv64_i_arith src1 src2 dest imm)
                                   --, (1, uniformTemplate $ rv32_i_arith src1 src2 dest imm longImm)
                                       (1, uniformTemplate $ rv64_i_mem src1 src2 dest imm)
                                   --, (1, uniformTemplate $ rv32_i_mem src1 src2 dest imm fenceOp1 fenceOp2)
                                   ])
  return $ Sequence [ access_inst
                    , Single $ csrrs src2 sstatus 0
                    , Single $ sret
                    ]

prepareSBCExcpsGen :: Template
prepareSBCExcpsGen = Random $ do
  let fcsr = 0x003
  let mstatus = 0x300
  let a0 = 10
  return $ instSeq [ (lui a0 2)
                   , (csrrs 0 mstatus a0)
                   , (addi a0 0 192)
                   , (csrrs 0 fcsr a0)
                   ]


setUpPageTable :: Template
setUpPageTable = Random $ do
  let a0 = 10
  let t0 = 6
  return $ Sequence [ NoShrink( li64 a0 0x80002000)
                    , NoShrink( li64 t0 0x20000c01)
                    , NoShrink(Single $ sd a0 t0 0)
                    , NoShrink( li64 t0 0x20000801)
                    , NoShrink(Single $ sd a0 t0 16)
                    , NoShrink( li64 a0 0x80003000)
                    , NoShrink( li64 t0 0x2000004b)
                    , NoShrink(Single $ sd a0 t0 0)
                    , NoShrink( li64 t0 0x20000447)
                    , NoShrink(Single $ sd a0 t0 8)
                    , NoShrink( li64 t0 0x2000105b)
                    , NoShrink(Single $ sd a0 t0 32)
                    , NoShrink( li64 t0 0x20001457)
                    , NoShrink(Single $ sd a0 t0 40)
                    ]

prepareSTCGen :: Template
prepareSTCGen = Random $ do
  let s0 = 8
  let s1 = 9
  let s2 = 18
  let counterReg = 30
  let hpmCntIdx = 3
  let evt = 0x31
  let mstatus = 0x300
  let sstatus = 0x100
  let mepc = 0x341
  let sepc = 0x141
  let satp = 0x180
  let medeleg = 0x302
  let sedeleg = 0x102
  let stval = 0x143
  return $ instSeq [ (lui s1 0x100)
                   , (csrrc 0 mstatus s1)
                   , (lui s1 0x1)
                   , (csrrc 0 mstatus s1)
                   , (lui s1 0x1)
                   , (addi s1 s1 0x800)
                   , (csrrs 0 mstatus s1)
                   , (auipc s2 0)
                   , (addi s2 s2 16)
                   , (csrrw 0 mepc s2)
                   , (lui s2 0xa)
                   , (csrrw 0 medeleg s2)
                   --, (csrrw 0 sedeleg s2)
                   ]
                   <>
                     (setUpPageTable)
                   <>
                     (setupHPMEventSel counterReg hpmCntIdx evt)
                   <>
                     (enableHPMCounterM counterReg hpmCntIdx)
                   <>
           instSeq [ (mret)
                   , (lui s0 0xfffe0)
                   , (addi s0 s0 1)
                   , (slli s0 s0 0x1b)
                   , (addi s0 s0 1)
                   , (slli s0 s0 0x13)
                   , (addi s0 s0 2)
                   , (csrrw 0 satp s0)
                   , (addi s1 s1 256)
                   , (csrrc 0 sstatus s1)
                   , (lui s2 2)
                   --, (csrrw 0 sedeleg s2)
                   ]
                   <>
                     (enableHPMCounterS counterReg hpmCntIdx)
                   <>
                     (li64 s2 0x80004000)
                   <>
            instSeq[ (csrrw 0 sepc s2)
                   , (csrrw 0 stval s2)
                   , (sret)
                   ]

gen_data_scc_verify = Random $ do
  let capReg = 1
  let tmpReg0 = 30
  let tmpReg1 = 31
  let bitsReg = 3
  let sldReg = 4
  let nopermReg = 5
  let authReg = 6
  let hpmEventIdx_dcache_miss = 0x31
  let hpmCntIdx = 3
  size <- getSize
  return $ Sequence [ NoShrink (makeCap capReg  authReg tmpReg1 0x80010000     8 0)
                    , NoShrink (makeCap bitsReg authReg tmpReg1 0x80014000 0x100 0)
                    , NoShrink (Single $ csealentry sldReg bitsReg)
                    , NoShrink (Single $ candperm nopermReg bitsReg 0)
                    , NoShrink (Single $ ccleartag bitsReg bitsReg)
                    , NoShrink (Single $ lw tmpReg1 capReg 0)
                    , surroundWithHPMAccess_core False hpmEventIdx_dcache_miss (replicateTemplate (size - 100) (genDataSCCTorture capReg tmpReg1 bitsReg sldReg nopermReg authReg)) tmpReg0 hpmCntIdx Nothing
                    , NoShrink (SingleAssert (addi tmpReg0 tmpReg0 0) 0)
                    ]



genJump :: Integer -> Integer -> Integer -> Integer -> Integer -> Integer -> Template
genJump memReg reg0 reg1 reg2 imm offset = Random $ do
  let czero = 0
  let ra = 1
  return $ instSeq [ --(cload reg0 memReg 0x1f)
                     (cjalr ra reg1)
                   , (cjalr czero ra)
                   ]

genInstSCC :: Integer -> Integer -> Integer -> Integer -> Template
genInstSCC memReg reg0 reg1 reg2 = Random $ do
  let czero = 0
  --return $ instSeq [ (cjalr czero reg0)
  --                 , (auipc reg2 0)
  --                 , (cload reg1 reg2 0x8)
  --                 ]
  --reg0 <- sbcRegs
  --let reg1 = reg0 + 1
  --let reg2 = reg0 - 1
  return $ (Distribution [ (1, Single $ (cjalr czero reg0))
                         , (2, Single $ (add 29 29 29))
                         , (1, Single $ (cload reg1 reg2 0x8))
                         , (1, Single $ (auipc reg2 0))
                         ])

-- | Verify instruction Speculative Capability Constraint (SCC)
gen_inst_scc_verify = Random $ do
  let hpmEventIdx_dcache_miss = 0x31
  let hpmCntIdx_dcache_miss = 3
  let rand = 7
  let zeroReg = 0
  let jumpReg = 10
  let dataReg = 11
  let tmpReg = 12
  let counterReg = 13
  let authReg = 14
  let startReg = 15
  let pccReg = 16
  let loadReg = 17
  let authReg2 = 18
  let memReg = 19
  let memReg2 = 20
  let memReg3 = 21
  let reg0 = 23
  let reg1 = 24
  let reg2 = 25
  let mtcc = 28
  let startSeq = Sequence [NoShrink (Single $ cjalr zeroReg startReg)]
  let trainSeq = replicateTemplate (18) (genJump memReg tmpReg pccReg loadReg 0x20 0x0)
  let leakSeq = replicateTemplate (1) (genJump memReg2 tmpReg pccReg loadReg 0x20 0x100)
  let tortSeq = startSeq <> leakSeq
  return $ Sequence [ NoShrink (switchEncodingMode)
                    , NoShrink (Single $ cspecialrw authReg2 0 0) -- read PCC
                    , NoShrink (makeCap_core jumpReg authReg2 tmpReg 0x80001000)
                    , NoShrink (makeCap_core pccReg authReg2 tmpReg 0x80002000)
                    , NoShrink (makeCap_core memReg authReg2 tmpReg 0x80007000)
                    , NoShrink (makeCap_core memReg2 authReg2 tmpReg 0x80007100)
                    --, NoShrink (makeCap_core memReg3 authReg2 tmpReg 0x80008100)
                    , NoShrink (Single $ cmove startReg jumpReg)
                    , NoShrink (Single $ cstore jumpReg memReg 0x0c)
                    , NoShrink (Single $ cincoffsetimmediate tmpReg jumpReg 0x100)
                    , NoShrink (Single $ ccleartag tmpReg tmpReg)
                    , NoShrink (Single $ cstore tmpReg memReg2 0x0c)
                    , NoShrink (Single $ cload tmpReg memReg2 0x1f)
                    --, NoShrink (Single $ cload tmpReg memReg3 0x8)
                    , startSeq
                    , NoShrink (trainSeq)
                    --, NoShrink (Single $ csetboundsimmediate startReg startReg 0x8)
                    --, NoShrink (Single $ lw loadReg startReg 0)
                    --, NoShrink (Single $ lw loadReg pccReg 0)
                    , NoShrink (Single $ cload tmpReg jumpReg 0x8)
                    , NoShrink (Single $ cincoffsetimmediate tmpReg jumpReg 0x40)
                    , NoShrink (Single $ cload tmpReg tmpReg 0x8)
                    , NoShrink (Single $ cincoffsetimmediate tmpReg jumpReg 0x80)
                    , NoShrink (Single $ cload tmpReg tmpReg 0x8)
                    , NoShrink (Single $ cincoffsetimmediate tmpReg jumpReg 0xc0)
                    , NoShrink (Single $ cload tmpReg tmpReg 0x8)
                    , NoShrink (Single $ cincoffsetimmediate tmpReg jumpReg 0x100)
                    , NoShrink (Single $ cload tmpReg tmpReg 0x8)
                    , NoShrink (Single $ add pccReg zeroReg zeroReg)
                    , NoShrink (Single $ cmove jumpReg startReg)
                    -- zero out all sbcRegs
                    , NoShrink (Single $ cmove 22 zeroReg)
                    , NoShrink (Single $ cmove 23 zeroReg)
                    , NoShrink (Single $ cmove 24 zeroReg)
                    , NoShrink (Single $ cmove 25 zeroReg)
                    , NoShrink (Single $ cmove 26 zeroReg)
                    , NoShrink (Single $ cmove 27 zeroReg)
                    , NoShrink (Single $ cmove 28 zeroReg)
                    , NoShrink (Single $ cmove 29 zeroReg)
                    , NoShrink (Single $ csetboundsimmediate jumpReg jumpReg 256)
                    , NoShrink (Single $ csetboundsimmediate tmpReg startReg 256)
                    , NoShrink (Single $ cspecialrw 0 mtcc jumpReg)
                    , startSeq
                    , NoShrink (Single $ fence 3 3) -- fence rw, rw
                    , surroundWithHPMAccess_core False hpmEventIdx_dcache_miss (replicateTemplate (64)(genInstSCC memReg2 reg0 reg1 reg2)) counterReg hpmCntIdx_dcache_miss Nothing
                    , NoShrink (SingleAssert (addi counterReg counterReg 0) 0)
                    ]


-- | Verify condition 1 of Speculative Branching Constraint (SBC)
gen_sbc_cond_1_verify = Random $ do
  let tmpReg1 = 1
  let tmpReg2 = 2
  let tmpReg3 = 3
  let tmpReg4 = 4
  let addrReg = 5
  let capReg = 15
  let authReg = 16
  let tmpReg5 = 17
  let addrVal = 0x80001000
  let hpmEventIdx_renamed_insts = 0x70
  let hpmCntIdx_renamed_insts = 3
  let hpmEventIdx_traps = 0x2
  let hpmCntIdx_traps = 4
  size <- getSize
  let inner_hpm_access = surroundWithHPMAccess_core False hpmEventIdx_renamed_insts (replicateTemplate (size - 100) ( (genSBC_Cond_1_Torture))) tmpReg1 hpmCntIdx_renamed_insts (Just (tmpReg2, tmpReg3))
  let outer_hpm_access = surroundWithHPMAccess_core False hpmEventIdx_traps inner_hpm_access tmpReg4 hpmCntIdx_traps Nothing
  return $ Sequence [ NoShrink ( (li64 addrReg addrVal))
                    , NoShrink ( (makeCap capReg authReg tmpReg5 addrVal 0x10000 0))
                    , outer_hpm_access
                    , NoShrink (Single $ sub tmpReg3 tmpReg3 tmpReg2)
                    , NoShrink (Single $ sub tmpReg1 tmpReg1 tmpReg3)
                    , NoShrink (SingleAssert (sub tmpReg1 tmpReg1 tmpReg4) 2)
                    ]

-- | Verify the jumping conditions of Speculative Branching Constraint (SBC)
gen_sbc_jumps_verify = Random $ do
  let zeroReg = 0
  let tmpReg = 21
  let regJump = 10
  let addrVal = 0x80001000
  let hpmCntIdx_wild_jumps = 3
  let hpmEventIdx_wild_jumps = 0x71
  size <- getSize
  return $ Sequence [ NoShrink ((li64 regJump addrVal))
                    , surroundWithHPMAccess_core False hpmEventIdx_wild_jumps (replicateTemplate (size - 100) (genSBC_Jumps_Torture)) tmpReg hpmCntIdx_wild_jumps Nothing
                    , NoShrink(SingleAssert (add tmpReg tmpReg zeroReg) 0)
                    ]

-- | Verify the exception conditions of Speculative Branching Constraint (SBC)
gen_sbc_exceptions_verify = Random $ do
  let zeroReg = 0
  let capReg = 12
  let authReg = 13
  let excReg = 14
  let tmpReg = 11
  let counterReg = 31
  let addr = 0x80002000
  let hpmCntIdx_wild_excps = 3
  let hpmEventIdx_wild_excps = 0x72
  size <- getSize
  return $ Sequence [ NoShrink (prepareSBCExcpsGen)
                    , NoShrink ((makeCap capReg authReg tmpReg addr 0x100 0))
                    , NoShrink ((makeCap_core excReg authReg tmpReg 0x80000000))
                    , NoShrink (Single $ cspecialrw 0 28 excReg)
                    , surroundWithHPMAccess_core False hpmEventIdx_wild_excps (replicateTemplate (size - 100) (genSBC_Excps_Torture tmpReg)) counterReg hpmCntIdx_wild_excps Nothing
                    , NoShrink(SingleAssert (add counterReg counterReg zeroReg) 0)
                    ]

-- | Verify Speculative Translation Constraint (STC)
gen_stc_verify = Random $ do
  let lxReg = 1
  let addrReg = 2
  let tmpReg = 31
  let counterReg = 30
  let addrReg1 = 16
  let addrReg2 = 17
  let addrReg3 = 18
  let hpmCntIdx_dcache_miss = 3
  let hpmEventIdx_dcache_miss = 0x31
  let uepc = 0x041
  size <- getSize
  return $ Sequence [ NoShrink(prepareSTCGen)
                    , NoShrink(Single $ sfence 0 0)
                    , NoShrink(li64 addrReg1 0x80001800)
                    , NoShrink(li64 addrReg2 0x80012000)
                    , NoShrink(li64 addrReg3 0x80008000)
                    , NoShrink(Single $ csrrs tmpReg 0xc03 0)
                    , (replicateTemplate (20) (genSTCTorture))
                    , NoShrink(Single $ csrrs counterReg 0xc03 0)
                    , NoShrink(SingleAssert (sub counterReg counterReg tmpReg) 0)
                    ]
