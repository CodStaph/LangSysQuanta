import LSys.EffHPath
import LSys.EvalConf
import LSys.EnvExt
import LSys.LamEff
import LSys.LamStep
import LSys.EffHCounterexample
import LSys.EvalEff
import LSys.EffHMeasure
import LSys.EffHC
import LSys.WTyH
import LSys.WTyHCtx
import LSys.WTyHStar
import LSys.WTKH
import LSys.WTKHPreservation
import LSys.EffHCK
import LSys.WTKHEnv
import LSys.FreeVars
import LSys.EffHCEnv
import LSys.CoherentH
import LSys.StepBridge
import LSys.LetHandle
import LSys.PlaceWF
import LSys.StepEval
import LSys.PreservationCounterexample
import LSys.WTPlugCounterexample
import LSys.WTPreservation
import LSys.T4aSafe
import LSys.T4a

#print axioms LSys.step_decreases
#print axioms LSys.stepStar_decreases
#print axioms LSys.l_consume
#print axioms LSys.l_holder
#print axioms LSys.adequacy_freeze
#print axioms LSys.progress_any
#print axioms LSys.progress
#print axioms LSys.l_no_stuck_wt
#print axioms LSys.terminates
#print axioms LSys.t4a
#print axioms LSys.wf_preserved_core
#print axioms LSys.t1_no_dangling
#print axioms LSys.t3_recover_unique
#print axioms LSys.wfe_letVar
#print axioms LSys.wfe_moveVar
#print axioms LSys.wfe_borrowVar
#print axioms LSys.consumeD_exact
#print axioms LSys.recoverD_clears
#print axioms LSys.consumeU_exact
#print axioms LSys.unified_safe
#print axioms LSys.progressP
#print axioms LSys.prefix_trans
#print axioms LSys.t4a_safe
#print axioms LSys.t4a_safeP
#print axioms LSys.runtime_safe
#print axioms LSys.recover_safe
#print axioms LSys.wfu_letVar
#print axioms LSys.wfu_moveVar
#print axioms LSys.wfu_borrowVar
#print axioms LSys.consumeU_wfu
#print axioms LSys.t1_wfu_no_dangling
#print axioms LSys.t1_wfu_env_no_dangling
#print axioms LSys.t3_consumeU_consumes
#print axioms LSys.stepPStar_decreases
#print axioms LSys.terminatesP
#print axioms LSys.t4a_safeP_wt
#print axioms LSys.f0_event_not_outside
#print axioms LSys.wt_of_plug
#print axioms LSys.wt_plug_of
#print axioms LSys.wt_preserved_step
#print axioms LSys.wtPreserved
#print axioms LSys.terminatesP_uncond
#print axioms LSys.t4a_safeP_final
#print axioms LSys.not_preservation_current
#print axioms LSys.not_wt_plug_eff
#print axioms LSys.Effect.regionSafe_val
#print axioms LSys.Effect.regionSafe_freeze
#print axioms LSys.Effect.regionSafe_seq
#print axioms LSys.not_regionSafe_eff_step
#print axioms LSys.Effect.eff_plug_decomp
#print axioms LSys.Effect.eff_plug_compose
#print axioms LSys.Effect.regionSafe_to_ctxSafe
#print axioms LSys.StepEval.toStep
#print axioms LSys.stepEval_decreases
#print axioms LSys.Effect.effStepEval_eff_compose
#print axioms LSys.Effect.effStepCtx_decomp
#print axioms LSys.Effect.effPost_congr
#print axioms LSys.Effect.regionSafe_ctx_hole
#print axioms LSys.Effect.regionSafe_step
#print axioms LSys.effH_plug_decomp
#print axioms LSys.StepEvalC.toStep
#print axioms LSys.stepEvalC_decreases
#print axioms LSys.effH_var_inv
#print axioms LSys.setHolders_ne
#print axioms LSys.not_effHStepEvalC_eff_compose
#print axioms LSys.StepEvalC.toEffStepEvalC
#print axioms LSys.effStepEvalC_eff_compose
#print axioms LSys.regionSafe_stepC
#print axioms LSys.EffHStepEvalC.toStepEvalC
#print axioms LSys.EffHStepEvalC.step_decreases_or
#print axioms LSys.holdersOfV_toVal
#print axioms LSys.effHStepEvalC_effHC_compose
#print axioms LSys.EffHStepEvalC.env_heap
#print axioms LSys.regionSafeHC_step
#print axioms LSys.EffHC.env_heap_congr
#print axioms LSys.WTyH.toEffHC
#print axioms LSys.WTyH.preserved
#print axioms LSys.WTyH.env_heap_congr
#print axioms LSys.WTyH.plug_preserved
#print axioms LSys.WTyH.preserved_star
#print axioms LSys.EffStepStar.trans
#print axioms LSys.WTyH.plug_star_preserved
#print axioms LSys.WTKH.letE_inv
#print axioms LSys.WTKH.letV_inv
#print axioms LSys.WTKH.letE_ctx
#print axioms LSys.WTKH.borrow_inv
#print axioms LSys.RedexK.toEffHStepEvalCK
#print axioms LSys.WTKH.preserved_redex
#print axioms LSys.WTKH.preserved
#print axioms LSys.WTKH.env_heap_trans
#print axioms LSys.EnvExtends.setEnv
#print axioms LSys.EnvExtends.setEnv_self
#print axioms LSys.EffHStepEvalCK.env_ext
#print axioms LSys.WTKH.env_ext
#print axioms LSys.WTKH.vars_bound
#print axioms LSys.EffHC.env_agree
#print axioms LSys.RegionSafeHC.env_agree
#print axioms LSys.RegionSafeHC.env_ext
#print axioms LSys.noEscape_of_lamSub
#print axioms LSys.LamSub.trans
#print axioms LSys.lamSub_consumeResult
#print axioms LSys.LamEff.coarsen
#print axioms LSys.EffHStepEvalCK.gamma_same
#print axioms LSys.LamEff.gamma_eq
#print axioms LSys.LamEff.mono
#print axioms LSys.LamEff.step_compose
#print axioms LSys.regionSafeLam_step
#print axioms LSys.StepPMH.wt
#print axioms LSys.StepPMH.wt_ctx
#print axioms LSys.StepPMH.wt_ctx_star
#print axioms LSys.StepPMH.ofStepRefl
#print axioms LSys.StepPMH.borrowEnter
#print axioms LSys.StepPMH.borrowExit
#print axioms LSys.StepPMH.varV
#print axioms LSys.StepPMHStar.toEffStepStar
#print axioms LSys.WTyH.preserved_stepPMH_star
#print axioms LSys.StepPMHStar.wt_ctx
#print axioms LSys.StepPMH.preservation
#print axioms LSys.StepPMHStar.preservation
#print axioms LSys.StepPMHStar.preservation_ctx
#print axioms LSys.StepPMH.moveV
#print axioms LSys.StepPMH.readV
#print axioms LSys.StepPMH.abortBorrow
#print axioms LSys.MatchV.rstep
#print axioms LSys.varPlace_inj
#print axioms LSys.heapPlace_ne_varPlace
#print axioms LSys.MatchUS.letVarWithHolders
#print axioms LSys.WFLam.addBorrow
#print axioms LSys.WFHolds.clearPlace
#print axioms LSys.WFHolds.setHolders
#print axioms LSys.WFHolds.removeOcc
#print axioms LSys.WFHolds.consumeResult
#print axioms LSys.WFLam.consumeResult
#print axioms LSys.MatchU.borrowPush
#print axioms LSys.MatchU.borrowPop
#print axioms LSys.MatchU.toMatchUS
#print axioms LSys.MatchUS.letVar
#print axioms LSys.MatchUS.borrowPush
#print axioms LSys.StepPMH.letV
#print axioms LSys.StepPMH.redex
#print axioms LSys.StepPMH.op
#print axioms LSys.StepPMH.write
#print axioms LSys.StepPMH.freeze
#print axioms LSys.StepPMH.recover
#print axioms LSys.StepPMH.alloc
#print axioms LSys.StepPMH.drop
#print axioms LSys.StepPMH.derefV
#print axioms LSys.EffHC.plug_step_compose
#print axioms LSys.RegionSafeHC.plug_preserved
#print axioms LSys.RegionSafeHC.env_heap_congr
#print axioms LSys.MatchV.letVar
#print axioms LSys.MatchV.rstep
#print axioms LSys.varPlace_inj
#print axioms LSys.heapPlace_ne_varPlace
#print axioms LSys.MatchUS.letVarWithHolders
#print axioms LSys.WFLam.addBorrow
#print axioms LSys.WFHolds.clearPlace
#print axioms LSys.WFHolds.setHolders
#print axioms LSys.WFHolds.removeOcc
#print axioms LSys.WFHolds.consumeResult
#print axioms LSys.WFLam.consumeResult
#print axioms LSys.MatchU.borrowPush
#print axioms LSys.MatchU.borrowPop
#print axioms LSys.MatchU.toMatchUS
#print axioms LSys.MatchUS.letVar
#print axioms LSys.MatchUS.borrowPush
#print axioms LSys.StepPMH.letV
#print axioms LSys.StepPMH.redex
#print axioms LSys.StepPMH.op
#print axioms LSys.StepPMH.write
#print axioms LSys.StepPMH.freeze
#print axioms LSys.StepPMH.recover
#print axioms LSys.StepPMH.alloc
#print axioms LSys.StepPMH.drop
#print axioms LSys.StepPMH.derefV
#print axioms LSys.EffHStepEvalC.var_inv
#print axioms LSys.not_match_step_naive
#print axioms LSys.MatchV.letVar
#print axioms LSys.MatchV.borrowVar
