/-
Copyright (c) 2022 Henrik Böving. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Henrik Böving
-/
import Lean

import DocGen4.Process.Base
import DocGen4.Process.NameInfo

namespace DocGen4.Process

open Lean Meta Widget

partial def stripArgs (e : Expr) : Expr :=
  match e.consumeMData with
  | Expr.lam name type body data =>
    let name := name.eraseMacroScopes
    stripArgs (Expr.instantiate1 body (mkFVar ⟨name⟩))
  | Expr.forallE name type body data =>
    let name := name.eraseMacroScopes
    stripArgs (Expr.instantiate1 body (mkFVar ⟨name⟩))
  | _ => e

def processEq (eq : Name) : MetaM CodeWithInfos := do
  let type ← (mkConstWithFreshMVarLevels eq >>= inferType)
  let final := stripArgs type
  prettyPrintTerm final

def valueToEq (v : DefinitionVal) : MetaM Expr := withLCtx {} {} do
  let env ← getEnv
  withOptions (tactic.hygienic.set . false) do
    lambdaTelescope v.value fun xs body => do
      let us := v.levelParams.map mkLevelParam
      let type ← mkEq (mkAppN (Lean.mkConst v.name us) xs) body
      let type ← mkForallFVars xs type
      pure type

def DefinitionInfo.ofDefinitionVal (v : DefinitionVal) : MetaM DefinitionInfo := do
  let info ← Info.ofConstantVal v.toConstantVal
  let isUnsafe := v.safety == DefinitionSafety.unsafe
  let isNonComput := isNoncomputable (←getEnv) v.name
  try
    let eqs? ← getEqnsFor? v.name
    match eqs? with
    | some eqs =>
      let prettyEqs ← eqs.mapM processEq
      pure <| DefinitionInfo.mk info isUnsafe v.hints prettyEqs isNonComput
    | none =>
      let eq ← prettyPrintTerm <| stripArgs (←valueToEq v)
      pure <| DefinitionInfo.mk info isUnsafe v.hints (some #[eq]) isNonComput
  catch err =>
    IO.println s!"WARNING: Failed to calculate equational lemmata for {v.name}: {←err.toMessageData.toString}"
    pure <| DefinitionInfo.mk info isUnsafe v.hints none isNonComput


end DocGen4.Process
